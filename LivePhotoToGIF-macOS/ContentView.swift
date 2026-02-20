import AVKit
import Photos
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    enum Screen: Equatable {
        case idle
        case loadingVideo
        case editing
        case converting
        case done
    }

    @State private var screen: Screen = .idle
    @State private var isDragOver = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var errorMessage: String?
    @State private var showSettingsAlert = false
    @State private var heicWarning = false

    // Video
    @State private var videoURL: URL?
    @State private var videoDuration: Double = 3
    @State private var player: AVPlayer?

    // Settings
    @State private var fps: Double = 15
    @State private var maxWidth: Double = 480
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 3

    // Progress & result
    @State private var progress: Double = 0
    @State private var gifURL: URL?
    @State private var gifSize: String = ""

    var body: some View {
        VStack(spacing: 0) {
            switch screen {
            case .idle:
                idleView
            case .loadingVideo:
                loadingView
            case .editing:
                editingView
            case .converting:
                convertingView
            case .done:
                doneView
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 500, idealHeight: 640)
        .animation(.default, value: screen)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadVideoFromFile(url: url)
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            MacPhotoPicker { assetId in
                Task { await loadVideoFromAsset(assetId: assetId) }
            }
            .frame(width: 600, height: 500)
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("That's the still image", isPresented: $heicWarning) {
            Button("OK") {}
        } message: {
            Text("You dropped a .HEIC file, which is just the still photo.\n\nLive Photos are two separate files — drop the .MOV companion video instead.\n\nIn Photos: File → Export → Export Unmodified Original to get both files.")
        }
        .alert("Photo Access Required", isPresented: $showSettingsAlert) {
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This app needs access to your Photos library to read Live Photos. Please grant access in System Settings → Privacy & Security → Photos.")
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            // Drop zone
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(isDragOver ? Color.accentColor : .secondary.opacity(0.3))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragOver ? Color.accentColor.opacity(0.05) : Color.clear)
                )
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 36))
                            .foregroundStyle(isDragOver ? .primary : .secondary)
                        Text("Drop .MOV file here")
                            .font(.title3.weight(.medium))
                        Text("from a Live Photo export or AirDrop")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                .padding()

            Divider().padding(.horizontal)

            // Buttons
            VStack(spacing: 12) {
                Text("or").foregroundStyle(.tertiary).font(.subheadline)

                HStack(spacing: 12) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Open File...", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button {
                        Task { await pickFromPhotos() }
                    } label: {
                        Label("Pick from Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)

            Spacer()

            // Tip
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How to get the .MOV from a Live Photo")
                        .font(.subheadline.weight(.semibold))
                    Text("**AirDrop** from iPhone → arrives as .HEIC + .MOV pair\n**Photos app** → File → Export → Export Unmodified Original\n**iPhone** → Photos → tap ··· → Save as Video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
            .padding()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Extracting video from Live Photo...")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Editing

    private var editingView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Video preview
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onAppear { player.play() }
                }

                // Trim
                GroupBox("Trim") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Start: \(String(format: "%.1fs", trimStart))")
                            Spacer()
                            Text("Duration: \(String(format: "%.1fs", trimEnd - trimStart))")
                                .foregroundStyle(.purple)
                                .fontWeight(.medium)
                            Spacer()
                            Text("End: \(String(format: "%.1fs", trimEnd))")
                        }
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start").font(.caption2).foregroundStyle(.tertiary)
                                Slider(value: $trimStart, in: 0...max(0.01, trimEnd - 0.1), step: 0.1)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("End").font(.caption2).foregroundStyle(.tertiary)
                                Slider(value: $trimEnd, in: (trimStart + 0.1)...videoDuration, step: 0.1)
                            }
                        }
                    }
                }

                // Settings
                GroupBox("Settings") {
                    VStack(spacing: 14) {
                        HStack {
                            Text("FPS").frame(width: 70, alignment: .leading)
                            Picker("FPS", selection: $fps) {
                                Text("10").tag(10.0)
                                Text("15").tag(15.0)
                                Text("20").tag(20.0)
                                Text("25").tag(25.0)
                                Text("30").tag(30.0)
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack {
                            Text("Max width").frame(width: 70, alignment: .leading)
                            Slider(value: $maxWidth, in: 200...1080, step: 40)
                            Text("\(Int(maxWidth))px")
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    .font(.subheadline)
                }

                // Convert
                HStack {
                    Button(role: .cancel) {
                        reset()
                    } label: {
                        Text("Cancel")
                    }
                    .controlSize(.large)

                    Spacer()

                    Button {
                        Task { await convert() }
                    } label: {
                        Label("Convert to GIF", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
            .padding()
        }
    }

    // MARK: - Converting

    private var convertingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView(value: progress) {
                Text("Converting...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
            }
            .tint(.purple)
            .padding(.horizontal, 60)

            Text(progress < 0.8 ? "Extracting frames..." : "Encoding GIF...")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let gifURL {
                    AnimatedGIFView(url: gifURL)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Text(gifSize)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        saveAs()
                    } label: {
                        Label("Save As...", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Button {
                        revealInFinder()
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }

                Button {
                    if let gifURL {
                        let picker = NSSharingServicePicker(items: [gifURL])
                        if let window = NSApp.keyWindow, let contentView = window.contentView {
                            picker.show(
                                relativeTo: .zero,
                                of: contentView,
                                preferredEdge: .minY
                            )
                        }
                    }
                } label: {
                    Label("Share...", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Divider()

                Button("Convert Another") {
                    reset()
                }
                .font(.subheadline)
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                processDroppedURL(url)
            }
        }
    }

    private func processDroppedURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()

        if ["mov", "mp4", "m4v"].contains(ext) {
            loadVideoFromFile(url: url)
            return
        }

        if ["heic", "heif"].contains(ext) {
            heicWarning = true
            return
        }

        errorMessage = "Unsupported file type. Drop a .MOV or .MP4 video file."
    }

    private func loadVideoFromFile(url: URL) {
        // Copy to temp to handle sandboxed / security-scoped URLs
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("livephoto_import.\(url.pathExtension)")
        try? FileManager.default.removeItem(at: temp)
        do {
            try FileManager.default.copyItem(at: url, to: temp)
        } catch {
            errorMessage = "Could not read the file: \(error.localizedDescription)"
            return
        }

        loadVideo(url: temp)
    }

    private func pickFromPhotos() async {
        let granted = await LivePhotoExtractor.requestAccess()
        if granted {
            showPhotoPicker = true
        } else {
            showSettingsAlert = true
        }
    }

    private func loadVideoFromAsset(assetId: String) async {
        screen = .loadingVideo
        do {
            let url = try await LivePhotoExtractor.extractVideo(assetIdentifier: assetId)
            loadVideo(url: url)
        } catch {
            errorMessage = error.localizedDescription
            screen = .idle
        }
    }

    private func loadVideo(url: URL) {
        Task {
            let dur = await LivePhotoExtractor.videoDuration(url: url)
            videoURL = url
            videoDuration = dur
            trimStart = 0
            trimEnd = dur
            player = AVPlayer(url: url)
            player?.actionAtItemEnd = .none
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
            screen = .editing
        }
    }

    private func convert() async {
        guard let videoURL else { return }
        screen = .converting
        progress = 0

        let settings = GIFSettings(
            fps: fps,
            maxWidth: maxWidth,
            trimStart: trimStart,
            trimEnd: trimEnd
        )

        do {
            let url = try await GIFConverter.convert(
                videoURL: videoURL,
                settings: settings,
                progress: { p in self.progress = p }
            )
            gifURL = url

            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int {
                let mb = Double(size) / (1024 * 1024)
                gifSize = mb >= 1
                    ? String(format: "%.1f MB", mb)
                    : "\(size / 1024) KB"
            }

            screen = .done
        } catch {
            errorMessage = error.localizedDescription
            screen = .editing
        }
    }

    private func saveAs() {
        guard let gifURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "live-photo.gif"
        panel.begin { response in
            if response == .OK, let dest = panel.url {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: gifURL, to: dest)
            }
        }
    }

    private func revealInFinder() {
        guard let gifURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([gifURL])
    }

    private func reset() {
        screen = .idle
        player?.pause()
        player = nil
        videoURL = nil
        gifURL = nil
        progress = 0
    }
}
