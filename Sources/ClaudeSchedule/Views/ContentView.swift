import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case today, schedule, planner, timer, leitner, spelling, countdown, phoneSync, notchbit, tasks, calendar, reports, galaxy, store, friends, groups, challenges, fightClub, settings, about

    var id: String { rawValue }

    /// Sidebar groups, in order: plan the week → do the work → progress & rewards → people → app
    static let sections: [(title: String, items: [SidebarItem])] = [
        ("Plan", [.today, .schedule, .tasks, .calendar, .planner]),
        ("Focus", [.timer, .leitner, .spelling, .countdown, .reports]),
        ("Rewards", [.galaxy, .store]),
        ("Social", [.friends, .groups, .challenges, .fightClub]),
        ("App", [.notchbit, .phoneSync, .settings, .about]),
    ]
    var title: String {
        switch self {
        case .today: "Today"
        case .schedule: "Weekly Schedule"
        case .planner: "Mission Control"
        case .timer: "Timer"
        case .leitner: "Leitner Box"
        case .spelling: "Spelling"
        case .notchbit: "Notchbit"
        case .countdown: "Countdown"
        case .phoneSync: "Phone Sync"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .reports: "Reports"
        case .galaxy: "My Galaxy"
        case .store: "Store"
        case .friends: "Friends"
        case .groups: "Groups"
        case .challenges: "Challenges"
        case .fightClub: "Fight Club"
        case .settings: "Settings"
        case .about: "About"
        }
    }
    var icon: String {
        switch self {
        case .today: "checklist"
        case .schedule: "tablecells"
        case .planner: "square.grid.2x2.fill"
        case .timer: "timer"
        case .leitner: "archivebox.fill"
        case .spelling: "ear.and.waveform"
        case .notchbit: "capsule.tophalf.filled"
        case .countdown: "hourglass"
        case .phoneSync: MacSync.unlocked ? "iphone" : "lock.fill"
        case .tasks: "tray.full"
        case .calendar: "calendar"
        case .reports: "chart.bar.xaxis"
        case .galaxy: "sparkles"
        case .store: "bag"
        case .friends: "person.2"
        case .groups: "person.3"
        case .challenges: "flag.checkered"
        case .fightClub: "burst.fill"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }
}

struct ContentView: View {
    @Environment(Router.self) private var router
    @Environment(TimerEngine.self) private var timer
    @Environment(AppStore.self) private var store
    @Environment(FriendsService.self) private var friends
    @Environment(AccountService.self) private var account
    @Environment(UpdateChecker.self) private var updates
    @Environment(ChallengeService.self) private var challenges
    @Environment(FightClubService.self) private var fightClub
    @State private var showAdmin = false
    @State private var gifts = PlanetGiftService.shared
    @State private var showQuickTask = false
    @State private var showAbout = false
    @State private var donePrompt: TimerEngine.FinishedTask?

