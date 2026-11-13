import SwiftUI

/// Root chrome: a single continuous glass panel holding the sidebar and the
/// active tab, floating on a frosted view of the desktop.
///
/// The sidebar, the top bar and the content share one surface; only a hairline
/// separates the sidebar from the content. Tab views draw no background of
/// their own so the panel's material stays visible through them.
struct RootView: View {
    @EnvironmentObject private var state: AppState

    enum Tab: String, CaseIterable, Identifiable {
        case library
        case displays
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .library: return "Library"
            case .displays: return "Displays"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .library: return "square.grid.2x2"
            case .displays: return "display"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var selection: Tab = .library
    @State private var preview: Wallpaper?

    var body: some View {
        ZStack {
            UnderWindowGlass()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                Sidebar(selection: $selection)
                    .frame(width: Theme.sidebarWidth)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 4)
            .padding([.horizontal, .bottom], 8)
        }
        .sheet(item: $preview) { wallpaper in
            PreviewSheet(wallpaper: wallpaper)
                .environmentObject(state)
                .environmentObject(state.library)
        }
        .overlay(alignment: .bottom) {
            if let message = state.statusMessage {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25)))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.statusMessage)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .library:
            LibraryView(preview: $preview)
        case .displays:
            DisplaysView(preview: $preview)
        case .settings:
            SettingsView()
        }
    }
}

/// The left column: app name and navigation. Sits directly on the panel
/// material, so it reads as part of the top bar rather than a separate box.
private struct Sidebar: View {
    @Binding var selection: RootView.Tab
    @State private var hovered: RootView.Tab?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("duskpaper")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 12)

            ForEach(RootView.Tab.allCases) { tab in
                row(tab)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func row(_ tab: RootView.Tab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tab.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
            Text(tab.title)
                .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovered == tab && selection != tab ? 0.04 : 0))
        }
        .overlay {
            if selection == tab {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? tab : nil }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { selection = tab }
        }
    }
}

/// Frosted view of the desktop behind the window. The glass base that the
/// panel and every material inside it sit on.
struct UnderWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
