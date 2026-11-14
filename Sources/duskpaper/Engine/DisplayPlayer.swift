import AppKit
import AVFoundation
import CoreGraphics

/// Window level used by the wallpaper overlay.
///
/// A live wallpaper has to sit in a narrow band:
///
/// * **above** the window the system draws the desktop picture in, and
/// * **below** the window that draws the desktop icons.
///
/// On older macOS the desktop picture is painted by the window server itself,
/// so `kCGDesktopWindowLevel` was enough. Current releases draw it in a real
/// window owned by the Dock, at a level *higher* than `kCGDesktopWindowLevel` —
/// an overlay at the classic level is simply hidden behind the desktop
/// picture. The level is therefore measured at runtime instead of hardcoded.
enum WallpaperWindowLevel {
    /// Used when the relevant system windows cannot be found.
    static let fallback = NSWindow.Level(rawValue: Int(Int32.min) + 30)

    /// Finds a level that is above the desktop picture and below the icons.
    static func resolve() -> NSWindow.Level {
        var pictureLevel: Int?
        var iconLevel: Int?

        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            let owner = window["kCGWindowOwnerName"] as? String ?? ""
            let layer = window["kCGWindowLayer"] as? Int ?? 0
            guard layer < 0 else { continue }   // ignore normal app windows

            // The Dock owns the window that shows the desktop picture.
            if owner == "Dock" {
                pictureLevel = max(pictureLevel ?? layer, layer)
            }
            // The Finder draws the desktop icons in a very low layer window.
            if owner == "Finder" {
                iconLevel = min(iconLevel ?? layer, layer)
            }
        }

        var level = fallback.rawValue
        if let pictureLevel {
            level = max(level, pictureLevel + 2)
        }
        if let iconLevel {
            level = min(level, iconLevel - 1)
        }
        Log.debug("WindowLevel: picture=\(pictureLevel.map(String.init) ?? "-") icons=\(iconLevel.map(String.init) ?? "-") -> \(level)")
        return NSWindow.Level(rawValue: level)
    }
}

/// A view whose backing layer is an `AVPlayerLayer`.
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        // AppKit keeps the backing layer sized to the view's bounds.
        layer = playerLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Owns the wallpaper window and player for a single display.
@MainActor
final class DisplayPlayer {
    let displayID: CGDirectDisplayID

    private var window: NSWindow?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var item: AVPlayerItem?
    private var heartbeat: Timer?

    private(set) var isPlaying = false
    private var playbackRate: Float = 1.0
    private var isMuted = true
    private var volume: Float = 0.5
    private var gravity: VideoGravity = .fill
    private var adjustments: DisplayAdjustments = .default

    init(displayID: CGDirectDisplayID, level: NSWindow.Level) {
        self.displayID = displayID
        self.level = level
    }

    /// The window level this player's window uses.
    private let level: NSWindow.Level

    deinit {
        // AVPlayer/AVPlayerLooper must be released off the main actor.
        let player = self.player
        let looper = self.looper
        Task { @MainActor in
            player?.pause()
            looper?.disableLooping()
            _ = player
            _ = looper
        }
    }

    // MARK: - Window

    /// Creates (or reuses) the borderless desktop window for this display.
    @discardableResult
    private func ensureWindow(for screen: NSScreen) -> NSWindow {
        if let window { return window }

        // Use the full display frame (not visibleFrame) so the menu bar strip
        // is covered too — the system draws its own menu bar on top.
        let frame = screen.frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = level
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        window.isOpaque = false
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.canHide = false
        window.isMovableByWindowBackground = false
        window.contentView = PlayerLayerView(frame: frame)

        window.setFrame(frame, display: false)
        window.orderFrontRegardless()

        self.window = window
        return window
    }

