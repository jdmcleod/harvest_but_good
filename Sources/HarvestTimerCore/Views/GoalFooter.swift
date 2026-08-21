import SwiftUI

/// The selected day set against its goal, at the foot of the entries list so
/// the figures sit under the entries they are measuring and stay put while the
/// list scrolls.
///
/// A day with no goal still gets a row rather than nothing, so the list above
/// does not change height as you move across the week.
struct GoalFooter: View {
    @Environment(AppState.self) private var state
    let openSettings: () -> Void

    private var day: Date { state.selectedDay }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if let progress = state.goalProgress(forDay: day) {
                bar(progress)
                figures(progress)
            } else {
                noGoal
            }
        }
    }

    private func bar(_ progress: GoalProgress) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(progress.isMet ? Color.harvestGreen : Color.harvest)
                    .frame(width: geometry.size.width * progress.fraction)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewBuilder private func figures(_ progress: GoalProgress) -> some View {
        HStack(spacing: 6) {
            Text("\(Hours.formatted(progress.workedHours)) of \(Hours.formatted(progress.goalHours))")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(progress.isMet ? "· met" : "· \(Hours.formatted(progress.remainingHours)) left")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            // Only today can be skipped — `breakSkippedOn` holds one day at a
            // time — and only today has a finish time left to move.
            if state.isToday(day) {
                if let goal = state.goal(forDay: day), goal.breakHours > 0 {
                    breakChip(goal)
                }
                Spacer()
                finish(progress)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    /// The break allowance, and the switch for waving it off. Clicking it moves
    /// the finish time sitting at the other end of the same row, which is the
    /// point of showing the two together.
    private func breakChip(_ goal: DayGoal) -> some View {
        let skipped = state.isBreakSkipped(forDay: day)
        return Button {
            state.toggleBreakSkip(forDay: day)
        } label: {
            Text("Break \(Hours.formatted(goal.breakHours))")
                .font(.caption)
                .monospacedDigit()
                .strikethrough(skipped)
                .foregroundStyle(skipped ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(skipped ? 0.02 : 0.06))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .help(
            skipped
                ? "Break skipped today — click to put it back"
                : "Click to skip today's break"
        )
    }

    @ViewBuilder private func finish(_ progress: GoalProgress) -> some View {
        if let finishAt = progress.finishTime(from: state.now) {
            let time = finishAt.formatted(date: .omitted, time: .shortened)
            Text(state.runningEntry == nil ? "Done \(time)" : "Until \(time)")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.harvest)
                .help(
                    state.runningEntry == nil
                        ? "When the day ends if you start now"
                        : "When the day ends if the timer runs on"
                )
        } else {
            Text("Goal met")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.harvestGreen)
        }
    }

    private var noGoal: some View {
        HStack(spacing: 8) {
            Text("No goal for \(Weekday(day).name)s")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Set Goals…", action: openSettings)
                .buttonStyle(.link)
                .font(.caption)
                .pointingCursor()
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
    }
}
