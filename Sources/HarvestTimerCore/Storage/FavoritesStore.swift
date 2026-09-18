import Foundation

/// The favourite project and task pairs, in a JSON file of their own.
///
/// Losing favourites is a nuisance, not a disaster, so a failed read or write
/// is quiet: the app carries on with whatever it has.
public struct FavoritesStore {
    private let url: URL
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        self.url = directory.appendingPathComponent("favorites.json")
    }

    public func load() -> [Favorite] {
        guard let data = try? Data(contentsOf: url),
              let favorites = try? JSONDecoder().decode([Favorite].self, from: data) else {
            return []
        }
        return favorites
    }

    public func save(_ favorites: [Favorite]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
