import SwiftUI
import AVFoundation
import AppKit

/// A large preview of a wallpaper with playback controls and per-display
/// assignment.
struct PreviewSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    let wallpaper: Wallpaper

    @Environment(\.dismiss) private var dismiss
    @State private var isPlaying = true
    @State private var isMuted = false
    @State private var player: AVPlayer?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            playerArea
            controls
        }
        .frame(width: 940, height: 600)
        .background(Color.black)
        .task { await prepare() }
        .onDisappear { player?.pause() }
    }

    // MARK: - Player

    private var playerArea: some View {
        ZStack {
            Color.black
            if let player {
                PreviewPlayerView(player: player)
                    .ignoresSafeArea()
            } else if let loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 22)
                }
                .buttonStyle(.borderedProminent)
                .help(isPlaying ? "Pause" : "Play")

                Button {
                    isMuted.toggle()
                    player?.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .help(isMuted ? "Unmute" : "Mute")

                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    state.applyToAll(wallpaper)
                    dismiss()
                } label: {
                    Label("Apply to All", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    ForEach(state.displays) { display in
                        Button(display.name) {
                            state.apply(to: display.id, wallpaper: wallpaper)
                            dismiss()
                        }
                    }
                } label: {
                    Label("Apply to…", systemImage: "display")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if !state.displays.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Text("Assign to:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(state.displays) { display in
                        Button {
                            state.apply(to: display.id, wallpaper: wallpaper)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isAssigned(to: display) ? "checkmark.circle.fill" : "display")
                                Text(display.name)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(isAssigned(to: display) ? Theme.accent : .secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var details: String {
        var parts: [String] = [wallpaper.kind.displayName]
        if wallpaper.kind == .video { parts.append(formatDuration(wallpaper.duration)) }
        parts.append("\(Int(wallpaper.pixelSize.width)) × \(Int(wallpaper.pixelSize.height))")
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Actions

    private func isAssigned(to display: DisplayInfo) -> Bool {
        state.wallpaper(for: display.id)?.id == wallpaper.id
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private func prepare() async {
        do {
            let url = try await MediaBuilder.playableURL(for: wallpaper, settings: state.settings)
            let item = AVPlayerItem(asset: AVURLAsset(url: url))
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = isMuted
            newPlayer.actionAtItemEnd = .none
            newPlayer.play()
            player = newPlayer
            isPlaying = true
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Hosts an `AVPlayer` inside a layer-backed view.
struct PreviewPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: PreviewLayerView, context: Context) {
        nsView.playerLayer.player = player
    }
}

final class PreviewLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer = playerLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
