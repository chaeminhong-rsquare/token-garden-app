import AppKit
import Combine

@MainActor
class MenuBarController: ObservableObject {
    @Published var todayTokens: Int = 0

    private var currentFrame = 0
    private weak var statusItem: NSStatusItem?
    private let displayMode: () -> String

    init(
        statusItem: NSStatusItem,
        initialTodayTokens: Int = 0,
        displayMode: @escaping () -> String = { UserDefaults.standard.string(forKey: "displayMode") ?? MenuBarDisplayMode.iconOnly.rawValue }
    ) {
        self.statusItem = statusItem
        self.todayTokens = initialTodayTokens
        self.displayMode = displayMode
        updateTitle()
    }

    func onTokenEvent(_ event: TokenEvent) {
        todayTokens += event.totalTokens
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let mode = MenuBarDisplayMode(rawValue: displayMode()) ?? .iconOnly

        switch mode {
        case .iconOnly:
            button.title = ""
        case .iconAndNumber:
            button.title = " \(TokenFormatter.format(todayTokens))"
        case .iconAndMiniGraph:
            button.title = ""
        }
    }

    /// Called by AppDelegate's timer on every tick
    func tick() {
        currentFrame = (currentFrame + 1) % AnimationFrames.frameCount
        statusItem?.button?.image = AnimationFrames.image(for: currentFrame)
    }
}
