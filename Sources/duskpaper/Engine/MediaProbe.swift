import Foundation
import AVFoundation
import ImageIO

/// Reads basic metadata (duration, pixel dimensions) off a media file.
enum MediaProbe {
    /// Duration in seconds. Images report a nominal 10s so the UI stays sane.
    static func duration(of url: URL, kind: MediaKind) async -> TimeInterval {
        switch kind {
        case .video:
            let asset = AVURLAsset(url: url)
            guard let loaded = try? await asset.load(.duration) else { return 0 }
            let seconds = CMTimeGetSeconds(loaded)
            return seconds.isFinite && seconds > 0 ? seconds : 0
        case .gif:
            return gifDuration(of: url) ?? 10
        case .image:
            return 10
        }
    }

    static func pixelSize(of url: URL, kind: MediaKind) async -> CGSize {
        switch kind {
        case .video:
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let naturalSize = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform)
            else {
                return CGSize(width: 1920, height: 1080)
            }
            let size = naturalSize.applying(transform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        case .gif, .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else {
                return CGSize(width: 1920, height: 1080)
            }
            let width = (properties[kCGImagePropertyPixelWidth] as? Double) ?? 1920
            let height = (properties[kCGImagePropertyPixelHeight] as? Double) ?? 1080
            return CGSize(width: width, height: height)
        }
    }

    static func gifDuration(of url: URL) -> TimeInterval? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var total: TimeInterval = 0
        for index in 0..<count {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            else { continue }
            let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            total += max(delay, 0.02)
        }
        return total > 0 ? total : nil
    }
}
