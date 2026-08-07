import SwiftUI

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
