import Foundation

/// Reads/writes `AppSettings` as JSON and keeps a copy in UserDefaults so the
/// engine can be restored early during launch.
final class SettingsStore {
    private let url: URL

    init(url: URL = Paths.settingsFile) {
        self.url = url
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            Log.info("Settings: no stored settings, using defaults")
            return .default
        }
        return decoded
    }

    func save(_ settings: AppSettings) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Settings: failed to save — \(error.localizedDescription)")
        }
    }
}
