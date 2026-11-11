import SwiftUI

struct ProjectTaskPickerSheet: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @Environment(WindowCommands.self) private var commands
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionLabel: String
    var initialProjectId: Int64?
    var initialTaskId: Int64?
    /// Starting a timer can say what the time is for; editing an entry cannot,
    /// because the card already has a notes box of its own.
    var showsNotes = false
    var showsFavoriteToggle = false
    var dismissesOnConfirm = true
    let onConfirm: (ProjectAssignment, NamedRef, String) -> Void
    @State private var search = ""
    @State private var selectedAssignmentId: Int64?
    @State private var selectedTaskId: Int64?
    @State private var notes = ""
    @State private var highlightedAssignmentId: Int64?
    /// Return can reach both the notes box and the default button, and one
    /// press must not start two timers.
    @State private var confirmed = false
    @FocusState private var searchFocused: Bool
    @FocusState private var notesFocused: Bool

    private var selectedAssignment: ProjectAssignment? {
        state.projectAssignments.first { $0.id == selectedAssignmentId }
    }

    private var selectedTask: NamedRef? {
        guard let taskId = selectedTaskId else { return nil }
        return selectedAssignment?.taskAssignments.first { $0.task.id == taskId }?.task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

            if state.projectAssignments.isEmpty {
                ProgressView("Loading projects…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if let assignment = selectedAssignment {
                TaskStepView(
                    assignment: assignment,
                    selectedTaskId: $selectedTaskId,
                    onBack: {
                        selectedAssignmentId = nil
                        selectedTaskId = nil
                    },
                    takesFocus: !showsNotes
                )
                if showsNotes { notesField }
            } else {
                projectStep
            }

            HStack {
                if showsFavoriteToggle, let assignment = selectedAssignment, let task = selectedTask {
                    favoriteToggle(assignment: assignment, task: task)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) { confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedAssignment == nil || selectedTaskId == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await state.loadProjectAssignments(force: true)
            applyInitialSelection()
        }
        .onDisappear { commands.backStep = nil }
        .onChange(of: selectedAssignmentId) { _, id in
            commands.backStep = id == nil ? nil : {
                selectedAssignmentId = nil
                selectedTaskId = nil
            }
        }
    }

    private var projectStep: some View {
        Group {
            TextField("Search projects or tasks…", text: $search)
                .pickerSearchFieldStyle()
                .focused($searchFocused)
                .onSubmit {
                    if let match = highlightedMatch ?? filteredAssignments.first { select(match) }
                }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onAppear { searchFocused = true }

            ScrollViewReader { list in
                PickerListBox {
                    ForEach(filteredAssignments, id: \.assignment.id) { match in
                        PickerRow(
                            title: match.assignment.project.name,
                            subtitle: match.subtitle,
                            isSelected: match.assignment.id == highlightedAssignmentId
                        ) {
                            select(match)
                        }
                    }
                    if filteredAssignments.isEmpty {
                        Text("No projects match “\(search)”")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
                .onChange(of: highlightedAssignmentId) { _, id in
                    if let id { list.scrollTo(id) }
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes (optional) · ↩ starts · ↑↓ change the task")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .onSubmit { confirm() }
                // Straight to the notes once the project is picked: the task
                // usually comes with it, and ↑↓ here still change it. A beat
                // late, so the search field it replaces has let go first.
                .task {
                    try? await Task.sleep(for: .milliseconds(80))
                    notesFocused = true
                }
                .onKeyPress(.upArrow) { moveTask(by: -1) }
                .onKeyPress(.downArrow) { moveTask(by: 1) }
        }
    }

    private func moveTask(by step: Int) -> KeyPress.Result {
        guard !notes.contains("\n"), let assignment = selectedAssignment else { return .ignored }
        let ids = assignment.taskAssignments.map(\.task.id)
        selectedTaskId = ListCursor.moved(from: selectedTaskId, by: step, in: ids) ?? selectedTaskId
        return .handled
    }

    private func applyInitialSelection() {
        guard selectedAssignmentId == nil,
              let initialProjectId,
              let assignment = state.projectAssignments.first(where: { $0.project.id == initialProjectId })
        else { return }
        selectedAssignmentId = assignment.id
        selectedTaskId = initialTaskId
    }

    private var highlightedMatch: ProjectSearch.Match? {
        filteredAssignments.first { $0.assignment.id == highlightedAssignmentId }
    }

    private func moveHighlight(by step: Int) -> KeyPress.Result {
        highlightedAssignmentId = ListCursor.moved(
            from: highlightedAssignmentId,
            by: step,
            in: filteredAssignments.map(\.assignment.id)
        )
        return .handled
    }

    private func select(_ match: ProjectSearch.Match) {
        selectedAssignmentId = match.assignment.id
        selectedTaskId = match.defaultTaskId
    }

    private var filteredAssignments: [ProjectSearch.Match] {
        ProjectSearch.matches(in: state.projectAssignments, query: search)
    }

    private func favoriteToggle(assignment: ProjectAssignment, task: NamedRef) -> some View {
        let isFavorite = state.isFavorite(projectId: assignment.project.id, taskId: task.id)
        return Button {
            state.toggleFavorite(Favorite(
                projectId: assignment.project.id,
                taskId: task.id,
                clientName: assignment.client.name,
                projectName: assignment.project.name,
                taskName: task.name
            ))
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? palette.favorite : Color.secondary)
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .help(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func confirm() {
        guard !confirmed, let assignment = selectedAssignment, let task = selectedTask else { return }
        confirmed = dismissesOnConfirm
        onConfirm(assignment, task, notes)
        if dismissesOnConfirm { dismiss() }
    }
}
