import SwiftUI

/// Adding a favourite in two steps inside one sheet: which project and task,
/// then what the chip should look like. Two steps in one sheet rather than a
/// sheet presenting a sheet, which macOS handles badly.
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
