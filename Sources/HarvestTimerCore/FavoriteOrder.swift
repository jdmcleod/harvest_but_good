import CoreGraphics

/// Where a dragged favourite chip lands, and how the chips around it slide to
/// make room.
///
/// The row is fixed pitch, so a drop index is arithmetic on the distance
/// dragged rather than hit testing. That matters: a chip is 14pt wide, and
/// asking someone to land the pointer inside a 14pt target would make
/// reordering a fight. The cost is that the view must lay the chips out at
/// exactly this width and spacing — hence the constants living here, next to
/// the sums that assume them. Variable-width chips would need `destination` to
/// become a scan of cumulative widths.
public enum FavoriteOrder {
    public static let chipWidth: CGFloat = 14
    public static let chipSpacing: CGFloat = 4

    /// One chip plus the gap after it: how far you drag to move one place.
    public static var pitch: CGFloat { chipWidth + chipSpacing }

    /// The index a chip dragged this far would land on, pinned to the row.
    /// Rounding means half a pitch of travel commits the move, so a small
    /// wobble leaves the order alone.
    public static func destination(from index: Int, translation: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let places = Int((translation / pitch).rounded())
        return min(max(index + places, 0), count - 1)
    }

    /// How far a chip that is *not* being dragged slides, so the gap opens
    /// where the dragged chip is about to land.
    public static func displacement(of index: Int, draggedFrom from: Int, to: Int) -> CGFloat {
        if index > from, index <= to { return -pitch }
        if index < from, index >= to { return pitch }
        return 0
    }

    /// The dragged chip's own offset, held inside the row. Without this a long
    /// drag parks the chip out past the "+" button while its landing index has
    /// already pinned to the end.
    public static func heldTranslation(_ translation: CGFloat, from index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let left = -pitch * CGFloat(index)
        let right = pitch * CGFloat(count - 1 - index)
        return min(max(translation, left), right)
    }

    /// The array with one element moved. An unchanged or out-of-range index
    /// gives the array back untouched, so a drag that ends where it began
    /// writes nothing — and a favourite removed mid-drag costs us the reorder
    /// rather than a crash.
    ///
    /// `to` is the element's final resting index, not an insertion point before
    /// removal: moving 0 to 2 in [A, B, C] gives [B, C, A].
    public static func moving<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return items }
        var moved = items
        moved.insert(moved.remove(at: from), at: to)
        return moved
    }
}
