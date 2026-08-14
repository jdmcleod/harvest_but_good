import SwiftUI

/// The second step of a project picker: which task on the project already
/// chosen. Shared by the favourite/start picker and the move sheet.
struct TaskStepView: View {
    let assignment: ProjectAssignment
    @Binding var selectedTaskId: Int64?
    let onBack: () -> Void
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            HStack(spacing: 8) {
                Button(action: onBack) {
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

            ScrollViewReader { list in
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
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onAppear { listFocused = true }
                .onMoveCommand { direction in
                    guard let step = step(for: direction) else { return }
                    guard let taskId = ListCursor.moved(from: selectedTaskId, by: step, in: taskIds)
                    else { return }
                    selectedTaskId = taskId
                    list.scrollTo(taskId)
                }
            }
        }
    }

    private var taskIds: [Int64] {
        assignment.taskAssignments.map(\.task.id)
    }

    private func step(for direction: MoveCommandDirection) -> Int? {
        switch direction {
        case .up: -1
        case .down: 1
        default: nil
        }
    }
}
