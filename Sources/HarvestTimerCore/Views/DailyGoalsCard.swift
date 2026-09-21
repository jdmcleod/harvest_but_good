import SwiftUI

/// The per-weekday hours goals and break allowances, as a settings card.
struct DailyGoalsCard: View {
    @Environment(AppState.self) private var state

    /// `goalSettings` is read-only from outside `AppState`, so the switch goes
    /// through the setter that saves rather than a binding into the store.
    private var isEnabled: Binding<Bool> {
        Binding(
            get: { state.goalSettings.isEnabled },
            set: { state.setGoalsEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(Color.harvest)
                    .frame(width: 24, height: 24)
                Text("Daily Pace")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if state.goalSettings.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How many hours you're aiming for each day, and the break you usually take. Breaks don't count toward the goal. They just push back when you finish.")
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
                    Text(
                        state.goalSettings.almanacEnabled
                            ? "The fallback for whenever Almanac is off or hasn't answered yet. Leave a day blank if you don't work it."
                            : "Leave a day blank if you don't work it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    AlmanacPaceSection()
                }
                .padding(.leading, 32)
            }
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

/// Almanac's suggested pace, as a source for the goal above instead of the
/// hand-set weekday hours — an experiment, not the finished feature.
private struct AlmanacPaceSection: View {
    @Environment(AppState.self) private var state

    @State private var apiKey = ""
    @State private var email = ""
    @State private var syncing = false
    @FocusState private var focused: Field?

    private enum Field { case apiKey, email }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { state.goalSettings.almanacEnabled },
            set: { state.setAlmanacEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Pace from Almanac")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("", isOn: isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(state.needsSetup)
            }
            if state.needsSetup {
                Text("Connect to Harvest above before adding Almanac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if state.goalSettings.almanacEnabled {
                TextField("Almanac API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .apiKey)
                    .onSubmit(commit)
                TextField("Email at Almanac", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .email)
                    .onSubmit(commit)
                status
            }
        }
        .onAppear(perform: load)
        .onChange(of: focused) { _, now in
            if now == nil { commit() }
        }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 8) {
            if state.almanac.isUnavailable {
                Text("Almanac didn't accept that — check the key and email.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let pace = state.almanac.pace {
                // Everything Almanac sent, while this is new enough that a
                // surprising number is more likely than not.
                Text(
                    "Pace \(Hours.formatted(pace.suggestedDailyPace))/day"
                        + " · target \(Hours.formatted(pace.target))"
                        + " · worked \(Hours.formatted(pace.worked))"
                        + " · remaining \(Hours.formatted(pace.remaining))"
                        + " · person #\(state.almanac.personId ?? "?")"
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            } else {
                Text(syncing ? "Syncing…" : "Not synced yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Saves first regardless of what's focused — clicking this
            // shouldn't depend on AppKit having noticed a field lost focus.
            Button("Sync Now", action: commit)
                .buttonStyle(.link)
                .font(.caption)
                .disabled(apiKey.isEmpty || email.isEmpty)
        }
    }

    private func load() {
        let almanac = state.credentials?.almanac
        apiKey = almanac?.apiKey ?? ""
        email = almanac?.email ?? ""
    }

    /// Saves what's in the fields, and syncs right away so the status line
    /// doesn't sit stale until the next scheduled sync. Reachable from losing
    /// focus, pressing Return, or the Sync Now button, so nothing typed here
    /// depends on AppKit deciding a field has lost focus.
    private func commit() {
        guard !apiKey.isEmpty, !email.isEmpty else {
            if apiKey.isEmpty, email.isEmpty { state.removeAlmanacCredentials() }
            return
        }
        try? state.saveAlmanacCredentials(apiKey: apiKey, email: email)
        syncing = true
        Task {
            await state.refreshAlmanac(force: true)
            syncing = false
        }
    }
}
