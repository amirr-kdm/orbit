import SwiftUI

/// What kind of challenge it is: who can join
enum ChallengeType: String, CaseIterable, Identifiable {
    case `public`, `private`, group

    var id: String { rawValue }
    var title: String {
        switch self {
        case .public: "Public"
        case .private: "Private"
        case .group: "Group"
        }
    }
    var subtitle: String {
        switch self {
        case .public: "Anyone in Orbit can join"
        case .private: "Needs an invite code"
        case .group: "Only the members of one group"
        }
    }
    var icon: String {
        switch self {
        case .public: "globe"
        case .private: "lock.fill"
        case .group: "person.3.fill"
        }
    }
    var tint: Color {
        switch self {
        case .public: Color(hex: "#3B82F6")
        case .private: Color(hex: "#F97316")
        case .group: Color(hex: "#A855F7")
        }
    }
    var gradient: LinearGradient {
        let pair: (String, String) = switch self {
        case .public: ("#3B82F6", "#22D3EE")
        case .private: ("#F97316", "#EF4444")
        case .group: ("#A855F7", "#EC4899")
        }
        return LinearGradient(colors: [Color(hex: pair.0), Color(hex: pair.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A challenge or a promise to a friend (rules and payouts run on the server — see supabase/challenges.sql and challenges_v2.sql)
struct Challenge: Decodable, Identifiable, Hashable {
    let id: UUID
    let kind: String
    let group_id: UUID?
    let creator: UUID
    let friend: UUID?
    let title: String
    let target_minutes: Int
    let fee: Int
    let starts_at: Date
    let ends_at: Date
    let status: String
    /// "public", "private" or "group" (older rows have none: public)
    var visibility: String? = nil
    /// Private challenges: the code that lets someone in
    var invite_code: String? = nil

    var isPromise: Bool { kind == "promise" }
    var isOpen: Bool { status == "open" }
    var type: ChallengeType { group_id != nil ? .group : (visibility == "private" ? .private : .public) }
    func started(_ now: Date = Date()) -> Bool { now >= starts_at }
    func ended(_ now: Date = Date()) -> Bool { now >= ends_at }
    /// Running right now
    func isLive(_ now: Date = Date()) -> Bool { !isPromise && isOpen && started(now) && !ended(now) }
    /// Apps can still report minutes for this long after the end; then it pays out
    static let grace: TimeInterval = 3600
}

struct ChallengeMember: Decodable, Hashable {
    let challenge_id: UUID
    let user_id: UUID
    let minutes: Int
    /// When they joined (a late joiner's study counts from then)
    var joined_at: Date? = nil
}

/// Someone in a challenge I can see (they may not be my friend): username, planet and level
struct ChallengePerson: Decodable, Hashable {
    let id: UUID
    let name: String
    let avatar: String?
    let level: Int?
}

@MainActor @Observable
final class ChallengeService {
    private(set) var challenges: [Challenge] = []
    private(set) var members: [UUID: [ChallengeMember]] = [:]
    private(set) var people: [UUID: ChallengePerson] = [:]
    var error: String?
    var busy = false

    @ObservationIgnored private let client = SupabaseClient.shared
    @ObservationIgnored private let store: AppStore
    /// Called after rockets moved (entry fee, refund, payout) so the balance updates right away
    @ObservationIgnored var onRocketsMoved: (() async -> Void)?
    /// Looks up one of my groups' names (set by the app; used in notifications)
    @ObservationIgnored var groupName: (@MainActor (UUID) -> String?)?
    @ObservationIgnored var testGroupID: (@MainActor () -> UUID?)?

    init(store: AppStore) { self.store = store }

    func members(of c: Challenge) -> [ChallengeMember] { members[c.id] ?? [] }
    func joined(_ c: Challenge, me: UUID?) -> Bool { members(of: c).contains { $0.user_id == me } }
    func challenges(inGroup g: UUID) -> [Challenge] { challenges.filter { $0.group_id == g && !$0.isPromise } }
    var promises: [Challenge] { challenges.filter(\.isPromise) }
    /// Everything except promises, newest first
    var all: [Challenge] { challenges.filter { !$0.isPromise } }
    /// How many are running right now (for the sidebar)
    func liveCount(_ now: Date = Date()) -> Int { challenges.filter { $0.isLive(now) }.count }
    func name(of id: UUID) -> String? { people[id]?.name }

    /// Joining is open until the end (a private one needs its code; a group one needs the group)
    func canJoin(_ c: Challenge, me: UUID?, now: Date = Date(), myGroups: Set<UUID> = []) -> Bool {
        guard !c.isPromise, c.isOpen, !c.ended(now), !joined(c, me: me) else { return false }
        switch c.type {
        case .public: return true
        case .group: return c.group_id.map(myGroups.contains) ?? false
        case .private: return false
        }
    }

    /// Open ones, plus anything finished in the last week
    func load() async {
        guard let me = await client.userID else { return }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86400))
        do {
            let list = try await client.select("challenges?or=(status.eq.open,ends_at.gt.\(since))&order=starts_at.desc", as: [Challenge].self)
            var byID: [UUID: [ChallengeMember]] = [:]
            if !list.isEmpty {
                let ids = list.map { $0.id.uuidString.lowercased() }.joined(separator: ",")
                let rows = try await client.select("challenge_members?challenge_id=in.(\(ids))&select=challenge_id,user_id,minutes,joined_at", as: [ChallengeMember].self)
                for r in rows { byID[r.challenge_id, default: []].append(r) }
            }
            await loadPeople(Set(byID.values.flatMap { $0.map(\.user_id) }))
            challenges = list
            members = byID
            notifyNew(list, me: me)
            if ProcessInfo.processInfo.environment["CS_TEST_CHALLENGES"] != nil {
                addTestChallenges(me: me, groupID: testGroupID?())
            }
        } catch {
            // offline: keep what we have
        }
    }

    /// Developer tool: CS_TEST_CHALLENGES=1 shows pretend challenges and people (local only)
    private func addTestChallenges(me: UUID, groupID: UUID?) {
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000C%04d", n))! }
        let now = Date(), H: TimeInterval = 3600
        let sara = id(101), arash = id(102), negar = id(103)
        people[sara] = ChallengePerson(id: sara, name: "sara", avatar: "s4_spacecat", level: 12)
        people[arash] = ChallengePerson(id: arash, name: "arash", avatar: "lv_t3", level: 31)
        people[negar] = ChallengePerson(id: negar, name: "negar", avatar: "s5_duck", level: 7)
        func make(_ n: Int, _ title: String, start: TimeInterval, end: TimeInterval, vis: String, group: UUID? = nil, status: String = "open", code: String? = nil) -> Challenge {
            Challenge(id: id(n), kind: "group", group_id: group, creator: n == 3 ? me : sara, friend: nil, title: title, target_minutes: 360, fee: 300,
                      starts_at: now.addingTimeInterval(start * H), ends_at: now.addingTimeInterval(end * H), status: status, visibility: vis, invite_code: code)
        }
        func mem(_ c: Int, _ u: UUID, _ minutes: Int, joinedHoursAgo: Double = 30) -> ChallengeMember {
            ChallengeMember(challenge_id: id(c), user_id: u, minutes: minutes, joined_at: now.addingTimeInterval(-joinedHoursAgo * H))
        }
        let demo = [
            make(1, "Weekend sprint", start: 5, end: 29, vis: "public"),
            make(2, "Exam week grind", start: -6, end: 18, vis: "public"),
            make(3, "Private study room", start: -2, end: 22, vis: "private", code: "7F3A9C"),
            make(4, "Class focus battle", start: -3, end: 21, vis: "group", group: groupID),
            make(5, "First challenge", start: -40, end: -16, vis: "public", status: "settled"),
        ]
        challenges = demo + challenges
        members[id(1)] = [mem(1, sara, 0), mem(1, arash, 0, joinedHoursAgo: 1)]
        members[id(2)] = [mem(2, me, 155), mem(2, sara, 126), mem(2, arash, 173), mem(2, negar, 82, joinedHoursAgo: 2)]
        members[id(3)] = [mem(3, me, 95), mem(3, sara, 40)]
        members[id(4)] = [mem(4, me, 210), mem(4, arash, 188)]
        members[id(5)] = [mem(5, me, 360), mem(5, sara, 361), mem(5, arash, 372), mem(5, negar, 360)]
    }

    /// Names, planets and levels of people in challenges (they may not be friends)
    private func loadPeople(_ ids: Set<UUID>) async {
        let missing = ids.filter { people[$0] == nil }
        guard !missing.isEmpty else { return }
        struct Body: Encodable { let ids: [String] }
        let body = Body(ids: missing.map(\.uuidString))
        if let data = try? await client.rpc("challenge_people", body),
           let rows = try? SupabaseClient.decoder.decode([ChallengePerson].self, from: data) {
            for r in rows { people[r.id] = r }
            return
        }
        // a server without challenges v2: names only
        struct Row: Decodable { let id: UUID; let name: String }
        guard let data = try? await client.rpc("challenge_names", body),
              let rows = try? SupabaseClient.decoder.decode([Row].self, from: data) else { return }
        for r in rows { people[r.id] = ChallengePerson(id: r.id, name: r.name, avatar: nil, level: nil) }
    }

    /// A new public challenge, or one in one of my groups, that someone else made: tell me once
    private func notifyNew(_ list: [Challenge], me: UUID) {
        let key = "challenges.seen"
        let d = UserDefaults.standard
        let first = d.object(forKey: key) == nil
        var seen = Set(d.stringArray(forKey: key) ?? [])
        for c in list where !c.isPromise && !seen.contains(c.id.uuidString) {
            seen.insert(c.id.uuidString)
            guard !first, c.creator != me, c.isOpen, !c.ended() else { continue }
            let group = c.group_id.flatMap { groupName?($0) }
            if c.type == .group && group == nil { continue }
            if c.type == .private { continue }
            let by = people[c.creator].map { " by @\($0.name)" } ?? ""
            let what = "\(hm(c.target_minutes)) of study · \(c.fee) 🚀 entry"
            if let group {
                Inbox.shared.post(id: "challenge-\(c.id)", title: "New challenge in \(group): \(c.title)", body: what + " · anyone in the group can join",
                                  kind: .group, route: .challenges, target: c.id.uuidString)
            } else {
                Inbox.shared.post(id: "challenge-\(c.id)", title: "🏁 New public challenge: \(c.title)", body: what + by + " · join any time",
                                  kind: .challenge, route: .challenges, target: c.id.uuidString)
            }
        }
        d.set(Array(seen), forKey: key)
    }

    /// Every minute: report my study minutes in running challenges, and pay out finished ones
    func tick() async {
        guard let me = await client.userID else { return }
        await load()
        let now = Date()
        var settled = false
        for c in challenges where store.accountReady && c.isOpen && joined(c, me: me) && c.started(now) && now <= c.ends_at.addingTimeInterval(Challenge.grace) {
            // a late joiner's study counts from the moment they joined
            let joinedAt = members(of: c).first { $0.user_id == me }?.joined_at ?? c.starts_at
            let from = max(c.starts_at, joinedAt), to = max(from, min(now, c.ends_at))
            let minutes = Int(store.rewardTime(in: DateInterval(start: from, end: to)) / 60)
            struct Body: Encodable { let c: String; let minutes: Int }
            _ = try? await client.rpc("report_challenge", Body(c: c.id.uuidString, minutes: minutes))
        }
        for c in challenges where c.isOpen && now >= c.ends_at.addingTimeInterval(Challenge.grace) {
            _ = try? await client.rpc("settle_challenge", ["c": c.id.uuidString])
            settled = true
        }
        if settled { await load(); await onRocketsMoved?() }
    }

    // MARK: Actions

    /// Make a challenge. `group` is only for group challenges. Returns its id.
    func create(title: String, minutes: Int, fee: Int, start: Date, end: Date, type: ChallengeType, group: UUID?) async -> UUID? {
        struct Body: Encodable {
            let title: String; let target_minutes: Int; let fee: Int; let starts_at: String; let ends_at: String
            let visibility: String; let grp: String?
        }
        var made: UUID?
        let ok = await perform(cost: fee) {
            do {
                let data = try await self.client.rpc("create_challenge_v2", Body(title: title, target_minutes: minutes, fee: fee,
                    starts_at: Self.iso(start), ends_at: Self.iso(end), visibility: type.rawValue, grp: group?.uuidString))
                made = (try? JSONDecoder().decode(UUID.self, from: data))
            } catch let e as SupabaseClient.APIError where e.message.contains("create_challenge_v2") && type == .public {
                // a server without challenges v2: public challenges still work the old way
                struct Old: Encodable { let title: String; let target_minutes: Int; let fee: Int; let starts_at: String; let ends_at: String }
                let data = try await self.client.rpc("create_challenge", Old(title: title, target_minutes: minutes, fee: fee,
                    starts_at: Self.iso(start), ends_at: Self.iso(end)))
                made = (try? JSONDecoder().decode(UUID.self, from: data))
            }
        }
        return ok ? made : nil
    }

    func promise(to friend: UUID, minutes: Int, stake: Int, until end: Date) async -> Bool {
        struct Body: Encodable { let to_friend: String; let target_minutes: Int; let stake: Int; let ends_at: String }
        return await perform(cost: stake) {
            _ = try await self.client.rpc("create_promise", Body(to_friend: friend.uuidString, target_minutes: minutes, stake: stake, ends_at: Self.iso(end)))
        }
    }

    func join(_ c: Challenge) async { _ = await perform(cost: c.fee) { _ = try await self.client.rpc("join_challenge", ["c": c.id.uuidString]) } }
    func leave(_ c: Challenge) async { _ = await perform { _ = try await self.client.rpc("leave_challenge", ["c": c.id.uuidString]) } }
    func cancel(_ c: Challenge) async { _ = await perform { _ = try await self.client.rpc("cancel_challenge", ["c": c.id.uuidString]) } }

    /// Join a private challenge with its invite code. Returns its id.
    func join(code: String) async -> UUID? {
        var joinedID: UUID?
        let ok = await perform {
            let data = try await self.client.rpc("join_challenge_by_code", ["code": code.trimmingCharacters(in: .whitespaces)])
            joinedID = try? JSONDecoder().decode(UUID.self, from: data)
        }
        return ok ? joinedID : nil
    }

    private func perform(cost: Int = 0, _ work: @escaping () async throws -> Void) async -> Bool {
        if cost > store.rocketBalance { error = "Not enough rockets — you have \(store.rocketBalance)."; return false }
        busy = true
        defer { busy = false }
        do {
            try await work()
            error = nil
            await load()
            await onRocketsMoved?()
            return true
        } catch {
            self.error = (error as? SupabaseClient.APIError)?.message ?? "Can't reach the server. Check your internet or VPN."
            return false
        }
    }

    private static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}

// MARK: - Rules

/// Duration like "6h" or "1h 30m"
func hm(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
}

/// The rules (the server checks the same: supabase/challenges.sql)
enum ChallengeRules {
    static let minHours = 4
    static let minPeople = 2
    /// Entry fee: at least 50 rockets per hour of the goal (4h → 200, 5h → 250 …)
    static func minFee(hours: Int) -> Int { hours * 50 }
    /// Everyone finished: fee back plus as much again, at most 100 rockets per hour of the goal
    static func bonus(fee: Int, minutes: Int) -> Int { min(fee, minutes * 100 / 60) }
}

/// My promises and the ones made to me
struct PromisesCard: View {
    @Environment(ChallengeService.self) private var service
    @Environment(FriendsService.self) private var friends

    var body: some View {
        let me = friends.me?.id
        let list = service.promises
        if !list.isEmpty {
            Card(title: "Promises", systemImage: "hand.raised.fingers.spread") {
                ForEach(list) { c in
                    let mine = c.creator == me
                    let other = friends.people[mine ? (c.friend ?? c.creator) : c.creator]?.profile.name ?? "a friend"
                    let done = service.members(of: c).first?.minutes ?? 0
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(mine ? "You promised \(other)" : "\(other) promised you").font(.callout.weight(.semibold))
                            Spacer()
                            Text(c.status == "settled" ? (done >= c.target_minutes ? "Kept ✅" : "Missed ❌")
                                 : c.status == "cancelled" ? "Cancelled" : "Due \(c.ends_at.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            ProgressView(value: min(1, Double(done) / Double(max(1, c.target_minutes))))
                            Text("\(hm(done)) / \(hm(c.target_minutes)) · \(c.fee) 🚀 at stake").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
                }
            }
        }
    }
}

struct PromiseSheet: View {
    let friend: FriendCard
    @Environment(ChallengeService.self) private var service
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 4.0
    @State private var stake = 50
    @State private var deadline = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date().addingTimeInterval(3600 * 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Make a promise to \(friend.profile.name)", systemImage: "hand.raised.fingers.spread").font(.title3.weight(.bold))
            HStack {
                Text("I'll study")
                Stepper("\(hm(Int(hours * 60)))", value: $hours, in: 0.5...24, step: 0.5)
            }
            DatePicker("By", selection: $deadline, in: Date().addingTimeInterval(600)..., displayedComponents: [.date, .hourAndMinute])
            HStack {
                Text("Stake")
                TextField("", value: $stake, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
                RocketIcon(size: 16)
                Text("· you have \(store.rocketBalance)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Study counts from now until the deadline. Keep it → you get the stake back. Miss it → \(friend.profile.name) gets it.")
                .font(.caption).foregroundStyle(.secondary)
            if let e = service.error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Promise · stake \(stake) 🚀") {
                    Task { if await service.promise(to: friend.id, minutes: Int(hours * 60), stake: stake, until: deadline) { dismiss() } }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(service.busy || stake < 1)
            }
        }
        .padding(20).frame(width: 440)
        .onAppear { service.error = nil }
    }
}
