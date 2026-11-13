import AppKit
import AVFoundation
import CoreGraphics

/// Orchestrates the wallpaper overlay across every connected display.
///
/// One `DisplayPlayer` is kept per display. The engine is the only component
/// that talks to the window server, so pausing, re-applying and reacting to
/// display changes all happen in one place.
@MainActor
final class WallpaperEngine: ObservableObject {
    static let shared = WallpaperEngine()

    /// Wallpaper currently shown on each display.
    @Published private(set) var assignments: [CGDirectDisplayID: UUID] = [:]
    /// True while playback is suspended for a system reason (lock, sleep...).
    @Published private(set) var isSuspended = false
    /// The user pressed pause.
    @Published private(set) var isUserPaused = false

    private var players: [CGDirectDisplayID: DisplayPlayer] = [:]
    private var resolvedURLs: [CGDirectDisplayID: URL] = [:]
    private var rotationTimer: Timer?
    private var rotationIndex = 0

    /// The window level every wallpaper window uses. Resolved once and
    /// refreshed whenever the display configuration changes.
    private var windowLevel: NSWindow.Level = WallpaperWindowLevel.fallback

    private var settings = AppSettings.default
    private var libraryProvider: (() -> [Wallpaper]) = { [] }

    private init() {}

    // MARK: - Configuration

    func configure(settings: AppSettings, library: @escaping () -> [Wallpaper]) {
        self.settings = settings
        self.libraryProvider = library
        windowLevel = WallpaperWindowLevel.resolve()
        applySettingsToPlayers()
    }

    // MARK: - Display discovery

    /// All connected displays, main display first.
    ///
    /// Mirrored displays show up as several `NSScreen`s that share a single
    /// display id, so the list is de-duplicated: a wallpaper belongs to a
    /// display, not to a screen.
    static var displays: [DisplayInfo] {
        let screens = NSScreen.screens
        var result: [DisplayInfo] = []
        var seenIDs: Set<CGDirectDisplayID> = []

        // Count how many screens share each display id so mirrored setups can
        // be recognised.
        var screensPerID: [CGDirectDisplayID: Int] = [:]
        for screen in screens {
            if let id = displayID(of: screen) {
                screensPerID[id, default: 0] += 1
            }
        }

        let mainID = displayID(of: NSScreen.main)

        for screen in screens {
            guard let id = displayID(of: screen) else { continue }
            guard !seenIDs.contains(id) else { continue }
            seenIDs.insert(id)

            let size = screen.frame.size
            let resolution = "\(Int(size.width)) × \(Int(size.height))"
            result.append(
                DisplayInfo(
                    id: id,
                    name: screen.localizedName,
                    resolution: resolution,
                    isMain: id == mainID,
                    frame: screen.frame,
                    isMirrored: (screensPerID[id] ?? 1) > 1
                )
            )
        }

        result.sort { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.id < rhs.id
        }
        return result
    }

    /// The `CGDirectDisplayID` behind an `NSScreen`.
    private static func displayID(of screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen else { return nil }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: - Applying

    /// Applies a wallpaper to the given displays.
    func apply(wallpaper: Wallpaper, to displayIDs: [CGDirectDisplayID]) async {
        guard !displayIDs.isEmpty else { return }

        let playableURL: URL
        do {
            playableURL = try await MediaBuilder.playableURL(for: wallpaper, settings: settings)
        } catch {
            Log.error("Engine: could not prepare \(wallpaper.displayName) — \(error.localizedDescription)")
            return
        }

        for displayID in displayIDs {
            guard let screen = DisplayPlayer.screen(for: displayID) else { continue }

            let player = players[displayID] ?? {
                let new = DisplayPlayer(displayID: displayID, level: windowLevel)
                players[displayID] = new
                return new
            }()

            player.play(
                url: playableURL,
                gravity: settings.gravity,
                muted: settings.isMuted,
                volume: settings.volume,
                rate: settings.playbackSpeed
            )
            resolvedURLs[displayID] = playableURL
            assignments[displayID] = wallpaper.id

            // Keep the static desktop picture in sync with the overlay.
            if let still = await StillFrameService.stillFrame(for: playableURL) {
                StillFrameService.applyDesktopPicture(stillURL: still, to: screen)
            }
        }

        Log.info("Engine: applied \(wallpaper.displayName) to \(displayIDs.count) display(s)")
        refreshPlaybackState()
    }

    /// Applies the wallpaper assigned to each display, or the default one.
    func restoreAssignments() async {
        let all = WallpaperEngine.displays.map(\.id)
        let library = libraryProvider()
        Log.debug("Engine: restoring \(all.count) display(s) from \(library.count) wallpaper(s)")

        for displayID in all {
            let key = String(displayID)
            let wallpaperID = settings.perDisplayWallpapers[key] ?? settings.defaultWallpaperID
            guard let wallpaper = library.first(where: { $0.id == wallpaperID }) else {
                Log.debug("Engine: no wallpaper matched for display \(displayID)")
                continue
            }
            await apply(wallpaper: wallpaper, to: [displayID])
        }
    }

    /// Removes the wallpaper overlay from the given displays.
    func stop(displayIDs: [CGDirectDisplayID]) {
        for displayID in displayIDs {
            players[displayID]?.stop()
            assignments[displayID] = nil
            resolvedURLs[displayID] = nil
        }
    }

    func stopAll() {
        for player in players.values { player.stop() }
        assignments.removeAll()
        resolvedURLs.removeAll()
    }

    // MARK: - Playback control

    func setUserPaused(_ paused: Bool) {
        isUserPaused = paused
        refreshPlaybackState()
    }

    /// Suspends or resumes playback because of a system event (lock, sleep).
    func setSystemSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        refreshPlaybackState()
    }

