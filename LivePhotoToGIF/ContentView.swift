import AVKit
import Photos
import SwiftUI

struct ContentView: View {
    enum Screen {
        case idle
        case loadingVideo
        case editing
        case converting
        case done
    }

    @State private var screen: Screen = .idle
    @State private var showPicker = false
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var showSettingsAlert = false

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
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
                .padding()
                .animation(.default, value: screen == .idle)
            }
            .navigationTitle("Live Photo → GIF")
        }
        .sheet(isPresented: $showPicker) {
            LivePhotoPicker { assetId in
                Task { await handlePick(assetIdentifier: assetId) }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let gifURL {
                ShareSheet(items: [gifURL])
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Photo Access Required", isPresented: $showSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This app needs access to your Photos library to read Live Photos. Please grant access in Settings.")
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "livephoto")
                .font(.system(size: 64))
                .foregroundStyle(.purple)

            Text("Select a Live Photo to convert it to an animated GIF.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button {
                Task { await selectLivePhoto() }
            } label: {
                Label("Choose Live Photo", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .padding(.horizontal)

            Spacer().frame(height: 20)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            ProgressView()
                .scaleEffect(1.5)
            Text("Extracting video from Live Photo...")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Editing

    private var editingView: some View {
        VStack(spacing: 20) {
            // Video preview
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onAppear { player.play() }
            }

            // Trim
            GroupBox("Trim") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Start: \(String(format: "%.1fs", trimStart))")
                            .monospacedDigit()
                        Spacer()
                        Text("End: \(String(format: "%.1fs", trimEnd))")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Start").font(.caption2).foregroundStyle(.secondary)
                            Slider(value: $trimStart, in: 0...max(0.01, trimEnd - 0.1), step: 0.1)
                        }
                        VStack(alignment: .leading) {
                            Text("End").font(.caption2).foregroundStyle(.secondary)
                            Slider(value: $trimEnd, in: (trimStart + 0.1)...videoDuration, step: 0.1)
                        }
                    }

                    Text("Duration: \(String(format: "%.1fs", trimEnd - trimStart))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.purple)
                }
            }

            // Settings
            GroupBox("Settings") {
                VStack(spacing: 16) {
                    HStack {
                        Text("FPS")
                            .frame(width: 80, alignment: .leading)
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
                        Text("Max width")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $maxWidth, in: 200...1080, step: 40) {
                            Text("Width")
                        }
                        Text("\(Int(maxWidth))px")
                            .monospacedDigit()
                            .frame(width: 55, alignment: .trailing)
                    }
                }
                .font(.subheadline)
            }

            // Convert button
            Button {
                Task { await convert() }
            } label: {
                Label("Convert to GIF", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            // Start over
            Button("Choose Different Photo", role: .cancel) {
                reset()
            }
            .font(.subheadline)
        }
    }

    // MARK: - Converting

    private var convertingView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            ProgressView(value: progress) {
                Text("Converting...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
            }
            .tint(.purple)
            .padding(.horizontal, 40)

            Text(progress < 0.8 ? "Extracting frames..." : "Encoding GIF...")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            if let gifURL {
                AnimatedGIFView(url: gifURL)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(gifSize)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showShareSheet = true
            } label: {
                Label("Share GIF", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // Save to Photos
            Button {
                Task { await saveToPhotos() }
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)

            Button("Convert Another") {
                reset()
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func selectLivePhoto() async {
        let granted = await LivePhotoExtractor.requestAccess()
        if granted {
            showPicker = true
        } else {
            showSettingsAlert = true
        }
    }

    private func handlePick(assetIdentifier: String) async {
        screen = .loadingVideo
        do {
            let url = try await LivePhotoExtractor.extractVideo(assetIdentifier: assetIdentifier)
            let dur = await LivePhotoExtractor.videoDuration(url: url)
            videoURL = url
            videoDuration = dur
            trimStart = 0
            trimEnd = dur
            player = AVPlayer(url: url)
            player?.actionAtItemEnd = .none
            // Loop playback
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
            screen = .editing
        } catch {
            errorMessage = error.localizedDescription
            screen = .idle
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
                progress: { p in
                    self.progress = p
                }
            )
            gifURL = url

            // Compute file size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int {
                let mb = Double(size) / (1024 * 1024)
                if mb >= 1 {
                    gifSize = String(format: "%.1f MB", mb)
                } else {
                    gifSize = "\(size / 1024) KB"
                }
            }

            screen = .done
        } catch {
            errorMessage = error.localizedDescription
            screen = .editing
        }
    }

    private func saveToPhotos() async {
        guard let gifURL, let data = try? Data(contentsOf: gifURL) else { return }
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    errorMessage = nil
                    // Brief confirmation — reuse the alert
                    errorMessage = "Saved to Photos!"
                } else {
                    errorMessage = error?.localizedDescription ?? "Could not save to Photos."
                }
            }
        }
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

// Equatable conformance for animation
extension ContentView.Screen: Equatable {}
