import SwiftUI
import AppKit

/// All user-facing preferences.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Form {
            Section("Playback") {
                Picker("Scaling", selection: $state.settings.gravity) {
                    ForEach(VideoGravity.allCases, id: \.self) { gravity in
                        Text(gravity.displayName).tag(gravity)
                    }
                }

                Picker("Speed", selection: $state.settings.playbackSpeed) {
                    Text("0.5×").tag(0.5)
                    Text("0.75×").tag(0.75)
                    Text("1×").tag(1.0)
                    Text("1.5×").tag(1.5)
                    Text("2×").tag(2.0)
                }

                Toggle("Mute wallpaper audio", isOn: $state.settings.isMuted)

                if !state.settings.isMuted {
                    HStack {
                        Text("Volume")
                        Slider(value: $state.settings.volume, in: 0...1)
                        Text("\(Int(state.settings.volume * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Energy") {
                Toggle("Pause when the screen is locked", isOn: $state.settings.pauseWhenScreenLocked)
                Toggle("Pause when the display goes to sleep", isOn: $state.settings.pauseWhenDisplayAsleep)
                Toggle("Pause in Low Power Mode", isOn: $state.settings.pauseOnLowPowerMode)
                Toggle("Pause when running on battery", isOn: $state.settings.pauseOnBattery)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.settings.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Toggle("Show the menu bar icon", isOn: $state.settings.showMenuBarIcon)
                    .onChange(of: state.settings.showMenuBarIcon) { _, newValue in
                        AppDelegate.shared?.refreshMenuBarVisibility(visible: newValue)
                    }
                Toggle("Start minimised", isOn: $state.settings.launchMinimized)
            }

            Section("Rotation") {
                Toggle("Rotate wallpapers automatically", isOn: $state.settings.rotationEnabled)
                    .onChange(of: state.settings.rotationEnabled) { _, enabled in
                        if enabled {
                            state.engine.startRotation()
                        } else {
                            state.engine.stopRotation()
                        }
                    }

                if state.settings.rotationEnabled {
                    Picker("Every", selection: $state.settings.rotationIntervalMinutes) {
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("3 hours").tag(180)
                    }

                    Picker("Order", selection: $state.settings.rotationMode) {
                        ForEach(RotationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
            }

            Section("Still images") {
                HStack {
                    Text("Motion loop length")
                    Slider(value: $state.settings.stillDurationSeconds, in: 4...30, step: 1)
                    Text("\(Int(state.settings.stillDurationSeconds))s")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text("Zoom amount")
                    Slider(value: $state.settings.stillZoomAmount, in: 0...0.5, step: 0.02)
                    Text("\(Int(state.settings.stillZoomAmount * 100))%")
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }

                Text("Still images are turned into a slow looping video so they animate like a live wallpaper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Library") {
                LabeledContent("Wallpapers", value: "\(library.wallpapers.count)")
                LabeledContent("Cache size", value: state.cacheSize)

                if !state.settings.watchedFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watched folders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(state.settings.watchedFolders, id: \.self) { folder in
                            HStack {
                                Text(folder.path)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Spacer()
                                Button {
                                    state.settings.watchedFolders.removeAll { $0 == folder }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("Reveal Library Folder") {
                        NSWorkspace.shared.open(Paths.managedMediaDirectory)
                    }
                    Button("Clear Caches") {
                        state.clearCaches()
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Text("duskpaper is free and open source. It has no accounts, no telemetry and no network access — your wallpapers never leave your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
