import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Produces and caches poster thumbnails for library items.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private var memory: [String: NSImage] = [:]
    private let memoryLimit = 120

    /// Returns a cached thumbnail, generating one if needed.
    func thumbnail(for wallpaper: Wallpaper) async -> NSImage? {
        let key = wallpaper.id.uuidString
        if let cached = memory[key] { return cached }

        if let disk = diskThumbnail(for: wallpaper), let image = NSImage(contentsOf: disk) {
            store(image, for: key)
            return image
        }

        guard let image = await generate(for: wallpaper) else { return nil }
        store(image, for: key)
        if let data = representation(of: image) {
            let destination = Paths.thumbnailDirectory.appendingPathComponent("\(key).png")
            try? data.write(to: destination, options: .atomic)
        }
        return image
    }

    func clearMemoryCache() {
        memory.removeAll()
    }

    func clearAll() {
        memory.removeAll()
        let contents = (try? FileManager.default.contentsOfDirectory(at: Paths.thumbnailDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Private

    private func store(_ image: NSImage, for key: String) {
        if memory.count >= memoryLimit { memory.removeAll() }
        memory[key] = image
    }

    private func diskThumbnail(for wallpaper: Wallpaper) -> URL? {
        let url = Paths.thumbnailDirectory.appendingPathComponent("\(wallpaper.id.uuidString).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func generate(for wallpaper: Wallpaper) async -> NSImage? {
        switch wallpaper.kind {
        case .image, .gif:
            guard let source = CGImageSourceCreateWithURL(wallpaper.sourceURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        case .video:
            let asset = AVURLAsset(url: wallpaper.sourceURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
            generator.maximumSize = CGSize(width: 640, height: 640)
            do {
                let result = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600))
                let cgImage = result.image
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } catch {
                Log.warn("Thumbnail: could not render \(wallpaper.sourceURL.lastPathComponent) — \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func representation(of image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