    /// Re-applies geometry after a Space transition, display change or wake.
    func reassertGeometry(screen: NSScreen) {
        guard let window else { return }
        window.level = level
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        applyGravity()
        applyAdjustments()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func show() {
        window?.orderFrontRegardless()
    }

    // MARK: - Playback

    /// Starts (or restarts) playback of the given video on this display.
    func play(
        url: URL,
        gravity: VideoGravity,
        adjustments: DisplayAdjustments = .default,
        muted: Bool,
        volume: Double,
        rate: Double
    ) {
        self.gravity = gravity
        self.adjustments = adjustments
        self.isMuted = muted
        self.volume = Float(volume)
        self.playbackRate = Float(rate)

        guard let screen = Self.screen(for: displayID) else {
            Log.warn("DisplayPlayer: no screen for display \(displayID)")
            return
        }
        let window = ensureWindow(for: screen)

        // Tear down any previous item so we do not leak decoders.
        teardownPlayer()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1
        self.item = item

        // AVPlayerLooper drives an AVQueuePlayer and handles the seamless
        // wrap-around of the clip.
        let player = AVQueuePlayer()
        player.actionAtItemEnd = .none
        player.isMuted = muted
        player.volume = Float(volume)
        player.defaultRate = Float(rate)
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player

        let view = window.contentView as? PlayerLayerView
        view?.playerLayer.player = player
        applyGravity()
        applyAdjustments()

        looper = AVPlayerLooper(player: player, templateItem: item)

        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        startHeartbeat()
        Log.debug("DisplayPlayer: playing \(url.lastPathComponent) on display \(displayID)")
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        guard let player else { return }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    func stop() {
        stopHeartbeat()
        teardownPlayer()
        window?.orderOut(nil)
        isPlaying = false
    }

    /// Full teardown of the window and player.
    func dispose() {
        stopHeartbeat()
        teardownPlayer()
        window?.contentView = nil
        window?.orderOut(nil)
        window = nil
    }

    private func teardownPlayer() {
        player?.pause()
        looper?.disableLooping()
        (window?.contentView as? PlayerLayerView)?.playerLayer.player = nil
        player = nil
        looper = nil
        item = nil
    }

    // MARK: - Settings

    func update(gravity: VideoGravity) {
        self.gravity = gravity
        applyGravity()
    }

    func update(adjustments: DisplayAdjustments) {
        self.adjustments = adjustments
        applyAdjustments()
    }

    func update(muted: Bool, volume: Double) {
        self.isMuted = muted
        self.volume = Float(volume)
        player?.isMuted = muted
        player?.volume = Float(volume)
    }

    func update(rate: Double) {
        self.playbackRate = Float(rate)
        player?.defaultRate = Float(rate)
        if isPlaying { player?.rate = Float(rate) }
    }

    /// Applies the stored colour/tone adjustments as Core Image filters on the
    /// player layer. Runs live, even while playback is paused.
    private func applyAdjustments() {
        guard let view = window?.contentView as? PlayerLayerView else { return }
        view.contentFilters = adjustments.makeCIFilters()
    }

    private func applyGravity() {
        guard let view = window?.contentView as? PlayerLayerView else { return }
        switch gravity {
        case .fill:
            view.playerLayer.videoGravity = .resizeAspectFill
        case .fit:
            view.playerLayer.videoGravity = .resizeAspect
        case .stretch:
            view.playerLayer.videoGravity = .resize
        case .center:
            view.playerLayer.videoGravity = .resizeAspect
        }
    }

    // MARK: - Diagnostics

    /// Logs what the player and the window are doing. Only active when the
    /// `DUSKPAPER_DEBUG` environment variable is set.
    func startHeartbeat() {
        guard Log.debugEnabled else { return }
        heartbeat?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.logState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    func stopHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = nil
    }

    private func logState() {
        guard let player, let window else {
            Log.debug("Heartbeat: display \(displayID) has no player/window")
            return
        }
        let seconds = player.currentTime().seconds
        let time = seconds.isFinite ? String(format: "%.2f", seconds) : "nan"
        let layer = (window.contentView as? PlayerLayerView)?.playerLayer
        Log.debug("Heartbeat d\(displayID): time=\(time) rate=\(player.rate) tc=\(player.timeControlStatus.rawValue) visible=\(window.isVisible) onscreen=\(window.isOnActiveSpace) occlusion=\(window.occlusionState.rawValue) layerReady=\(layer?.isReadyForDisplay ?? false) alpha=\(window.alphaValue)")
    }

    // MARK: - Helpers

    /// Maps a `CGDirectDisplayID` to the matching `NSScreen`.
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        for screen in NSScreen.screens {
            if let id = screenID(of: screen), id == displayID {
                return screen
            }
        }
        return nil
    }

    /// The `CGDirectDisplayID` behind an `NSScreen`.
    static func screenID(of screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen else { return nil }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
