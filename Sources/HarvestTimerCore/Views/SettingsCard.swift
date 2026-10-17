import SwiftUI

/// The rounded panel every settings section sits in: an icon and title, a
/// control on the right, and a body indented under the title.
struct SettingsCard<Accessory: View, Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    /// Off, the card is its header alone: a feature switched off has nothing
    /// to tune.
    var isExpanded = true
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(palette.accent)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.headline)
                Spacer()
                accessory
            }
            // Left out entirely, since an empty body still takes the spacing.
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(.leading, 32)
            }
        }
        .settingsPanel()
    }
}

extension SettingsCard where Accessory == FeatureSwitch {
    /// A feature that can be switched off: the switch sits in the header and
    /// the body shows only while it is on.
    init(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            isExpanded: isOn.wrappedValue,
            accessory: { FeatureSwitch(isOn: isOn) },
            content: content
        )
    }
}

struct FeatureSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

extension View {
    /// The panel's fill, shape and padding, for a card that lays out its own
    /// header.
    func settingsPanel(padding: CGFloat = 14) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            // A wash rather than controlBackgroundColor, which matches a
            // sheet's own white and left the cards invisible.
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
