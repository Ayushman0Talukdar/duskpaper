import SwiftUI

/// Shared colours and small visual helpers used across the UI.
enum Theme {
    static let accent = Color(red: 0.55, green: 0.42, blue: 0.98)

    static let cardCornerRadius: CGFloat = 12
    static let cardSpacing: CGFloat = 14
    static let sidebarWidth: CGFloat = 208
}

/// The top bar of a tab. It draws no background of its own, so the sidebar,
/// the bar and the content below all read as one continuous glass panel.
struct GlassNavBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 12)
            trailing
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
    }
}

/// A small capsule used for media-type and duration badges.
struct Badge: View {
    let text: String
    var systemImage: String?
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.16), in: Capsule())
    }
}

/// Loads and shows a wallpaper thumbnail, with a placeholder while it renders.
struct ThumbnailView: View {
    let wallpaper: Wallpaper
    var cornerRadius: CGFloat = Theme.cardCornerRadius

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color.secondary.opacity(0.18), Color.secondary.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipped()
        .cornerRadius(cornerRadius)
        .task(id: wallpaper.id) {
            image = await ThumbnailService.shared.thumbnail(for: wallpaper)
        }
    }
}

/// Formats a duration as `m:ss`.
func formatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "--" }
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let remainder = total % 60
    if minutes >= 60 {
        return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, remainder)
    }
    return String(format: "%d:%02d", minutes, remainder)
}
