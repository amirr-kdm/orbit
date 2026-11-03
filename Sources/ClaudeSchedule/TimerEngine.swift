import UserNotifications
import AppKit
import AVFoundation
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
        scheduleAlarm()
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
        cancelAlarm()
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
        cancelAlarm()
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

    // MARK: Pomodoro alarm
    //
    // When a Pomodoro phase starts, the system is asked to notify the user when it ends. The system delivers it on time even
    // when Orbit is in the background (or napping), so the user hears and sees it without looking at the app.

    private static let alarmID = "pomodoro-end"
    /// Bumped whenever the alarm is scheduled or cancelled, so a late answer from the system can't schedule a stale one
    @ObservationIgnored private var alarmToken = 0

    private func scheduleAlarm() {
        guard let phaseLength else { cancelAlarm(); return }
        let remaining = phaseLength - elapsed
        guard remaining > 1 else { return }
        let focus = phase == .focus
        let what = targetTitle
        let breakMin = store.settings.breakMinutes
        alarmToken += 1
        let token = alarmToken
        // keep the timer ticking on time while the window is hidden (macOS would otherwise put Orbit to sleep: "App Nap")
        if activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Pomodoro timer") }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = focus ? "Focus session finished 🍅" : "Break is over ⏰"
            c.body = focus ? "\(what.map { "\($0): " } ?? "")nice work! Take a \(breakMin)-minute break." : "Time to get back to studying."
            c.sound = nil   // Orbit plays the chosen sound itself, at the chosen volume
            c.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            DispatchQueue.main.async {
                guard let self, self.alarmToken == token else { return }
                center.removePendingNotificationRequests(withIdentifiers: [Self.alarmID])
                center.add(UNNotificationRequest(identifier: Self.alarmID, content: c, trigger: trigger))
            }
        }
    }

    @ObservationIgnored private var activity: NSObjectProtocol?

    private func cancelAlarm() {
        alarmToken += 1
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.alarmID])
    }

    /// Plays the chosen alarm sound. System sounds are quiet even at full volume, so the volume slider goes past "normal":
    /// the top of the slider is about 4 times louder (+12 dB). Also used by the Settings preview.
    @MainActor private static var engine: AVAudioEngine?

    static func playAlarm(sound: String, volume: Double) {
        let v = min(1, max(0, volume))
        guard v > 0 else { return }
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), eq = AVAudioUnitEQ(numberOfBands: 0)
        eq.globalGain = Float(20 * log10(max(0.001, 4 * v * v)))   // 100% → +12 dB, 50% → 0 dB, 10% → −28 dB
        engine.attach(player); engine.attach(eq)
        var length: TimeInterval = 3
        if let buffer = synthesized(sound) {
            engine.connect(player, to: eq, format: buffer.format)
            engine.connect(eq, to: engine.mainMixerNode, format: buffer.format)
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            length = Double(buffer.frameLength) / buffer.format.sampleRate
        } else {
            let url = URL(fileURLWithPath: "/System/Library/Sounds/\(sound).aiff")
            guard let file = try? AVAudioFile(forReading: url) else {
                // (not a file we can open: the plain way, at most full volume)
                if let s = NSSound(named: NSSound.Name(sound)) { s.volume = Float(v); s.play() }
                return
            }
            engine.connect(player, to: eq, format: file.processingFormat)
            engine.connect(eq, to: engine.mainMixerNode, format: file.processingFormat)
            player.scheduleFile(file, at: nil, completionHandler: nil)
            length = Double(file.length) / file.processingFormat.sampleRate
        }
        do { try engine.start() } catch { return }
        player.play()
        Task { @MainActor in Self.engine = engine }   // retain it while it plays
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.5) { engine.stop() }
    }

    /// Real alarm sounds made from code (no files): beeping like an alarm clock, a digital alarm and a siren.
    static let synthAlarms = ["Alarm Clock", "Digital Alarm", "Siren"]

    private static func synthesized(_ name: String) -> AVAudioPCMBuffer? {
        guard synthAlarms.contains(name) else { return nil }
        let sr = 44100.0
        var out: [Float] = []
        /// one beep: a bright, buzzy tone with a short fade in and out so it doesn't click
        func beep(_ f: Double, _ seconds: Double) {
            let n = Int(seconds * sr), fade = Int(0.004 * sr)
            for i in 0..<n {
                let t = Double(i) / sr
                var x = sin(2 * .pi * f * t) + 0.5 * sin(2 * .pi * 3 * f * t) + 0.25 * sin(2 * .pi * 5 * f * t)
                x *= 0.4
                let e = min(1, Double(min(i, n - 1 - i)) / Double(fade))
                out.append(Float(x * e))
            }
        }
        func silence(_ seconds: Double) { out.append(contentsOf: [Float](repeating: 0, count: Int(seconds * sr))) }
        switch name {
        case "Alarm Clock":      // beep-beep-beep-beep … pause … (4 times)
            for _ in 0..<4 { for _ in 0..<4 { beep(1450, 0.11); silence(0.08) }; silence(0.45) }
        case "Digital Alarm":    // fast high beeps in threes
            for _ in 0..<5 { for _ in 0..<3 { beep(2600, 0.14); silence(0.07) }; silence(0.4) }
        default:                 // siren: sweeping up and down for 6 seconds
            var phase = 0.0
            for i in 0..<Int(6 * sr) {
                let t = Double(i) / sr
                let f = 850 + 350 * sin(2 * .pi * t)
                phase += 2 * .pi * f / sr
                out.append(Float(0.4 * (sin(phase) + 0.4 * sin(2 * phase))))
            }
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(out.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(out.count)
        out.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: out.count) }
        return buffer
    }

    /// macOS system sounds offered in Settings
    static let alarmSounds = synthAlarms + ["Glass", "Ping", "Hero", "Submarine", "Funk", "Tink", "Pop", "Purr", "Bottle", "Blow", "Frog", "Morse", "Basso", "Sosumi"]

    private func phaseFinished(length: TimeInterval) {
        Self.playAlarm(sound: store.settings.alarmSound, volume: store.settings.alarmVolume)
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
