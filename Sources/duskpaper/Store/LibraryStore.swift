import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// The user's wallpaper library: a list of entries backed by files on disk,
/// persisted as JSON.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var wallpapers: [Wallpaper] = []
    @Published private(set) var isScanning = false

    private let url: URL
    private let fileManager = FileManager.default

    init(url: URL = Paths.libraryFile) {
        self.url = url
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Wallpaper].self, from: data)
        else {
            Log.info("Library: no stored library, starting empty")
            wallpapers = []
            return
        }
        // Drop entries whose file has disappeared.
        wallpapers = decoded.filter { fileManager.fileExists(atPath: $0.sourceURL.path) }
        Log.info("Library: loaded \(wallpapers.count) wallpaper(s)")
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(wallpapers)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Library: failed to save — \(error.localizedDescription)")
        }
    }

    // MARK: - Lookup

    func wallpaper(id: UUID?) -> Wallpaper? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }

    var favorites: [Wallpaper] { wallpapers.filter(\.isFavorite) }
    var videos: [Wallpaper] { wallpapers.filter { $0.kind == .video } }

    // MARK: - Importing

    /// Copies the given files into the managed library folder and adds them.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> [Wallpaper] {
        var added: [Wallpaper] = []
        for url in urls {
            guard let kind = Self.kind(for: url) else {
                Log.warn("Library: unsupported file \(url.lastPathComponent)")
                continue
            }
            guard let entry = await makeEntry(from: url, kind: kind, managed: true) else { continue }
            wallpapers.append(entry)
            added.append(entry)
        }
        if !added.isEmpty {
            save()
            Log.info("Library: imported \(added.count) item(s)")
        }
        return added
    }

    /// Adds every supported media file found in the folder, referencing the
    /// originals in place (nothing is copied).
    @discardableResult
    func importFolder(_ folder: URL) async -> [Wallpaper] {
        var added: [Wallpaper] = []
        let contents = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            guard let kind = Self.kind(for: url) else { continue }
            guard !wallpapers.contains(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) else {
                continue
            }
            guard let entry = await makeEntry(from: url, kind: kind, managed: false) else { continue }
            wallpapers.append(entry)
            added.append(entry)
        }
        if !added.isEmpty {
            save()
            Log.info("Library: added \(added.count) item(s) from \(folder.lastPathComponent)")
        }
        return added
    }

    /// Re-scans watched folders, picking up new files.
    func refreshWatchedFolders(_ folders: [URL]) async {
        var changed = false
        for folder in folders {
            let before = wallpapers.count
            _ = await importFolder(folder)
            if wallpapers.count != before { changed = true }
        }
        if changed { save() }
    }

    func remove(_ wallpaper: Wallpaper) {
        wallpapers.removeAll { $0.id == wallpaper.id }
        if wallpaper.isManaged {
            try? fileManager.removeItem(at: wallpaper.sourceURL)
        }
        save()
    }

    func toggleFavorite(_ wallpaper: Wallpaper) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        wallpapers[index].isFavorite.toggle()
        save()
    }

    func markUsed(_ wallpaper: Wallpaper) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        wallpapers[index].lastUsedAt = Date()
        save()
    }

    func rename(_ wallpaper: Wallpaper, to name: String) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        wallpapers[index].displayName = trimmed.isEmpty ? wallpaper.sourceURL.lastPathComponent : trimmed
        save()
    }

    // MARK: - Helpers

    private func makeEntry(from url: URL, kind: MediaKind, managed: Bool) async -> Wallpaper? {
        let fm = fileManager
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        let size = values?.fileSize ?? 0
        guard size > 0 else { return nil }

        var storedURL = url
        var isManaged = false
        if managed {
            let destination = uniqueDestination(for: url)
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: url, to: destination)
                storedURL = destination
                isManaged = true
            } catch {
                Log.error("Library: failed to copy \(url.lastPathComponent) — \(error.localizedDescription)")
                return nil
            }
        }

        let duration = await MediaProbe.duration(of: storedURL, kind: kind)
        let pixelSize = await MediaProbe.pixelSize(of: storedURL, kind: kind)

        return Wallpaper(
            displayName: storedURL.deletingPathExtension().lastPathComponent,
            sourceURL: storedURL,
            kind: kind,
            duration: duration,
            pixelSize: pixelSize,
            isManaged: isManaged
        )
    }

    private func uniqueDestination(for url: URL) -> URL {
        let base = Paths.managedMediaDirectory.appendingPathComponent(url.lastPathComponent)
        guard fileManager.fileExists(atPath: base.path) else { return base }
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var counter = 2
        var candidate = Paths.managedMediaDirectory.appendingPathComponent("\(stem)-\(counter).\(ext)")
        while fileManager.fileExists(atPath: candidate.path) {
            counter += 1
            candidate = Paths.managedMediaDirectory.appendingPathComponent("\(stem)-\(counter).\(ext)")
        }
        return candidate
    }

    /// Classifies a file by extension, falling back to the system type.
    static func kind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "mpeg", "mpg", "avi", "mkv", "webm":
            return .video
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp", "avif":
            return .image
        case "gif":
            return .gif
        default:
            guard let type = UTType(filenameExtension: ext) else { return nil }
            if type.conforms(to: .movie) { return .video }
            if type.conforms(to: .gif) { return .gif }
            if type.conforms(to: .image) { return .image }
            return nil
        }
    }
}
