import SwiftUI
import AppKit
import UserNotifications

/// An app that pauses the timer while it is in front (for example Telegram)
struct PauseApp: Codable, Identifiable, Hashable {
    var id: String      // bundle identifier
    var name: String
}

/// Two guards for a timer that is left running by mistake:
///  1. "Still studying?": every so often a small window pops up over whatever is on screen; no answer in 3 minutes stops the timer.
///  2. Chosen apps (Telegram, YouTube's browser …) pause the timer while they are in front and bring it back when the member leaves them.
/// Both settings live on this Mac only (UserDefaults).
@MainActor @Observable
final class TimerGuard {
    static let shared = TimerGuard()
    static let answerSeconds = 180.0

    /// The app that paused the timer right now (nil = not paused by an app)
    private(set) var pausedByApp: String?
    private(set) var asking = false

    @ObservationIgnored private weak var timer: TimerEngine?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var wasRunning = false
    @ObservationIgnored private var lastPresence = Date()
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var deadline = Date()
    @ObservationIgnored private var elapsedAtAsk: TimeInterval = 0
    @ObservationIgnored private var testing = false
    @ObservationIgnored private var lastBeep = Date.distantPast

    // MARK: Settings

    static var enabled: Bool { UserDefaults.standard.object(forKey: "awake.enabled") as? Bool ?? true }
    static var minutes: Int { max(1, UserDefaults.standard.object(forKey: "awake.minutes") as? Int ?? 30) }

    static var apps: [PauseApp] {
        get { (UserDefaults.standard.string(forKey: "timer.pauseApps")?.data(using: .utf8)).flatMap { try? JSONDecoder().decode([PauseApp].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set((try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]", forKey: "timer.pauseApps") }
    }

    // MARK: Start

    func start(timer: TimerEngine) {
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appChanged(app) }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    // MARK: Apps that pause the timer

    private func appChanged(_ app: NSRunningApplication?) {
        guard let timer else { return }
        let chosen = Self.apps
        if let id = app?.bundleIdentifier, chosen.contains(where: { $0.id == id }) {
            if timer.isRunning { timer.pause(); pausedByApp = app?.localizedName ?? id }
        } else if pausedByApp != nil {
            // left the app: the timer comes back (unless the member stopped or restarted it meanwhile)
            if timer.isActive && !timer.isRunning { timer.start() }
            pausedByApp = nil
        }
    }

    // MARK: "Still studying?"

    private func tick() {
        guard let timer else { return }
        let running = timer.isRunning
        if running && !wasRunning { lastPresence = Date() }
        wasRunning = running
        // the member paused, stopped or finished by themselves: the question is no longer needed
        if asking && !running && !testing { closePanel(); asking = false }
        guard Self.enabled, running, !asking, timer.mode == .stopwatch || timer.phase == .focus else { return }
        // using the keyboard or mouse recently means they are there
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle < 120 { lastPresence = Date(); return }
        if Date().timeIntervalSince(lastPresence) >= Double(Self.minutes) * 60 { ask(test: false) }
    }

    func ask(test: Bool) {
        guard !asking else { return }
        asking = true; testing = test
        elapsedAtAsk = timer?.elapsed ?? 0
        deadline = Date().addingTimeInterval(Self.answerSeconds)
        showPanel()
        beep()
        // no answer: the timer stops
        Task { [weak self] in
            while let self, self.asking, Date() < self.deadline {
                try? await Task.sleep(for: .seconds(1))
                if Date().timeIntervalSince(self.lastBeep) > 50 { self.beep() }
            }
            guard let self, self.asking else { return }
            self.timedOut()
        }
    }

    private func beep() { lastBeep = Date(); NSSound(named: NSSound.Name("Funk"))?.play() }

    func confirm() {
        lastPresence = Date()
        asking = false; closePanel()
    }

    /// "Stop timer" button, or the 3 minutes ran out
    func stopNow() { asking = false; closePanel(); if !testing { stopTimer() }; testing = false }

    private func timedOut() {
        asking = false; closePanel()
        if testing { testing = false; return }
        stopTimer()
        let c = UNMutableNotificationContent()
        c.title = "Timer stopped"
        c.body = "You didn't answer, so Orbit stopped the timer and kept the time up to the question."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "timer-idle-stop", content: c, trigger: nil))
    }

    private func stopTimer() { timer?.stopIdle(keeping: elapsedAtAsk) }

    // MARK: The question window

    private func showPanel() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 510), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .screenSaver
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.backgroundColor = .clear
            p.isOpaque = false
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { p.standardWindowButton(b)?.isHidden = true }
            p.contentView = NSHostingView(rootView: AwakeCheckView(guardian: self))
            panel = p
        }
        guard let p = panel else { return }
        p.center()
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
    }

    private func closePanel() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }

    var remaining: TimeInterval { max(0, deadline.timeIntervalSinceNow) }
    var isTest: Bool { testing }
}

