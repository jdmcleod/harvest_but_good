import SwiftUI

struct WeekHeader: View {
    @Environment(AppState.self) private var state
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
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

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Harvest Timer")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                    .foregroundStyle(isToday ? Color.harvest : .secondary)
                Text(formattedHours(state.total(forDay: day)))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 64)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.harvest.opacity(0.15) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.harvest : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
