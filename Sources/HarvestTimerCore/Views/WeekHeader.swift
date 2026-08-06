import SwiftUI

struct WeekHeader: View {
    @Environment(AppState.self) private var state
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .pointingCursor()

            HStack(spacing: 3) {
                ForEach(state.weekDays, id: \.self) { day in
                    DayTab(day: day)
                }
            }

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .pointingCursor()

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1, height: 28)

            FavoriteChips()

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .pointingCursor()
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .pointingCursor()
            .help("Quit Harvest Timer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(Color.harvest.ignoresSafeArea(edges: .top))
    }

    private func shiftWeek(by weeks: Int) {
        state.selectedDay = Calendar.current.date(
            byAdding: .day,
            value: weeks * 7,
            to: state.selectedDay
        )!
        Task { await state.sync() }
    }
}

private struct DayTab: View {
    @Environment(AppState.self) private var state
    let day: Date

    private var isSelected: Bool {
        Calendar.current.isDate(day, inSameDayAs: state.selectedDay)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    var body: some View {
        Button {
            state.selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(isToday ? .white : .white.opacity(0.7))
                Text(formattedHours(state.total(forDay: day)))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 56)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.2) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingCursor()
    }
}
