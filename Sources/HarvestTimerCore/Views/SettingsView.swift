import SwiftUI

/// The sheet behind the gear. The connection sits folded at the top since
/// it is set once; the rest is what gets tuned from week to week.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Past this the cards scroll rather than grow off a laptop screen.
    private static let maxScrollHeight: CGFloat = 620
    /// How far the cards fade as they pass under the title or the Done row.
    private static let fade: CGFloat = 14

    /// How tall the cards stood when the sheet opened. Kept from then on, so
    /// opening the token form or a card scrolls instead of growing the sheet.
    @State private var openingHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AccountCard()
                    ShortcutCard()
                    IdleDetectionCard()
                    DailyGoalsCard()
                    CustomColorsCard()
                    if let version = BuildInfo.current.version {
                        ReleaseUpdatesCard(version: version)
                    } else {
                        UpdatesCard()
                    }
                }
                .padding(.horizontal, 20)
                // Room for the fade, so nothing sits in it until scrolled.
                .padding(.vertical, Self.fade)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    if openingHeight == nil { openingHeight = height }
                }
            }
            // Without this it rubber-bands even when everything fits.
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(openingHeight ?? Self.maxScrollHeight, Self.maxScrollHeight))
            .mask(EdgeFade(length: Self.fade))

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 4)
        }
        .frame(width: 560)
    }
}

/// Opaque in the middle and clear at both ends, so content scrolling out
/// fades away instead of being cut off at a hard line.
private struct EdgeFade: View {
    let length: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: length)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: length)
        }
    }
}
