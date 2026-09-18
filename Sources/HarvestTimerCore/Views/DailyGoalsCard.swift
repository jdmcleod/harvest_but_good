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
        SettingsCard(title: "Daily Pace", systemImage: "target", isOn: isEnabled) {
            Text(
                "Hours you aim for each day and the break you usually take. Breaks push back when you finish, not the goal. "
                    + (state.goalSettings.almanacEnabled
                        ? "The fallback for whenever Almanac is off or hasn't answered yet. Leave a day blank if you don't work it."
                        : "Leave a day blank if you don't work it.")
            )
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(Weekday.workdays, id: \.self) { weekday in
                        Text(weekday.shortName.uppercased())
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.center)
                    }
                }
                ForEach(GoalField.Kind.allCases, id: \.self) { kind in
                    GridRow {
                        Text(kind.label)
                            .foregroundStyle(.secondary)
                        ForEach(Weekday.workdays, id: \.self) { weekday in
                            GoalField(weekday: weekday, kind: kind)
                        }
                    }
                }
            }
            Divider()
            AlmanacPaceSection()
        }
    }
}

/// One day's goal or break. Written back on leaving the field rather than on
/// every keystroke, so a half-typed "8:" never counts as a day with no goal.
private struct GoalField: View {
    enum Kind: CaseIterable {
        case goal, breakAllowance

        var label: String { self == .goal ? "Goal" : "Break" }
        var placeholder: String { self == .goal ? "8:00" : "0:30" }
    }

    @Environment(AppState.self) private var state
    let weekday: Weekday
    let kind: Kind

    @State private var text = ""
    @FocusState private var focused: Bool

    private var stored: DayGoal? { state.goalSettings.days[weekday] }

    var body: some View {
        TextField(kind.placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 56)
            .focused($focused)
            .onSubmit(commit)
            .onAppear(perform: load)
            .onChange(of: focused) { _, now in
                if !now { commit() }
            }
            // Clearing a day's goal clears its break too, so the field
            // beside this one follows whatever was stored.
            .onChange(of: stored) { _, _ in
                if !focused { load() }
            }
    }

    private func load() {
        switch kind {
        case .goal:
            text = stored.map { Hours.formatted($0.hours) } ?? ""
        case .breakAllowance:
            let breakHours = stored?.breakHours ?? 0
            text = breakHours > 0 ? Hours.formatted(breakHours) : ""
        }
    }

    private func commit() {
        let typed = Hours.parse(text) ?? 0
        state.setGoal(
            hours: kind == .goal ? typed : stored?.hours ?? 0,
            breakHours: kind == .breakAllowance ? typed : stored?.breakHours ?? 0,
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
                TextField("Email at Almanac", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .email)
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
                Text("Pace \(Hours.formatted(pace.suggestedDailyPace))/day")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(syncing ? "Syncing…" : "Not synced yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sync Now") {
                syncing = true
                Task {
                    await state.refreshAlmanac(force: true)
                    syncing = false
                }
            }
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

    private func commit() {
        guard !apiKey.isEmpty, !email.isEmpty else {
            if apiKey.isEmpty, email.isEmpty { state.removeAlmanacCredentials() }
            return
        }
        try? state.saveAlmanacCredentials(apiKey: apiKey, email: email)
        Task { await state.refreshAlmanac(force: true) }
    }
}
