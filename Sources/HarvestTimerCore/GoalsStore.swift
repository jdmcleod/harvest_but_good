import Foundation

/// The per-weekday hours goals and break allowances, in a JSON file of their own.
///
/// Losing a goal is a nuisance, not a disaster, so a failed read or write is
/// quiet: the app carries on with whatever it has.
public struct GoalsStore {
    private let url: URL
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        self.url = directory.appendingPathComponent("goals.json")
    }

    public func load() -> GoalSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(GoalSettings.self, from: data) else {
            return GoalSettings()
        }
        return settings
    }

    public func save(_ settings: GoalSettings) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
