import Foundation

/// Works out how much time leaves an entry when you move some of it elsewhere.
public enum TimeMove {
    public struct Plan: Equatable {
        /// Hours to add to the destination entry.
        public let moved: Double
        /// Hours left on the source entry.
        public let remaining: Double

        /// Nothing worth keeping is left, so the source entry goes.
        public var emptiesSource: Bool { remaining < Plan.roundingSlack }

        /// Half a minute — below this the leftover is just rounding dust.
        static let roundingSlack = 0.5 / 60
    }

    /// Nil when there is nothing to move. A request larger than the entry
    /// moves the whole entry.
    public static func plan(sourceHours: Double, requested: Double) -> Plan? {
        guard requested > 0, sourceHours > 0 else { return nil }
        let moved = min(requested, sourceHours)
        let remaining = sourceHours - moved
        return Plan(
            moved: moved,
            remaining: remaining < Plan.roundingSlack ? 0 : remaining
        )
    }
}