struct AwakeCheckView: View {
    let guardian: TimerGuard
    private let night = Color(hex: "#21094A")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            let left = guardian.remaining
            let hurry = 1 - left / TimerGuard.answerSeconds          // 0 → 1 as the minutes run out
            let t = ctx.date.timeIntervalSinceReferenceDate
            VStack(spacing: 0) {
                ZStack {
                    let frames = PlanetPainter.frames("awake_pig")
                    if !frames.isEmpty {
                        // the little animation, 15 pictures a second
                        Image(nsImage: frames[Int(t * 15) % frames.count]).resizable().scaledToFit()
                        // the fire breathes, and burns hotter as the time runs out
                        GeometryReader { g in
                            let flicker = 0.5 + 0.5 * sin(t * 7) * sin(t * 3.1)
                            Ellipse().fill(RadialGradient(colors: [Color(hex: "#FF8A3D").opacity(0.10 + 0.40 * hurry + 0.08 * flicker), .clear], center: .center, startRadius: 0, endRadius: 80))
                                .frame(width: 170, height: 120)
                                .scaleEffect(1 + 0.08 * flicker + 0.2 * hurry)
                                .position(x: g.size.width * 0.5, y: g.size.height * 0.74)
                                .blendMode(.plusLighter)
                        }
                    } else {
                        Text("😴").font(.system(size: 80)).frame(height: 240)
                    }
                    VStack { HStack { Spacer(); countdown(left) }; Spacer() }.padding(14)
                }
                .frame(width: 440, height: 330)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))

                VStack(spacing: 10) {
                    Text("Are you still there?").font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text(guardian.isTest ? "This is only a test: nothing will stop."
                         : hurry > 0.6 ? "Hurry! Answer, or the timer stops and you'll be the one roasting 🔥"
                         : "Your timer is running. No answer in 3 minutes and it stops, keeping the time up to now.")
                        .font(.callout).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center).frame(height: 40)
                    HStack(spacing: 10) {
                        Button { guardian.stopNow() } label: { Text(guardian.isTest ? "Close" : "Stop timer").frame(maxWidth: .infinity) }
                            .controlSize(.large).tint(.white)
                        Button { guardian.confirm() } label: { Text("I'm here  ⏎").fontWeight(.bold).frame(maxWidth: .infinity) }
                            .controlSize(.large).buttonStyle(.borderedProminent).tint(Color(hex: "#FF5E7E")).keyboardShortcut(.defaultAction)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26).padding(.bottom, 22).offset(y: -22)
            }
            .frame(width: 440, height: 510)
            .background(night)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12)))
        }
    }

    private func countdown(_ left: TimeInterval) -> some View {
        Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(left < 45 ? Color.red.opacity(0.85) : Color.black.opacity(0.35)))
    }
}

// MARK: - Settings pieces

struct AwakeCheckSettings: View {
    @AppStorage("awake.enabled") private var enabled = true
    @AppStorage("awake.minutes") private var minutes = 30

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask if I'm still there")
                Text("A small window pops up over any app and asks \"Are you still there?\". If you don't answer in 3 minutes, the timer stops and keeps the time up to the question. It doesn't ask while you are typing or moving the mouse.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if enabled {
            Stepper(value: $minutes, in: 5...180, step: 5) { LabeledContent("Ask every", value: "\(minutes) min") }
        }
        Button("Try it now") { TimerGuard.shared.ask(test: true) }
    }
}

struct PauseAppsSettings: View {
    @State private var apps = TimerGuard.apps

    var body: some View {
        Text("While one of these apps is in front, the timer pauses. When you leave it, the timer starts again by itself.")
            .font(.caption).foregroundStyle(.secondary)
        ForEach(apps) { a in
            HStack(spacing: 10) {
                Image(nsImage: icon(a.id)).resizable().frame(width: 24, height: 24)
                Text(a.name)
                Spacer()
                Button(role: .destructive) { apps.removeAll { $0.id == a.id }; save() } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
        }
        HStack {
            Menu("Add an open app") {
                ForEach(running(), id: \.id) { a in Button(a.name) { add(a) } }
            }
            .fixedSize()
            Button("Choose from Applications…") { choose() }
        }
    }

    private func save() { TimerGuard.apps = apps }
    private func add(_ a: PauseApp) { if !apps.contains(where: { $0.id == a.id }) { apps.append(a); save() } }

    private func icon(_ id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    /// Apps that are open now (not background helpers), except the ones already added and Orbit itself
    private func running() -> [PauseApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { PauseApp(id: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!) }
            .filter { r in !apps.contains { $0.id == r.id } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for url in p.urls {
            if let b = Bundle(url: url), let id = b.bundleIdentifier {
                add(PauseApp(id: id, name: (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent))
            }
        }
    }
}
