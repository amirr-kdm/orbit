import SwiftUI
import AppKit

/// One item of the weekly schedule that is about to start
struct NextUpInfo: Equatable {
    var ref: TodoRef?
    var title: String
    var timeText: String
    var start: Date
    var colorHex: String
    var canStart: Bool
    var key: String
}

/// Shows "Next up" in the notch a few minutes before a weekly-schedule item starts (default 10).
/// It sleeps until that moment (one timer, no polling) and looks again when the schedule changes.
@MainActor
final class NextUp {
    static let shared = NextUp()
    private var store: AppStore?
    private var timer: TimerEngine?
    private var work: DispatchWorkItem?
    private var shown = Set<String>()
    private var started = false
    private var lastSig = ""

    func configure(store: AppStore, timer: TimerEngine) {
        self.store = store
        self.timer = timer
    }

    private var enabled: Bool {
        let d = UserDefaults.standard
        return (d.object(forKey: "notchbit.enabled") as? Bool ?? true) && (d.object(forKey: "notchbit.nextUp") as? Bool ?? true)
    }
    private var leadMinutes: Int { max(1, UserDefaults.standard.object(forKey: "notchbit.nextUpLead") as? Int ?? 10) }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .orbitDataSaved, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NextUp.shared.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NextUp.shared.refresh() }
        }
        refresh()
    }

    /// Called when a setting may have changed
    func settingsChanged() {
        let sig = "\(enabled)|\(leadMinutes)"
        if sig != lastSig { lastSig = sig; refresh() }
    }

    func refresh() {
        work?.cancel(); work = nil
        guard started, enabled, let store else { return }
        let now = Date()
        let day = Calendar.current.startOfDay(for: now)
        let lead = TimeInterval(leadMinutes * 60)
        var best: (fire: Date, info: NextUpInfo)?
        for r in store.scheduleRows(on: now) where !r.isDone && !r.isSkipped {
            let start = day.addingTimeInterval(TimeInterval(r.slot.startMinute * 60))
            guard start > now else { continue }
            let key = "\(r.entry.id)|\(Int(day.timeIntervalSince1970))"
            if shown.contains(key) { continue }
            if let b = best, b.info.start <= start { continue }
            let info = NextUpInfo(ref: r.entry.kind == .todo ? .schedule(r.entry.id) : nil, title: r.entry.title, timeText: r.slot.title, start: start,
                                  colorHex: store.colorHex(of: r.entry) ?? "#6366F1", canStart: r.entry.kind == .todo, key: key)
            best = (start.addingTimeInterval(-lead), info)
        }
        // wake up at the moment it is due, and at least every 30 minutes (new day, edited schedule)
        var wake = now.addingTimeInterval(30 * 60)
        if let best {
            if best.fire <= now {
                if NotchbitController.shared.showNextUp(best.info) { shown.insert(best.info.key) }
                wake = now.addingTimeInterval(45)   // the next item, or try again if the notch was busy
            } else {
                wake = min(wake, best.fire)
            }
        }
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, wake.timeIntervalSinceNow), execute: w)
    }
}
