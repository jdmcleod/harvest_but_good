import SwiftUI

struct AddFavoriteSheet: View {
    @State private var draft: Favorite?

    var body: some View {
        if let draft {
            FavoriteDetailsSheet(favorite: draft, isNew: true)
        } else {
            ProjectTaskPickerSheet(
                title: "Add Favorite",
                actionLabel: "Next",
                dismissesOnConfirm: false
            ) { assignment, task, _ in
                draft = Favorite(
                    projectId: assignment.project.id,
                    taskId: task.id,
                    clientName: assignment.client.name,
                    projectName: assignment.project.name,
                    taskName: task.name
                )
            }
        }
    }
}
