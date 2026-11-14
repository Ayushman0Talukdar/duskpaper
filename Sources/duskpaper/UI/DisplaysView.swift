import SwiftUI

/// Per-display wallpaper assignment and visual adjustments.
struct DisplaysView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    @Binding var preview: Wallpaper?
    @State private var assigning: DisplayInfo?

    var body: some View {
        VStack(spacing: 0) {
            GlassNavBar(title: "Displays")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose a wallpaper for each display and tune its colour, tone and scaling. Displays left on “Default” follow the wallpaper applied to all screens.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 560, alignment: .leading)

                    ForEach(state.displays) { display in
                        DisplayCard(display: display, assigning: $assigning)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $assigning) { display in
            WallpaperPickerSheet(display: display) { wallpaper in
                state.apply(to: display.id, wallpaper: wallpaper)
            }
            .environmentObject(state)
            .environmentObject(library)
        }
    }
}

/// One display: assignment, live colour/tone adjustments and scaling.
private struct DisplayCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: LibraryStore

    let display: DisplayInfo
    @Binding var assigning: DisplayInfo?

    private var assigned: Wallpaper? { state.wallpaper(for: display.id) }

    /// Two-way binding for a single adjustment field on this display.
    private func adjBinding(_ keyPath: WritableKeyPath<DisplayAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { state.settings.adjustments(for: display.id)[keyPath: keyPath] },
            set: { var a = state.settings.adjustments(for: display.id); a[keyPath: keyPath] = $0; state.setAdjustments(a, for: display.id) }
        )
    }

    private var contrastBinding: Binding<Double> { adjBinding(\.contrast) }
    private var brightnessBinding: Binding<Double> { adjBinding(\.brightness) }
    private var saturationBinding: Binding<Double> { adjBinding(\.saturation) }
    private var warmthBinding: Binding<Double> { adjBinding(\.warmth) }
    private var hueBinding: Binding<Double> { adjBinding(\.hue) }
    private var gammaBinding: Binding<Double> { adjBinding(\.gamma) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 128, height: 80)
                    if let assigned {
                        ThumbnailView(wallpaper: assigned)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 128, height: 80)
                            .clipped()
                            .cornerRadius(10)
                    } else {
                        Image(systemName: "display")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.secondary)
                    }
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

            Divider().padding(.leading, 14).padding(.trailing, 14)

            VStack(alignment: .leading, spacing: 12) {
                // Presets -------------------------------------------------
                HStack(spacing: 8) {
                    Text("Look")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(AdjustmentPreset.allCases) { preset in
                        PresetButton(preset: preset, display: display)
                    }
                    Spacer(minLength: 0)
                }

                // Sliders -------------------------------------------------
                VStack(alignment: .leading, spacing: 10) {
                    adjustmentSlider(
                        title: "Contrast",
                        value: contrastBinding,
                        in: 0.5...1.5,
                        formatter: { String(format: "%.0f%%", $0 * 100) }
                    )
                    adjustmentSlider(
                        title: "Brightness",
                        value: brightnessBinding,
                        in: -0.5...0.5,
                        formatter: { String(format: "%+.0f%%", $0 * 100) }
                    )
                    adjustmentSlider(
                        title: "Saturation",
                        value: saturationBinding,
                        in: 0...2,
                        formatter: { String(format: "%.0f%%", $0 * 100) }
                    )
                    adjustmentSlider(
                        title: "Warmth",
                        value: warmthBinding,
                        in: -1...1,
                        formatter: { String(format: "%+.0f", $0) }
                    )
                    adjustmentSlider(
                        title: "Hue",
                        value: hueBinding,
                        in: -180...180,
                        formatter: { String(format: "%.0f°", $0) }
                    )
                    adjustmentSlider(
                        title: "Gamma",
                        value: gammaBinding,
                        in: 0.5...1.5,
                        formatter: { String(format: "%.0f%%", $0 * 100) }
                    )
                }

                // Scaling + reset -----------------------------------------
                HStack(spacing: 12) {
                    Text("Scaling")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScalingPicker(display: display)

                    Spacer(minLength: 0)

                    Button("Reset") {
                        state.resetAdjustments(for: display.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.settings.adjustments(for: display.id).isDefault ? Color.secondary : Color.red)
                    .disabled(state.settings.adjustments(for: display.id).isDefault)
                }
            }
            .padding(14)
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCornerRadius).strokeBorder(Color.primary.opacity(0.08)))
    }


    private func adjustmentSlider(
        title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        formatter: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatter(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 44, alignment: .trailing)
            }
            Slider(value: value, in: range, step: sliderStep(for: range))
        }
    }

    private func sliderStep(for range: ClosedRange<Double>) -> Double {
        (range.upperBound - range.lowerBound) / 200
    }

}

/// A single preset pill that applies a look to one display.
private struct PresetButton: View {
    @EnvironmentObject private var state: AppState
    let preset: AdjustmentPreset
    let display: DisplayInfo

    var body: some View {
        Button(preset.displayName) {
            let current = state.settings.adjustments(for: display.id)
            let next = preset.applying(keepingGravity: current.gravity)
            state.setAdjustments(next, for: display.id)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            presetMatches ? Theme.accent.opacity(0.2) : Color.primary.opacity(0.06),
            in: Capsule()
        )
        .foregroundStyle(presetMatches ? Theme.accent : .primary)
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var presetMatches: Bool {
        preset.matches(state.settings.adjustments(for: display.id))
    }
}

/// Segmented per-display scaling picker.
private struct ScalingPicker: View {
    @EnvironmentObject private var state: AppState
    let display: DisplayInfo

    private var currentGravity: VideoGravity {
        state.settings.effectiveGravity(for: display.id)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(VideoGravity.allCases, id: \.self) { gravity in
                Button(gravity.displayName) {
                    var a = state.settings.adjustments(for: display.id)
                    a.gravity = gravity
                    state.setAdjustments(a, for: display.id)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    currentGravity == gravity ? Theme.accent : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(currentGravity == gravity ? .white : .primary)
            }
        }
        .frame(width: 300)
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
