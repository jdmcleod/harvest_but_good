import SwiftUI

struct WeekHeader: View {
    @Environment(AppState.self) private var state
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .pointingCursor()

            HStack(spacing: 3) {
                ForEach(state.weekDays, id: \.self) { day in
                    DayTab(day: day, openSettings: { showingSettings = true })
                }
            }

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .pointingCursor()

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1, height: 28)

            FavoriteChips()

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .pointingCursor()
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(Color.harvest.ignoresSafeArea(edges: .top))
    }

    private func shiftWeek(by weeks: Int) {
        state.selectedDay = Calendar.current.date(
            byAdding: .day,
            value: weeks * 7,
            to: state.selectedDay
        )!
        Task { await state.sync() }
    }
}

private struct DayTab: View {
    @Environment(AppState.self) private var state
    let day: Date
    let openSettings: () -> Void
    @State private var showingGoal = false

    private var isSelected: Bool {
        Calendar.current.isDate(day, inSameDayAs: state.selectedDay)
    }

    private var isToday: Bool {
        state.isToday(day)
    }

    /// Selection is the solid border; today keeps a fainter one of its own so
    /// you can still pick it out of the row after clicking another day. The two
    /// land on the same tab often enough that selection has to win outright,
    /// otherwise today would read as the dimmer of the two while selected.
    private var borderColor: Color {
        if isSelected { return .white }
        return isToday ? .white.opacity(0.35) : .clear
    }

    /// How full the day is, drawn as the tab's own border so a 56pt tab does
    /// not have to find room for a ring of its own.
    @ViewBuilder private var goalRing: some View {
        if let progress = state.goalProgress(forDay: day) {
            RoundedRectangle(cornerRadius: 8)
                .trim(from: 0, to: progress.fraction)
                .stroke(
                    progress.isMet ? Color.harvestGreen : .white,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
        }
    }

    var body: some View {
        Button {
            // The second click on a tab is the one that asks about the goal;
            // the first is still just picking the day.
            if isSelected {
                showingGoal.toggle()
            } else {
                state.selectedDay = day
            }
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(isToday ? .white : .white.opacity(0.7))
                Text(Hours.formatted(state.total(forDay: day)))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 56)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.2) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay(goalRing)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .help(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).month().day()))
        .popover(isPresented: $showingGoal, arrowEdge: .bottom) {
            GoalPopover(day: day, openSettings: {
                showingGoal = false
                openSettings()
            })
            .environment(state)
        }
    }
}

/// The figures behind a day tab's ring: the goal, what is left of it, and the
/// time the day ends if the work carries on from here.
private struct GoalPopover: View {
    @Environment(AppState.self) private var state
    let day: Date
    let openSettings: () -> Void

    private var isToday: Bool { state.isToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)

            if let progress = state.goalProgress(forDay: day) {
                figures(progress)
                if let goal = state.goal(forDay: day), goal.breakHours > 0 {
                    Divider()
                    breakSection(goal: goal, progress: progress)
                }
            } else {
                Text("No goal set for \(Weekday(day).name)s.")
                    .foregroundStyle(.secondary)
                Button("Set Goals…", action: openSettings)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }

    @ViewBuilder private func figures(_ progress: GoalProgress) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            row("Goal", Hours.formatted(progress.goalHours))
            row("Worked", Hours.formatted(progress.workedHours))
            if progress.isMet {
                row("Left", "met")
            } else {
                row("Left", Hours.formatted(progress.remainingHours))
            }
        }

        // Only today has a finish time worth naming — on any other day the
        // clock has already had its say.
        if isToday {
            if let finish = progress.finishTime(from: state.now) {
                let time = finish.formatted(date: .omitted, time: .shortened)
                Text(
                    state.runningEntry == nil
                        ? "Done at \(time), if you start now"
                        : "Work until \(time)"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.harvest)
            } else {
                Text("Goal met for today.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.harvestGreen)
            }
        }
    }

    @ViewBuilder private func breakSection(goal: DayGoal, progress: GoalProgress) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            row("Break", Hours.formatted(goal.breakHours))
            row("Taken", Hours.formatted(progress.breakTakenHours))
        }
        if isToday {
            Toggle(
                "Skip today's break",
                isOn: Binding(
                    get: { state.isBreakSkipped(forDay: day) },
                    set: { _ in state.toggleBreakSkip(forDay: day) }
                )
            )
            .toggleStyle(.checkbox)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
        }
    }
}
