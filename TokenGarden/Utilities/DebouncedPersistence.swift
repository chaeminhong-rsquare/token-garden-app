import Foundation

/// Debounces UserDefaults writes so rapid updates collapse into a single write.
/// Used by LogWatcher for `saveOffsets()` which was being called on every FSEvent.
@MainActor
final class DebouncedPersistence {
    private let key: String
    private let delay: TimeInterval
    private var pendingValue: Any?
    private var timer: Timer?

    init(key: String, delay: TimeInterval = 2.0) {
        self.key = key
        self.delay = delay
    }

    /// Schedule a value to be written after `delay` seconds.
    /// Subsequent calls within that window replace the pending value and reset the timer.
    func schedule(_ value: Any) {
        pendingValue = value
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flushNow()
            }
        }
    }

    /// Write the pending value immediately. Called on app stop/terminate.
    func flushNow() {
        timer?.invalidate()
        timer = nil
        if let value = pendingValue {
            UserDefaults.standard.set(value, forKey: key)
            pendingValue = nil
        }
    }
}
