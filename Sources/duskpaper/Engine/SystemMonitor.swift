import AppKit
import Combine
import IOKit.ps

/// Watches system-level events that affect wallpaper playback and tells the
/// engine when it should pause, resume or repair itself.
@MainActor
final class SystemMonitor: ObservableObject {
    /// True while the session is locked (the screen is behind the lock screen).
    @Published private(set) var isScreenLocked = false
    /// True while the displays are asleep.
    @Published private(set) var isDisplayAsleep = false
    /// True while the machine is running on battery.
    @Published private(set) var isOnBattery = false
    /// True when the system is in Low Power Mode.
    @Published private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var observers: [NSObjectProtocol] = []
    private var powerSourceTimer: Timer?
    private var lockPollTimer: Timer?

    /// Bundle identifier of the macOS login window — the lock screen.
    private static let loginWindowBundleID = "com.apple.loginwindow"

    /// Called when the lock state changes.
    var onLockStateChange: ((Bool) -> Void)?
    /// Called when the displays sleep or wake.
    var onDisplaySleepChange: ((Bool) -> Void)?
    /// Called when displays or spaces changed.
    var onDisplayChange: (() -> Void)?
    /// Called when power conditions changed.
    var onPowerChange: (() -> Void)?

    init() {
        observeNotifications()
        refreshPowerState()
        powerSourceTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPowerState() }
        }
        RunLoop.main.add(powerSourceTimer!, forMode: .common)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        powerSourceTimer?.invalidate()
        lockPollTimer?.invalidate()
    }

    // MARK: - Notifications

    private func observeNotifications() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared

        observers.append(
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    Log.debug("System: screen parameters changed")
                    self?.onDisplayChange?()
                }
            }
        )

        observers.append(
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onDisplayChange?()
                }
            }
        )

        // Display sleep / wake. This is deliberately kept separate from the
        // lock state: a display can sleep without the session being locked.
        observers.append(
            workspace.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    Log.info("System: displays slept")
                    self?.setDisplayAsleep(true)
                }
            }
        )

        observers.append(
            workspace.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    Log.info("System: displays woke")
                    self?.setDisplayAsleep(false)
                    self?.onDisplayChange?()
                }
            }
        )

        // Screen lock / unlock.
        //
        // macOS has no public notification for the lock state, and the
        // commonly cited `com.apple.screenIsLocked` distributed notification
        // is not delivered on current releases. The login window *is* the
        // lock screen, so it becomes the frontmost application when the Mac
        // locks — that is a reliable, public signal. When the screen is
        // merely unlocked and another app is focused, the frontmost
        // application is a normal app, so there is no false positive.
        observers.append(
            workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    self?.setLocked(app?.bundleIdentifier == Self.loginWindowBundleID)
                }
            }
        )

        // A slow poll as a safety net: some transitions (fast lock/unlock,
        // waking from sleep straight into the lock screen) can slip past the
        // activation notification.
        lockPollTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.setLocked(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.loginWindowBundleID)
            }
        }
        RunLoop.main.add(lockPollTimer!, forMode: .common)

        // The distributed notifications are kept as an extra signal for
        // systems where they are delivered.
        let distributed = DistributedNotificationCenter.default()
        observers.append(
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(true) }
            }
        )
        observers.append(
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(false) }
            }
        )
    }

    private func setLocked(_ locked: Bool) {
        guard isScreenLocked != locked else { return }
        isScreenLocked = locked
        Log.info("System: screen \(locked ? "locked" : "unlocked")")
        onLockStateChange?(locked)
    }

    private func setDisplayAsleep(_ asleep: Bool) {
        guard isDisplayAsleep != asleep else { return }
        isDisplayAsleep = asleep
        onDisplaySleepChange?(asleep)
    }

    // MARK: - Power

    private func refreshPowerState() {
        let previousBattery = isOnBattery
        let previousLowPower = isLowPowerMode

        isOnBattery = Self.currentPowerSourceIsBattery()
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        if previousBattery != isOnBattery || previousLowPower != isLowPowerMode {
            Log.debug("System: power state changed (battery: \(isOnBattery), low power: \(isLowPowerMode))")
            onPowerChange?()
        }
    }

    /// Detects whether the machine is currently running on battery.
    ///
    /// `IOPSGetProvidingPowerSourceType` answers the question in a single call
    /// and returns a borrowed reference, which avoids the fiddly ownership
    /// rules around the power-source array.
    private static func currentPowerSourceIsBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSInternalBatteryType
    }
}
