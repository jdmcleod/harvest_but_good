import Foundation

enum ListCursor {
    /// Where an arrow key lands. With nothing picked yet it takes the end the
    /// key points away from; at either end it stays put rather than wrapping.
    static func moved<ID: Equatable>(from current: ID?, by step: Int, in items: [ID]) -> ID? {
        guard !items.isEmpty else { return nil }
        guard let current, let index = items.firstIndex(of: current) else {
            return step > 0 ? items.first : items.last
        }
        let next = index + step
        guard items.indices.contains(next) else { return current }
        return items[next]
    }
}
