import SwiftUI

struct AFKPromptView: View {
    @Environment(AppState.self) private var state
    let prompt: AFKPrompt
    @State private var loggingElsewhere = false

    private var timeGone: String { formattedDuration(prompt.duration) }
    private var entry: TimeEntry? { state.entry(withId: prompt.entryId) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.harvest)
            Text("Welcome back")
                .font(.title2.weight(.semibold))
            VStack(spacing: 4) {
                Text("You were away for **\(timeGone)**.")
                if let entry {
                    Text("\(entry.project.name) — \(entry.task.name) kept running the whole time.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your timer kept running the whole time.")
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button("Remove \(timeGone)") {
                    Task { await state.removeAFKTime() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                HStack(spacing: 12) {
                    Button("Log \(timeGone) to another task…") {
                        loggingElsewhere = true
                    }
                    Button("Keep the time") {
                        state.dismissAFKPrompt()
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 400)
        .interactiveDismissDisabled()
        .sheet(isPresented: $loggingElsewhere) {
            ProjectTaskPickerSheet(
                title: "Log Away Time",
                actionLabel: "Log \(timeGone)"
            ) { assignment, task, _ in
                Task {
                    await state.moveAFKTime(projectId: assignment.project.id, taskId: task.id)
                }
            }
        }
    }
}
