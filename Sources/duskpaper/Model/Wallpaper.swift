import Foundation
import CoreGraphics

/// The kind of source media a wallpaper is built from.
enum MediaKind: String, Codable, Sendable {
    case video
    case image
    case gif

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .image: return "Image"
        case .gif: return "Animation"
        }
    }
}

/// A single entry in the user's wallpaper library.
struct Wallpaper: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var displayName: String
    /// Where the original media lives on disk.
    var sourceURL: URL
    var kind: MediaKind
    /// Length of the loop in seconds. Images use the configured still duration.
    var duration: TimeInterval
    var pixelSize: CGSize
    var addedAt: Date = Date()
    var lastUsedAt: Date?
    var isFavorite: Bool = false
    /// True when duskpaper owns the file and may delete it when the entry is removed.
    var isManaged: Bool = false

    var fileExtension: String { sourceURL.pathExtension.lowercased() }

    var isVideo: Bool { kind == .video }

    init(
        id: UUID = UUID(),
        displayName: String,
        sourceURL: URL,
        kind: MediaKind,
        duration: TimeInterval,
        pixelSize: CGSize,
        addedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        isFavorite: Bool = false,
        isManaged: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.kind = kind
        self.duration = duration
        self.pixelSize = pixelSize
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
        self.isFavorite = isFavorite
        self.isManaged = isManaged
    }

    /// Decoding is lenient so that a single unexpected value never throws away
    /// the user's whole library. Anything missing falls back to a sensible
    /// default.
    init() {
        displayName = "Untitled"
        sourceURL = URL(fileURLWithPath: "/")
        kind = .video
        duration = 0
        pixelSize = CGSize(width: 1920, height: 1080)
    }

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

        id = value(.id, UUID())
        sourceURL = value(.sourceURL, URL(fileURLWithPath: "/"))
        displayName = value(.displayName, sourceURL.lastPathComponent)
        kind = value(.kind, MediaKind.video)
        duration = value(.duration, 0)
        pixelSize = value(.pixelSize, CGSize(width: 1920, height: 1080))
        addedAt = value(.addedAt, Date())
        lastUsedAt = try? container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        isFavorite = value(.isFavorite, false)
        isManaged = value(.isManaged, false)
    }
}

/// How a video is mapped onto the display bounds.
enum VideoGravity: String, Codable, CaseIterable, Sendable {
    case fill
    case fit
    case stretch
    case center

    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        case .center: return "Center"
        }
    }
}

/// Order in which the rotation cycles through the library.
enum RotationMode: String, Codable, CaseIterable, Sendable {
    case sequential
    case random

    var displayName: String {
        switch self {
        case .sequential: return "In order"
        case .random: return "Shuffle"
        }
    }
}

/// A display the user can assign a wallpaper to.
struct DisplayInfo: Identifiable, Hashable, Sendable {
    /// `CGDirectDisplayID`
    let id: CGDirectDisplayID
    let name: String
    let resolution: String
    let isMain: Bool
    let frame: CGRect
    /// True for displays that are not part of the active desktop (mirrored).
    let isMirrored: Bool

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
