import SwiftUI

struct EntryList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let entries = state.entries(forDay: state.selectedDay)
        let counts = state.startCounts(forDay: state.selectedDay)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if entries.isEmpty {
                        Text("No entries for this day.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(entries) { entry in
                            EntryCard(entry: entry, startCount: counts[entry.id] ?? 0)
                                .id(entry.id)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .top)
            }
            .onChange(of: state.selectedEntryId) { _, entryId in
                guard let entryId else { return }
                withAnimation {
                    proxy.scrollTo(entryId)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

private struct EntryCard: View {
    @Environment(AppState.self) private var state
    let entry: TimeEntry
    let startCount: Int
    @State private var notes: String
    @State private var confirmingDelete = false
    @FocusState private var notesFocused: Bool

    init(entry: TimeEntry, startCount: Int) {
        self.entry = entry
        self.startCount = startCount
        _notes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(projectColor(entry.project.id))
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.project.name)
                            .font(.callout.weight(.semibold))
                        Text("\(entry.client.name) · \(entry.task.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formattedHours(state.liveHours(for: entry)))
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(entry.isRunning ? Color.harvest : .primary)
                        if startCount > 0 {
                            Text("\(startCount) start\(startCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Started \(startCount) time(s) from this app")
                        } else {
                            Text("started elsewhere")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...4)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(notesFocused ? 1 : 0.5))
                    )
                    .focused($notesFocused)
                    .onSubmit { save() }
                    .onChange(of: notesFocused) { _, focused in
                        if !focused { save() }
                    }
            }

            Button {
                Task { await state.toggle(entry) }
            } label: {
                Image(systemName: entry.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(entry.isRunning ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(entry.isRunning ? "Stop timer" : "Start timer")
        }
        .onDisappear {
            if notesFocused { save() }
        }
        .padding(10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                RoundedRectangle(cornerRadius: 10)
                    .fill(highlightColor.opacity(0.08))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(highlightColor, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Delete Entry…", systemImage: "trash", role: .destructive) {
                confirmingDelete = true
            }
        }
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: $confirmingDelete
        ) {
            Button("Delete", role: .destructive) {
                Task { await state.deleteEntry(entry) }
            }
        } message: {
            Text("\(entry.project.name) · \(formattedHours(state.liveHours(for: entry)))")
        }
    }

    private var isSelected: Bool {
        state.selectedEntryId == entry.id
    }

    private var highlightColor: Color {
        if isSelected { return .accentColor }
        if entry.isRunning { return .harvest }
        return .clear
    }

    private func save() {
        Task { await state.saveNotes(entry, notes: notes) }
    }
}
