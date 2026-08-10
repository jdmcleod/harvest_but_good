import SwiftUI

struct EntryList: View {
    @Environment(AppState.self) private var state
    @State private var showingStartTimer = false

    var body: some View {
        let entries = state.entries(forDay: state.selectedDay)
        let counts = state.startCounts(forDay: state.selectedDay)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                WeekTotalCard(title: "Week", hours: state.weekTotal)
                WeekTotalCard(title: "Billable", hours: state.weekBillableTotal)
                Spacer()
                Button {
                    showingStartTimer = true
                } label: {
                    Label("Start Timer", systemImage: "play.circle")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .tint(.harvestGreen)
                .controlSize(.small)
                .pointingCursor()
                .help("Start a timer for any project")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if entries.isEmpty {
                            Text("No entries for this day.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        } else {
                            ForEach(entries) { entry in
                                EntryCard(entry: entry, startCount: counts[entry.id] ?? 0)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 0, alignment: .top)
                }
                .onChange(of: state.selectedEntryId) { _, entryId in
                    guard let entryId else { return }
                    withAnimation {
                        proxy.scrollTo(entryId)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .sheet(isPresented: $showingStartTimer) {
            ProjectTaskPickerSheet(
                title: "Start Timer",
                actionLabel: "Start Timer",
                showsNotes: true,
                showsFavoriteToggle: true
            ) { assignment, task, notes in
                Task {
                    await state.startTimer(projectId: assignment.project.id, taskId: task.id, notes: notes)
                }
            }
        }
    }
}

private struct WeekTotalCard: View {
    let title: String
    let hours: Double

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Hours.formatted(hours))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .help("\(title) hours logged this week")
    }
}

private struct EntryCard: View {
    @Environment(AppState.self) private var state
    let entry: TimeEntry
    let startCount: Int
    @State private var notes: String
    @State private var confirmingDelete = false
    @State private var editingProjectTask = false
    @State private var movingTime = false
    @State private var editingHours = false
    @State private var hoursText = ""
    @FocusState private var notesFocused: Bool
    @FocusState private var hoursFocused: Bool

    init(entry: TimeEntry, startCount: Int) {
        self.entry = entry
        self.startCount = startCount
        _notes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.forProject(entry.project.id))
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.project.name)
                            .font(.callout.weight(.semibold))
                        Text("\(entry.client.name) · \(entry.task.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingProjectTask = true }
                    .help("Double-click to change project or task")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if editingHours {
                            TextField("0:00", text: $hoursText)
                                .textFieldStyle(.plain)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .focused($hoursFocused)
                                .onSubmit { commitHours() }
                                .onExitCommand { cancelHoursEdit() }
                                .onChange(of: hoursFocused) { _, focused in
                                    if !focused { commitHours() }
                                }
                        } else {
                            Text(Hours.formatted(state.liveHours(for: entry)))
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(entry.isRunning ? Color.harvest : .primary)
                                .onTapGesture { beginHoursEdit() }
                                .pointingCursor(!entry.isRunning)
                                .help(entry.isRunning ? "Stop the timer to edit the duration" : "Click to edit duration")
                        }
                        if startCount > 0 {
                            Text("\(startCount) start\(startCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Started \(startCount) time(s) from this app")
                        } else {
                            Text("started elsewhere")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...4)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(notesFocused ? 0.06 : 0.035))
                    )
                    .focused($notesFocused)
                    .onSubmit { save() }
                    .onChange(of: notesFocused) { _, focused in
                        if !focused { save() }
                    }
                    .onChange(of: entry.notes) { _, incoming in
                        if let adopted = NotesField.adopting(
                            incoming: incoming,
                            shown: notes,
                            isEditing: notesFocused
                        ) {
                            notes = adopted
                        }
                    }
            }

            Button {
                Task { await state.toggle(entry) }
            } label: {
                Image(systemName: entry.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(entry.isRunning ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .pointingCursor()
            .help(entry.isRunning ? "Stop timer" : "Start timer")
        }
        .onDisappear {
            if notesFocused { save() }
        }
        .padding(10)
        // The gesture rides the background so the notes field keeps its own
        // double-click, the one that selects a word.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: 10)
                    .fill(highlightColor.opacity(0.08))
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editingProjectTask = true }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    highlightColor == .clear ? AnyShapeStyle(.quaternary) : AnyShapeStyle(highlightColor),
                    lineWidth: highlightColor == .clear ? 1 : 2
                )
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move Time…", systemImage: "arrow.right.arrow.left") {
                movingTime = true
            }
            .help("Move time to another task")
            Button("Delete Entry…", systemImage: "trash", role: .destructive) {
                confirmingDelete = true
            }
        }
        .sheet(isPresented: $editingProjectTask) {
            ProjectTaskPickerSheet(
                title: "Edit Entry",
                actionLabel: "Save",
                initialProjectId: entry.project.id,
                initialTaskId: entry.task.id
            ) { assignment, task, _ in
                Task {
                    await state.updateProjectTask(entry, projectId: assignment.project.id, taskId: task.id)
                }
            }
        }
        .sheet(isPresented: $movingTime) {
            MoveTimeSheet(entry: entry)
        }
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: $confirmingDelete
        ) {
            Button("Delete", role: .destructive) {
                Task { await state.deleteEntry(entry) }
            }
        } message: {
            Text("\(entry.project.name) · \(Hours.formatted(state.liveHours(for: entry)))")
        }
    }

    private var isSelected: Bool {
        state.selectedEntryId == entry.id
    }

    private var highlightColor: Color {
        if isSelected { return .accentColor }
        if entry.isRunning { return .harvest }
        return .clear
    }

    private func save() {
        Task { await state.saveNotes(entry, notes: notes) }
    }

    private func beginHoursEdit() {
        guard !entry.isRunning else { return }
        hoursText = Hours.formatted(entry.hours)
        editingHours = true
        DispatchQueue.main.async { hoursFocused = true }
    }

    private func commitHours() {
        guard editingHours else { return }
        editingHours = false
        guard let hours = Hours.parse(hoursText),
              abs(hours - entry.hours) > 0.0001 else { return }
        Task { await state.updateHours(entry, hours: hours) }
    }

    private func cancelHoursEdit() {
        editingHours = false
        hoursFocused = false
    }
}
