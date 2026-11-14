import Foundation
import CoreGraphics
import CoreImage

/// Per-display colour, tone and scaling adjustments.
struct DisplayAdjustments: Codable, Equatable, Sendable {
    /// 0.5 ... 1.5 (1.0 = 100%, neutral)
    var contrast: Double = 1.0
    /// -0.5 ... 0.5 (0.0 = 0%, neutral)
    var brightness: Double = 0.0
    /// 0.0 ... 2.0 (1.0 = 100%, neutral; 0.0 = monochrome)
    var saturation: Double = 1.0
    /// -1.0 ... 1.0 (0.0 = neutral; negative = cooler, positive = warmer)
    var warmth: Double = 0.0
    /// -180.0 ... 180.0 degrees (0.0 = neutral)
    var hue: Double = 0.0
    /// 0.5 ... 1.5 (1.0 = 100%, neutral)
    var gamma: Double = 1.0
    /// Optional per-display scaling override. `nil` follows the global setting.
    var gravity: VideoGravity? = nil

    static let `default` = DisplayAdjustments()

    var hasColorAdjustments: Bool {
        abs(contrast - 1.0) > 0.001
            || abs(brightness) > 0.001
            || abs(saturation - 1.0) > 0.001
            || abs(warmth) > 0.001
            || abs(hue) > 0.1
            || abs(gamma - 1.0) > 0.001
    }

    var isDefault: Bool {
        !hasColorAdjustments && gravity == nil
    }

    var cacheSignature: String {
        String(
            format: "c%.2f-b%.2f-s%.2f-w%.2f-h%.0f-g%.2f",
            contrast, brightness, saturation, warmth, hue, gamma
        )
    }

    init(
        contrast: Double = 1.0,
        brightness: Double = 0.0,
        saturation: Double = 1.0,
        warmth: Double = 0.0,
        hue: Double = 0.0,
        gamma: Double = 1.0,
        gravity: VideoGravity? = nil
    ) {
        self.contrast = contrast
        self.brightness = brightness
        self.saturation = saturation
        self.warmth = warmth
        self.hue = hue
        self.gamma = gamma
        self.gravity = gravity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard let decoded = try? container.decodeIfPresent(T.self, forKey: key) else {
                return fallback
            }
            return decoded
        }

        contrast = value(.contrast, 1.0)
        brightness = value(.brightness, 0.0)
        saturation = value(.saturation, 1.0)
        warmth = value(.warmth, 0.0)
        hue = value(.hue, 0.0)
        gamma = value(.gamma, 1.0)
        gravity = try? container.decodeIfPresent(VideoGravity.self, forKey: .gravity)
    }

    /// Builds the Core Image filter chain applied to the display's player layer.
    func makeCIFilters() -> [CIFilter] {
        guard hasColorAdjustments else { return [] }
        var filters: [CIFilter] = []

        if abs(contrast - 1.0) > 0.001 || abs(brightness) > 0.001 || abs(saturation - 1.0) > 0.001,
           let controls = CIFilter(name: "CIColorControls") {
            controls.setDefaults()
            controls.setValue(contrast, forKey: kCIInputContrastKey)
            controls.setValue(brightness, forKey: kCIInputBrightnessKey)
            controls.setValue(saturation, forKey: kCIInputSaturationKey)
            filters.append(controls)
        }

        if abs(warmth) > 0.001,
           let temperature = CIFilter(name: "CITemperatureAndTint") {
            temperature.setDefaults()
            temperature.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            temperature.setValue(CIVector(x: 6500 - warmth * 2500, y: 0), forKey: "inputTargetNeutral")
            filters.append(temperature)
        }

        if abs(hue) > 0.1,
           let hueFilter = CIFilter(name: "CIHueAdjust") {
            hueFilter.setDefaults()
            hueFilter.setValue(hue * .pi / 180.0, forKey: kCIInputAngleKey)
            filters.append(hueFilter)
        }

        if abs(gamma - 1.0) > 0.001,
           let gammaFilter = CIFilter(name: "CIGammaAdjust") {
            gammaFilter.setDefaults()
            gammaFilter.setValue(1.0 / max(gamma, 0.1), forKey: "inputPower")
            filters.append(gammaFilter)
        }

        return filters
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Applies the same Core Image filter chain to a still `CGImage`.
    func apply(to cgImage: CGImage) -> CGImage {
        let filters = makeCIFilters()
        guard !filters.isEmpty else { return cgImage }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        var ciImage = CIImage(cgImage: cgImage)
        for filter in filters {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                ciImage = output
            }
        }
        return Self.ciContext.createCGImage(ciImage, from: bounds) ?? cgImage
    }
}

