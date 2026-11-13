import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The wallpaper library: a searchable grid of the user's own media.
struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    @Binding var preview: Wallpaper?

    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var selected: Wallpaper?

    enum Filter: String, CaseIterable, Identifiable {
        case all, videos, images, favorites
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .videos: return "Videos"
            case .images: return "Images"
            case .favorites: return "Favorites"
            }
        }
    }

    private var filtered: [Wallpaper] {
        var items = library.wallpapers
        switch filter {
        case .all: break
        case .videos: items = items.filter { $0.kind == .video }
        case .images: items = items.filter { $0.kind != .video }
        case .favorites: items = items.filter(\.isFavorite)
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            items = items.filter {
                $0.displayName.lowercased().contains(query)
                    || $0.sourceURL.lastPathComponent.lowercased().contains(query)
            }
        }
        return items.sorted { $0.addedAt > $1.addedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            GlassNavBar(title: "Library") {
                FilterPills(selection: $filter)
                searchField
                addButton
                moreMenu
            }
            content
        }
    }

    // MARK: - Top bar controls

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .frame(width: 150)
    }

    private var addButton: some View {
        Button(action: importFiles) {
            Label("Add", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(Theme.accent, in: Capsule())
        .buttonStyle(.plain)
        .help("Add video or image files to your library")
    }

    private var moreMenu: some View {
        Menu {
            Button("Add Folder…") { importFolder() }
            Button("Reveal Library Folder") {
                NSWorkspace.shared.open(Paths.managedMediaDirectory)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: Theme.cardSpacing)],
                    spacing: Theme.cardSpacing
                ) {
                    ForEach(filtered) { wallpaper in
                        WallpaperCard(
                            wallpaper: wallpaper,
                            isSelected: selected?.id == wallpaper.id,
                            onSelect: { selected = wallpaper },
                            onPreview: { preview = wallpaper },
                            onApply: { state.applyToAll(wallpaper) }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: library.wallpapers.isEmpty ? "sparkles.tv" : "magnifyingglass")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(library.wallpapers.isEmpty ? "Your library is empty" : "No wallpapers match")
                .font(.title3.weight(.medium))
            Text(library.wallpapers.isEmpty
                 ? "Add any video, image or GIF from your Mac to use it as a live wallpaper."
                 : "Try a different search or filter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if library.wallpapers.isEmpty {
                HStack(spacing: 10) {
                    Button("Add Files…") { importFiles() }
                        .buttonStyle(.borderedProminent)
                    Button("Add Folder…") { importFolder() }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Import

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add Wallpapers"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .image, .gif]
        if panel.runModal() == .OK {
            state.importFiles(panel.urls)
        }
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Folder"
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            state.importFolder(url)
        }
    }
}

/// The pill filter control in the library's top bar.
private struct FilterPills: View {
    @Binding var selection: LibraryView.Filter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibraryView.Filter.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            if selection == option {
                                Capsule().fill(Color.primary.opacity(0.1))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// A single tile in the library grid.
struct WallpaperCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    let wallpaper: Wallpaper
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onApply: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(wallpaper: wallpaper)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                            .strokeBorder(
                                isSelected ? Theme.accent : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 5) {
                            Badge(text: wallpaper.kind.displayName, systemImage: iconName)
                            if wallpaper.kind == .video {
                                Badge(text: formatDuration(wallpaper.duration), systemImage: "clock")
                            }
                        }
                        .padding(7)
                    }
                    .overlay {
                        if isHovering {
                            Button(action: onPreview) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(.black.opacity(0.45), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }

                Button {
                    library.toggleFavorite(wallpaper)
                } label: {
                    Image(systemName: wallpaper.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(wallpaper.isFavorite ? .yellow : .white)
                        .padding(6)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
            }
            .onHover { isHovering = $0 }

            HStack(spacing: 6) {
                Text(wallpaper.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button(action: onApply) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Apply to all displays")
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onApply)
        .contextMenu {
            Button("Apply to All Displays", action: onApply)
            Button("Preview", action: onPreview)
            Divider()
            Button(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                library.toggleFavorite(wallpaper)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([wallpaper.sourceURL])
            }
            Divider()
            Button("Remove from Library", role: .destructive) {
                state.removeFromLibrary(wallpaper)
            }
        }
    }

    private var iconName: String {
        switch wallpaper.kind {
        case .video: return "film"
        case .image: return "photo"
        case .gif: return "square.stack.3d.up"
        }
    }
}
