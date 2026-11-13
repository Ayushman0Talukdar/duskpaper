import Foundation

/// Everything the user can tune. Persisted as JSON in Application Support.
struct AppSettings: Codable, Equatable {
    // Playback -------------------------------------------------------------
    var gravity: VideoGravity = .fill
    var isMuted: Bool = true
    var volume: Double = 0.5
    var playbackSpeed: Double = 1.0

    // Power ----------------------------------------------------------------
    var pauseWhenScreenLocked: Bool = true
    var pauseWhenDisplayAsleep: Bool = true
    var pauseOnLowPowerMode: Bool = true
    var pauseOnBattery: Bool = false

    // Startup --------------------------------------------------------------
    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true
    var launchMinimized: Bool = false

    // Rotation -------------------------------------------------------------
    var rotationEnabled: Bool = false
    var rotationIntervalMinutes: Int = 30
    var rotationMode: RotationMode = .sequential

    // Still images ---------------------------------------------------------
    /// Duration of the generated motion loop for still images.
    var stillDurationSeconds: Double = 12
    /// Ken Burns zoom amount for still images (0 disables the motion).
    var stillZoomAmount: Double = 0.18

    // Assignments ----------------------------------------------------------
    /// wallpaperID per `CGDirectDisplayID`.
    var perDisplayWallpapers: [String: UUID] = [:]
    /// Wallpaper applied to displays that have no explicit assignment.
    var defaultWallpaperID: UUID?

    // Library --------------------------------------------------------------
    /// Folders scanned in place (in addition to the managed library).
    var watchedFolders: [URL] = []

    static let `default` = AppSettings()

    /// Decoding is deliberately lenient: every key falls back to its default
    /// when missing, so settings written by an older version of the app keep
    /// working after an upgrade instead of resetting the whole file.
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            // `try?` flattens the optional, so a missing key, a `null` value
            // and a decoding error all end up as `nil` here.
            guard let decoded = try? container.decodeIfPresent(T.self, forKey: key) else {
                return fallback
            }
            return decoded
        }

        gravity = value(.gravity, VideoGravity.fill)
        isMuted = value(.isMuted, true)
        volume = value(.volume, 0.5)
        playbackSpeed = value(.playbackSpeed, 1.0)

        pauseWhenScreenLocked = value(.pauseWhenScreenLocked, true)
        pauseWhenDisplayAsleep = value(.pauseWhenDisplayAsleep, true)
        pauseOnLowPowerMode = value(.pauseOnLowPowerMode, true)
        pauseOnBattery = value(.pauseOnBattery, false)

        launchAtLogin = value(.launchAtLogin, false)
        showMenuBarIcon = value(.showMenuBarIcon, true)
        launchMinimized = value(.launchMinimized, false)

        rotationEnabled = value(.rotationEnabled, false)
        rotationIntervalMinutes = value(.rotationIntervalMinutes, 30)
        rotationMode = value(.rotationMode, RotationMode.sequential)

        stillDurationSeconds = value(.stillDurationSeconds, 12)
        stillZoomAmount = value(.stillZoomAmount, 0.18)

        perDisplayWallpapers = value(.perDisplayWallpapers, [:])
        defaultWallpaperID = try? container.decodeIfPresent(UUID.self, forKey: .defaultWallpaperID)
        watchedFolders = value(.watchedFolders, [])
    }
}
