import SwiftUI

// MARK: - Server rows

struct FriendProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var friend_code: String
    var level: Int?
    var avatar: String?
    var galaxy: GalaxyData?
}

struct SubjectStat: Codable, Hashable {
    var name: String
    var minutes: Int
    var color: String
}

struct DailyStat: Codable, Hashable {
    var user_id: UUID
    var day: String            // yyyy-MM-dd
    var minutes: Int
    var todos_done: Int
    var todos_total: Int
    var subjects: [SubjectStat]
}

struct LiveStatus: Codable, Hashable {
    var user_id: UUID
    var studying: String?
    var started_at: Date?
    var updated_at: Date?
}

/// A person on the Friends page (a friend, or me), with derived numbers
struct FriendCard: Identifiable, Hashable {
    let profile: FriendProfile
    let stats: [String: DailyStat]   // by day key
    let live: LiveStatus?
    let isMe: Bool

    var id: UUID { profile.id }

    func minutes(on day: Date) -> Int { stats[Cal.dayKey(day)]?.minutes ?? 0 }

    var todayMinutes: Int { minutes(on: Date()) }
    var today: DailyStat? { stats[Cal.dayKey(Date())] }

    var weekMinutes: Int {
        Cal.persian.days(in: Cal.persian.dateInterval(of: .weekOfYear, for: Date())!)
            .reduce(0) { $0 + minutes(on: $1) }
    }

