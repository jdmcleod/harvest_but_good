import SwiftUI

struct AFKPromptView: View {
    @Environment(AppState.self) private var state
    let prompt: AFKPrompt

    private var currentPrompt: AFKPrompt { state.afkPrompt ?? prompt }
    private var timeGone: String { formattedDuration(currentPrompt.duration(now: state.now)) }
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

            HStack(spacing: 12) {
                Button("Keep the time") {
                    state.dismissAFKPrompt()
                }
                .keyboardShortcut(.cancelAction)
                Button("Remove \(timeGone)") {
                    Task { await state.removeAFKTime() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 400)
    }
}
