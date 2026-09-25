import SwiftUI

/// The selected day set against its goal, at the foot of the entries list so
/// the figures sit under the entries they are measuring and stay put while the
/// list scrolls.
///
/// A day with no goal still gets a row rather than nothing, so the list above
/// does not change height as you move across the week.
struct GoalFooter: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    let openSettings: () -> Void

    private var day: Date { state.selectedDay }

    // The divider lives inside, so switching goals off takes the separator
    // with the rest of the footer and the list above keeps its own edge.
    @ViewBuilder var body: some View {
        if state.goalSettings.isEnabled {
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
    }

    private func bar(_ progress: GoalProgress) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.track)
                Capsule()
                    .fill(palette.accent)
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
            // Names whichever Almanac time off scaled the goal below its
            // usual number, so it doesn't just look like the app miscounted.
            if let reason = state.timeOffReason(forDay: day) {
                Text("· \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                        .strokeBorder(palette.outline, lineWidth: 1)
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
                .foregroundStyle(palette.accent)
                .help(
                    state.runningEntry == nil
                        ? "When the day ends if you start now"
                        : "When the day ends if the timer runs on"
                )
        } else {
            Text("Pace met")
                .font(.callout.weight(.medium))
                .foregroundStyle(palette.accent)
        }
    }

    private var noGoal: some View {
        HStack(spacing: 8) {
            // A day fully off reads as "no goal" the same way an unset
            // weekday does — there is nothing left to work toward — but it
            // deserves its own words rather than looking like a gap.
            if let reason = state.timeOffReason(forDay: day) {
                Text("Day off · \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No goal for \(Weekday(day).name)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Set Goals…", action: openSettings)
                    .buttonStyle(.link)
                    .font(.caption)
                    .pointingCursor()
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
    }
}
