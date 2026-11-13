import AppKit

// duskpaper is a menu bar app: the delegate owns the window, so the entry point is
// deliberately explicit rather than using the `@main` attribute.
MainActor.assumeIsolated {
    let arguments = CommandLine.arguments

    // Small command line switches, handy for scripting and for verifying the
    // login item without going through the UI.
    if arguments.contains("--enable-login-item") {
        LoginItemController.setEnabled(true)
        exit(LoginItemController.isEnabled ? 0 : 1)
    }
    if arguments.contains("--disable-login-item") {
        LoginItemController.setEnabled(false)
        exit(LoginItemController.isEnabled ? 1 : 0)
    }
    if arguments.contains("--status") {
        print("login item: \(LoginItemController.isEnabled ? "enabled" : "disabled")")
        exit(0)
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // Menu bar app: no Dock icon, ever. The wallpaper windows are invisible to
    // the Dock anyway, and the main window opens fine from the menu bar.
    application.setActivationPolicy(.accessory)
    application.run()
}