    private func refreshPlaybackState() {
        let shouldPlay = !isUserPaused && !isSuspended
        for player in players.values {
            if shouldPlay {
                if !player.isPlaying { player.resume() }
            } else {
                if player.isPlaying { player.pause() }
            }
        }
    }

    private func applySettingsToPlayers() {
        for player in players.values {
            player.update(gravity: settings.gravity)
            player.update(muted: settings.isMuted, volume: settings.volume)
            player.update(rate: settings.playbackSpeed)
        }
    }

    // MARK: - System events

    /// Called when the display configuration changed (plugged in, resolution
    /// change, display removed).
    func handleScreenParametersChanged() {
        // The window level depends on where the system draws the desktop
        // picture and the icons, so it is worth re-measuring here.
        windowLevel = WallpaperWindowLevel.resolve()

        let screens = NSScreen.screens
        var liveIDs: Set<CGDirectDisplayID> = []
        for screen in screens {
            if let id = DisplayPlayer.screenID(of: screen) {
                liveIDs.insert(id)
            }
        }

        // Drop players for displays that went away.
        for id in players.keys where !liveIDs.contains(id) {
            players[id]?.dispose()
            players.removeValue(forKey: id)
            assignments.removeValue(forKey: id)
            resolvedURLs.removeValue(forKey: id)
        }

        // Make sure every live display has a player and correct geometry.
        for screen in screens {
            guard let id = DisplayPlayer.screenID(of: screen) else { continue }
            let player = players[id] ?? {
                let new = DisplayPlayer(displayID: id, level: windowLevel)
                players[id] = new
                return new
            }()
            player.reassertGeometry(screen: screen)
        }

        Log.debug("Engine: display configuration changed (\(liveIDs.count) display(s))")

        // A display that appears after launch (a monitor waking up, a dock
        // being plugged in) has no wallpaper yet — give it the one it is
        // assigned.
        Task { @MainActor in
            await applyMissingAssignments()
        }
    }

    /// Applies the assigned wallpaper to any display that does not have one.
    func applyMissingAssignments() async {
        let library = libraryProvider()
        guard !library.isEmpty else { return }

        for displayID in WallpaperEngine.displays.map(\.id) where assignments[displayID] == nil {
            let key = String(displayID)
            let wallpaperID = settings.perDisplayWallpapers[key] ?? settings.defaultWallpaperID
            guard let wallpaper = library.first(where: { $0.id == wallpaperID }) else { continue }
            Log.debug("Engine: applying \(wallpaper.displayName) to newly connected display \(displayID)")
            await apply(wallpaper: wallpaper, to: [displayID])
        }
    }

    /// Called after a Space transition or when the screen wakes.
    func reassertGeometry() {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            players[number.uint32Value]?.reassertGeometry(screen: screen)
        }
    }

    // MARK: - Rotation

    /// Starts the automatic wallpaper rotation.
    func startRotation() {
        stopRotation()
        let minutes = max(settings.rotationIntervalMinutes, 1)
        let timer = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceRotation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
        Log.info("Engine: rotation started every \(minutes) minute(s)")
    }

    func stopRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    private func advanceRotation() {
        let library = libraryProvider()
        guard !library.isEmpty else { return }

        let next: Wallpaper
        switch settings.rotationMode {
        case .sequential:
            let list = library.sorted { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }
            next = list[rotationIndex % list.count]
            rotationIndex += 1
        case .random:
            next = library.randomElement() ?? library[0]
        }

        let displayIDs = WallpaperEngine.displays.map(\.id)
        Task { @MainActor in
            await apply(wallpaper: next, to: displayIDs)
        }
    }
}
