import SwiftUI
import AppKit

/// What the notch shows and how big it is
@MainActor @Observable
final class NotchbitModel {
    static let shared = NotchbitModel()

    enum Level: Int { case closed, peek, full }
    enum Tab: String, CaseIterable, Identifiable {
        case timer = "Timer", tasks = "Tasks", music = "Music", countdown = "Days"
        var id: String { rawValue }
        var icon: String { self == .timer ? "timer" : self == .tasks ? "checklist" : self == .music ? "music.note" : "hourglass" }
    }

    var level: Level = .closed
    /// The size the content is laid out at. It follows `level` at once when opening and only after the shape has shrunk when closing,
    /// so the content never gets squeezed while the shape grows or shrinks.
    var layoutLevel: Level = .closed
    var tab: Tab = .timer
    /// Typing in the "add a task" field: the notch stays open
    var editing = false
    /// A list that scrolls is showing (tasks, task picker): only the top strip takes the swipe
    var listOpen = false
    /// The real notch (or a pretend one on a Mac without a notch)
    var notchW: CGFloat = 190
    var notchH: CGFloat = 32

    /// Bumped when a Notchbit setting changes, so the notch redraws at once (its own copy of the settings can lag behind)
    var settingsRevision = 0

    @ObservationIgnored var timer: TimerEngine?

    /// A volume / brightness change shown in the notch for a moment
    struct HUD: Equatable {
        enum Kind { case volume, brightness, keyboard, battery, song }
        var kind: Kind
        var value: Double
        var muted: Bool
        /// keyboard layout: the short code ("EN") and the layout's name
        var code = ""
        var name = ""
        var charging = false
    }
    var hud: HUD?
    /// The screen is locked: the notch shows only the planet and a lock, and does not open
    var screenLocked = false
    /// "Next up": the weekly-schedule item that is about to start (the small view shows it)
    var nextUp: NextUpInfo?
    @ObservationIgnored private var hudWork: DispatchWorkItem?

    var hudShown: Bool { hud != nil && Self.flag("notchbit.hud") }
    /// "drop": a second row under the notch (default); "inline": beside the notch
    static var hudDrop: Bool { (UserDefaults.standard.string(forKey: "notchbit.hudStyle") ?? "drop") == "drop" }
    var hudInline: Bool { hudShown && !Self.hudDrop && hud?.kind != .battery && hud?.kind != .song }
    var hudDropShown: Bool { hudShown && (Self.hudDrop || hud?.kind == .song) && hud?.kind != .battery }
    /// The battery is always a tiny icon and percentage on the right of the notch
    var batteryShown: Bool { hudShown && hud?.kind == .battery }

    /// A lock / unlock sign on the right of the notch
    enum LockState { case locked, unlocked }
    var lock: LockState?
    var lockShown: Bool { lock != nil && Self.flag("notchbit.hudLock") }
    @ObservationIgnored private var lockWork: DispatchWorkItem?

