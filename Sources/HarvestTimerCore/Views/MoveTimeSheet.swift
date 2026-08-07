import SwiftUI

/// Moves some of an entry's time somewhere else. Most moves land on another
/// entry from the same day, so those come first; the full project list is
/// underneath for the rest.
struct MoveTimeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let entry: TimeEntry
    @State private var amountText = ""
    @State private var search = ""
    @State private var destinationProjectId: Int64?
    @State private var destinationTaskId: Int64?
    /// Set while drilling into a project's tasks.
    @State private var browsingAssignmentId: Int64?
    @FocusState private var amountFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move Time")
                .font(.title3.weight(.semibold))

            amountField

            if let assignment = browsingAssignment {
                TaskStepView(assignment: assignment, selectedTaskId: $destinationTaskId) {
                    browsingAssignmentId = nil
                    destinationProjectId = nil
                    destinationTaskId = nil
                }
            } else {
                destinationStep
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Move") { move() }
                    .buttonStyle(.borderedProminent)
                    .disabled(amount == nil || destinationTaskId == nil)
            }

            if entry.isRunning {
                Text("The timer keeps running — on the destination if this entry ends up empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await state.loadProjectAssignments() }
        .onAppear { amountText = Hours.formatted(sourceHours) }
    }

    private var amountField: some View {
        HStack(spacing: 8) {
            Text("Move")
            TextField("0:00", text: $amountText)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 70)
                .focused($amountFocused)
                .onAppear { amountFocused = true }
            Text("of \(Hours.formatted(sourceHours)) from \(entry.project.name) · \(entry.task.name) to:")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .font(.callout)
    }

    private var destinationStep: some View {
        Group {
            TextField("Search this day's entries or all projects…", text: $search)
                .textFieldStyle(.roundedBorder)

            PickerListBox {
                if !dayEntries.isEmpty {
                    sectionHeader("On this day")
                    ForEach(dayEntries) { other in
                        PickerRow(
                            title: other.project.name,
                            subtitle: other.task.name,
                            detail: Hours.formatted(other.hours),
                            isSelected: isSelected(projectId: other.project.id, taskId: other.task.id)
                        ) {
                            destinationProjectId = other.project.id
                            destinationTaskId = other.task.id
                        }
                    }
                }
                sectionHeader(dayEntries.isEmpty ? "Projects" : "Other projects")
                ForEach(matchingProjects, id: \.assignment.id) { match in
                    PickerRow(
                        title: match.assignment.project.name,
                        subtitle: match.subtitle,
                        isSelected: false
                    ) {
                        browsingAssignmentId = match.assignment.id
                        destinationProjectId = match.assignment.project.id
                        destinationTaskId = match.defaultTaskId
                    }
                }
                if matchingProjects.isEmpty && dayEntries.isEmpty {
                    Text("Nothing matches “\(search)”")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    /// The day's other entries — where a move usually goes.
    private var dayEntries: [TimeEntry] {
        state.entries(onDate: entry.spentDate).filter {
            $0.id != entry.id
                && ProjectSearch.matches("\($0.client.name) \($0.project.name) \($0.task.name)", query: search)
        }
    }

    /// The clock keeps ticking while the sheet is open, so a running entry's
    /// time is whatever it has reached now.
    private var sourceHours: Double {
        state.liveHours(for: state.entry(withId: entry.id) ?? entry)
    }

    private var matchingProjects: [ProjectSearch.Match] {
        ProjectSearch.matches(in: state.projectAssignments, query: search)
    }

    private var browsingAssignment: ProjectAssignment? {
        state.projectAssignments.first { $0.id == browsingAssignmentId }
    }

    private var amount: Double? {
        guard let hours = Hours.parse(amountText), hours > 0 else { return nil }
        return hours
    }

    private func isSelected(projectId: Int64, taskId: Int64) -> Bool {
        destinationProjectId == projectId && destinationTaskId == taskId
    }

    private func move() {
        guard let amount, let projectId = destinationProjectId, let taskId = destinationTaskId else { return }
        Task {
            await state.moveTime(entry, hours: amount, projectId: projectId, taskId: taskId)
        }
        dismiss()
    }
}
