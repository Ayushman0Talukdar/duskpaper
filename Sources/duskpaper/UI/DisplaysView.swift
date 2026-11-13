import SwiftUI

/// Per-display wallpaper assignment.
struct DisplaysView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    @Binding var preview: Wallpaper?
    @State private var assigning: DisplayInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Displays")
                    .font(.system(size: 22, weight: .semibold))

                Text("Choose a wallpaper for each display. Displays left on “Default” follow the wallpaper applied to all screens.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)

                ForEach(state.displays) { display in
                    DisplayRow(display: display, assigning: $assigning)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $assigning) { display in
            WallpaperPickerSheet(display: display) { wallpaper in
                state.apply(to: display.id, wallpaper: wallpaper)
            }
            .environmentObject(state)
            .environmentObject(library)
        }
    }
}

private struct DisplayRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    let display: DisplayInfo
    @Binding var assigning: DisplayInfo?

    private var assigned: Wallpaper? { state.wallpaper(for: display.id) }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 128, height: 80)
                Image(systemName: "display")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.system(size: 14, weight: .semibold))
                    if display.isMain {
                        Text("Main")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(display.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let assigned {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(assigned.displayName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                } else {
                    Text("No wallpaper assigned")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Change…") { assigning = display }
                if assigned != nil {
                    Button("Clear") {
                        state.clear(displayID: display.id)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

/// Modal list used to pick a wallpaper for a specific display.
private struct WallpaperPickerSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let display: DisplayInfo
    let onPick: (Wallpaper) -> Void

    @State private var search = ""

    private var filtered: [Wallpaper] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return library.wallpapers }
        return library.wallpapers.filter { $0.displayName.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Wallpaper for \(display.name)")
                    .font(.headline)
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(14)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("Nothing to choose from yet")
                        .foregroundStyle(.secondary)
                    Text("Add wallpapers in the Library first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { wallpaper in
                            Button {
                                onPick(wallpaper)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    ThumbnailView(wallpaper: wallpaper)
                                        .aspectRatio(16 / 9, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(wallpaper.displayName)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 700, height: 470)
    }
}
