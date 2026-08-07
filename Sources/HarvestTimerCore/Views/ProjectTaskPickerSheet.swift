import SwiftUI

struct ProjectTaskPickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionLabel: String
    var initialProjectId: Int64?
    var initialTaskId: Int64?
    /// Starting a timer can say what the time is for; editing an entry cannot,
    /// because the card already has a notes box of its own.
    var showsNotes = false
    /// Adding a favourite carries on to a second step in the same sheet, so it
    /// keeps the sheet open and dismisses itself later.
    var dismissesOnConfirm = true
    let onConfirm: (ProjectAssignment, NamedRef, String) -> Void
    @State private var search = ""
    @State private var selectedAssignmentId: Int64?
    @State private var selectedTaskId: Int64?
    @State private var notes = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var notesFocused: Bool

    private var selectedAssignment: ProjectAssignment? {
        state.projectAssignments.first { $0.id == selectedAssignmentId }
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
                TaskStepView(assignment: assignment, selectedTaskId: $selectedTaskId) {
                    selectedAssignmentId = nil
                    selectedTaskId = nil
                }
                if showsNotes { notesField }
            } else {
                projectStep
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(actionLabel) { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAssignment == nil || selectedTaskId == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await state.loadProjectAssignments()
            applyInitialSelection()
        }
    }

    private var projectStep: some View {
        Group {
            TextField("Search projects or tasks…", text: $search)
                .pickerSearchFieldStyle()
                .focused($searchFocused)
                .onSubmit {
                    if let first = filteredAssignments.first { select(first) }
                }
                .onAppear { searchFocused = true }

            PickerListBox {
                ForEach(filteredAssignments, id: \.assignment.id) { match in
                    PickerRow(
                        title: match.assignment.project.name,
                        subtitle: match.subtitle,
                        isSelected: false
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
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes (optional)")
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
        }
    }

    private func applyInitialSelection() {
        guard selectedAssignmentId == nil,
              let initialProjectId,
              let assignment = state.projectAssignments.first(where: { $0.project.id == initialProjectId })
        else { return }
        selectedAssignmentId = assignment.id
        selectedTaskId = initialTaskId
    }

    private func select(_ match: ProjectSearch.Match) {
        selectedAssignmentId = match.assignment.id
        selectedTaskId = match.defaultTaskId
    }

    private var filteredAssignments: [ProjectSearch.Match] {
        ProjectSearch.matches(in: state.projectAssignments, query: search)
    }

    private func confirm() {
        guard let assignment = selectedAssignment,
              let taskId = selectedTaskId,
              let task = assignment.taskAssignments.first(where: { $0.task.id == taskId })?.task
        else { return }
        onConfirm(assignment, task, notes)
        if dismissesOnConfirm { dismiss() }
    }
}
