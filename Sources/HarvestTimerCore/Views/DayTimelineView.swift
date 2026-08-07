import SwiftUI

private struct TimelineScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DayTimelineView: View {
    @Environment(AppState.self) private var state
    @State private var zoom: CGFloat = 1
    @State private var pendingZoom: CGFloat?
    @State private var scrollOffset: CGFloat = 0
    @State private var markerY: CGFloat = 0
    @State private var hasAppliedDefaultView = false

    private let scale = DayScale()
    private var startHour: Int { scale.startHour }
    private var endHour: Int { scale.endHour }
    private let labelWidth: CGFloat = 44
    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 8
    private let zoomStep: CGFloat = 2
    private let defaultTopHour: CGFloat = 9
    private let scrollMarkerId = "timelineScrollMarker"

    var body: some View {
        let blocks = state.timelineBlocks(forDay: state.selectedDay)
        let projectNames = projectNamesById()
        let modifiedIds = state.modifiedEntryIds(forDay: state.selectedDay)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                if blocks.contains(where: { modifiedIds.contains($0.entryId) }) {
                    legend
                }
                zoomControls
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            GeometryReader { geometry in
                let viewportHeight = geometry.size.height - 16
                let height = viewportHeight * zoom
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            gridlines(height: height, width: geometry.size.width)
                            ForEach(blocks) { block in
                                blockView(
                                    block,
                                    projectName: projectNames[block.projectId],
                                    isModified: modifiedIds.contains(block.entryId),
                                    height: height,
                                    width: geometry.size.width
                                )
                            }
                            if Calendar.current.isDateInToday(state.selectedDay) {
                                nowLine(height: height, width: geometry.size.width)
                            }
                            scrollMarker
                        }
                        .frame(width: geometry.size.width, height: height)
                        .padding(.vertical, 8)
                        .background(
                            GeometryReader { contentGeometry in
                                Color.clear.preference(
                                    key: TimelineScrollOffsetKey.self,
                                    value: -contentGeometry.frame(in: .named("timelineScroll")).minY
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "timelineScroll")
                    .onPreferenceChange(TimelineScrollOffsetKey.self) { scrollOffset = $0 }
                    .onChange(of: pendingZoom) { _, newZoom in
                        guard let newZoom else { return }
                        applyZoom(
                            newZoom,
                            viewportHeight: viewportHeight,
                            visibleHeight: geometry.size.height,
                            proxy: proxy
                        )
                        pendingZoom = nil
                    }
                    .onAppear {
                        applyDefaultView(viewportHeight: viewportHeight, proxy: proxy)
                    }
                    .onChange(of: geometry.size.height) { _, newHeight in
                        applyDefaultView(viewportHeight: newHeight - 16, proxy: proxy)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                pendingZoom = max(zoom / zoomStep, minZoom)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoom <= minZoom)
            .pointingCursor(zoom > minZoom)
            .help("Zoom out")
            Button {
                pendingZoom = min(zoom * zoomStep, maxZoom)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoom >= maxZoom)
            .pointingCursor(zoom < maxZoom)
            .help("Zoom in")
            Button {
                pendingZoom = minZoom
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(zoom <= minZoom)
            .pointingCursor(zoom > minZoom)
            .help("Fit full day")
        }
        .buttonStyle(.borderless)
    }

    private var legend: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.5))
                .overlay(StripeTexture().clipShape(RoundedRectangle(cornerRadius: 3)))
                .frame(width: 22, height: 12)
            Text("Edited or deleted")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 8)
        .help("Striped blocks belong to entries whose duration was edited or that were deleted")
    }

    private var scrollMarker: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .position(x: 0, y: markerY)
            .id(scrollMarkerId)
    }

    private func applyZoom(
        _ newZoom: CGFloat,
        viewportHeight: CGFloat,
        visibleHeight: CGFloat,
        proxy: ScrollViewProxy
    ) {
        let oldHeight = viewportHeight * zoom
        let centerY = scrollOffset + visibleHeight / 2 - 8
        let centerFraction = min(max(centerY / oldHeight, 0), 1)
        zoom = newZoom
        markerY = centerFraction * viewportHeight * newZoom
        DispatchQueue.main.async {
            proxy.scrollTo(scrollMarkerId, anchor: .center)
        }
    }

    private func applyDefaultView(viewportHeight: CGFloat, proxy: ScrollViewProxy) {
        guard !hasAppliedDefaultView, viewportHeight > 0 else { return }
        hasAppliedDefaultView = true
        let totalHours = CGFloat(scale.hourCount)
        let isAfternoon = Calendar.current.component(.hour, from: state.now) >= 12
        let visibleHours: Double = isAfternoon ? 8 : 3
        zoom = CGFloat(scale.zoom(toShow: visibleHours, min: Double(minZoom), max: Double(maxZoom)))
        markerY = (defaultTopHour - CGFloat(startHour)) / totalHours * viewportHeight * zoom
        DispatchQueue.main.async {
            proxy.scrollTo(scrollMarkerId, anchor: .top)
        }
    }

    private func projectNamesById() -> [Int64: String] {
        state.entries(forDay: state.selectedDay).reduce(into: [:]) { names, entry in
            names[entry.project.id] = entry.project.name
        }
    }

    private func yPosition(for date: Date, height: CGFloat) -> CGFloat {
        CGFloat(scale.position(of: date, height: Double(height)))
    }

    @ViewBuilder
    private func gridlines(height: CGFloat, width: CGFloat) -> some View {
        ForEach(startHour...endHour, id: \.self) { hour in
            let y = CGFloat(hour - startHour) / CGFloat(endHour - startHour) * height
            HStack(spacing: 6) {
                Text(hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)
            }
            .frame(width: width)
            .position(x: width / 2, y: y)
        }
        if height / CGFloat(endHour - startHour) >= 80 {
            quarterHourLines(height: height, width: width)
        }
    }

    @ViewBuilder
    private func quarterHourLines(height: CGFloat, width: CGFloat) -> some View {
        let totalQuarters = (endHour - startHour) * 4
        ForEach(1..<totalQuarters, id: \.self) { quarter in
            if quarter % 4 != 0 {
                let y = CGFloat(quarter) / CGFloat(totalQuarters) * height
                HStack(spacing: 6) {
                    Text(quarterLabel(quarter))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: labelWidth, alignment: .trailing)
                    Rectangle()
                        .fill(.separator.opacity(0.4))
                        .frame(height: 1)
                }
                .frame(width: width)
                .position(x: width / 2, y: y)
            }
        }
    }

    @ViewBuilder
    private func blockView(
        _ block: TimelineBlock,
        projectName: String?,
        isModified: Bool,
        height: CGFloat,
        width: CGFloat
    ) -> some View {
        let top = yPosition(for: block.start, height: height)
        let bottom = yPosition(for: block.end, height: height)
        let blockHeight = max(bottom - top, 3)
        let blockWidth = width - labelWidth - 22
        let isSelected = state.selectedEntryId == block.entryId

        RoundedRectangle(cornerRadius: 4)
            .fill(Color.forProject(block.projectId).opacity(isSelected ? 0.9 : 0.65))
            .overlay {
                if isModified {
                    StripeTexture()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if blockHeight >= 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(projectName ?? "Project \(block.projectId)")
                            .font(.caption.weight(.semibold))
                        Text(timeRange(block))
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.top, 3)
                } else if blockHeight >= 16 {
                    Text(block.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.top, 2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2)
            )
            .frame(width: blockWidth, height: blockHeight)
            .position(x: labelWidth + 12 + blockWidth / 2, y: top + blockHeight / 2)
            .help(blockTooltip(block, projectName: projectName))
            .pointingCursor()
            .onTapGesture {
                state.selectedEntryId = isSelected ? nil : block.entryId
            }
    }

    @ViewBuilder
    private func nowLine(height: CGFloat, width: CGFloat) -> some View {
        let y = yPosition(for: state.now, height: height)
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(.red)
                .frame(height: 1.5)
        }
        .frame(width: width - labelWidth - 8)
        .position(x: labelWidth + 8 + (width - labelWidth - 8) / 2, y: y)
    }

    private func hourLabel(_ hour: Int) -> String {
        scale.hourLabel(hour)
    }

    private func quarterLabel(_ quarter: Int) -> String {
        scale.quarterLabel(quarter)
    }

    private func timeRange(_ block: TimelineBlock) -> String {
        let start = block.start.formatted(date: .omitted, time: .shortened)
        let end = block.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private func blockTooltip(_ block: TimelineBlock, projectName: String?) -> String {
        "\(projectName ?? "Project \(block.projectId)"): \(timeRange(block))"
    }
}

private struct StripeTexture: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 7
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 2.5)
                x += spacing
            }
        }
    }
}
