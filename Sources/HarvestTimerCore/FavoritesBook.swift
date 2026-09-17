import Foundation
import Observation

/// The favourite project and task pairs, and every way of changing them.
///
/// Owns its file, so a change is saved the moment it is made and no caller has
/// to remember to write one out.
@MainActor
@Observable
public final class FavoritesBook {
    public private(set) var all: [Favorite] = []
    private let store: FavoritesStore

    public init(store: FavoritesStore) {
        self.store = store
        all = store.load()
    }

    public var isEmpty: Bool { all.isEmpty }
    public var count: Int { all.count }

    public func add(_ favorite: Favorite) {
        // Matched by id, not by every field: a project renamed in Harvest is
        // still the same favorite.
        guard !all.contains(where: { $0.id == favorite.id }) else { return }
        all.append(favorite)
        store.save(all)
    }

    public func remove(_ favorite: Favorite) {
        all.removeAll { $0.id == favorite.id }
        store.save(all)
    }

    public func contains(projectId: Int64, taskId: Int64) -> Bool {
        all.contains { $0.projectId == projectId && $0.taskId == taskId }
    }

    public func toggle(_ favorite: Favorite) {
        if all.contains(where: { $0.id == favorite.id }) {
            remove(favorite)
        } else {
            add(favorite)
        }
    }

    public func move(from: Int, to: Int) {
        let reordered = FavoriteOrder.moving(all, from: from, to: to)
        guard reordered != all else { return }
        all = reordered
        store.save(all)
    }

    public func update(_ favorite: Favorite) {
        guard let index = all.firstIndex(where: { $0.id == favorite.id }) else { return }
        guard all[index] != favorite else { return }
        all[index] = favorite
        store.save(all)
    }
}
