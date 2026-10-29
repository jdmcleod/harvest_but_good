import SwiftUI

/// ⌘K: one box that finds projects, favorites, the day's entries and every
/// command, and runs whichever is picked. Return runs a row, Shift-Return
/// starts it with a note, Tab lists what else a row can do.
struct CommandPalette: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @Environment(WindowCommands.self) private var commands
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode: Equatable {
        case search
        case projects
        case actions(PaletteItem)
        case note(projectId: Int64, taskId: Int64, title: String, subtitle: String)
    }

    @State private var query = ""
    @State private var mode: Mode = .search
    @State private var selection = 0
    /// When the keys last moved the selection. Rows scrolling under a still
    /// pointer report a hover, which would otherwise yank the pick back.
    @State private var keyedAt = Date.distantPast
    @State private var note = ""
    @FocusState private var fieldFocused: Bool

    private var context: PaletteContext { commands.paletteContext() }

    private var sections: [PaletteSection] {
        switch mode {
        case .search:
            return PaletteSearch.sections(for: query, in: context)
        case .projects:
            let items = PaletteSearch.projects(matching: query, in: context)
            return items.isEmpty ? [] : [PaletteSection(title: query.isEmpty ? "All projects" : "Projects", items: items)]
        case let .actions(item):
            let items = PaletteSearch.actions(for: item, in: context).filter {
                PaletteSearch.score($0.title, PaletteQuery(">" + query).terms) != nil
            }
            return [PaletteSection(title: "Actions", items: items)]
        case .note:
            return []
        }
    }

    var body: some View {
        let sections = self.sections
        let items = sections.flatMap(\.items)
        // Inside the window rather than a sheet, so it never outgrows it, and
        // pinned near the top where the eye already is after pressing ⌘K.
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .contentShape(Rectangle())
                .onTapGesture { commands.closePalette() }
            VStack(spacing: 0) {
                header(items: items)
                Divider()
                if case let .note(projectId, taskId, title, subtitle) = mode {
                    noteStep(projectId: projectId, taskId: taskId, title: title, subtitle: subtitle)
                } else {
                    list(sections, items: items)
                }
                footer(selected: items.indices.contains(selection) ? items[selection] : nil)
            }
            .frame(width: 540)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .onAppear { fieldFocused = true }
        .task { await commands.loadProjects() }
        .onChange(of: query) { selection = 0 }
        .onChange(of: mode) {
            selection = 0
            fieldFocused = true
            commands.backStep = mode == .search ? nil : { mode = .search; query = "" }
        }
        .onAppear { commands.paletteMove = { move(by: $0) } }
        .onDisappear {
            commands.backStep = nil
            commands.paletteMove = nil
        }
    }

    // MARK: Header

    private func header(items: [PaletteItem]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if let crumb {
                Text(crumb)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.accent.opacity(0.16)))
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize()
            }
            if case .note = mode {
                TextField("What are you working on?", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onKeyPress(.return) { confirmNote() }
                    .onKeyPress(.escape) {
                        mode = .search
                        return .handled
                    }
            } else {
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onKeyPress(keys: [.return]) { press in
                        runSelected(in: items, withNote: press.modifiers.contains(.shift))
                    }
                    .onKeyPress(.tab) { openActions(in: items) }
                    .onKeyPress(.escape) { back() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var crumb: String? {
        switch mode {
        case .search: nil
        case .projects: "Start a timer"
        case let .actions(item): "\(item.title) ›"
        case .note: "Note"
        }
    }

    private var placeholder: String {
        switch mode {
        case .projects: "Project, client or task…"
        case .actions: "Filter actions…"
        default:
            query.hasPrefix(">") ? "Search commands…" : "Search projects and commands…"
        }
    }

    // MARK: List

    private func list(_ sections: [PaletteSection], items: [PaletteItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(section.items) { item in
                            let index = items.firstIndex { $0.id == item.id } ?? 0
                            PaletteRow(item: item, isSelected: index == selection)
                                .id(item.id)
                                .onTapGesture { run(item, withNote: false) }
                                .onHover { inside in
                                    guard inside, Date.now.timeIntervalSince(keyedAt) > 0.4 else { return }
                                    selection = index
                                }
                        }
                    }
                    if items.isEmpty {
                        Text(query.isEmpty ? "Nothing here yet." : "Nothing matches “\(query)”.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 340)
            .onChange(of: selection) { _, index in
                guard items.indices.contains(index) else { return }
                // The first row takes its section heading along, so the top
                // of the list comes fully back into view.
                proxy.scrollTo(items[index].id, anchor: index == 0 ? .bottom : nil)
            }
        }
    }

    private func noteStep(projectId: Int64, taskId: Int64, title: String, subtitle: String) -> some View {
        let recent = commands.recentNotes(projectId: projectId, taskId: taskId)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(palette.forProject(projectId))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !recent.isEmpty {
                Text("RECENT NOTES ON THIS TASK")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                FlowRow(recent) { text in
                    Button(text) { start(projectId: projectId, taskId: taskId, notes: text) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(selected: PaletteItem?) -> some View {
        HStack(spacing: 12) {
            ForEach(hints(for: selected), id: \.label) { hint in
                Text("\(hint.key) \(hint.label)")
            }
            Spacer()
            if mode == .search, query.isEmpty {
                Text("> commands · “dev 1:30” logs time")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
    }

    private func hints(for selected: PaletteItem?) -> [(key: String, label: String)] {
        if case .note = mode { return [("↩", "start"), ("esc", "back")] }
        var hints: [(key: String, label: String)] = []
        if let selected, selected.startTarget != nil {
            hints += [("↩", "start"), ("⇧↩", "with a note")]
        } else {
            hints.append(("↩", "run"))
        }
        if mode == .search, selected?.hasActions == true { hints.append(("⇥", "more")) }
        if mode != .search { hints.append(("⌫", "back")) }
        return hints
    }

    // MARK: Keys

    /// Arrows step one row, Page Up and Down a screenful, and the list
    /// scrolls along like a page would.
    private func move(by step: Int) {
        let count = sections.flatMap(\.items).count
        guard count > 0 else { return }
        keyedAt = .now
        selection = min(max(selection + step, 0), count - 1)
    }

    private func runSelected(in items: [PaletteItem], withNote: Bool) -> KeyPress.Result {
        guard items.indices.contains(selection) else { return .handled }
        run(items[selection], withNote: withNote)
        return .handled
    }

    private func openActions(in items: [PaletteItem]) -> KeyPress.Result {
        guard mode == .search, items.indices.contains(selection), items[selection].hasActions else { return .handled }
        mode = .actions(items[selection])
        query = ""
        return .handled
    }

    private func back() -> KeyPress.Result {
        if !query.isEmpty {
            query = ""
        } else if mode != .search {
            mode = .search
        } else {
            commands.closePalette()
        }
        return .handled
    }

    private func confirmNote() -> KeyPress.Result {
        guard case let .note(projectId, taskId, _, _) = mode else { return .ignored }
        start(projectId: projectId, taskId: taskId, notes: note)
        return .handled
    }

    // MARK: Running

    private func run(_ item: PaletteItem, withNote: Bool) {
        if item.id == "note" || (withNote && item.startTarget != nil), let target = item.startTarget {
            note = ""
            let assignment = commands.assignment(projectId: target.projectId)
            let task = assignment?.taskAssignments.first { $0.task.id == target.taskId }?.task.name
            mode = .note(
                projectId: target.projectId, taskId: target.taskId,
                title: assignment?.project.name ?? item.title,
                subtitle: [task, assignment?.client.name].compactMap { $0 }.joined(separator: " · ")
            )
            return
        }
        switch item.action {
        case .allCommands:
            query = ">"
        case .command(.startTimer):
            query = ""
            mode = .projects
        default:
            commands.closePalette { commands.run(item.action) }
        }
    }

    private func start(projectId: Int64, taskId: Int64, notes: String) {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        commands.closePalette {
            commands.run(.start(projectId: projectId, taskId: taskId), notes: notes.isEmpty ? nil : notes)
        }
    }
}

private struct PaletteRow: View {
    @Environment(\.palette) private var palette
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            mark
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let detail = item.detail {
                Text(detail)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // Only on the row you're on: a keycap on every line read as noise,
            // and arrowing through still teaches each one.
            if isSelected {
                HStack(spacing: 3) {
                    ForEach(Array(item.keycaps.enumerated()), id: \.offset) { _, cap in
                        Keycap(cap)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? palette.accent.opacity(0.13) : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel([item.title, item.subtitle].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder private var mark: some View {
        switch item.mark {
        case let .project(projectId):
            Circle().fill(palette.forProject(projectId)).frame(width: 9, height: 9)
        case let .favorite(favorite):
            Circle().fill(palette.forFavorite(favorite)).frame(width: 9, height: 9)
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? palette.accent : Color.secondary)
        }
    }
}

/// A key as it is printed on the keyboard.
struct Keycap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.75))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 19)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// Lays its children out left to right, wrapping onto new lines.
private struct FlowRow<Content: View>: View {
    let texts: [String]
    let content: (String) -> Content

    init(_ texts: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.texts = texts
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(texts, id: \.self) { content($0) }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (index, frame) in rows.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.x, y: bounds.minY + frame.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(x: CGFloat, y: CGFloat, height: CGFloat)] {
        var frames: [(x: CGFloat, y: CGFloat, height: CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append((x, y, size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
