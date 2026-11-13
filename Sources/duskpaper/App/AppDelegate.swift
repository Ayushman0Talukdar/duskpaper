import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?

    private var state: AppState?
    private var menuBar: MenuBarController?
    private var mainWindow: NSWindow?
    private var mainController: NSHostingController<AnyView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // The wallpaper must keep running with no windows open, so opt out of
        // macOS automatic and sudden termination for the whole process.
        ProcessInfo.processInfo.disableAutomaticTermination("duskpaper is showing a live wallpaper")
        ProcessInfo.processInfo.disableSuddenTermination()

        let state = AppState()
        self.state = state
        state.bootstrap()

        let menuBar = MenuBarController(state: state)
        self.menuBar = menuBar
        if state.settings.showMenuBarIcon {
            menuBar.install()
        }

        buildMainWindow()

        if !state.settings.launchMinimized {
            showMainWindow()
        }

        Log.info("duskpaper started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("duskpaper: terminating")
        state?.engine.stopAll()
        state?.engine.stopRotation()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let ev = NSAppleEventManager.shared().currentAppleEvent {
            let pid = ev.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value ?? -1
            let name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?"
            Log.info("duskpaper: quit event from pid \(pid) \(name)")
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The wallpaper keeps running in the background, so closing the window
        // should not quit the app.
        Log.info("duskpaper: last window closed, staying alive")
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - Window

    private func buildMainWindow() {
        guard let state else { return }

        let root = RootView()
            .environmentObject(state)
            .environmentObject(state.library)
            .environmentObject(state.engine)

        let controller = NSHostingController(rootView: AnyView(root))
        mainController = controller

        let window = NSWindow(contentViewController: controller)
        window.title = "duskpaper"
        window.setContentSize(NSSize(width: 1040, height: 660))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // The window chrome is drawn by SwiftUI; the title bar becomes part of
        // the glass panel, and the desktop shows through behind it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        mainWindow = window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Log.info("duskpaper: main window will close (open windows: \(NSApp.windows.count))")
    }

    func showMainWindow() {
        // The app runs as `.accessory` (menu bar app), so it never appears in
        // the Dock. Activate so the window can still take keyboard focus.
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Shows or hides the menu bar item at runtime.
    func refreshMenuBarVisibility(visible: Bool) {
        guard let menuBar else { return }
        if visible {
            menuBar.install()
        } else {
            menuBar.remove()
        }
    }
}
