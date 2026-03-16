import SwiftUI

enum HeatmapCalculator {
    static func calculateLevels(dailyTotals: [Int]) -> [Int] {
        guard !dailyTotals.isEmpty else { return [] }

        let nonZero = dailyTotals.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else {
            return dailyTotals.map { _ in 0 }
        }

        let maxVal = nonZero.last!
        let percentiles = (1...6).map { i in
            nonZero[nonZero.count * i / 7]
        }

        return dailyTotals.map { total in
            if total == 0 { return 0 }
            if total == maxVal { return 7 }
            for (i, p) in percentiles.enumerated() {
                if total <= p { return i + 1 }
            }
            return 7
        }
    }
}

enum HeatmapRange: String, CaseIterable {
    case `default` = "Default"
    case day = "D"
    case week = "W"
    case month = "M"
    case year = "Y"

    var columns: Int {
        switch self {
        case .default: return 12
        case .day: return 2
        case .week: return 4
        case .month: return 12
        case .year: return 52
        }
    }
}

struct HeatmapView: View {
    let dailyUsages: [(date: Date, tokens: Int)]
    @Binding var selectedDate: Date?
    @State private var range: HeatmapRange = .default

    private let rows = 7
    private let cellSize: CGFloat = 18
    private let spacing: CGFloat = 2
    private let dayLabelWidth: CGFloat = 28

    private let dayLabels = ["", "Mon", "", "Wed", "", "Fri", ""]

    @AppStorage("heatmapTheme") private var themeName = HeatmapTheme.green.rawValue
    private var colors: [Color] {
        (HeatmapTheme(rawValue: themeName) ?? .green).colors
    }

    private var isYearView: Bool { range == .year }

