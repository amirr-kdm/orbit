import AppKit
import SwiftUI

/// Study timer: stopwatch (counts up) or Pomodoro (counts down with breaks).
/// Elapsed time is computed from Dates, so it stays accurate in the background.
@MainActor @Observable
final class TimerEngine {
    enum Mode: String, CaseIterable, Identifiable {
        case stopwatch, pomodoro
        var id: String { rawValue }
        var title: String { self == .stopwatch ? "Stopwatch" : "Pomodoro" }
    }

    enum Phase { case focus, rest }

    var mode: Mode = .stopwatch
    /// What is being studied (a to-do from today's list); nil = free study
    var target: TodoRef?
    /// Used for free study (no target)
    var categoryID: UUID?
    var note = ""

    private(set) var phase: Phase = .focus
    private(set) var isRunning = false
    private(set) var accumulated: TimeInterval = 0
    private(set) var runStart: Date?
    private(set) var sessionStart: Date?
    private(set) var now = Date()
    private(set) var completedPomodoros = 0

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let store: AppStore

    /// Sessions shorter than this are not saved
    static let minimumSession: TimeInterval = 30

    init(store: AppStore) {
        self.store = store
    }

    var elapsed: TimeInterval {
        accumulated + (runStart.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Pomodoro phase length
    var phaseLength: TimeInterval? {
        guard mode == .pomodoro else { return nil }
        let minutes = phase == .focus ? store.settings.pomodoroMinutes : store.settings.breakMinutes
        return TimeInterval(minutes * 60)
    }

    var displayTime: TimeInterval {
        if let phaseLength { return max(0, phaseLength - elapsed) }
        return elapsed
    }

    /// Started (running or paused)
    var isActive: Bool { sessionStart != nil }

    var targetTitle: String? { target.flatMap(store.title(of:)) }

    // MARK: Controls

    func start() {
        guard !isRunning else { return }
        if sessionStart == nil { sessionStart = Date() }
        runStart = Date()
        now = Date()
        isRunning = true
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard isRunning else { return }
        now = Date()
        accumulated = elapsed
        runStart = nil
        isRunning = false
        ticker?.invalidate()
        ticker = nil
    }

    func toggle() { isRunning ? pause() : start() }

    /// Finish and save the session
    func stop(save: Bool = true) {
        now = Date()
        if save, phase == .focus { saveSession(duration: elapsed) }
        reset()
        phase = .focus
    }

    /// Pick what to study (only while the timer is idle)
    func select(_ ref: TodoRef?) {
        guard !isActive else { return }
        target = ref
    }

    func skipBreak() {
        reset()
        phase = .focus
    }

    // MARK: Internals

    private func reset() {
        ticker?.invalidate()
        ticker = nil
        accumulated = 0
        runStart = nil
        sessionStart = nil
        isRunning = false
    }

    private func saveSession(duration: TimeInterval) {
        guard duration >= Self.minimumSession, let start = sessionStart else { return }
        store.addSession(store.makeSession(ref: target, categoryID: categoryID,
                                           start: start, duration: duration, note: note))
        note = ""
    }

    private func tick() {
        now = Date()
        if let phaseLength, elapsed >= phaseLength { phaseFinished(length: phaseLength) }
    }

    private func phaseFinished(length: TimeInterval) {
        NSSound(named: "Glass")?.play()
        NSApp.requestUserAttention(.informationalRequest)
        if phase == .focus {
            saveSession(duration: length)
            completedPomodoros += 1
            reset()
            phase = .rest
            start() // the break starts automatically
        } else {
            reset()
            phase = .focus
        }
    }
}
