import SwiftUI

struct ProjectTaskPickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionLabel: String
    var initialProjectId: Int64?
    var initialTaskId: Int64?
    let onConfirm: (ProjectAssignment, NamedRef) -> Void
    @State private var search = ""
    @State private var selectedAssignmentId: Int64?
    @State private var selectedTaskId: Int64?
    @FocusState private var searchFocused: Bool

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
                taskStep(for: assignment)
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
                .textFieldStyle(.roundedBorder)
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

    private func taskStep(for assignment: ProjectAssignment) -> some View {
        Group {
            HStack(spacing: 8) {
                Button {
                    selectedAssignmentId = nil
                    selectedTaskId = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    Text(assignment.project.name)
                        .font(.callout.weight(.semibold))
                    Text(assignment.client.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PickerListBox {
                ForEach(assignment.taskAssignments, id: \.task.id) { taskAssignment in
                    PickerRow(
                        title: taskAssignment.task.name,
                        subtitle: nil,
                        isSelected: taskAssignment.task.id == selectedTaskId
                    ) {
                        selectedTaskId = taskAssignment.task.id
                    }
                }
                if assignment.taskAssignments.isEmpty {
                    Text("No tasks on this project")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
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
        // One matching task means the search already said which one they want.
        if match.matchedTasks.count == 1 {
            selectedTaskId = match.matchedTasks[0].id
            return
        }
        selectedTaskId = match.assignment.taskAssignments.first {
            $0.task.name.caseInsensitiveCompare("Development") == .orderedSame
        }?.task.id
    }

    private var filteredAssignments: [ProjectSearch.Match] {
        ProjectSearch.matches(in: state.projectAssignments, query: search)
    }

    private func confirm() {
        guard let assignment = selectedAssignment,
              let taskId = selectedTaskId,
              let task = assignment.taskAssignments.first(where: { $0.task.id == taskId })?.task
        else { return }
        onConfirm(assignment, task)
        dismiss()
    }
}