    func showLock(_ locked: Bool) {
        guard Self.flag("notchbit.enabled"), Self.flag("notchbit.hudLock") else { return }
        lockWork?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { lock = locked ? .locked : .unlocked }
        if !locked {
            let w = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self?.lock = nil } }
            }
            lockWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: w)
        }
    }

    /// The next song: its name under the notch for a moment
    func showSong(title: String, artist: String) {
        guard Self.flag("notchbit.hudSong"), level == .closed, !screenLocked else { return }
        showHUD(.song, 0, muted: false, code: artist, name: title, seconds: 3.2)
    }

    func showKeyboard(code: String, name: String) {
        guard Self.flag("notchbit.hudKeyboard") else { return }
        showHUD(.keyboard, 0, muted: false, code: code, name: name)
    }

    func showBattery(percent: Int, charging: Bool, text: String) {
        guard Self.flag("notchbit.hudBattery") else { return }
        showHUD(.battery, Double(percent) / 100, muted: false, name: text, charging: charging, seconds: 2.6)
    }

    func showHUD(_ kind: HUD.Kind, _ value: Double, muted: Bool, code: String = "", name: String = "", charging: Bool = false, seconds: Double = 1.7) {
        guard Self.flag("notchbit.enabled"), Self.flag("notchbit.hud") else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            hud = HUD(kind: kind, value: max(0, min(1, value)), muted: muted, code: code, name: name, charging: charging)
        }
        hudWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self?.hud = nil } }
        }
        hudWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private static func flag(_ key: String, _ fallback: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    /// Settings (Notchbit page)
    static var planetSize: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "notchbit.planetSize") as? Double ?? 30) }
    static var speed: Double { UserDefaults.standard.object(forKey: "notchbit.speed") as? Double ?? 1 }
    static var openDelay: Double { UserDefaults.standard.object(forKey: "notchbit.openDelay") as? Double ?? 0.12 }
    static var closeDelay: Double { UserDefaults.standard.object(forKey: "notchbit.closeDelay") as? Double ?? 0.35 }
    static var spring: Animation { .spring(response: 0.42 / max(0.3, speed), dampingFraction: 0.78) }

    var timerShown: Bool { timer?.isActive ?? false }
    var badgeShown: Bool { !screenLocked && Self.flag("notchbit.leitner", false) && LeitnerStore.shared.totalDue > 0 }

    /// The black wings on each side of the notch while it is closed
    private var leftNeed: CGFloat { screenLocked ? Self.planetSize + 12 : hudInline ? max(Self.planetSize + 12, 52) : Self.planetSize + 12 + (badgeShown ? 26 : 0) }
    /// While music plays the right side shows headphones instead of the timer
    var musicShown: Bool { NowPlaying.shared.isActive }
    private var rightNeed: CGFloat { hudInline ? 122 : (batteryShown ? 66 : (lockShown ? 36 : (musicShown ? 42 : (timerShown ? 80 : 0)))) }
    /// Both sides of the notch are always the same width, so the shape stays centred on the real notch
    var leftWing: CGFloat { max(leftNeed, rightNeed) }
    var rightWing: CGFloat { max(leftNeed, rightNeed) }

    func size(_ l: Level) -> CGSize {
        switch l {
        case .closed: CGSize(width: notchW + leftWing + rightWing, height: notchH + (hudDropShown ? (hud?.kind == .keyboard || hud?.kind == .song ? 26 : 29) : 0))
        case .peek: CGSize(width: max(336, notchW + 150), height: notchH + 60)
        case .full: CGSize(width: 372, height: notchH + (tab == .timer ? 160 : (tab == .tasks ? 176 : 120)))
        }
    }

    /// Where the black shape is on the screen (screen coordinates, origin bottom-left)
    func rect(_ l: Level, on screen: NSScreen) -> NSRect {
        let s = size(l)
        let offset: CGFloat = 0
        return NSRect(x: screen.frame.midX + offset - s.width / 2, y: screen.frame.maxY - s.height, width: s.width, height: s.height)
    }
}

private final class NotchPanel: NSPanel {
    /// Only the big view has a text field; elsewhere the notch must never take the keyboard (or the mouse-over effects) from Orbit's windows
    override var canBecomeKey: Bool { MainActor.assumeIsolated { NotchbitModel.shared.level == .full } }
    override var canBecomeMain: Bool { false }
}

/// The small window that sits over the notch: hover to open it, two fingers up / down on the trackpad to open or close it
@MainActor
final class NotchbitController {
    static let shared = NotchbitController()

    private let model = NotchbitModel.shared
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var poll: Timer?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var frameToken = 0
    /// After closing with a swipe, stay closed until the pointer has left the notch
    private var suppress = false
    private var configured = false
    private var scrollSum: CGFloat = 0
    private var scrollDone = false
    private var sideSum: CGFloat = 0
    private var axis = 0
    private var lastWheel = Date.distantPast

