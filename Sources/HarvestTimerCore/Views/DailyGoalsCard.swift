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

    /// What the hand-set hours below are actually for, given the two
    /// Almanac switches — the goal itself, the base Almanac's time off
    /// scales, or the fallback for whenever Almanac has nothing to say.
    private var weekdayGoalsCaption: String {
        state.goalSettings.almanacTimeOffEnabled
            ? "The base Almanac adjusts for time off. Leave a day blank if you don't work it."
            : "Leave a day blank if you don't work it."
    }

    var body: some View {
        SettingsCard(title: "Daily Pace", systemImage: "target", isOn: isEnabled) {
            // Almanac's pace replaces the hand-set hours, so they're put away
            // rather than left looking editable. What's saved still stands
            // in for any day Almanac hasn't answered.
            if state.goalSettings.almanacPaceEnabled {
                Text("Almanac sets each day's goal. Turn its pace off below to set your own hours and breaks.")
                    .foregroundStyle(.secondary)
            } else {
                weekdayGoals
            }
            Divider()
            AlmanacPaceSection()
        }
    }

    @ViewBuilder private var weekdayGoals: some View {
        Text(
            "Hours you aim for each day and the break you usually take. Breaks push back when you finish, not the goal. "
                + weekdayGoalsCaption
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

/// Almanac's suggested pace and its time off, as two independent inputs to
/// the goal above instead of one combined switch — an experiment, not the
/// finished feature. Saved credentials fold to one line with an Edit button,
/// like the Harvest account at the top of Settings.
private struct AlmanacPaceSection: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state

    @State private var apiKey = ""
    @State private var email = ""
    @State private var editing = false
    @State private var syncing = false
    @State private var showingDetails = false
    @FocusState private var keyFocused: Bool

    private var paceEnabled: Binding<Bool> {
        Binding(
            get: { state.goalSettings.almanacPaceEnabled },
            set: { state.setAlmanacPaceEnabled($0) }
        )
    }

    private var timeOffEnabled: Binding<Bool> {
        Binding(
            get: { state.goalSettings.almanacTimeOffEnabled },
            set: { state.setAlmanacTimeOffEnabled($0) }
        )
    }

    /// Whether either switch needs Almanac connected at all.
    private var anyEnabled: Bool {
        state.goalSettings.almanacPaceEnabled || state.goalSettings.almanacTimeOffEnabled
    }

    private var saved: AlmanacCredentials? { state.credentials?.almanac }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Almanac")
                .font(.subheadline.weight(.medium))
            if state.needsSetup {
                Text("Connect to Harvest above before adding Almanac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                toggleRow("Use Almanac's suggested pace as the goal", isOn: paceEnabled)
                toggleRow("Adjust for Almanac time off", isOn: timeOffEnabled)
                if anyEnabled {
                    if let saved, !editing {
                        connection(saved)
                        details
                    } else {
                        form
                    }
                }
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func connection(_ saved: AlmanacCredentials) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.almanac.isUnavailable ? palette.danger : palette.success)
                    .frame(width: 7, height: 7)
                Text(saved.email)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Edit…") {
                    apiKey = saved.apiKey
                    email = saved.email
                    editing = true
                }
                .controlSize(.small)
                Button(action: sync) {
                    HStack(spacing: 5) {
                        if syncing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(syncing ? "Syncing…" : "Sync Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(syncing)
            }
            if state.almanac.isUnavailable {
                Text("Almanac didn't accept that — check the key and email.")
                    .font(.caption)
                    .foregroundStyle(palette.danger)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Almanac API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .focused($keyFocused)
                .onSubmit(save)
            TextField("Email at Almanac", text: $email)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                if saved != nil {
                    Button("Remove", role: .destructive) {
                        state.removeAlmanacCredentials()
                        apiKey = ""
                        email = ""
                        editing = false
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(palette.danger)
                    .font(.caption)
                }
                Spacer()
                if saved != nil {
                    Button("Cancel") { editing = false }
                        .controlSize(.small)
                }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(apiKey.isEmpty || email.isEmpty)
            }
        }
        .onAppear { if editing { keyFocused = true } }
    }

    /// What Almanac last sent, folded away under the sync row: useful when a
    /// number looks wrong, noise the rest of the time.
    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { showingDetails.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showingDetails ? 90 : 0))
                    Text(showingDetails ? "Hide details" : "Show details")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingCursor()
            if showingDetails {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if state.goalSettings.almanacTimeOffEnabled {
                        ForEach(Array(state.almanac.constraints.enumerated()), id: \.offset) { _, constraint in
                            Text(constraintDebugLine(constraint))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .textSelection(.enabled)
                .padding(.leading, 14)
            }
        }
    }

    /// Everything Almanac sent for whichever switches are on, while this is
    /// new enough that a surprising number is more likely than not.
    private var statusText: String {
        var parts: [String] = []
        if state.goalSettings.almanacPaceEnabled, let pace = state.almanac.pace {
            parts.append("pace \(Hours.formatted(pace.suggestedDailyPace))/day")
            parts.append("target \(Hours.formatted(pace.target))")
            parts.append("worked \(Hours.formatted(pace.worked))")
            parts.append("remaining \(Hours.formatted(pace.remaining))")
            parts.append("person #\(state.almanac.personId ?? "?")")
        }
        if state.goalSettings.almanacTimeOffEnabled {
            parts.append("\(state.almanac.constraints.count) time off item(s) synced")
        }
        guard !parts.isEmpty else { return "Not synced yet" }
        return parts.joined(separator: " · ")
    }

    private func constraintDebugLine(_ constraint: AlmanacConstraint) -> String {
        let times: String
        if constraint.isPartialDay, let start = constraint.startTime, let end = constraint.endTime {
            times = "\(Hours.formatted(start.hours))–\(Hours.formatted(end.hours))"
        } else {
            times = "all day"
        }
        return "\(constraint.name ?? "?"): \(constraint.startDate)–\(constraint.endDate) · \(times)"
            + " · partial=\(constraint.isPartialDay) · billableOnly=\(constraint.billableOnly)"
    }

    /// Saves what's in the fields and syncs straight away, so the details
    /// don't sit stale until the next scheduled sync.
    private func save() {
        guard !apiKey.isEmpty, !email.isEmpty else { return }
        try? state.saveAlmanacCredentials(apiKey: apiKey, email: email)
        editing = false
        sync()
    }

    private func sync() {
        syncing = true
        Task {
            await state.refreshAlmanac(force: true)
            syncing = false
        }
    }
}
