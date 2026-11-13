import Foundation

/// Canonical on-disk locations used by duskpaper.
///
/// Everything lives under Application Support / Caches so the app stays
/// self-contained and never writes outside its own footprint (apart from the
/// user's wallpaper media, which the user explicitly imports).
enum Paths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("duskpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where imported media is copied so the library keeps working even if the
    /// original file is moved or deleted.
    static var managedMediaDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generated video renditions (image/GIF -> motion video).
    static var renditionsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Renditions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var libraryFile: URL { supportDirectory.appendingPathComponent("library.json") }
    static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        let dir = base.appendingPathComponent("duskpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var thumbnailDirectory: URL {
        let dir = cacheDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Extracted still frames used as the static desktop picture so the desktop
    /// never flashes the wrong image when playback pauses.
    static var stillFrameDirectory: URL {
        let dir = cacheDirectory.appendingPathComponent("StillFrames", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var logFile: URL { cacheDirectory.appendingPathComponent("duskpaper.log") }
}
