import SwiftUI

struct ProjectTaskPickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionLabel: String
    let initialProjectId: Int64?
    let initialTaskId: Int64?
    let onConfirm: (ProjectAssignment, ProjectAssignment.TaskAssignment.Task) -> Void
    @State private var search = ""
    @State private var selectedAssignmentId: Int64?
    @State private var selectedTaskId: Int64?
    @FocusState private var searchFocused: Bool

    init(
        title: String,
        actionLabel: String,
        initialProjectId: Int64? = nil,
        initialTaskId: Int64? = nil,
        onConfirm: @escaping (ProjectAssignment, ProjectAssignment.TaskAssignment.Task) -> Void
    ) {
        self.title = title
        self.actionLabel = actionLabel
        self.initialProjectId = initialProjectId
        self.initialTaskId = initialTaskId
        self.onConfirm = onConfirm
    }

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
            TextField("Search projects…", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit {
                    if let first = filteredAssignments.first { select(first) }
                }
                .onAppear { searchFocused = true }

            listContainer {
                ForEach(filteredAssignments, id: \.id) { assignment in
                    PickerRow(
                        title: assignment.project.name,
                        subtitle: assignment.client.name,
                        isSelected: false
                    ) {
                        select(assignment)
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

            listContainer {
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

    private func listContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                content()
            }
            .padding(4)
        }
        .frame(height: 220)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
        )
    }

    private func applyInitialSelection() {
        guard selectedAssignmentId == nil,
              let initialProjectId,
              let assignment = state.projectAssignments.first(where: { $0.project.id == initialProjectId })
        else { return }
        selectedAssignmentId = assignment.id
        selectedTaskId = initialTaskId
    }

    private func select(_ assignment: ProjectAssignment) {
        selectedAssignmentId = assignment.id
        selectedTaskId = assignment.taskAssignments.first {
            $0.task.name.caseInsensitiveCompare("Development") == .orderedSame
        }?.task.id
    }

    private var filteredAssignments: [ProjectAssignment] {
        let sorted = state.projectAssignments.sorted {
            ($0.client.name, $0.project.name) < ($1.client.name, $1.project.name)
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            "\($0.client.name) \($0.project.name)".localizedCaseInsensitiveContains(query)
        }
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

struct AddFavoriteSheet: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ProjectTaskPickerSheet(title: "Add Favorite", actionLabel: "Add Favorite") { assignment, task in
            state.addFavorite(Favorite(
                projectId: assignment.project.id,
                taskId: task.id,
                clientName: assignment.client.name,
                projectName: assignment.project.name,
                taskName: task.name
            ))
        }
    }
}

private struct PickerRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.harvest : .clear)
        )
        .foregroundStyle(isSelected ? .white : .primary)
        // A gesture, not a Button: while the search field is being edited AppKit
        // spends the first click on a Button resigning the field editor.
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}
