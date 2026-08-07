import Foundation

/// Whether a notes box should take up what Harvest now says.
///
/// The box holds its own text while it is being typed into, so a sync landing
/// mid-sentence must not overwrite it. Once the cursor is elsewhere the box has
/// no claim on its contents, and notes changed in Harvest or on a phone should
/// show up.
public enum NotesField {
    /// The text the box should show, or nil to leave it as it is.
    public static func adopting(
        incoming: String?,
        shown: String,
        isEditing: Bool
    ) -> String? {
        let incoming = incoming ?? ""
        guard !isEditing, incoming != shown else { return nil }
        return incoming
    }
}
