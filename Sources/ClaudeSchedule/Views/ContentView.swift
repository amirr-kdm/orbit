import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case today, schedule, planner, timer, tasks, calendar, reports, galaxy, store, friends, challenges, fightClub, settings, about

    var id: String { rawValue }

    /// Sidebar groups, in order: plan the week → do the work → progress & rewards → people → app
    static let sections: [(title: String, items: [SidebarItem])] = [
        ("Plan", [.today, .schedule, .tasks, .calendar, .planner]),
        ("Focus", [.timer, .reports]),
        ("Rewards", [.galaxy, .store]),
        ("Social", [.friends, .challenges, .fightClub]),
        ("App", [.settings, .about]),
    ]
    var title: String {
        switch self {
        case .today: "Today"
        case .schedule: "Weekly Schedule"
        case .planner: "Notes & Brainstorm"
        case .timer: "Timer"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .reports: "Reports"
        case .galaxy: "My Galaxy"
        case .store: "Store"
        case .friends: "Friends"
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
        case .planner: "brain.head.profile"
        case .timer: "timer"
        case .tasks: "tray.full"
        case .calendar: "calendar"
        case .reports: "chart.bar.xaxis"
        case .galaxy: "sparkles"
        case .store: "bag"
        case .friends: "person.2"
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
    @State private var showAbout = false
    @Environment(\.colorScheme) private var scheme
    /// Midnight Black in dark mode: the whole app turns pure black (sidebar and pages)
    private var allBlack: Bool { store.settings.template == .midnight && scheme == .dark }

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.selection) {
                ForEach(SidebarItem.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Label(item.title, systemImage: item.icon).tag(item)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .scrollContentBackground(allBlack ? .hidden : .automatic)
            .background(allBlack ? Color.black : Color.clear)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if timer.isActive { miniTimer }
                    AccountChip()
                }
            }
        } detail: {
            VStack(spacing: 0) {
                banners
                page
            }
            .background(allBlack ? Color.black : Color.clear)
        }
        // About opens as a small window over the current page (the page stays where it was)
        .onChange(of: router.selection) { old, new in
            if new == .about { showAbout = true; router.selection = old ?? .today }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        // Developer tool: CS_TEST_PASS=2 opens the Level Pass as if 2 hours were just studied
        .onAppear {
            if let h = ProcessInfo.processInfo.environment["CS_TEST_PASS"].flatMap(Double.init) {
                let total = store.sessions.reduce(0) { $0 + $1.duration } / 3600
                store.passMoment = PassMoment(fromHours: max(0, total - h), toHours: total)
            }
        }
        // After a study session: the ship flies along the Level Pass
        .sheet(item: Binding(get: { store.passMoment }, set: { store.passMoment = $0 })) { m in
            LevelPassView(fromHours: m.fromHours)
        }
        // The owner's admin panel (right side) — only for the admin account
        .inspector(isPresented: Binding(get: { showAdmin && account.isAdmin }, set: { showAdmin = $0 })) {
            AdminPanel().inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .toolbar {
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
        .onAppear { NSApp.appearance = store.settings.appearance.nsAppearance }
        .onChange(of: store.settings.appearance) { _, mode in NSApp.appearance = mode.nsAppearance }
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

    @ViewBuilder private var page: some View {
            switch router.selection ?? .today {
            case .today: TodayView()
            case .schedule: WeeklyScheduleView()
            case .planner: PlannerView()
            case .timer: TimerView()
            case .tasks: TasksView()
            case .calendar: CalendarView()
            case .reports: ReportsView()
            case .galaxy: GalaxyPage()
            case .store: StoreView()
            case .friends: FriendsView()
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

    private var miniTimer: some View {
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
