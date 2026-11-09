import SwiftUI

@main
struct ClaudeScheduleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore
    @State private var timer: TimerEngine
    @State private var friends: FriendsService
    @State private var account: AccountService
    @State private var challenges: ChallengeService
    @State private var fightClub: FightClubService
    @State private var router = Router()
    @State private var updates = UpdateChecker()
    /// With Notchbit on, the timer lives in the notch and this menu bar icon is hidden
    @AppStorage("notchbit.enabled") private var notchOn = true

    init() {
        // Developer tool: CS_RENDER_PLANETS=/path.png renders all planets to one image and quits
        // (add CS_RENDER_STORE=1 for the store planets)
        if let out = ProcessInfo.processInfo.environment["CS_RENDER_PLANETS"] {
            PlanetSheet.render(to: URL(fileURLWithPath: out),
                               store: ProcessInfo.processInfo.environment["CS_RENDER_STORE"] != nil)
            exit(0)
        }
        if let out = ProcessInfo.processInfo.environment["CS_RENDER_GIFT"] {
            GiftSheet.render(to: URL(fileURLWithPath: out))
            exit(0)
        }
        if let out = ProcessInfo.processInfo.environment["CS_RENDER_SYSTEM"] {
            let system = GalaxyData.System(id: UUID(), name: "Home System", sun: .binary,
                                           planets: ["terra", "saturnella", "kitty", "heartbeat", "phoenix", "royale", "octo", "claude"])
            let r = ImageRenderer(content: SolarSystemView(system: system, large: true).frame(width: 1100, height: 600))
            if let img = r.nsImage, let t = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
            }
            exit(0)
        }
        let store = AppStore()
        _store = State(initialValue: store)
        let engine = TimerEngine(store: store)
        _timer = State(initialValue: engine)
        TimerGuard.shared.start(timer: engine)
        NotchbitController.shared.configure(store: store, timer: engine)
        MacSync.shared.start(store: store)
        let friends = FriendsService(store: store)
        _friends = State(initialValue: friends)
        let account = AccountService(store: store, friends: friends)
        _account = State(initialValue: account)
        let challenges = ChallengeService(store: store)
        challenges.onRocketsMoved = { [weak account] in await account?.claimGifts() }
        challenges.groupName = { [weak friends] id in friends?.groups.first { $0.id == id }?.name }
        challenges.testGroupID = { [weak friends] in friends?.groups.first?.id }
        _challenges = State(initialValue: challenges)
        let fightClub = FightClubService(store: store)
        fightClub.onRocketsMoved = { [weak account] in await account?.claimGifts() }
        fightClub.testFriendID = { [weak friends] in friends?.friends.first?.id }
        _fightClub = State(initialValue: fightClub)
    }

    var body: some Scene {
        Window("Orbit", id: "main") {
            RootView()
                .background(WindowOpener())
                .frame(minWidth: 1080, minHeight: 660)
                .environment(account)
                .environment(store)
                .environment(timer)
                .environment(router)
                .environment(friends)
                .environment(updates)
                .environment(challenges)
                .environment(fightClub)
                .task { updates.start() }
        }
        .defaultSize(width: 1320, height: 820)

        MenuBarExtra(isInserted: Binding(get: { !notchOn }, set: { _ in })) {
            MenuBarContent()
                .environment(store)
                .environment(timer)
                .environment(router)
        } label: {
            if timer.isActive {
                Text("⏱ " + Fmt.clock(timer.displayTime))
            } else {
                Image(systemName: "timer")
            }
        }
    }
}

/// Today's word count beside the clock (Settings → Leitner words can turn it off). Plain AppKit: a menu bar item that
/// follows the "leitner.showInMenuBar" setting and refreshes its number every second or two.
@MainActor
final class WordsStatusItem: NSObject, NSMenuDelegate {
    static let shared = WordsStatusItem()
    private var item: NSStatusItem?
    private var timer: Timer?
    var openLeitner: (() -> Void)?

    func start() {
        apply()
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    @objc private func defaultsChanged() { apply() }

    private var wanted: Bool { UserDefaults.standard.object(forKey: "leitner.showInMenuBar") as? Bool ?? true }

    private func apply() {
        if wanted, item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let m = NSMenu(); m.delegate = self
            i.menu = m
            item = i
            refresh()
        } else if !wanted, let i = item {
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
    }

    private func refresh() {
        guard let b = item?.button else { return }
        let n = LeitnerStore.shared.reviewedToday
        b.image = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: "Words reviewed today")
        b.imagePosition = .imageLeading
        b.title = " \(n)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let l = LeitnerStore.shared
        menu.removeAllItems()
        menu.addItem(withTitle: "Words today: \(l.reviewedToday) of \(l.dailyGoal)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "\(l.totalDue) left to review", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let review = NSMenuItem(title: "Review Words…  ⌃⌥L", action: #selector(review), keyEquivalent: ""); review.target = self
        let open = NSMenuItem(title: "Open Leitner Box", action: #selector(openBox), keyEquivalent: ""); open.target = self
        menu.addItem(review); menu.addItem(open)
    }

    @objc private func review() { LeitnerQuickPanel.shared.show() }
    @objc private func openBox() { openLeitner?() }
}

/// The timer's menu in the macOS menu bar
struct MenuBarContent: View {
    @Environment(TimerEngine.self) private var timer
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if timer.isActive {
            Text("\(timer.phase == .rest ? "Break" : (timer.targetTitle ?? "Studying")) — \(Fmt.clock(timer.displayTime))")
            Button(timer.isRunning ? "Pause" : "Resume") { timer.toggle() }
            Button("Finish & Save") { timer.stop() }
        } else {
            Button("Start Timer") { timer.start() }
        }
        Divider()
        Text("Studied today: \(Fmt.duration(store.studyTime(on: Date())))")
        Text("Words: \(LeitnerStore.shared.reviewedToday) reviewed · \(LeitnerStore.shared.totalDue) left")
        Button("Review Words…  ⌃⌥L") { LeitnerQuickPanel.shared.show() }
        Divider()
        Button("Open Orbit") {
            AppDelegate.openMain = AppDelegate.openMain ?? { openWindow(id: "main") }
            AppDelegate.showMain()
            router.selection = .timer
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Brings the main window back after it was closed with the red button
/// (the app keeps running for the menu bar timer).
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var openMain: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { LeitnerHotKey.register(); WordsStatusItem.shared.start(); NotchbitController.shared.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { Self.showMain() } }
        return true
    }

    @MainActor static func showMain() {
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Keeps a way to reopen the main window from outside SwiftUI
private struct WindowOpener: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(Router.self) private var router
    var body: some View {
        Color.clear.onAppear {
            AppDelegate.openMain = { openWindow(id: "main") }
            NotchbitController.shared.openCountdown = { router.selection = .countdown; AppDelegate.showMain() }
            NotchbitController.shared.openSettings = { router.selection = .notchbit; AppDelegate.showMain() }
            WordsStatusItem.shared.openLeitner = { router.selection = .leitner; AppDelegate.showMain() }
        }
    }
}
