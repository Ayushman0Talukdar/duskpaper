import AppKit
import Combine
import SwiftUI

/// The menu bar presence: quick access to pause/resume, the next wallpaper and
/// the main window.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var state: AppState?
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles.tv",
            accessibilityDescription: "duskpaper"
        )
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        Log.info("MenuBar: status item installed")
    }

    func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let state else { return }

        let title = NSMenuItem(title: "duskpaper", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let pauseTitle = state.engine.isUserPaused ? "Resume Wallpaper" : "Pause Wallpaper"
        let pause = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let next = NSMenuItem(title: "Next Wallpaper", action: #selector(nextWallpaper), keyEquivalent: "")
        next.target = self
        next.isEnabled = !state.library.wallpapers.isEmpty
        menu.addItem(next)

        menu.addItem(.separator())

        let library = NSMenuItem(title: "Open Library", action: #selector(openLibrary), keyEquivalent: "")
        library.target = self
        menu.addItem(library)

        let open = NSMenuItem(title: "Open duskpaper", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit duskpaper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func togglePause() {
        state?.engine.setUserPaused(!(state?.engine.isUserPaused ?? false))
    }

    @objc private func nextWallpaper() {
        guard let state, !state.library.wallpapers.isEmpty else { return }
        let current = state.settings.defaultWallpaperID
        let list = state.library.wallpapers
        let index = list.firstIndex { $0.id == current } ?? -1
        let next = list[(index + 1) % list.count]
        state.applyToAll(next)
    }

    @objc private func openLibrary() {
        NSWorkspace.shared.open(Paths.managedMediaDirectory)
    }

    @objc private func openWindow() {
        AppDelegate.shared?.showMainWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
