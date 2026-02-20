import AVFoundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

// MARK: - Video extraction from Live Photo PHAsset

enum LivePhotoExtractor {

    enum Error: LocalizedError {
        case assetNotFound
        case noVideoResource
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .assetNotFound: return "Could not find the selected photo."
            case .noVideoResource: return "No video found in this Live Photo."
            case .permissionDenied: return "Photo library access is required."
            }
        }
    }

    /// Request photo library read access. Returns true if granted (full or limited).
    static func requestAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    /// Extract the paired .MOV video from a Live Photo asset.
    static func extractVideo(assetIdentifier: String) async throws -> URL {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw Error.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo })
                ?? resources.first(where: { $0.type == .video }) else {
            throw Error.noVideoResource
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("livephoto_\(assetIdentifier.prefix(8)).mov")
        try? FileManager.default.removeItem(at: tempURL)

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(
                for: videoResource,
                toFile: tempURL,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: tempURL)
                }
            }
        }
    }

    /// Get the duration of a video file in seconds.
    static func videoDuration(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        return duration?.seconds ?? 0
    }
}

// MARK: - GIF Converter

struct GIFSettings {
    var fps: Double = 15
    var maxWidth: CGFloat = 480
    var trimStart: Double = 0 // seconds
    var trimEnd: Double? = nil // nil = end of video
}

enum GIFConverter {

    enum Error: LocalizedError {
        case noVideoTrack
        case cannotCreateDestination
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "No video track found in the file."
            case .cannotCreateDestination: return "Could not create GIF output file."
            case .encodingFailed: return "GIF encoding failed."
            }
        }
    }

    /// Convert a video file to an animated GIF.
    /// `progress` is called with values from 0.0 to 1.0 on the main actor.
    @MainActor
    static func convert(
        videoURL: URL,
        settings: GIFSettings,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let endTime = settings.trimEnd ?? duration
        let startTime = settings.trimStart
        let clipDuration = endTime - startTime

        // Set up frame generator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: settings.maxWidth, height: settings.maxWidth)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)

        let frameCount = max(1, Int(ceil(clipDuration * settings.fps)))
        let delay = 1.0 / settings.fps

        // Extract frames
        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let time = CMTime(
                seconds: startTime + Double(i) / settings.fps,
                preferredTimescale: 600
            )
            let (image, _) = try await generator.image(at: time)
            frames.append(image)
            progress(Double(i + 1) / Double(frameCount) * 0.8)
        }

        // Encode GIF
        progress(0.85)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("livephoto_\(Int(Date().timeIntervalSince1970)).gif")
        try? FileManager.default.removeItem(at: outputURL)

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw Error.cannotCreateDestination
        }

        // GIF properties: loop forever
        let gifFileProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, gifFileProperties)

        // Per-frame properties
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]
        ] as CFDictionary

        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }

        progress(0.95)

        guard CGImageDestinationFinalize(destination) else {
            throw Error.encodingFailed
        }

        progress(1.0)
        return outputURL
    }
}
