import CoreGraphics

public enum FavoriteOrder {
    public static let chipWidth: CGFloat = 14
    public static let chipSpacing: CGFloat = 4

    public static var pitch: CGFloat { chipWidth + chipSpacing }

    public static func destination(from index: Int, translation: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let places = Int((translation / pitch).rounded())
        return min(max(index + places, 0), count - 1)
    }

    public static func displacement(of index: Int, draggedFrom from: Int, to: Int) -> CGFloat {
        if index > from, index <= to { return -pitch }
        if index < from, index >= to { return pitch }
        return 0
    }

    public static func heldTranslation(_ translation: CGFloat, from index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let left = -pitch * CGFloat(index)
        let right = pitch * CGFloat(count - 1 - index)
        return min(max(translation, left), right)
    }

    public static func moving<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return items }
        var moved = items
        moved.insert(moved.remove(at: from), at: to)
        return moved
    }
}
