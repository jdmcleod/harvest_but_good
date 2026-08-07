import SwiftUI

struct ProjectTaskPickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionLabel: String
    var initialProjectId: Int64?
    var initialTaskId: Int64?
    var showsNotes = false
    let onConfirm: (ProjectAssignment, ProjectAssignment.TaskAssignment.Task, String) -> Void
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

            if showsNotes {
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
        onConfirm(assignment, task, notes)
        dismiss()
    }
}

struct AddFavoriteSheet: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ProjectTaskPickerSheet(title: "Add Favorite", actionLabel: "Add Favorite") { assignment, task, _ in
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

/// The framed, scrolling box every picker list sits in.
struct PickerListBox<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
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
}

struct PickerRow: View {
    let title: String
    let subtitle: String?
    /// Trailing text, such as the hours already on an entry.
    var detail: String?
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
            if let detail {
                Text(detail)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
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
