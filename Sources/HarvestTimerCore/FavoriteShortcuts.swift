/// Which bare key starts which favorite while the window is in front. The
/// first ten take 1–9 then 0 from their place in the row; a key a favorite
/// was given outright wins over that, and takes the key from its place too.
public enum FavoriteShortcuts {
    public static let placeKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    public static let choices = placeKeys.sorted()
        + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)

    public static func placeKey(at index: Int) -> String? {
        placeKeys.indices.contains(index) ? placeKeys[index] : nil
    }

    public static func key(for favorite: Favorite, in favorites: [Favorite]) -> String? {
        if let custom = favorite.shortcut { return custom }
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }),
              let key = placeKey(at: index) else { return nil }
        return favorites.contains { $0.shortcut == key } ? nil : key
    }

    public static func favorite(forKey key: String, in favorites: [Favorite]) -> Favorite? {
        let key = key.uppercased()
        return favorites.first { self.key(for: $0, in: favorites) == key }
    }
}