/// Quick one-click looks for a display.
enum AdjustmentPreset: String, CaseIterable, Identifiable, Sendable {
    case standard
    case vivid
    case soft
    case dimmed
    case warm
    case cool
    case monochrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .vivid: return "Vivid"
        case .soft: return "Soft"
        case .dimmed: return "Dimmed"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .monochrome: return "Mono"
        }
    }

    func applying(keepingGravity gravity: VideoGravity?) -> DisplayAdjustments {
        switch self {
        case .standard:
            return DisplayAdjustments(gravity: gravity)
        case .vivid:
            return DisplayAdjustments(contrast: 1.15, brightness: 0.0, saturation: 1.30, warmth: 0.0, hue: 0.0, gamma: 1.0, gravity: gravity)
        case .soft:
            return DisplayAdjustments(contrast: 0.85, brightness: -0.03, saturation: 0.90, warmth: 0.0, hue: 0.0, gamma: 1.05, gravity: gravity)
        case .dimmed:
            return DisplayAdjustments(contrast: 0.95, brightness: -0.22, saturation: 0.95, warmth: 0.0, hue: 0.0, gamma: 0.90, gravity: gravity)
        case .warm:
            return DisplayAdjustments(contrast: 1.05, brightness: 0.0, saturation: 1.05, warmth: 0.38, hue: 0.0, gamma: 1.0, gravity: gravity)
        case .cool:
            return DisplayAdjustments(contrast: 1.05, brightness: 0.0, saturation: 1.0, warmth: -0.38, hue: 0.0, gamma: 1.0, gravity: gravity)
        case .monochrome:
            return DisplayAdjustments(contrast: 1.12, brightness: 0.0, saturation: 0.0, warmth: 0.0, hue: 0.0, gamma: 1.0, gravity: gravity)
        }
    }

    func matches(_ adjustments: DisplayAdjustments) -> Bool {
        let target = applying(keepingGravity: adjustments.gravity)
        return abs(adjustments.contrast - target.contrast) < 0.005
            && abs(adjustments.brightness - target.brightness) < 0.005
            && abs(adjustments.saturation - target.saturation) < 0.005
            && abs(adjustments.warmth - target.warmth) < 0.005
            && abs(adjustments.hue - target.hue) < 0.5
            && abs(adjustments.gamma - target.gamma) < 0.005
    }
}

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
    /// Per-display colour, tone and scaling adjustments keyed by `CGDirectDisplayID`.
    var perDisplayAdjustments: [String: DisplayAdjustments] = [:]
    /// Wallpaper applied to displays that have no explicit assignment.
    var defaultWallpaperID: UUID?

    // Library --------------------------------------------------------------
    /// Folders scanned in place (in addition to the managed library).
    var watchedFolders: [URL] = []

    static let `default` = AppSettings()

    func adjustments(for displayID: CGDirectDisplayID) -> DisplayAdjustments {
        perDisplayAdjustments[String(displayID)] ?? .default
    }

    func effectiveGravity(for displayID: CGDirectDisplayID) -> VideoGravity {
        adjustments(for: displayID).gravity ?? gravity
    }

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
        perDisplayAdjustments = value(.perDisplayAdjustments, [:])
        defaultWallpaperID = try? container.decodeIfPresent(UUID.self, forKey: .defaultWallpaperID)
        watchedFolders = value(.watchedFolders, [])
    }
}