    private func flag(_ key: String, _ fallback: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    private var enabled: Bool { flag("notchbit.enabled") }

    /// Looked up once (and again when the screens change): asking macOS for the screen list 25 times a second is wasteful
    private var cachedScreen: NSScreen?
    private var screen: NSScreen {
        if let cachedScreen { return cachedScreen }
        let s = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        cachedScreen = s
        return s
    }
    private var lastMouse = NSPoint(x: -1, y: -1)

    /// Opens the Notchbit page in the Orbit window (set by the app)
    var openSettings: (() -> Void)?
    var openCountdown: (() -> Void)?
    private var store: AppStore?
    private var timer: TimerEngine?

    /// Called while the app is being built: only remembers what it needs (the screen is not ready yet)
    func configure(store: AppStore, timer: TimerEngine) {
        self.store = store
        self.timer = timer
        model.timer = timer
        NextUp.shared.configure(store: store, timer: timer)
    }

    /// Called once the app has launched
    func start() {
        guard !configured, let store, let timer else { return }
        configured = true
        NowPlaying.shared.start()
        NextUp.shared.start()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchbitController.shared.refresh(); NotchbitController.shared.settingsMayHaveChanged(); NowPlayingBridge.shared.sync() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchbitController.shared.measure(); NotchbitController.shared.applyFrame() }
        }
        let host = NSHostingView(rootView: NotchbitView().environment(store).environment(timer))
        host.sizingOptions = []
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.acceptsMouseMovedEvents = true
        p.becomesKeyOnlyIfNeeded = true
        p.ignoresMouseEvents = true
        panel = p
        refresh()
    }

    private var lastSettings = ""

    /// Looks at the settings the notch shows and tells it to redraw when one of them changed
    func settingsMayHaveChanged() {
        let d = UserDefaults.standard
        let keys = ["notchbit.planet", "notchbit.planetSize", "notchbit.logo", "notchbit.logoScales", "notchbit.leitner", "notchbit.speed", "notchbit.hud", "notchbit.hudStyle", "notchbit.hudVolumeHex", "notchbit.hudBrightnessHex"]
        let sig = keys.map { "\(d.object(forKey: $0) ?? "-")" }.joined(separator: "|")
        if sig != lastSettings { lastSettings = sig; model.settingsRevision += 1 }
        SystemHUD.shared.syncKeys()
        NextUp.shared.settingsChanged()
    }

    private var wasEnabled: Bool?
    private var lockAttached = false

    /// The window only has its number once it is really on screen: try again a few times
    private func attachLockScreen(tries: Int) {
        guard !lockAttached, LockScreen.wanted, let p = panel else { return }
        if LockScreen.attach(p) { lockAttached = true; return }
        guard tries > 0 else { NSLog("[Notchbit] lock screen: gave up (window number %d)", p.windowNumber); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated { self?.attachLockScreen(tries: tries - 1) }
        }
    }

    /// Switch on / off. Called whenever any setting changes, so it only acts when the on / off switch itself changed
    /// (the timer saves its state every few seconds, which also counts as a settings change).
    func refresh() {
        guard configured else { return }
        let on = enabled
        if on == wasEnabled { return }
        wasEnabled = on
        if on {
            measure()
            applyFrame()
            panel?.orderFrontRegardless()
            attachLockScreen(tries: 8)
            SystemHUD.shared.start()
            // The pointer is checked on a light timer: mouse-moved events are not delivered while Orbit itself is in front
            if poll == nil {
                let t = Timer(timeInterval: 0.05, repeats: true) { _ in
                    MainActor.assumeIsolated { NotchbitController.shared.moved() }
                }
                RunLoop.main.add(t, forMode: .common)
                poll = t
            }
            if monitors.isEmpty {
                // scroll events only: reading scroll fields from a mouse-moved event throws an exception on every move, which made Orbit lag
                let mask: NSEvent.EventTypeMask = [.scrollWheel]
                if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { e in
                    let type = e.type, dx = e.scrollingDeltaX, dy = e.scrollingDeltaY, inverted = e.isDirectionInvertedFromDevice
                    let phase = e.phase, momentum = e.momentumPhase, precise = e.hasPreciseScrollingDeltas
                    MainActor.assumeIsolated { NotchbitController.shared.event(type, dx, dy, inverted, phase, momentum, precise) }
                }) { monitors.append(g) }
                if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in
                    let type = e.type, dx = e.scrollingDeltaX, dy = e.scrollingDeltaY, inverted = e.isDirectionInvertedFromDevice
                    let phase = e.phase, momentum = e.momentumPhase, precise = e.hasPreciseScrollingDeltas
                    MainActor.assumeIsolated { NotchbitController.shared.event(type, dx, dy, inverted, phase, momentum, precise) }
                    return e
                }) { monitors.append(l) }
            }
        } else {
            poll?.invalidate(); poll = nil
            SystemHUD.shared.stop()
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
            model.level = .closed
            panel?.orderOut(nil)
        }
    }

    // MARK: Geometry

    func measure() {
        cachedScreen = nil
        let s = screen
        let h = s.safeAreaInsets.top
        if h > 0 {
            let left = s.auxiliaryTopLeftArea?.width ?? 0, right = s.auxiliaryTopRightArea?.width ?? 0
            model.notchW = (left > 0 && right > 0 ? s.frame.width - left - right : 190) + 2
            model.notchH = h
        } else {
            // a Mac without a notch: a pretend one the height of the menu bar
            model.notchW = 170
            model.notchH = max(24, s.frame.maxY - s.visibleFrame.maxY)
        }
    }

    /// The panel is only as big as what is showing (the rest of the screen stays clickable)
    private func panelFrame(for level: NotchbitModel.Level, minHeight: CGFloat = 0) -> NSRect {
        let s = screen
        var size = model.size(level)
        let pad: CGFloat = 16
        if level == .closed {
            // room for a big music picture (it may reach beyond the notch); this window ignores the mouse while closed
            let wing = max(model.leftWing, model.rightWing, 90) + 120
            size = CGSize(width: model.notchW + 2 * wing, height: model.notchH + 90)
        }
        let w = size.width + 2 * pad, h = max(size.height, minHeight) + pad
        return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h)
    }

    func applyFrame() {
        guard let p = panel else { return }
        p.setFrame(panelFrame(for: model.level), display: true)
    }

    private func zone(_ level: NotchbitModel.Level) -> NSRect {
        let r = model.rect(level, on: screen)
        return level == .closed ? NSRect(x: r.minX - 3, y: r.minY - 3, width: r.width + 6, height: r.height + 12)
                                : NSRect(x: r.minX - 10, y: r.minY - 12, width: r.width + 20, height: r.height + 24)
    }

    /// Called when the screen locks or unlocks
    func screenLockChanged(_ locked: Bool) {
        model.screenLocked = locked
        if locked {
            openWork?.cancel(); openWork = nil; closeWork?.cancel(); closeWork = nil
            model.nextUp = nil
            if model.level != .closed { set(.closed) }
        }
        if let p = panel { LockScreen.attach(p) }
    }

    // MARK: Next up

    private var nextUpWork: DispatchWorkItem?

    /// Opens the small view with the item that is about to start. false = not now (the notch is busy)
    func showNextUp(_ info: NextUpInfo) -> Bool {
        guard enabled, panel != nil, model.level == .closed, !model.editing else { return false }
        model.nextUp = info
        set(.peek)
        nextUpWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.autoDismissNextUp(info.key) }
        nextUpWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 14, execute: w)
        return true
    }

    /// Goes away by itself, but not while the pointer is on it
    private func autoDismissNextUp(_ key: String) {
        guard model.nextUp?.key == key else { return }
        if zone(model.level).contains(NSEvent.mouseLocation) {
            let w = DispatchWorkItem { [weak self] in self?.autoDismissNextUp(key) }
            nextUpWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
        } else {
            dismissNextUp()
        }
    }

    func dismissNextUp() {
        nextUpWork?.cancel(); nextUpWork = nil
        model.nextUp = nil
        if model.level == .peek { set(.closed) }
    }

    // MARK: Opening and closing

    func set(_ level: NotchbitModel.Level, tab: NotchbitModel.Tab? = nil) {
        if let tab { model.tab = tab }
        guard level != model.level, let p = panel else { return }
        openWork?.cancel(); openWork = nil; closeWork?.cancel(); closeWork = nil
        let growing = level.rawValue > model.level.rawValue
        frameToken += 1
        let token = frameToken
        if growing {
            p.ignoresMouseEvents = false
            p.setFrame(panelFrame(for: level), display: false)
        }
        if growing { haptic() }
        if growing { model.layoutLevel = level }
        withAnimation(NotchbitModel.spring) { model.level = level }
        if !growing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 / max(0.3, NotchbitModel.speed)) { [weak self] in
                guard let self, self.frameToken == token, let p = self.panel else { return }
                self.model.layoutLevel = level
                p.setFrame(self.panelFrame(for: level), display: true)
                if p.isKeyWindow {
                    p.resignKey()
                    NSApp.windows.first { $0 !== p && $0.canBecomeKey && $0.isVisible }?.makeKey()
                }
                if level == .closed {
                    NowPlaying.shared.dropHold()
                    p.ignoresMouseEvents = true
                    self.model.editing = false
                    self.model.nextUp = nil
                    p.makeFirstResponder(nil)
                }
            }
        }
    }

    private func event(_ type: NSEvent.EventType, _ dx: CGFloat, _ dy: CGFloat, _ inverted: Bool,
                       _ phase: NSEvent.Phase, _ momentum: NSEvent.Phase, _ precise: Bool) {
        guard enabled, !model.screenLocked else { return }
        if type == .scrollWheel { scrolled(dx, dy, inverted, phase, momentum, precise) }
    }

    private func moved() {
        if model.screenLocked { return }
        let loc = NSEvent.mouseLocation
        // nothing to do while the pointer stands still (pending opens / closes run on their own timers)
        if loc == lastMouse { return }
        lastMouse = loc
        if model.level == .closed {
            if zone(.closed).contains(loc) {
                guard flag("notchbit.hover"), !suppress, openWork?.isCancelled ?? true else { return }
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.openWork = nil
                    if self.zone(.closed).contains(NSEvent.mouseLocation) { self.set(.peek) }
                }
                openWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchbitModel.openDelay, execute: w)
            } else {
                openWork?.cancel(); openWork = nil
                suppress = false
            }
        } else {
            if zone(model.level).contains(loc) {
                closeWork?.cancel(); closeWork = nil
            } else if closeWork?.isCancelled ?? true, !model.editing {
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.closeWork = nil
                    if !self.model.editing, !self.zone(self.model.level).contains(NSEvent.mouseLocation) { self.set(.closed) }
                }
                closeWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchbitModel.closeDelay, execute: w)
            }
        }
    }

    /// Two fingers down on the notch opens it a step; two fingers up closes it a step.
    /// Sideways: next / previous song (small view while music plays), or flip tabs (big view).
    /// A swipe is read as one direction only: it is locked to up/down or left/right after its first moment.
    private func scrolled(_ dx: CGFloat, _ dy: CGFloat, _ inverted: Bool, _ phase: NSEvent.Phase, _ momentum: NSEvent.Phase, _ precise: Bool) {
        guard flag("notchbit.scroll") else { return }
        let loc = NSEvent.mouseLocation
        let s = screen
        guard zone(model.level).contains(loc) else { return }
        guard momentum.isEmpty else { return }
        let sideways = model.level == .full || (model.level == .peek && NowPlaying.shared.showing)

        if !precise {
            // a mouse wheel: one step per click, up / down only
            if model.level == .full, model.listOpen, loc.y < s.frame.maxY - model.notchH - 8 { return }
            guard Date().timeIntervalSince(lastWheel) > 0.35, dy != 0 else { return }
            lastWheel = Date()
            step(down: (inverted ? dy : -dy) > 0)
            return
        }

        if phase.contains(.began) || phase.contains(.mayBegin) { scrollSum = 0; sideSum = 0; axis = 0; scrollDone = false }
        scrollSum += inverted ? dy : -dy      // positive = fingers moved down
        sideSum += inverted ? dx : -dx        // negative = fingers moved left
        if phase.contains(.ended) || phase.contains(.cancelled) { scrollSum = 0; sideSum = 0; axis = 0; scrollDone = false; return }

        if axis == 0, abs(scrollSum) + abs(sideSum) > 10 {
            axis = sideways && abs(sideSum) > abs(scrollSum) * 1.6 ? 1 : 2
        }
        guard axis != 0, !scrollDone else { return }

        if axis == 1 {
            guard abs(sideSum) > 36 else { return }
            scrollDone = true
            if model.level == .peek {
                if sideSum > 0 { NowPlaying.shared.previous() } else { NowPlaying.shared.next() }   // fingers right = previous, left = next
                haptic()
            } else {
                let tabs = NotchbitModel.Tab.allCases
                if let i = tabs.firstIndex(of: model.tab) {
                    let next = sideSum < 0 ? i + 1 : i - 1
                    if tabs.indices.contains(next) { setTab(tabs[next]) }
                }
            }
        } else {
            // while a list is showing on the big view, the list scrolls: only the top strip takes the swipe
            if model.level == .full, model.listOpen, loc.y < s.frame.maxY - model.notchH - 8 { return }
            guard abs(scrollSum) > 16 else { return }
            scrollDone = true
            step(down: scrollSum > 0)
        }
    }

    private func step(down: Bool) {
        switch (model.level, down) {
        case (.closed, true): set(.peek)
        case (.peek, true): set(.full)
        case (.full, false): set(.peek)
        case (.peek, false): suppress = true; set(.closed)
        default: break
        }
    }

    /// A tap on the trackpad as the notch opens
    func haptic() {
        guard flag("notchbit.haptic") else { return }
        let style = UserDefaults.standard.integer(forKey: "notchbit.hapticStyle")
        let pattern: NSHapticFeedbackManager.FeedbackPattern = style == 0 ? .alignment : style == 1 ? .generic : .levelChange
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// Switch tab; the window grows first and shrinks after, so nothing is cut off
    func setTab(_ t: NotchbitModel.Tab) {
        guard t != model.tab, let p = panel else { return }
        let oldHeight = model.size(.full).height
        frameToken += 1
        let token = frameToken
        p.setFrame(panelFrame(for: .full, minHeight: oldHeight), display: false)
        withAnimation(NotchbitModel.spring) { model.tab = t }
        let big = max(oldHeight, model.size(.full).height)
        p.setFrame(panelFrame(for: .full, minHeight: big), display: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.frameToken == token, self.model.level == .full else { return }
            self.applyFrame()
        }
    }

    func closeNow() { suppress = true; set(.closed) }
}
