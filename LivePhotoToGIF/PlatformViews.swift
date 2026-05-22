import PhotosUI
import SwiftUI

// MARK: - Photo Picker (wraps PHPickerViewController for both platforms)

#if os(iOS)

struct PhotoPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .livePhotos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let result = results.first, let id = result.assetIdentifier else { return }
            parent.onPick(id)
        }
    }
}

#elseif os(macOS)

struct PhotoPicker: NSViewControllerRepresentable {
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
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let result = results.first, let id = result.assetIdentifier else { return }
            parent.onPick(id)
        }
    }
}

#endif

// MARK: - Animated GIF View

#if os(iOS)

import UIKit
import ImageIO

struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        return iv
    }

    func updateUIView(_ iv: UIImageView, context: Context) {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var duration: Double = 0

        for i in 0..<count {
            if let cg = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: cg))
            }
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                let d = (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    .flatMap({ $0 > 0 ? $0 : nil })
                    ?? gif[kCGImagePropertyGIFDelayTime as String] as? Double
                    ?? 0.1
                duration += d
            }
        }

        iv.animationImages = images
        iv.animationDuration = duration
        iv.animationRepeatCount = 0
        iv.startAnimating()
    }
}

#elseif os(macOS)

import AppKit

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

#endif

// MARK: - Share Sheet (iOS only)

#if os(iOS)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#endif
