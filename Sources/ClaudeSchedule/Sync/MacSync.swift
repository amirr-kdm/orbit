import SwiftUI

extension Notification.Name { static let orbitDataSaved = Notification.Name("orbitDataSaved") }

/// Connects this Mac's data to the phone through the shared sync engine
@MainActor @Observable
final class MacSync {
    static let shared = MacSync()
    var status = "Off"
    var ok = true
    private let engine = SyncEngine()
    private weak var store: AppStore?
    @ObservationIgnored private var timer: Timer?

    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    /// Phone Sync is not open to everyone yet ("coming soon"). A developer switch keeps it running on the author's own Mac:
    /// defaults write com.amir.orbit phoneSync.unlocked -bool true
    nonisolated static var unlocked: Bool { UserDefaults.standard.bool(forKey: "phoneSync.unlocked") }

    func start(store: AppStore) {
        guard Self.unlocked else { return }
        self.store = store
        engine.export = { [unowned self] in self.exportDoc() }
        engine.apply = { [unowned self] doc in self.applyDoc(doc) }
        engine.onStatus = { [unowned self] s, good in self.status = s; self.ok = good }
        NotificationCenter.default.addObserver(forName: .orbitDataSaved, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MacSync.shared.engine.changed() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Task { await MacSync.shared.syncNow() } }
        }
        // look for changes from the phone every few minutes (one small request; nothing runs while sync is off)
        let t = Timer(timeInterval: 180, repeats: true) { _ in MainActor.assumeIsolated { Task { await MacSync.shared.syncNow() } } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        settingsChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { Task { await MacSync.shared.syncNow() } } }
    }

    var enabled: Bool { engine.enabled }
    func syncNow() async { if engine.enabled { status = "Syncing…" }; await engine.syncNow() }
    func settingsChanged() { if !engine.enabled { status = UserDefaults.standard.bool(forKey: "sync.enabled") ? "Needs a code" : "Off" } }

    // MARK: Data

    private func obj<T: Encodable>(_ v: T) -> Any {
        (try? JSONSerialization.jsonObject(with: encoder.encode(v))) ?? []
    }

    private func exportDoc() -> [String: Any] {
        guard let s = store else { return [:] }
        let l = LeitnerStore.shared.exportSync()
        func keys(_ set: Set<String>) -> [[String: Any]] { set.sorted().map { ["id": $0] } }
        return ["tasks": obj(s.tasks), "categories": obj(s.categories), "sessions": obj(s.sessions),
                "countdowns": obj(CountdownStore.shared.events),
                "schedule": obj(s.schedule), "timeSlots": obj(s.settings.timeSlots),
                "scheduleDone": keys(s.scheduleDone), "scheduleMoved": keys(s.scheduleMoved), "scheduleSkipped": keys(s.scheduleSkipped),
                "leitnerBoxes": l.boxes, "leitnerCards": l.cards, "leitnerLog": l.log, "leitnerDailyGoal": LeitnerStore.shared.dailyGoal,
                "evenWeekAnchor": ISO8601DateFormatter().string(from: s.settings.evenWeekAnchor),
                "pomodoroMinutes": s.settings.pomodoroMinutes, "breakMinutes": s.settings.breakMinutes, "dailyGoalMinutes": s.settings.dailyGoalMinutes]
    }

    private func decode<T: Decodable>(_ type: [T].Type, _ any: Any?) -> [T]? {
        guard let any, JSONSerialization.isValidJSONObject(any), let d = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? decoder.decode(type, from: d)
    }

    private func applyDoc(_ doc: [String: Any]) {
        guard let s = store else { return }
        if let v = decode([TaskItem].self, doc["tasks"]), v != s.tasks { s.tasks = v }
        if let v = decode([Category].self, doc["categories"]), v != s.categories { s.categories = v }
        if let v = decode([StudySession].self, doc["sessions"]), v != s.sessions { s.sessions = v }
        if let v = decode([CountdownEvent].self, doc["countdowns"]), v != CountdownStore.shared.events { CountdownStore.shared.events = v }
        if let v = decode([ScheduleEntry].self, doc["schedule"]), v != s.schedule { s.schedule = v }
        if let v = decode([TimeSlot].self, doc["timeSlots"]), !v.isEmpty, v != s.settings.timeSlots { s.settings.timeSlots = v }
        func keys(_ name: String) -> Set<String>? { (doc[name] as? [[String: Any]]).map { Set($0.compactMap { $0["id"] as? String }) } }
        if let v = keys("scheduleDone"), v != s.scheduleDone { s.scheduleDone = v }
        if let v = keys("scheduleMoved"), v != s.scheduleMoved { s.scheduleMoved = v }
        if let v = keys("scheduleSkipped"), v != s.scheduleSkipped { s.scheduleSkipped = v }
        if let a = (doc["evenWeekAnchor"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }), a != s.settings.evenWeekAnchor { s.settings.evenWeekAnchor = a }
        if let boxes = doc["leitnerBoxes"] as? [[String: Any]], let cards = doc["leitnerCards"] as? [[String: Any]], let log = doc["leitnerLog"] as? [[String: Any]] {
            LeitnerStore.shared.applySync(boxes: boxes, cards: cards, log: log)
        }
        if let g = doc["leitnerDailyGoal"] as? Int, g > 0, g != LeitnerStore.shared.dailyGoal { LeitnerStore.shared.dailyGoal = g }
        if let v = doc["pomodoroMinutes"] as? Int, v != s.settings.pomodoroMinutes { s.settings.pomodoroMinutes = v }
        if let v = doc["breakMinutes"] as? Int, v != s.settings.breakMinutes { s.settings.breakMinutes = v }
        if let v = doc["dailyGoalMinutes"] as? Int, v != s.settings.dailyGoalMinutes { s.settings.dailyGoalMinutes = v }
    }
}

