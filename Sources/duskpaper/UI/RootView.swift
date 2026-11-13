import SwiftUI

/// Root navigation: a sidebar with Library / Displays / Settings.
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
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: Theme.sidebarWidth, max: 260)
        } detail: {
            detail
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
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