    /// Opens "Is it done?" once no other window (the Level Pass) is up; a little later, so the other one has finished closing
    private func showDonePromptWhenFree() {
        guard timer.finished != nil, donePrompt == nil, store.passMoment == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if donePrompt == nil, store.passMoment == nil, let f = timer.finished { donePrompt = f }
        }
    }
    @Environment(\.colorScheme) private var scheme
    /// Midnight Black in dark mode: the whole app turns pure black (sidebar and pages)
    private var allBlack: Bool { store.settings.template == .midnight && scheme == .dark }
    /// Page colour behind everything: pure black for Midnight Black in dark mode, warm cream in light mode
    private var pageColor: Color? { allBlack ? .black : (scheme == .light ? store.settings.template.lightPage : nil) }

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.selection) {
                ForEach(SidebarItem.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Label(item.title, systemImage: item.icon)
                                    Spacer(minLength: 4)
                                    sidebarBadge(item)
                                }
                                if item == .galaxy {
                                    Text("🪐 \(store.galaxy.count)  ·  ☀️ \(store.solarSystems.count)")
                                        .font(.caption2).foregroundStyle(.secondary).padding(.leading, 26)
                                }
                            }
                            .tag(item)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .scrollContentBackground(pageColor != nil ? .hidden : .automatic)
            .background(pageColor ?? Color.clear)
            .safeAreaInset(edge: .top) { SidebarCountdown() }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if timer.isActive { MiniTimer() }
                    AccountChip()
                }
            }
        } detail: {
            // The admin panel is a plain column beside the page. (As a system ".inspector" its drawing sat about 58 points below where
            // clicks landed, so buttons missed: clicking the message box hit "Send".)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    banners
                    page
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showAdmin && account.isAdmin {
                    Divider()
                    AdminPanel().frame(width: 330)
                        .background(.background)
                }
            }
            .background(pageColor ?? Color.clear)
        }
        // About opens as a small window over the current page (the page stays where it was)
        .onChange(of: router.selection) { old, new in
            if new == .about { showAbout = true; router.selection = old ?? .today }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showQuickTask) { QuickTaskSheet() }
        // a gift box from a friend opens as a little window in the middle of the screen
        .overlay {
            if let g = gifts.next {
                GiftPopup(gift: g).id(g.id).transition(.opacity)
            }
        }
        .task {
            gifts.store = store
            while !Task.isCancelled {
                await gifts.refresh()
                try? await Task.sleep(for: .seconds(25))
            }
        }
        // a new notification slides in at the top right
        .overlay(alignment: .topTrailing) {
            if let t = Inbox.shared.toast {
                NoticeToast(notice: t)
                    .padding(.top, 12).padding(.trailing, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(t.id)
            }
        }
        // Developer tool: CS_TEST_PASS=2 opens the Level Pass as if 2 hours were just studied
        .onAppear {
            // Developer tool: CS_TEST_NOTICES=1 puts a few pretend notifications in the bell
            if ProcessInfo.processInfo.environment["CS_TEST_NOTICES"] != nil {
                Inbox.shared.post(id: "test-1", title: "🏁 New public challenge: Weekend sprint", body: "6h of study · 300 🚀 entry by @sara · join any time",
                                  kind: .challenge, route: .challenges, system: false)
                Inbox.shared.post(id: "test-2", title: "+800 🚀 rockets", body: "Welcome gift from the Orbit admin!", kind: .gift, route: .store, system: false)
                Inbox.shared.post(id: "test-3", title: "New challenge in Class 12: Focus battle", body: "5h of study · 250 🚀 entry · anyone in the group can join",
                                  kind: .group, route: .groups, system: false)
            }
            if let h = ProcessInfo.processInfo.environment["CS_TEST_PASS"].flatMap(Double.init) {
                let total = store.sessions.reduce(0) { $0 + $1.duration } / 3600
                store.passMoment = PassMoment(fromHours: max(0, total - h), toHours: total)
            }
        }
        // After a study session: the ship flies along the Level Pass
        .sheet(item: Binding(get: { store.passMoment }, set: { store.passMoment = $0 })) { m in
            LevelPassView(fromHours: m.fromHours)
        }
        // After "Finish & Save" on a to-do: is it finished? (waits for the Level Pass window, so the two never collide)
        .sheet(item: $donePrompt, onDismiss: { timer.finished = nil }) { f in
            TaskDonePrompt(finished: f)
        }
        .onAppear { SidebarReclick.install(router: router) }
        // every change of page (also inside Mission Control) is remembered for ⌘← and ⌘→
        .onChange(of: router.snapshot) { old, new in router.record(old: old, new: new) }
        .onChange(of: timer.finished) { _, _ in showDonePromptWhenFree() }
        .onChange(of: store.passMoment == nil) { _, _ in showDonePromptWhenFree() }
        // The owner's admin panel (right side) — only for the admin account
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showQuickTask = true } label: { Image(systemName: "plus") }
                    .keyboardShortcut("n", modifiers: .command).help("New task (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) { InboxBell() }
            if account.isAdmin {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdmin.toggle() } label: {
                        Label("Admin", systemImage: "crown")
                            .overlay(alignment: .topTrailing) {
                                if account.pendingCount > 0 {
                                    Text("\(account.pendingCount)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        .padding(3).background(Circle().fill(.red)).offset(x: 8, y: -6)
                                }
                            }
                    }
                    .help("Admin: sign-ups and members (only you see this)")
                }
            }
        }
        // App-wide look: template accent, font design, light/dark mode
        .tint(store.settings.template.style.accent)
        .fontDesign(store.settings.font.design ?? .default)
        .onAppear {
            NSApp.appearance = store.settings.appearance.nsAppearance
            // Developer tool: CS_APPEARANCE=light|dark forces the look (for screenshots and testing)
            if let a = ProcessInfo.processInfo.environment["CS_APPEARANCE"] { NSApp.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua) }
        }
        .onChange(of: store.settings.appearance) { _, mode in if ProcessInfo.processInfo.environment["CS_APPEARANCE"] == nil { NSApp.appearance = mode.nsAppearance } }
        // Friends: share my daily summary and what I'm studying right now
        .task {
            while !Task.isCancelled {
                await friends.syncNow()
                await friends.pushLive(timer: timer, force: timer.isRunning)
                await challenges.tick()
                await fightClub.tick()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: timer.isRunning) { _, _ in Task { await friends.pushLive(timer: timer) } }
        .onChange(of: timer.phase) { _, _ in Task { await friends.pushLive(timer: timer) } }
        .onChange(of: store.sessions.count) { _, _ in Task { await friends.syncNow() } }
    }

    /// Little numbers beside the sidebar names: friends studying now, live challenges, my rank in the fight
    @ViewBuilder private func sidebarBadge(_ item: SidebarItem) -> some View {
        switch item {
        case .friends:
            let n = friends.friends.filter { $0.studyingNow != nil }.count
            if n > 0 { badge("\(n)", .green, help: "\(n) friend\(n == 1 ? " is" : "s are") studying right now") }
        case .leitner:
            let n = LeitnerStore.shared.totalDue
            if n > 0 { badge("\(n)", .orange, help: "\(n) word\(n == 1 ? "" : "s") to review today") }
        case .challenges:
            let n = challenges.liveCount()
            if n > 0 { badge("\(n)", .orange, help: "\(n) challenge\(n == 1 ? "" : "s") running now") }
        case .fightClub:
            if let r = fightClub.myRank(me: friends.me?.id) { badge("#\(r)", .red, help: "Your place on this week's World Boss board") }
        default:
            EmptyView()
        }
    }

    private func badge(_ text: String, _ color: Color, help: String) -> some View {
        Text(text).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(Capsule().fill(color.gradient))
            .help(help)
    }

    @ViewBuilder private var page: some View {
            switch router.selection ?? .today {
            case .today: TodayView()
            case .schedule: WeeklyScheduleView()
            case .planner: MissionControlView()
            case .timer: TimerView()
            case .leitner: LeitnerView()
            case .spelling: LeitnerSpellingPage()
            case .notchbit: NotchbitPage()
            case .countdown: CountdownPage()
            case .phoneSync: PhoneSyncPage()
            case .tasks: TasksView()
            case .calendar: CalendarView()
            case .reports: ReportsView()
            case .galaxy: GalaxyPage()
            case .store: StoreView()
            case .friends: FriendsView()
            case .groups: GroupsPage()
            case .challenges: ChallengesPage()
            case .fightClub: FightClubPage()
            case .settings: SettingsView()
            case .about: EmptyView()
            }
    }

    /// Rocket gifts and new versions
    @ViewBuilder private var banners: some View {
        if let n = account.giftNotice {
            banner(icon: "gift.fill", tint: .orange, text: n,
                   action: ("Open Store", { router.selection = .store; account.giftNotice = nil })) { account.giftNotice = nil }
        }
        if let v = updates.available, !updates.dismissed {
            banner(icon: "arrow.down.circle.fill", tint: .accentColor, text: "Orbit \(v) is out — you have \(updates.current).",
                   action: ("Download", { updates.openDownload() })) { updates.dismissed = true }
        }
    }

    private func banner(icon: String, tint: Color, text: String, action: (String, () -> Void), close: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.callout.weight(.medium))
            Spacer()
            Button(action.0, action: action.1).buttonStyle(.borderedProminent).controlSize(.small)
            Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(tint.opacity(0.15))
    }

}