/// Settings → Phone Sync
/// What everyone sees: the iPhone app is not out yet
struct PhoneSyncPage: View {
    var body: some View {
        if MacSync.unlocked { PhoneSyncPageContent() } else { PhoneSyncSoon() }
    }
}

private struct PhoneSyncSoon: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: "#6366F1").opacity(0.35), Color(hex: "#EC4899").opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 112, height: 112)
                Image(systemName: "iphone").font(.system(size: 46, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                Image(systemName: "lock.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .padding(8).background(Circle().fill(Color(hex: "#6366F1"))).offset(x: 34, y: 38)
            }
            Text("Coming soon").font(.system(size: 28, weight: .heavy, design: .rounded))
            Text("The Orbit app for iPhone is on its way. It will keep your tasks, study time, weekly schedule and Leitner words in step with this Mac, with no login.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
        .navigationTitle("Phone Sync")
    }
}

private struct PhoneSyncPageContent: View {
    @AppStorage("sync.enabled") private var on = false
    @AppStorage("sync.code") private var code = ""
    @State private var sync = MacSync.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                card("Phone sync", "iphone") {
                    Toggle(isOn: Binding(get: { on }, set: { v in
                        on = v
                        if v && code.isEmpty { code = SyncEngine.newCode() }
                        sync.settingsChanged()
                        Task { await sync.syncNow() }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep this Mac and the iPhone app in step")
                            Text("Tasks, categories, study time, countdowns and Pomodoro lengths. Nothing needs a login: the private code below is the key.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.switch)
                }
                if on {
                    card("Your private code", "key.fill") {
                        HStack {
                            Text(code).font(.system(.title3, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                            Spacer()
                            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                        }
                        Text("Type or paste this code into the iPhone app (Today → gear). Anyone with the code can read and change this data, so keep it private.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Make a new code…", role: .destructive) { code = SyncEngine.newCode(); Task { await sync.syncNow() } }
                            .controlSize(.small)
                    }
                    card("Status", "arrow.triangle.2.circlepath") {
                        HStack {
                            Image(systemName: sync.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(sync.ok ? .green : .orange)
                            Text(sync.status)
                            Spacer()
                            Button("Sync now") { Task { await sync.syncNow() } }
                        }
                        Text("It syncs a few seconds after each change, when Orbit comes to the front, and every 3 minutes.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle("Phone Sync")
    }

    private func card<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background.secondary))
    }
}
