import Testing
@testable import TokenGarden

@Test func heatmapLevelWithNoData() {
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: [])
    #expect(levels.isEmpty)
}

@Test func heatmapLevelQuartiles() {
    // 7-level scale: zeros stay 0, the max becomes 7, and everything in
    // between is bucketed by septile.
    let totals = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 0]
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: totals)

    #expect(levels.count == 12)
    #expect(levels[0] == 0)
    #expect(levels[11] == 0)
    #expect(levels[1] >= 1)
    #expect(levels[10] == 7)
}

@Test func heatmapLevelAllSameUsage() {
    // Every non-zero value equals maxVal → all land in the top bucket (7).
    let totals = [500, 500, 500, 500]
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: totals)
    for level in levels {
        #expect(level == 7)
    }
}
