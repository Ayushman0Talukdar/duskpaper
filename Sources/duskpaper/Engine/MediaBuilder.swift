import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia
import ImageIO

/// Turns non-video sources (still images, GIFs) into a seamless looping video
/// that the wallpaper engine can play.
///
/// Stills get a slow Ken Burns push so the result feels alive rather than
/// static; GIFs are re-encoded frame-by-frame preserving their original timing.
enum MediaBuilder {
    enum BuilderError: LocalizedError {
        case cannotDecodeImage
        case cannotCreateWriter
        case cannotAppendFrame
        case cannotFinishWriting

        var errorDescription: String? {
            switch self {
            case .cannotDecodeImage: return "The image could not be decoded."
            case .cannotCreateWriter: return "A video encoder could not be created."
            case .cannotAppendFrame: return "A frame could not be written."
            case .cannotFinishWriting: return "The video could not be finalised."
            }
        }
    }

    /// A plan describing the frames to encode. Images are produced lazily so a
    /// long Ken Burns render never holds every frame in memory at once.
    private struct FramePlan {
        var count: Int
        var times: [CMTime]
        var imageAt: (Int) -> CGImage?
    }

    // MARK: - Public API

    /// Builds (or reuses) a playable video for the given wallpaper.
    static func playableURL(for wallpaper: Wallpaper, settings: AppSettings) async throws -> URL {
        switch wallpaper.kind {
        case .video:
            return wallpaper.sourceURL
        case .image:
            return try await renderStill(wallpaper, settings: settings)
        case .gif:
            return try await renderGIF(wallpaper)
        }
    }

    /// Destination for a generated rendition. The name encodes the source and
    /// the settings that affect the output so changing them invalidates it.
    static func renditionURL(for wallpaper: Wallpaper, settings: AppSettings) -> URL? {
        switch wallpaper.kind {
        case .video:
            return nil
        case .image:
            let signature = String(format: "still-%.1f-%.3f", settings.stillDurationSeconds, settings.stillZoomAmount)
            return Paths.renditionsDirectory.appendingPathComponent("\(wallpaper.id.uuidString)-\(signature).mp4")
        case .gif:
            return Paths.renditionsDirectory.appendingPathComponent("\(wallpaper.id.uuidString)-gif.mp4")
        }
    }

    /// Deletes generated renditions whose source wallpaper is gone.
    static func pruneRenditions(keeping wallpapers: [Wallpaper]) {
        let fm = FileManager.default
        let liveIDs = wallpapers.map(\.id.uuidString)
        let contents = (try? fm.contentsOfDirectory(at: Paths.renditionsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            let stem = url.deletingPathExtension().lastPathComponent
            // Renditions are named "<uuid>-<signature>", and UUIDs contain
            // dashes, so match on the prefix rather than splitting.
            if !liveIDs.contains(where: { stem.hasPrefix($0) }) {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Still images (Ken Burns)

    private static func renderStill(_ wallpaper: Wallpaper, settings: AppSettings) async throws -> URL {
        let destination = renditionURL(for: wallpaper, settings: settings)!
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        guard let source = CGImageSourceCreateWithURL(wallpaper.sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw BuilderError.cannotDecodeImage
        }

        let target = CGSize(width: 1920, height: 1080)
        let fps: Int32 = 30
        let duration = max(settings.stillDurationSeconds, 2)
        let frameCount = max(Int(duration * Double(fps)), 1)
        let zoom = max(settings.stillZoomAmount, 0)

        var times: [CMTime] = []
        times.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            times.append(CMTime(value: CMTimeValue(index), timescale: fps))
        }

        let plan = FramePlan(count: frameCount, times: times) { index in
            let progress = frameCount == 1 ? 0.0 : Double(index) / Double(frameCount - 1)
            // Slow push-in that eases in and out so the loop seam is invisible.
            let eased = 0.5 - 0.5 * cos(progress * 2 * .pi)
            return draw(image: cgImage, in: target, zoom: 1 + zoom * eased)
        }

        try await encode(plan, to: destination, size: target, fps: fps)
        Log.info("MediaBuilder: rendered still \(destination.lastPathComponent)")
        return destination
    }

    /// Draws an image into a target rect, optionally zoomed, preserving aspect
    /// ratio and cropping the overflow.
    private static func draw(image: CGImage, in size: CGSize, zoom: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }

        let scale = max(size.width / width, size.height / height) * zoom
        let drawSize = CGSize(width: width * scale, height: height * scale)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        let rect = CGRect(origin: origin, size: drawSize)

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }

    // MARK: - GIFs

    private static func renderGIF(_ wallpaper: Wallpaper) async throws -> URL {
        let destination = renditionURL(for: wallpaper, settings: .default)!
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        guard let source = CGImageSourceCreateWithURL(wallpaper.sourceURL as CFURL, nil) else {
            throw BuilderError.cannotDecodeImage
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw BuilderError.cannotDecodeImage }

        var images: [CGImage] = []
        var times: [CMTime] = []
        var elapsed = CMTime.zero
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            var delay: TimeInterval = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                    ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
                    ?? 0.1
            }
            images.append(image)
            times.append(elapsed)
            elapsed = CMTimeAdd(elapsed, CMTime(seconds: max(delay, 0.02), preferredTimescale: 600))
        }
        guard !images.isEmpty else { throw BuilderError.cannotDecodeImage }

        let target = CGSize(width: 1920, height: 1080)
        let plan = FramePlan(count: images.count, times: times) { index in
            draw(image: images[min(index, images.count - 1)], in: target, zoom: 1)
        }

        try await encode(plan, to: destination, size: target, fps: 60)
        Log.info("MediaBuilder: rendered gif \(destination.lastPathComponent)")
        return destination
    }

    // MARK: - Encoder

    private static func encode(
        _ plan: FramePlan,
        to destination: URL,
        size: CGSize,
        fps: Int32
    ) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )

        guard writer.canAdd(input) else { throw BuilderError.cannotCreateWriter }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? BuilderError.cannotCreateWriter
        }
        writer.startSession(atSourceTime: .zero)

        for index in 0..<plan.count {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 4_000_000)
            }
            guard let image = plan.imageAt(index) else { continue }
            guard let buffer = makePixelBuffer(from: image, size: size) else { continue }
            let time = plan.times[index]
            if !adaptor.append(buffer, withPresentationTime: time) {
                writer.cancelWriting()
                throw writer.error ?? BuilderError.cannotAppendFrame
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status != .completed {
            throw writer.error ?? BuilderError.cannotFinishWriting
        }
    }

    // MARK: - Pixel buffers

    private static func makePixelBuffer(from image: CGImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
