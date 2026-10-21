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

    init() {
        // Developer tool: CS_RENDER_PLANETS=/path.png renders all planets to one image and quits
        // (add CS_RENDER_STORE=1 for the store planets)
        if let out = ProcessInfo.processInfo.environment["CS_RENDER_PLANETS"] {
            PlanetSheet.render(to: URL(fileURLWithPath: out),
                               store: ProcessInfo.processInfo.environment["CS_RENDER_STORE"] != nil)
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
        _timer = State(initialValue: TimerEngine(store: store))
        let friends = FriendsService(store: store)
        _friends = State(initialValue: friends)
        let account = AccountService(store: store, friends: friends)
        _account = State(initialValue: account)
        let challenges = ChallengeService(store: store)
        challenges.onRocketsMoved = { [weak account] in await account?.claimGifts() }
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

        MenuBarExtra {
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
    var body: some View {
        Color.clear.onAppear { AppDelegate.openMain = { openWindow(id: "main") } }
    }
}