    /// Days in a row with study time, ending today (or yesterday if today is still empty)
    var streak: Int {
        var day = Date()
        if minutes(on: day) == 0 { day = Cal.persian.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while minutes(on: day) > 0 {
            n += 1
            day = Cal.persian.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    /// Studying right now (live status updated in the last 15 minutes)
    var studyingNow: String? {
        guard let live, let what = live.studying, let updated = live.updated_at,
              Date().timeIntervalSince(updated) < 15 * 60 else { return nil }
        return what
    }

    var weekSubjects: [SubjectStat] {
        let days = Cal.persian.days(in: Cal.persian.dateInterval(of: .weekOfYear, for: Date())!)
        var totals: [String: SubjectStat] = [:]
        for d in days {
            for s in stats[Cal.dayKey(d)]?.subjects ?? [] {
                totals[s.name, default: SubjectStat(name: s.name, minutes: 0, color: s.color)].minutes += s.minutes
            }
        }
        return totals.values.sorted { $0.minutes > $1.minutes }
    }
}

// MARK: - Service

/// Talks to Supabase: my profile, friends, and syncing my daily summary + live status.
/// Only summaries are shared — never the full schedule, tasks or notes.
@MainActor @Observable
final class FriendsService {
    private(set) var me: FriendProfile?
    private(set) var friends: [FriendCard] = []
    private(set) var isLoading = false
    private(set) var hasSession = false
    private(set) var lastSync: Date?
    var error: String?

    @ObservationIgnored private let client = SupabaseClient()
    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private var lastLiveSent: String??
    @ObservationIgnored private var lastStatsSent: [DailyStat] = []
    @ObservationIgnored private var lastExtrasSent: ProfileExtras?

    /// Level, profile planet and galaxy layout, shown to friends
    struct ProfileExtras: Encodable, Equatable {
        let level: Int
        let avatar: String?
        let galaxy: GalaxyData
    }

    init(store: AppStore) {
        self.store = store
        Task { await bootstrap() }
    }

    var isSetUp: Bool { me != nil }

    private func bootstrap() async {
        guard SupabaseConfig.isConfigured else { return }
        hasSession = await client.userID != nil
        guard hasSession else { return }
        await refresh()
    }

    // MARK: Profile

    func createProfile(name: String) async {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await run {
            if await self.client.userID == nil { try await self.client.signInAnonymously() }
            guard let uid = await self.client.userID else { return }
            struct NewProfile: Encodable { let id: UUID; let name: String }
            let rows = try await self.client.insert("profiles", NewProfile(id: uid, name: name), returning: [FriendProfile].self)
            self.me = rows.first
            self.hasSession = true
        }
        await syncNow()
    }

    func rename(_ name: String) async {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let me, !name.isEmpty else { return }
        await run {
            try await self.client.update("profiles?id=eq.\(me.id.uuidString)", ["name": name])
            self.me?.name = name
        }
    }

    /// Forget the account on this Mac (the server copy stays, but can't be reached again)
    func signOut() async {
        await client.signOut()
        me = nil
        friends = []
        hasSession = false
    }

    /// Delete my profile, friendships and shared stats from the server, then sign out on this Mac
    func deleteProfile() async {
        guard let me else { return }
        var ok = false
        await run {
            try await self.client.delete("profiles?id=eq.\(me.id.uuidString)")
            ok = true
        }
        if ok { await signOut() }
    }

    // MARK: Friends

    /// Returns the friend's name on success
    @discardableResult
    func addFriend(code: String) async -> String? {
        var added: String?
        await run {
            let data = try await self.client.rpc("add_friend", ["code": code])
            added = try JSONDecoder().decode(String.self, from: data)
        }
        if added != nil { await refresh() }
        return added
    }

    func removeFriend(_ id: UUID) async {
        await run { _ = try await self.client.rpc("remove_friend", ["friend": id.uuidString]) }
        friends.removeAll { $0.id == id }
    }

    /// Reload my profile, my friends and their stats
    func refresh() async {
        guard let uid = await client.userID else { return }
        isLoading = true
        defer { isLoading = false }
        await run {
            let mine = try await self.client.select("profiles?id=eq.\(uid.uuidString)", as: [FriendProfile].self)
            self.me = mine.first

            struct Link: Decodable { let friend_id: UUID }
            let links = try await self.client.select("friendships?select=friend_id&user_id=eq.\(uid.uuidString)", as: [Link].self)
            let ids = links.map(\.friend_id)
            guard !ids.isEmpty else {
                self.friends = []
                self.lastSync = Date()
                return
            }
            let list = "(" + ids.map(\.uuidString).joined(separator: ",") + ")"
            let since = Cal.dayKey(Cal.persian.date(byAdding: .day, value: -35, to: Date())!)

            async let profiles = self.client.select("profiles?id=in.\(list)", as: [FriendProfile].self)
            async let stats = self.client.select("daily_stats?user_id=in.\(list)&day=gte.\(since)", as: [DailyStat].self)
            async let live = self.client.select("live_status?user_id=in.\(list)", as: [LiveStatus].self)
            let (p, s, l) = try await (profiles, stats, live)

            let statsByUser = Dictionary(grouping: s, by: \.user_id)
            self.friends = p.map { prof in
                FriendCard(profile: prof,
                           stats: Dictionary((statsByUser[prof.id] ?? []).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a }),
                           live: l.first { $0.user_id == prof.id },
                           isMe: false)
            }
            .sorted { $0.weekMinutes > $1.weekMinutes }
            self.lastSync = Date()
        }
    }

    // MARK: Sync my data

    /// My own card, built from local data (always up to date)
    func myCard(timer: TimerEngine) -> FriendCard? {
        guard var me else { return nil }
        me.level = store.galaxyProgress().level
        me.avatar = store.avatarPlanet
        me.galaxy = store.galaxyData
        let days = (0..<35).compactMap { Cal.persian.date(byAdding: .day, value: -$0, to: Date()) }
        let stats = Dictionary(days.map { (Cal.dayKey($0), localStat(for: $0, userID: me.id)) }, uniquingKeysWith: { a, _ in a })
        let live = LiveStatus(user_id: me.id, studying: liveTitle(timer), started_at: timer.sessionStart, updated_at: Date())
        return FriendCard(profile: me, stats: stats, live: live, isMe: true)
    }

    /// Upload the last 7 days of my summary (only rows that changed)
    func syncNow() async {
        guard let me else { return }
        let rows = (0..<7).compactMap { Cal.persian.date(byAdding: .day, value: -$0, to: Date()) }
            .map { localStat(for: $0, userID: me.id) }
        let extras = ProfileExtras(level: store.galaxyProgress().level, avatar: store.avatarPlanet, galaxy: store.galaxyData)
        if extras != lastExtrasSent {
            await run {
                try await self.client.update("profiles?id=eq.\(me.id.uuidString)", extras)
                self.lastExtrasSent = extras
            }
        }
        guard rows != lastStatsSent else { return }
        await run {
            try await self.client.upsert("daily_stats", rows)
            self.lastStatsSent = rows
            self.lastSync = Date()
        }
    }

    /// Tell friends what I'm studying right now (nil = idle). Only sends when it changes.
    func pushLive(timer: TimerEngine, force: Bool = false) async {
        guard let me else { return }
        let title = liveTitle(timer)
        if !force, let last = lastLiveSent, last == title { return }
        lastLiveSent = .some(title)
        await run {
            try await self.client.upsert("live_status",
                                         LiveStatus(user_id: me.id, studying: title,
                                                    started_at: title == nil ? nil : timer.sessionStart,
                                                    updated_at: Date()))
        }
    }

    private func liveTitle(_ timer: TimerEngine) -> String? {
        guard timer.isRunning, timer.phase == .focus else { return nil }
        return timer.targetTitle ?? store.category(timer.categoryID)?.name ?? "Studying"
    }

    private func localStat(for day: Date, userID: UUID) -> DailyStat {
        let sessions = store.sessions(in: Cal.persian.dayInterval(day))
        let todos = store.todos(on: day)
        var subjects: [String: SubjectStat] = [:]
        for s in sessions {
            let subj = store.subject(of: s)
            subjects[subj.name, default: SubjectStat(name: subj.name, minutes: 0, color: s.colorHex.isEmpty ? "#8E8E93" : s.colorHex)]
                .minutes += Int(s.duration / 60)
        }
        return DailyStat(user_id: userID,
                         day: Cal.dayKey(day),
                         minutes: Int(sessions.reduce(0) { $0 + $1.duration } / 60),
                         todos_done: todos.filter(\.isDone).count,
                         todos_total: todos.count,
                         subjects: Array(subjects.values.sorted { $0.minutes > $1.minutes }.prefix(20)))
    }

    // MARK: Helpers

    private func run(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
            error = nil
        } catch let e as SupabaseClient.APIError {
            error = Self.friendly(e.message)
        } catch {
            self.error = (error as? URLError)?.code == .notConnectedToInternet || (error as? URLError) != nil
                ? "Can't reach the server. Check your internet or VPN."
                : error.localizedDescription
        }
    }

    private static func friendly(_ message: String) -> String {
        if message.contains("own code") { return "That's your own code 🙂" }
        return message
    }
}
