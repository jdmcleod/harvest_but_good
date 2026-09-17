import Foundation

/// A budget and what has been spent against it, in hours or in money. Both
/// the project-wide report row and a single task's budget end up here, so the
/// card draws them the same way.
public struct BudgetLine: Equatable {
    public let isMonetary: Bool
    public let budget: Double
    public let spent: Double

    public init?(isMonetary: Bool, budget: Double?, spent: Double?) {
        guard let budget, budget > 0 else { return nil }
        self.isMonetary = isMonetary
        self.budget = budget
        self.spent = spent ?? 0
    }

    public var remaining: Double { budget - spent }

    /// The card line: "Budget remaining: $4.2k (42%)", "Budget remaining:
    /// 12.5h (31%)", or "Over budget by $500" once it is spent.
    public var summary: String {
        if remaining < 0 { return "Over budget by \(compact(-remaining))" }
        return "Budget remaining: \(compact(remaining)) (\(Int((remaining / budget * 100).rounded()))%)"
    }

    /// "12.5h left of 40h", "$4,200 left of $10,000", or the "over" versions
    /// once the budget is spent.
    public var detail: String {
        if remaining < 0 {
            return "\(amount(-remaining)) over the \(amount(budget)) budget"
        }
        return "\(amount(remaining)) left of \(amount(budget))"
    }

    private func compact(_ value: Double) -> String {
        guard isMonetary else { return amount(value) }
        if value >= 1000 {
            let thousands = (value / 100).rounded() / 10
            let text = thousands == thousands.rounded()
                ? String(format: "%.0f", thousands)
                : String(format: "%.1f", thousands)
            return "$\(text)k"
        }
        return "$\(Int(value.rounded()))"
    }

    private func amount(_ value: Double) -> String {
        if isMonetary {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.locale = Locale(identifier: "en_US")
            return "$" + (formatter.string(from: NSNumber(value: value)) ?? String(Int(value)))
        }
        let rounded = (value * 10).rounded() / 10
        return String(format: rounded == rounded.rounded() ? "%.0fh" : "%.1fh", rounded)
    }
}
