import SwiftUI

@main
struct ClaudeScheduleApp: App {
    @State private var store: AppStore
    @State private var timer: TimerEngine
    @State private var friends: FriendsService
    @State private var router = Router()

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
        _friends = State(initialValue: FriendsService(store: store))
    }

    var body: some Scene {
        WindowGroup("Orbit", id: "main") {
            ContentView()
                .frame(minWidth: 1080, minHeight: 660)
                .environment(store)
                .environment(timer)
                .environment(router)
                .environment(friends)
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
            openWindow(id: "main")
            router.selection = .timer
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
