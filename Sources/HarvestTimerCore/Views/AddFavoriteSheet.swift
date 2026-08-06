import SwiftUI

struct AddFavoriteSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedAssignmentId: Int64?
    @State private var selectedTaskId: Int64?

    private var selectedAssignment: ProjectAssignment? {
        state.projectAssignments.first { $0.id == selectedAssignmentId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Favorite")
                .font(.title3.weight(.semibold))

            if state.projectAssignments.isEmpty {
                ProgressView("Loading projects…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                TextField("Search projects…", text: $search)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredAssignments, id: \.id) { assignment in
                            ProjectRow(
                                assignment: assignment,
                                isSelected: assignment.id == selectedAssignmentId
                            ) {
                                selectedAssignmentId = assignment.id
                            }
                        }
                        if filteredAssignments.isEmpty {
                            Text("No projects match “\(search)”")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        }
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

                Picker("Task", selection: $selectedTaskId) {
                    Text("Choose a task").tag(Int64?.none)
                    ForEach(selectedAssignment?.taskAssignments ?? [], id: \.task.id) { taskAssignment in
                        Text(taskAssignment.task.name).tag(Int64?.some(taskAssignment.task.id))
                    }
                }
                .disabled(selectedAssignment == nil)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Favorite") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAssignment == nil || selectedTaskId == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await state.loadProjectAssignments()
        }
        .onChange(of: selectedAssignmentId) {
            selectedTaskId = nil
        }
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

    private func add() {
        guard let assignment = selectedAssignment,
              let taskId = selectedTaskId,
              let task = assignment.taskAssignments.first(where: { $0.task.id == taskId })?.task
        else { return }
        state.addFavorite(Favorite(
            projectId: assignment.project.id,
            taskId: task.id,
            clientName: assignment.client.name,
            projectName: assignment.project.name,
            taskName: task.name
        ))
        dismiss()
    }
}

private struct ProjectRow: View {
    let assignment: ProjectAssignment
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(assignment.project.name)
                        .font(.callout)
                    Text(assignment.client.name)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
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
        }
        .buttonStyle(.plain)
    }
}
