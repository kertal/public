import AppKit
import PhotosUI
import SwiftUI

// MARK: - PHPicker for macOS (NSViewControllerRepresentable)

struct MacPhotoPicker: NSViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    func makeNSViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .livePhotos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateNSViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MacPhotoPicker
        init(_ parent: MacPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let result = results.first, let id = result.assetIdentifier else { return }
            parent.onPick(id)
        }
    }
}

// MARK: - Animated GIF view (NSImage handles GIF animation natively)

struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.animates = true
        iv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iv.setContentHuggingPriority(.defaultLow, for: .vertical)
        return iv
    }

    func updateNSView(_ iv: NSImageView, context: Context) {
        iv.image = NSImage(contentsOf: url)
    }
}