/// Small window after "Finish & Save" on a to-do: tick it as done, or leave it
struct TaskDonePrompt: View {
    let finished: TimerEngine.FinishedTask
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(.green)
            Text("Is this task finished?").font(.headline)
            Text(finished.title).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            if let m = store.neededMinutes(for: finished.ref) {
                NeedProgress(studied: store.studiedSeconds(for: finished.ref, on: Date()), needed: m).frame(width: 200)
            }
            HStack {
                Button("Not yet") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Yes, tick it ✓") {
                    if !store.isDone(finished.ref, on: Date()) { withAnimation { store.toggleDone(finished.ref, on: Date()) } }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.green)
            }
        }
        .padding(24).frame(width: 320)
    }
}


/// The small timer at the bottom of the sidebar. It is a view of its own so that only it redraws while the clock runs
/// (the sidebar list around it used to be rebuilt four times a second, and clicks on its rows were lost).
struct MiniTimer: View {
    @Environment(Router.self) private var router
    @Environment(TimerEngine.self) private var timer

    var body: some View {
        Button {
            router.selection = .timer
        } label: {
            HStack {
                Image(systemName: timer.isRunning ? "timer" : "pause.circle")
                    .foregroundStyle(timer.phase == .rest ? .green : .accentColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.clock(timer.displayTime)).font(.headline.monospacedDigit())
                    Text(timer.phase == .rest ? "Break" : (timer.targetTitle ?? "Free study"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}


/// Clicking the row that is already selected (Mission Control) sends that page back to its first screen.
/// It only watches mouse-downs on the sidebar and never touches the click itself, so selecting rows works as the system does it.
@MainActor
enum SidebarReclick {
    private static var monitor: Any?

    static func install(router: Router) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if router.selection == .planner, let content = event.window?.contentView, let outline = findOutline(in: content),
               outline.selectedRow >= 0 {
                // is the click on the selected row? (compared in window coordinates)
                let row = outline.convert(outline.rect(ofRow: outline.selectedRow), to: nil)
                if row.contains(event.locationInWindow) { router.missionHome += 1 }
            }
            return event
        }
    }

    private static func findOutline(in view: NSView) -> NSOutlineView? {
        if let o = view as? NSOutlineView { return o }
        for v in view.subviews { if let o = findOutline(in: v) { return o } }
        return nil
    }
}
