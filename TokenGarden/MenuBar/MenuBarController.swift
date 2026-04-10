import AppKit
import Combine

@MainActor
class MenuBarController: ObservableObject {
    @Published var todayTokens: Int = 0

    private var currentFrame = 0
    private weak var statusItem: NSStatusItem?
    private let displayMode: () -> String

    // Track last 3 hours of tokens for mini graph
    private var hourlyBuckets: [Int] = [0, 0, 0]
    private var bucketHours: [Int] = [-1, -1, -1]
    private var lastKnownDay: Date = .distantPast

    // Dirty tracking — skip NSImage rendering when nothing visible has changed
    private var needsDisplayUpdate = true
    private var lastActivityTime: Date = .distantPast
    private let idleTimeout: TimeInterval = 60  // stop animation after 60s of no events

    init(
        statusItem: NSStatusItem,
        initialTodayTokens: Int = 0,
        initialHourlyBuckets: [Int] = [0, 0, 0],
        displayMode: @escaping () -> String = { UserDefaults.standard.string(forKey: "displayMode") ?? MenuBarDisplayMode.iconOnly.rawValue }
    ) {
        self.statusItem = statusItem
        self.todayTokens = initialTodayTokens
        self.displayMode = displayMode
        lastKnownDay = Calendar.current.startOfDay(for: Date())
        refreshBucketHours()
        // Load persisted hourly data
        if initialHourlyBuckets.count == 3 {
            self.hourlyBuckets = initialHourlyBuckets
        }
        updateDisplay()
        needsDisplayUpdate = false
    }

    func onTokenEvent(_ event: TokenEvent) {
        let cal = Calendar.current
        guard cal.isDateInToday(event.timestamp) else { return }
        todayTokens += event.totalTokens
        refreshBucketHours()
        let hour = cal.component(.hour, from: event.timestamp)
        if let idx = bucketHours.firstIndex(of: hour) {
            hourlyBuckets[idx] += event.totalTokens
        }
        lastActivityTime = Date()
        needsDisplayUpdate = true
        updateDisplay()
        needsDisplayUpdate = false
    }

    /// Reload data after async backfill completes
    func reloadData(todayTokens: Int, hourlyBuckets: [Int]) {
        self.todayTokens = todayTokens
        if hourlyBuckets.count == 3 {
            self.hourlyBuckets = hourlyBuckets
        }
        needsDisplayUpdate = true
        updateDisplay()
        needsDisplayUpdate = false
    }

    /// Called by AppDelegate's timer on every tick.
    /// Skips frame advance and rendering when idle (no token events in last 60s).
    func tick() {
        let isActive = Date().timeIntervalSince(lastActivityTime) < idleTimeout

        if isActive {
            // Animation only runs while recent activity — advances frame and redraws
            currentFrame = (currentFrame + 1) % AnimationFrames.frameCount
            needsDisplayUpdate = true
        }

        let hourChanged = refreshBucketHours()
        if hourChanged {
            needsDisplayUpdate = true
        }

        if needsDisplayUpdate {
            updateDisplay()
            needsDisplayUpdate = false
        }
    }

    // MARK: - Private

    /// Refreshes day/hour state. Returns true if anything observable changed (day rollover or hour shift).
    @discardableResult
    private func refreshBucketHours() -> Bool {
        let cal = Calendar.current
        let now = Date()
        var changed = false

        // Reset all state when the day changes
        let today = cal.startOfDay(for: now)
        if today != lastKnownDay {
            lastKnownDay = today
            todayTokens = 0
            hourlyBuckets = [0, 0, 0]
            bucketHours = [-1, -1, -1]
            changed = true
        }

        let currentHour = cal.component(.hour, from: now)
        let expected = [currentHour - 2, currentHour - 1, currentHour]

        if bucketHours != expected {
            var newBuckets = [0, 0, 0]
            for (i, h) in expected.enumerated() {
                if let oldIdx = bucketHours.firstIndex(of: h) {
                    newBuckets[i] = hourlyBuckets[oldIdx]
                }
            }
            hourlyBuckets = newBuckets
            bucketHours = expected
            changed = true
        }
        return changed
    }

    private func updateDisplay() {
        guard let button = statusItem?.button else { return }
        let mode = MenuBarDisplayMode(rawValue: displayMode()) ?? .iconOnly

        let animImage = AnimationFrames.image(for: currentFrame)

        switch mode {
        case .iconOnly:
            statusItem?.length = NSStatusItem.squareLength
            button.image = animImage
            button.title = ""

        case .iconAndNumber:
            button.title = ""
            let combined = renderIconWithText(icon: animImage, text: TokenFormatter.format(todayTokens))
            button.image = combined
            statusItem?.length = combined.size.width

        case .iconAndMiniGraph:
            button.title = ""
            let combined = renderIconWithGraph(icon: animImage)
            button.image = combined
            statusItem?.length = combined.size.width
        }
    }

    // MARK: - Token Text Rendering

    private func renderIconWithText(icon: NSImage, text: String) -> NSImage {
        let iconW: CGFloat = 18
        let gap: CGFloat = 1
        let h: CGFloat = 18
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.controlTextColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let totalW = iconW + gap + textSize.width + 2

        let img = NSImage(size: NSSize(width: totalW, height: h), flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: 0, width: iconW, height: h))
            let textX = totalW - textSize.width - 1
            let textY: CGFloat = 1
            (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Mini Graph Rendering

    private func renderIconWithGraph(icon: NSImage) -> NSImage {
        let iconW: CGFloat = 18
        let graphW: CGFloat = 16
        let gap: CGFloat = 2
        let totalW = iconW + gap + graphW
        let h: CGFloat = 18

        let img = NSImage(size: NSSize(width: totalW, height: h), flipped: false) { rect in
            // Draw icon
            icon.draw(in: NSRect(x: 0, y: 0, width: iconW, height: h))

            // Draw 3 bars
            let maxVal = max(self.hourlyBuckets.max() ?? 0, 1)
            let barW: CGFloat = 3
            let barSpacing: CGFloat = 1.5
            let barBaseX = iconW + gap
            let barMaxH: CGFloat = 12
            let barY: CGFloat = 3

            NSColor.controlTextColor.setFill()
            for i in 0..<3 {
                let val = self.hourlyBuckets[i]
                let ratio = CGFloat(val) / CGFloat(maxVal)
                let barH = max(1.5, ratio * barMaxH)
                let x = barBaseX + CGFloat(i) * (barW + barSpacing)
                let bar = NSBezierPath(roundedRect: NSRect(x: x, y: barY, width: barW, height: barH),
                                       xRadius: 0.5, yRadius: 0.5)
                bar.fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
