import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Extracts a still frame from a video and uses it as the desktop picture.
///
/// A live wallpaper is an overlay on top of the system wallpaper. Setting the
/// static desktop picture to the same frame means:
/// * the desktop never flashes a different image when playback starts, and
/// * pausing (screen locked, display asleep) still leaves a correct-looking
///   desktop behind.
enum StillFrameService {
    /// One cache entry per (video path, adjustment signature).
    private static var cache: [String: URL] = [:]

    /// Extracts (and caches) the still frame for a video. When `adjustments`
    /// carries colour/tone changes they are applied to the extracted frame so
    /// the static desktop picture matches the adjusted overlay.
    static func stillFrame(for url: URL, adjustments: DisplayAdjustments = .default) async -> URL? {
        let key = "\(url.path)|\(adjustments.cacheSignature)"
        if let cached = cache[key], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 3840, height: 2160)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let result = try await generator.image(at: time)
            var cgImage = result.image
            if adjustments.hasColorAdjustments {
                cgImage = adjustments.apply(to: cgImage)
            }
            let signature = adjustments.cacheSignature
            let destination = Paths.stillFrameDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(abs(url.path.hashValue))-\(signature.hashValue).png")
            guard let data = representation(of: cgImage) else { return nil }
            try data.write(to: destination, options: .atomic)
            cache[key] = destination
            return destination
        } catch {
            Log.warn("StillFrame: failed to extract a frame from \(url.lastPathComponent) — \(error.localizedDescription)")
            return nil
        }
    }

    /// Applies the still frame as the desktop picture for the given screen.
    @MainActor
    static func applyDesktopPicture(stillURL: URL, to screen: NSScreen) {
        do {
            try NSWorkspace.shared.setDesktopImageURL(stillURL, for: screen, options: [.allowClipping: true])
        } catch {
            Log.warn("StillFrame: could not set the desktop picture — \(error.localizedDescription)")
        }
    }

    private static func representation(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
