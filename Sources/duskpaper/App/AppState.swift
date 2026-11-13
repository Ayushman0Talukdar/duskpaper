import AppKit
import Combine
import SwiftUI

/// Central coordinator: owns the settings, the library and the engine, and
/// exposes the actions the UI and the menu bar call into.
@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            engine.configure(settings: settings, library: { [weak self] in self?.library.wallpapers ?? [] })
        }
    }

    let library = LibraryStore()
    let engine = WallpaperEngine.shared
    let monitor = SystemMonitor()

    @Published var displays: [DisplayInfo] = []
    @Published var isBusy = false
    @Published var statusMessage: String?

    private let settingsStore = SettingsStore()

    init() {
        settings = settingsStore.load()
        library.load()
        Task { await library.refreshWatchedFolders(settings.watchedFolders) }

        engine.configure(settings: settings, library: { [weak self] in self?.library.wallpapers ?? [] })

        monitor.onDisplayChange = { [weak self] in
            self?.handleDisplayChange()
        }
        monitor.onLockStateChange = { [weak self] _ in
            self?.applyPauseRules()
        }
        monitor.onDisplaySleepChange = { [weak self] _ in
            self?.applyPauseRules()
        }
        monitor.onPowerChange = { [weak self] in
            self?.applyPauseRules()
        }
    }

    // MARK: - Lifecycle

    func bootstrap() {
        refreshDisplays()
        applyPauseRules()
        Task { await restoreWallpapers() }
        if settings.rotationEnabled {
            engine.startRotation()
        }
        if settings.launchAtLogin {
            setLaunchAtLogin(true)
        }
    }

    func refreshDisplays() {
        displays = WallpaperEngine.displays
    }

    private func handleDisplayChange() {
        refreshDisplays()
        engine.handleScreenParametersChanged()
    }

    /// Recomputes whether playback should be suspended for a system reason.
    func applyPauseRules() {
        var suspend = false
        if settings.pauseWhenScreenLocked && monitor.isScreenLocked { suspend = true }
        if settings.pauseWhenDisplayAsleep && monitor.isDisplayAsleep { suspend = true }
        if settings.pauseOnLowPowerMode && monitor.isLowPowerMode { suspend = true }
        if settings.pauseOnBattery && monitor.isOnBattery { suspend = true }
        engine.setSystemSuspended(suspend)
    }

    // MARK: - Applying

    /// Applies a wallpaper to every display.
    func applyToAll(_ wallpaper: Wallpaper) {
        let ids = displays.filter { !$0.isMirrored }.map(\.id)
        Task {
            await engine.apply(wallpaper: wallpaper, to: ids)
            settings.perDisplayWallpapers = [:]
            settings.defaultWallpaperID = wallpaper.id
            library.markUsed(wallpaper)
        }
    }

    /// Applies a wallpaper to a single display.
    func apply(to displayID: CGDirectDisplayID, wallpaper: Wallpaper) {
        Task {
            await engine.apply(wallpaper: wallpaper, to: [displayID])
            settings.perDisplayWallpapers[String(displayID)] = wallpaper.id
            library.markUsed(wallpaper)
        }
    }

    /// The wallpaper currently assigned to a display.
    func wallpaper(for displayID: CGDirectDisplayID) -> Wallpaper? {
        let key = String(displayID)
        let id = settings.perDisplayWallpapers[key] ?? settings.defaultWallpaperID
        return library.wallpaper(id: id)
    }

    /// Removes the wallpaper from a display.
    func clear(displayID: CGDirectDisplayID) {
        engine.stop(displayIDs: [displayID])
        settings.perDisplayWallpapers.removeValue(forKey: String(displayID))
    }

    func restoreWallpapers() async {
        await engine.restoreAssignments()
    }

    // MARK: - Library

    func importFiles(_ urls: [URL]) {
        Task {
            let added = await library.importFiles(urls)
            if !added.isEmpty {
                statusMessage = "Added \(added.count) wallpaper\(added.count == 1 ? "" : "s")"
                clearStatusLater()
            }
        }
    }

    func importFolder(_ url: URL) {
        Task {
            let added = await library.importFolder(url)
            if !added.isEmpty {
                statusMessage = "Added \(added.count) item\(added.count == 1 ? "" : "s") from \(url.lastPathComponent)"
                clearStatusLater()
            }
            if !settings.watchedFolders.contains(url) {
                settings.watchedFolders.append(url)
            }
        }
    }

    func removeFromLibrary(_ wallpaper: Wallpaper) {
        // Only tear down the displays that were actually using this wallpaper.
        let affected = displays
            .filter { self.wallpaper(for: $0.id)?.id == wallpaper.id }
            .map(\.id)
        if !affected.isEmpty {
            engine.stop(displayIDs: affected)
        }

        library.remove(wallpaper)

        if settings.defaultWallpaperID == wallpaper.id { settings.defaultWallpaperID = nil }
        settings.perDisplayWallpapers = settings.perDisplayWallpapers.filter { $0.value != wallpaper.id }

        MediaBuilder.pruneRenditions(keeping: library.wallpapers)
    }

    private func clearStatusLater() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = nil
        }
    }

    // MARK: - Settings

    private func persistSettings() {
        settingsStore.save(settings)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        LoginItemController.setEnabled(enabled)
    }

    func clearCaches() {
        Task { await ThumbnailService.shared.clearAll() }
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: Paths.stillFrameDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? fm.removeItem(at: url) }
        statusMessage = "Caches cleared"
        clearStatusLater()
    }

    var cacheSize: String {
        let fm = FileManager.default
        var total = 0
        for directory in [Paths.thumbnailDirectory, Paths.stillFrameDirectory, Paths.renditionsDirectory] {
            let contents = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            for url in contents {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                total += size
            }
        }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }
}