    var body: some View {
        let columns = range.columns
        let gridData = buildGrid(columns: columns)

        VStack(alignment: .leading, spacing: 0) {
            // Range picker
            HStack(spacing: 2) {
                Spacer()
                ForEach(HeatmapRange.allCases, id: \.self) { r in
                    Text(r.rawValue)
                        .font(.system(size: 9, weight: range == r ? .semibold : .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            range == r
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .foregroundStyle(range == r ? .primary : .secondary)
                        .onTapGesture {
                            range = r
                        }
                }
            }
            .padding(.bottom, 4)

            if range == .year {
                yearGrid(gridData: gridData, columns: columns)
            } else {
                fixedGrid(gridData: gridData, columns: columns)
            }
        }
    }

    // MARK: - Fixed cell size grid for D/W/M

    @ViewBuilder
    private func fixedGrid(gridData: [GridCell], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Month labels
            HStack(spacing: 0) {
                Text("")
                    .frame(width: dayLabelWidth)

                let monthLabels = buildMonthLabels(gridData: gridData, columns: columns)
                ForEach(monthLabels, id: \.offset) { label in
                    Text(label.text)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: CGFloat(label.span) * (cellSize + spacing), alignment: .leading)
                }
            }
            .padding(.bottom, 2)

            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        Text(dayLabels[row])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: cellSize, alignment: .trailing)
                    }
                }

                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<columns, id: \.self) { col in
                                cellView(gridData: gridData, col: col, row: row, cellSize: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Dynamic cell size grid for Year

    @ViewBuilder
    private func yearGrid(gridData: [GridCell], columns: Int) -> some View {
        GeometryReader { geo in
            let gridWidth = geo.size.width
            let yearCellSize = max(1, (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))

            VStack(alignment: .leading, spacing: 0) {
                // Month labels
                HStack(spacing: 0) {
                    let monthLabels = buildMonthLabels(gridData: gridData, columns: columns)
                    ForEach(monthLabels, id: \.offset) { label in
                        Text(label.text)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: CGFloat(label.span) * (yearCellSize + spacing), alignment: .leading)
                    }
                }
                .padding(.bottom, 2)

                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<columns, id: \.self) { col in
                                cellView(gridData: gridData, col: col, row: row, cellSize: yearCellSize)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: yearGridHeight)
    }

    private var yearGridHeight: CGFloat {
        let geo_width: CGFloat = 296 // approximate available width
        let yearCellSize = max(1, (geo_width - spacing * CGFloat(51)) / CGFloat(52))
        return 14 + 2 + CGFloat(rows) * (yearCellSize + spacing) - spacing
    }

    // MARK: - Cell view

    @ViewBuilder
    private func cellView(gridData: [GridCell], col: Int, row: Int, cellSize: CGFloat) -> some View {
        let index = col * rows + row
        let cornerR: CGFloat = range == .year ? 1 : 2
        if index < gridData.count {
            let cell = gridData[index]
            if cell.level < 0 {
                // Future placeholder — invisible
                Color.clear
                    .frame(width: cellSize, height: cellSize)
            } else {
                let isSelected = selectedDate != nil &&
                    Calendar.current.isDate(cell.date, inSameDayAs: selectedDate!)
                RoundedRectangle(cornerRadius: cornerR)
                    .fill(colors[cell.level])
                    .frame(width: cellSize, height: cellSize)
                    .overlay(
                        isSelected ?
                            RoundedRectangle(cornerRadius: cornerR)
                                .stroke(Color.primary, lineWidth: 1.5) : nil
                    )
                    .help(cell.tooltip)
                    .onTapGesture {
                        if isSelected {
                            selectedDate = nil
                        } else {
                            selectedDate = cell.date
                        }
                    }
            }
        } else {
            Color.clear
                .frame(width: cellSize, height: cellSize)
        }
    }

    // MARK: - Data

    private struct GridCell {
        let date: Date
        let tokens: Int
        let level: Int
        let tooltip: String
    }

    private struct MonthLabel {
        let text: String
        let span: Int
        let offset: Int
    }

    private func buildGrid(columns: Int) -> [GridCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // weekday: 1=Sun, 2=Mon, ..., 7=Sat → row index (Sun=0, Mon=1, ...)
        let todayWeekday = calendar.component(.weekday, from: today)
        let todayRow = todayWeekday - 1 // 0-based row for today

        // Last column ends at today's row. Total grid slots = columns * rows
        // Days after today in the last column are empty (future)
        let totalSlots = columns * rows
        let futureSlotsInLastCol = rows - 1 - todayRow
        let totalDays = totalSlots - futureSlotsInLastCol
        let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today)!

        var usageByDate: [Date: Int] = [:]
        for usage in dailyUsages {
            let day = calendar.startOfDay(for: usage.date)
            usageByDate[day] = (usageByDate[day] ?? 0) + usage.tokens
        }

        // Build date/token arrays for actual days
        var dayDates: [Date] = []
        var dayTotals: [Int] = []
        for i in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: i, to: startDate)!
            dayDates.append(date)
            dayTotals.append(usageByDate[date] ?? 0)
        }
        let gridLevels = HeatmapCalculator.calculateLevels(dailyTotals: dayTotals)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateStyle = .medium

        // Fill grid: totalSlots, with future slots as empty
        var grid: [GridCell] = []
        for i in 0..<totalSlots {
            if i < totalDays {
                let tooltip = "\(dateFormatter.string(from: dayDates[i])): \(TokenFormatter.format(dayTotals[i]))"
                grid.append(GridCell(
                    date: dayDates[i],
                    tokens: dayTotals[i],
                    level: i < gridLevels.count ? gridLevels[i] : 0,
                    tooltip: tooltip
                ))
            } else {
                // Future placeholder
                grid.append(GridCell(date: today, tokens: -1, level: -1, tooltip: ""))
            }
        }

        return grid
    }

    private func buildMonthLabels(gridData: [GridCell], columns: Int) -> [MonthLabel] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM"

        var labels: [MonthLabel] = []
        var currentMonth = -1
        var currentSpan = 0
        var labelOffset = 0

        for col in 0..<columns {
            let index = col * rows
            guard index < gridData.count else { break }
            let month = calendar.component(.month, from: gridData[index].date)

            if month != currentMonth {
                if currentMonth != -1 {
                    labels.append(MonthLabel(text: formatter.string(from: gridData[(col - currentSpan) * rows].date),
                                             span: currentSpan, offset: labelOffset))
                    labelOffset += currentSpan
                }
                currentMonth = month
                currentSpan = 1
            } else {
                currentSpan += 1
            }
        }
        if currentSpan > 0 {
            let col = columns - currentSpan
            let index = col * rows
            if index < gridData.count {
                labels.append(MonthLabel(text: formatter.string(from: gridData[index].date),
                                         span: currentSpan, offset: labelOffset))
            }
        }

        return labels
    }
}
