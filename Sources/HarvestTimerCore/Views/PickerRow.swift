import SwiftUI

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
