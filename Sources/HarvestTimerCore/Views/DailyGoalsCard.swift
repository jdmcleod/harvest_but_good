import SwiftUI

/// The per-weekday hours goals and break allowances, as a settings card.
struct DailyGoalsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(Color.harvest)
                    .frame(width: 24, height: 24)
                Text("Daily Goals")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("How long each weekday is meant to be, and how much of a break goes with it. The break is not part of the goal — it only moves the time you finish at.")
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        Text("Goal")
                        Text("Break")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(Weekday.workdays, id: \.self) { weekday in
                        GoalRow(weekday: weekday)
                    }
                }
                Text("Leave a goal blank for a day you don't track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct GoalRow: View {
    @Environment(AppState.self) private var state
    let weekday: Weekday

    @State private var goalText = ""
    @State private var breakText = ""
    @FocusState private var focused: Field?

    private enum Field { case goal, breakAllowance }

    var body: some View {
        GridRow {
            Text(weekday.shortName)
                .frame(width: 34, alignment: .leading)
            field($goalText, placeholder: "8:00", field: .goal)
            field($breakText, placeholder: "0:30", field: .breakAllowance)
        }
        .onAppear(perform: load)
        // Written back on leaving the field rather than on every keystroke,
        // so a half-typed "8:" never counts as a day with no goal.
        .onChange(of: focused) { _, now in
            if now == nil { commit() }
        }
    }

    private func field(_ text: Binding<String>, placeholder: String, field: Field) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: 64)
            .focused($focused, equals: field)
            .onSubmit(commit)
    }

    private func load() {
        let goal = state.goalSettings.days[weekday]
        goalText = goal.map { Hours.formatted($0.hours) } ?? ""
        breakText = (goal?.breakHours ?? 0) > 0 ? Hours.formatted(goal!.breakHours) : ""
    }

    private func commit() {
        state.setGoal(
            hours: Hours.parse(goalText) ?? 0,
            breakHours: Hours.parse(breakText) ?? 0,
            for: weekday
        )
        // Reads back what was stored, so "7.5" settles as "7:30".
        load()
    }
}
