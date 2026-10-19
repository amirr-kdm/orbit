import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case today, schedule, planner, timer, tasks, calendar, reports, galaxy, friends, settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .schedule: "Weekly Schedule"
        case .planner: "Planner"
        case .timer: "Timer"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .reports: "Reports"
        case .galaxy: "My Galaxy"
        case .friends: "Friends"
        case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .today: "checklist"
        case .schedule: "tablecells"
        case .planner: "square.and.pencil"
        case .timer: "timer"
        case .tasks: "tray.full"
        case .calendar: "calendar"
        case .reports: "chart.bar.xaxis"
        case .galaxy: "sparkles"
        case .friends: "person.2"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(Router.self) private var router
    @Environment(TimerEngine.self) private var timer
    @Environment(AppStore.self) private var store
    @Environment(FriendsService.self) private var friends

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $router.selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                if timer.isActive { miniTimer }
            }
        } detail: {
            switch router.selection ?? .today {
            case .today: TodayView()
            case .schedule: WeeklyScheduleView()
            case .planner: PlannerView()
            case .timer: TimerView()
            case .tasks: TasksView()
            case .calendar: CalendarView()
            case .reports: ReportsView()
            case .galaxy: GalaxyPage()
            case .friends: FriendsView()
            case .settings: SettingsView()
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
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: timer.isRunning) { _, _ in Task { await friends.pushLive(timer: timer) } }
        .onChange(of: timer.phase) { _, _ in Task { await friends.pushLive(timer: timer) } }
        .onChange(of: store.sessions.count) { _, _ in Task { await friends.syncNow() } }
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
