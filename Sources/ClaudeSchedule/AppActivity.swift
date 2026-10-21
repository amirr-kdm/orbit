import AppKit
import Observation

/// Is Orbit the app in front? Decorative animations stop while it isn't (saves CPU and battery).
@MainActor @Observable
final class AppActivity {
    static let shared = AppActivity()
    private(set) var isActive = NSApp?.isActive ?? true

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = true }
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = false }
        }
    }

    /// For `TimelineView(.animation(minimumInterval:paused:))`
    static var paused: Bool { !shared.isActive }
}
