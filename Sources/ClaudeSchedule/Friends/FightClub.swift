import SwiftUI

// Fight Club (experiment): you set a goal (alone, then invite friends or a whole group), a space monster appears with one health point per minute
// the goal takes. Every minute you study after it appears is a bullet; fire them from your ship.
// Beat it before the deadline and the rockets are shared by damage done. Rules run on the server (supabase/bosses.sql).

struct Boss: Decodable, Identifiable, Hashable {
    let id: UUID
    let creator: UUID
    let title: String
    let hp: Int
    let deadline: Date
    let monster: Int
    let status: String
    let created_at: Date

    /// Same as the server: 45 rockets per hour of the goal, +15% per monster level above 1
    var pool: Int { Int((Double(hp) / 60 * 45 * (1 + 0.15 * Double(monster - 1))).rounded(.down)) }
    var isAlive: Bool { status == "alive" }
}

struct BossInvite: Decodable, Hashable {
    let boss_id: UUID
    let user_id: UUID
    let from_user: UUID
}

struct BossFighter: Decodable, Hashable {
    let boss_id: UUID
    let user_id: UUID
    let minutes: Int
    let damage: Int
    /// bullets used, hit or miss
    var spent: Int? = nil
    var used: Int { spent ?? damage }
}

@MainActor @Observable
final class FightClubService {
    private(set) var bosses: [Boss] = []
    private(set) var fighters: [UUID: [BossFighter]] = [:]
    /// Invites: to me (to answer) and the ones my fights sent out
    private(set) var invites: [BossInvite] = []
    @ObservationIgnored private var notified: Set<UUID> = []
    var error: String?
    var busy = false

    @ObservationIgnored private let client = SupabaseClient.shared
    @ObservationIgnored private let store: AppStore
    @ObservationIgnored var onRocketsMoved: (() async -> Void)?

    init(store: AppStore) { self.store = store }

    func fighters(of b: Boss) -> [BossFighter] { fighters[b.id] ?? [] }
    func damageDone(_ b: Boss) -> Int { fighters(of: b).reduce(0) { $0 + $1.damage } }
    func healthLeft(_ b: Boss) -> Int { max(0, b.hp - damageDone(b)) }
    func me(_ b: Boss, _ id: UUID?) -> BossFighter? { fighters(of: b).first { $0.user_id == id } }

    /// Bullets I've earned so far, counted from my own study (what the server will accept after the next report)
    func earned(_ b: Boss) -> Int {
        Int(store.studyTime(in: DateInterval(start: b.created_at, end: max(b.created_at, min(Date(), b.deadline)))) / 60)
    }

    func load() async {
        guard await client.userID != nil else { return }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86400))
        do {
            let list = try await client.select("bosses?or=(status.eq.alive,deadline.gt.\(since))&order=created_at.desc", as: [Boss].self)
            var by: [UUID: [BossFighter]] = [:]
            if !list.isEmpty {
                let ids = list.map { $0.id.uuidString.lowercased() }.joined(separator: ",")
                for r in try await client.select("boss_fighters?boss_id=in.(\(ids))", as: [BossFighter].self) { by[r.boss_id, default: []].append(r) }
            }
            let inv = try await client.select("boss_invites?select=boss_id,user_id,from_user", as: [BossInvite].self)
            bosses = list
            fighters = by
            invites = inv
            notifyNewInvites()
        } catch {}
        // Developer tool: CS_TEST_BOSS=1 shows a pretend monster (local only, firing does nothing)
        if ProcessInfo.processInfo.environment["CS_TEST_BOSS"] != nil, let me = await client.userID {
            let fake = Boss(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B055")!, creator: UUID(), title: "Test monster",
                            hp: 900, deadline: Date().addingTimeInterval(86400 * 2), monster: 3, status: "alive", created_at: Date().addingTimeInterval(-86400 * 3))
            if !bosses.contains(where: { $0.id == fake.id }) { bosses.insert(fake, at: 0) }
            fighters[fake.id] = [BossFighter(boss_id: fake.id, user_id: me, minutes: 300, damage: 240)]
        }
    }

    /// Every minute: report my bullets for living monsters, let late ones escape
    func tick() async {
        await load()
        for b in bosses where b.isAlive {
            if Date() > b.deadline {
                _ = try? await client.rpc("expire_boss", ["b": b.id.uuidString])
            } else {
                struct Body: Encodable { let b: String; let mins: Int }
                _ = try? await client.rpc("report_boss", Body(b: b.id.uuidString, mins: earned(b)))
            }
        }
        await load()
    }

    /// Summon a monster on your own; invite people afterwards. Returns its id.
    func create(title: String, minutes: Int, deadline: Date) async -> UUID? {
        struct Body: Encodable { let title: String; let goal: Int; let ends: String }
        busy = true
        defer { busy = false }
        do {
            let data = try await client.rpc("create_boss", Body(title: title, goal: minutes, ends: ISO8601DateFormatter().string(from: deadline)))
            let id = (try? JSONDecoder().decode(UUID.self, from: data))
            error = nil
            await load()
            return id
        } catch {
            self.error = (error as? SupabaseClient.APIError)?.message ?? "Can't reach the server."
            return nil
        }
    }

    // MARK: Invites

    func invitesToMe(_ me: UUID?) -> [BossInvite] { invites.filter { $0.user_id == me } }
    func invited(to b: Boss) -> [BossInvite] { invites.filter { $0.boss_id == b.id } }

    func invite(_ b: Boss, friend: UUID) async {
        struct Body: Encodable { let b: String; let who: String }
        await perform { _ = try await self.client.rpc("invite_boss", Body(b: b.id.uuidString, who: friend.uuidString)) }
    }

    /// Everyone in the group gets the invite
    func invite(_ b: Boss, group: UUID) async {
        struct Body: Encodable { let b: String; let g: String }
        await perform { _ = try await self.client.rpc("invite_boss_group", Body(b: b.id.uuidString, g: group.uuidString)) }
    }

    /// Invite some friends and whole groups in one go
    func sendInvites(_ b: Boss, friends: Set<UUID>, groups: Set<UUID>) async {
        for f in friends { await invite(b, friend: f) }
        for g in groups { await invite(b, group: g) }
    }

    /// Only the one who summoned it
    func delete(_ b: Boss) async {
        await perform { _ = try await self.client.rpc("delete_boss", ["b": b.id.uuidString]) }
    }

    func answer(_ b: UUID, accept: Bool) async {
        struct Body: Encodable { let b: String; let accept: Bool }
        await perform { _ = try await self.client.rpc("answer_boss_invite", Body(b: b.uuidString, accept: accept)) }
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await work(); error = nil } catch { self.error = (error as? SupabaseClient.APIError)?.message ?? "Can't reach the server." }
        await load()
    }

    private func notifyNewInvites() {
        Task {
            guard let me = await client.userID else { return }
            for inv in invitesToMe(me) where !notified.contains(inv.boss_id) {
                notified.insert(inv.boss_id)
                if let b = bosses.first(where: { $0.id == inv.boss_id }) {
                    Notifier.post(id: "boss-\(b.id)", title: "👾 You're invited to fight “\(b.title)”",
                                  body: "Open Fight Club to join — study to earn bullets and share the prize.")
                }
            }
        }
    }

    /// Bullets left for me
    func ammo(_ b: Boss, me: UUID?) -> Int {
        let f = self.me(b, me)
        return max(0, max(earned(b), f?.minutes ?? 0) - (f?.used ?? 0))
    }

    /// Send a burst: `shots` bullets used, `hits` of them landed. Returns the damage the server counted.
    @discardableResult
    func fire(_ b: Boss, shots: Int, hits: Int) async -> Int {
        struct Report: Encodable { let b: String; let mins: Int }
        struct Fire: Encodable { let b: String; let shots: Int; let hits: Int }
        let before = healthLeft(b)
        do {
            // make sure the server knows about my latest study first
            _ = try await client.rpc("report_boss", Report(b: b.id.uuidString, mins: earned(b)))
            _ = try await client.rpc("fire_boss", Fire(b: b.id.uuidString, shots: shots, hits: hits))
            error = nil
            await load()
            let after = bosses.first { $0.id == b.id }.map(healthLeft) ?? before
            if after == 0 { await onRocketsMoved?() }
            return max(0, before - after)
        } catch {
            self.error = (error as? SupabaseClient.APIError)?.message ?? "Can't reach the server."
            await load()
            return 0
        }
    }
}

// MARK: - Views

func monsterImage(_ n: Int) -> NSImage? { PlanetPainter.bundleImage("boss\(min(5, max(1, n)))") }
private func hm(_ m: Int) -> String { let h = m / 60, r = m % 60; return h == 0 ? "\(r)m" : (r == 0 ? "\(h)h" : "\(h)h \(r)m") }

/// Monsters you fight
struct FightClubCard: View {
    @Environment(FightClubService.self) private var fc
    @Environment(FriendsService.self) private var friends
    @State private var creating = false
    @State private var battle: Boss?
    @State private var deleting: Boss?

    var body: some View {
        let me = friends.me?.id
        let list = fc.bosses.filter { b in fc.fighters(of: b).contains { $0.user_id == me } || b.id.uuidString.hasSuffix("B055") }
        Card(title: "Your fights", systemImage: "burst.fill") {
            HStack {
                Text("Set a goal and a monster appears. Fight alone or invite friends or a whole group. Every minute you study is a bullet.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { fc.error = nil; creating = true } label: { Label("Summon Monster", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            if list.isEmpty { Text("No monsters yet — summon one!").font(.callout).foregroundStyle(.secondary) }
            ForEach(list) { b in
                Button { battle = b } label: {
                    HStack(spacing: 12) {
                        if let img = monsterImage(b.monster) {
                            Image(nsImage: img).resizable().scaledToFit().frame(width: 54, height: 54)
                                .saturation(b.isAlive ? 1 : 0.2)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(b.title).font(.headline)
                                Text("LV \(b.monster)").font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.red.opacity(0.25)))
                                Text(b.status == "defeated" ? "Defeated 🏆" : b.status == "escaped" ? "Escaped 💨" : "Due \(b.deadline.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Label("\(fc.fighters(of: b).count)", systemImage: "person.2.fill").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(fc.healthLeft(b)), total: Double(b.hp)).tint(.red)
                            Text("\(hm(fc.healthLeft(b))) of \(hm(b.hp)) health left · \(b.pool) 🚀 prize").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if b.creator == me { Button("Delete Monster…", role: .destructive) { deleting = b } }
                }
            }
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let d = deleting { Task { await fc.delete(d) } } }
        } message: { Text("It disappears for everyone fighting it. Bullets already fired are lost and nobody gets a prize.") }
        .sheet(isPresented: $creating) { NewBossSheet { id in creating = false; Task { await fc.load(); battle = fc.bosses.first { $0.id == id } } } }
        .sheet(item: $battle) { BattleView(bossID: $0.id) }
    }
}

/// Invites waiting for my answer
struct FightInvitesCard: View {
    @Environment(FightClubService.self) private var fc
    @Environment(FriendsService.self) private var friends

    var body: some View {
        let mine = fc.invitesToMe(friends.me?.id)
        if !mine.isEmpty {
            Card(title: "Invitations", systemImage: "envelope.badge.fill") {
                ForEach(mine, id: \.boss_id) { inv in
                    if let b = fc.bosses.first(where: { $0.id == inv.boss_id }) {
                        HStack(spacing: 12) {
                            if let img = monsterImage(b.monster) { Image(nsImage: img).resizable().scaledToFit().frame(width: 44, height: 44) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(friends.people[inv.from_user]?.profile.name ?? "A friend") invites you to fight “\(b.title)”").font(.callout.weight(.semibold))
                                Text("LV \(b.monster) · \(hm(b.hp)) of health · \(b.pool) 🚀 prize · due \(b.deadline.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Decline") { Task { await fc.answer(b.id, accept: false) } }
                            Button("Join the Fight") { Task { await fc.answer(b.id, accept: true) } }.buttonStyle(.borderedProminent).tint(.red)
                        }
                        .disabled(fc.busy)
                    }
                }
            }
        }
    }
}

/// Pick who to invite: tap friends' avatars and whole groups
struct InvitePicker: View {
    @Binding var friendIDs: Set<UUID>
    @Binding var groupIDs: Set<UUID>
    /// Already fighting or invited (shown, not selectable)
    var taken: Set<UUID> = []
    @Environment(FriendsService.self) private var friends

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if friends.friends.isEmpty && friends.groups.isEmpty {
                Text("Add friends or join a group to fight together — or just fight alone.").font(.caption).foregroundStyle(.secondary)
            }
            if !friends.friends.isEmpty {
                Text("FRIENDS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(friends.friends) { f in
                            let on = friendIDs.contains(f.id), done = taken.contains(f.id)
                            Button {
                                if on { friendIDs.remove(f.id) } else { friendIDs.insert(f.id) }
                            } label: {
                                VStack(spacing: 4) {
                                    Avatar(name: f.profile.name, color: .accentColor, size: 40, planet: f.profile.avatar)
                                        .overlay(alignment: .bottomTrailing) {
                                            if on || done {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(done ? .gray : .green)
                                                    .background(Circle().fill(.background)).offset(x: 4, y: 4)
                                            }
                                        }
                                    Text(f.profile.name).font(.caption).lineLimit(1).frame(width: 64)
                                    if done { Text("already in").font(.caption2).foregroundStyle(.secondary) }
                                }
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.red.opacity(0.18) : .clear))
                            }
                            .buttonStyle(.plain)
                            .disabled(done)
                        }
                    }
                }
            }
            if !friends.groups.isEmpty {
                Text("WHOLE GROUP").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(friends.groups) { g in
                        let on = groupIDs.contains(g.id)
                        Button {
                            if on { groupIDs.remove(g.id) } else { groupIDs.insert(g.id) }
                        } label: {
                            Label("\(g.name) · \(g.members.count)", systemImage: on ? "checkmark.circle.fill" : "person.3.fill")
                                .font(.callout)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(on ? Color.red.opacity(0.25) : Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Invite from the battle screen
struct InviteSheet: View {
    let boss: Boss
    @Environment(FightClubService.self) private var fc
    @Environment(\.dismiss) private var dismiss
    @State private var friendIDs: Set<UUID> = []
    @State private var groupIDs: Set<UUID> = []

    var body: some View {
        let taken = Set(fc.fighters(of: boss).map(\.user_id) + fc.invited(to: boss).map(\.user_id))
        VStack(alignment: .leading, spacing: 14) {
            Label("Invite to fight “\(boss.title)”", systemImage: "person.badge.plus").font(.title3.weight(.bold))
            InvitePicker(friendIDs: $friendIDs, groupIDs: $groupIDs, taken: taken)
            if let e = fc.error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send Invites") {
                    Task { await fc.sendInvites(boss, friends: friendIDs, groups: groupIDs); dismiss() }
                }
                .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.defaultAction)
                .disabled(friendIDs.isEmpty && groupIDs.isEmpty || fc.busy)
            }
        }
        .padding(20).frame(width: 480)
    }
}

/// Quick deadlines instead of a date picker
private enum Due: String, CaseIterable, Identifiable {
    case tonight = "Tonight", tomorrow = "Tomorrow", days3 = "3 days", week = "A week", custom = "Pick…"
    var id: String { rawValue }
    func date(custom: Date) -> Date {
        let cal = Calendar.current, now = Date()
        let tonight = cal.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        switch self {
        case .tonight: return now.addingTimeInterval(3600 * 2) > tonight ? tonight.addingTimeInterval(86400) : tonight
        case .tomorrow: return tonight.addingTimeInterval(86400)
        case .days3: return tonight.addingTimeInterval(3 * 86400)
        case .week: return tonight.addingTimeInterval(7 * 86400)
        case .custom: return custom
        }
    }
}

struct NewBossSheet: View {
    var onCreated: (UUID) -> Void = { _ in }
    @Environment(FightClubService.self) private var fc
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hours = 5.0
    @State private var due: Due = .days3
    @State private var customDate = Date().addingTimeInterval(5 * 86400)
    @State private var friendIDs: Set<UUID> = []
    @State private var groupIDs: Set<UUID> = []

    private var level: Int { let m = hours * 60; return m <= 300 ? 1 : m <= 600 ? 2 : m <= 1200 ? 3 : m <= 2400 ? 4 : 5 }
    private var pool: Int { Int(hours * 45 * (1 + 0.15 * Double(level - 1))) }
    private var deadline: Date { due.date(custom: customDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Summon a monster", systemImage: "burst.fill").font(.title3.weight(.bold))
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 6) {
                    if let img = monsterImage(level) {
                        Image(nsImage: img).resizable().scaledToFit()
                            .frame(width: 70 + CGFloat(level) * 14, height: 70 + CGFloat(level) * 14)
                            .animation(.spring(duration: 0.3), value: level)
                    }
                    Text("Level \(level)").font(.caption.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color.red.opacity(0.25)))
                    Text("\(pool) 🚀 prize").font(.caption.weight(.semibold))
                }
                .frame(width: 150)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Goal, e.g. Finish chapter 5", text: $title).textFieldStyle(.roundedBorder)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HOW MUCH STUDY").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach([2.0, 5, 10, 20], id: \.self) { h in
                                Button("\(Int(h))h") { hours = h }
                                    .buttonStyle(.bordered).tint(hours == h ? .red : nil)
                            }
                            Divider().frame(height: 18)
                            Text(hm(Int(hours * 60))).monospacedDigit().fontWeight(.semibold).frame(width: 64, alignment: .trailing)
                            Stepper("", value: $hours, in: 0.5...100, step: 0.5).labelsHidden()
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DEADLINE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Picker("", selection: $due) { ForEach(Due.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden()
                        if due == .custom {
                            DatePicker("", selection: $customDate, in: Date().addingTimeInterval(1800)..., displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                        }
                        Text("Escapes \(deadline.formatted(.dateTime.weekday(.wide).hour().minute())) · \(deadline.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(friendIDs.isEmpty && groupIDs.isEmpty ? "Fight alone, or tap friends and groups to invite them" : "Invites go out when you summon")
                    .font(.callout.weight(.semibold))
                InvitePicker(friendIDs: $friendIDs, groupIDs: $groupIDs)
            }
            Text("Each minute studied after it appears is one bullet. Only hits count. If the deadline comes first, it escapes and nobody wins.")
                .font(.caption).foregroundStyle(.secondary)
            if let e = fc.error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(friendIDs.isEmpty && groupIDs.isEmpty ? "Summon & Fight Alone" : "Summon & Invite") {
                    Task {
                        if let id = await fc.create(title: title.isEmpty ? "Study goal" : title, minutes: Int(hours * 60), deadline: deadline) {
                            if let b = fc.bosses.first(where: { $0.id == id }) { await fc.sendInvites(b, friends: friendIDs, groups: groupIDs) }
                            onCreated(id)
                        }
                    }
                }
                .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.defaultAction).disabled(fc.busy)
            }
        }
        .padding(20).frame(width: 600)
    }
}

/// The fight: a living monster drifts and dodges up top; move your jet with the mouse (or ← →)
/// and click or press Space to fire. Only bullets that hit do damage — misses still cost a bullet.
struct BattleView: View {
    let bossID: UUID
    @Environment(FightClubService.self) private var fc
    @Environment(FriendsService.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var shipX: CGFloat = 0.5          // 0…1 across the arena
    @State private var bullets: [Bullet] = []
    @State private var pendingShots = 0
    @State private var pendingHits = 0
    @State private var arenaSize = CGSize(width: 760, height: 420)
    @State private var flushing = false
    @FocusState private var focused: Bool
    @State private var confirmDelete = false
    @State private var inviting = false
    @State private var holdLeft = false
    @State private var holdRight = false
    @State private var lastShot = Date.distantPast
    private let start = Date()

    struct Bullet: Identifiable { let id = UUID(); let x: CGFloat; let t0: Double; let hit: Bool }
    static let flight = 0.55   // seconds from ship to monster height

    var body: some View {
        if let b = fc.bosses.first(where: { $0.id == bossID }) {
            let ammo = max(0, fc.ammo(b, me: friends.me?.id) - pendingShots)
            let left = max(0, fc.healthLeft(b) - pendingHits)
            VStack(spacing: 0) {
                header(b, left: left)
                arena(b, left: left, ammo: ammo)
                footer(b, ammo: ammo)
            }
            .frame(width: 760, height: 660)
            .background(Color(hex: "#070B1A"))
            .environment(\.colorScheme, .dark)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            // Keyboard: hold ← → (or A D) to fly, Space to fire (hold for rapid fire)
            .onKeyPress(keys: [.leftArrow, .rightArrow, "a", "d"], phases: [.down, .repeat, .up]) { press in
                let left = press.key == .leftArrow || press.key.character == "a"
                if press.phase == .up { if left { holdLeft = false } else { holdRight = false } }
                else { if left { holdLeft = true } else { holdRight = true } }
                return .handled
            }
            .onKeyPress(.space, phases: [.down, .repeat]) { _ in
                guard Date().timeIntervalSince(lastShot) > 0.12 else { return .handled }
                lastShot = Date()
                shoot(b, ammo: ammo, left: left)
                return .handled
            }
            .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1.2)); await flush(b) } }
            .task {
                // smooth flying while a key is held
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(16))
                    let dir: CGFloat = (holdRight ? 1 : 0) - (holdLeft ? 1 : 0)
                    if dir != 0 { shipX = min(0.96, max(0.04, shipX + dir * 0.011)) }
                }
            }
            .onDisappear { Task { await flush(b) } }
        } else {
            Text("Loading…").frame(width: 300, height: 200).task { await fc.load() }
        }
    }

    // MARK: The monster's life

    private var now: Double { Date().timeIntervalSince(start) }

    /// How lively it is: faster when bigger and when it's hurt
    private func pace(_ b: Boss, _ left: Int) -> Double {
        0.55 + 0.12 * Double(b.monster) + 0.9 * (1 - Double(left) / Double(max(1, b.hp)))
    }

    /// Where the monster's centre is (0…1 across) at time t — a wandering, dodging path
    private func monsterX(_ b: Boss, _ left: Int, at t: Double) -> CGFloat {
        let p = pace(b, left)
        let wander = sin(t * p) * 0.7 + sin(t * p * 2.3 + 1.1) * 0.25 + sin(t * p * 0.37 + 2) * 0.2
        return 0.5 + CGFloat(wander) * 0.33
    }

    private func monsterSize(_ b: Boss) -> CGFloat { min(arenaSize.height * 0.5, 120 + CGFloat(b.monster) * 18) }

    // MARK: Views

    private func header(_ b: Boss, left: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(b.title).font(.title2.weight(.bold))
                Text("LV \(b.monster)").font(.caption.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.red.opacity(0.3)))
                Spacer()
                Text(b.status == "defeated" ? "Defeated 🏆" : b.status == "escaped" ? "Escaped 💨" : "Escapes \(b.deadline.formatted(.relative(presentation: .named)))")
                    .font(.callout).foregroundStyle(.secondary)
                if b.isAlive { Button { inviting = true } label: { Label("Invite", systemImage: "person.badge.plus") } }
                if b.creator == friends.me?.id {
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .help("Delete this monster")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .sheet(isPresented: $inviting) { InviteSheet(boss: b) }
            .confirmationDialog("Delete “\(b.title)”?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await fc.delete(b); dismiss() } }
            } message: { Text("It disappears for everyone fighting it. Bullets already fired are lost and nobody gets a prize.") }
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                ProgressView(value: Double(left), total: Double(b.hp)).tint(.red)
                Text("\(left) / \(b.hp)").font(.callout.monospacedDigit().weight(.semibold))
            }
        }
        .padding(16)
    }

    private func arena(_ b: Boss, left: Int, ammo: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let size = monsterSize(b)
            let monsterY = size / 2 + 16
            let shipY = h - 56
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(start)
                let mx = monsterX(b, left, at: t) * w
                let p = pace(b, left)
                // alive: breathing, swaying, a little hop; flinches when hit
                let breath = 1 + 0.045 * sin(t * 3.1 * p)
                let sway = 5 * sin(t * 1.7 * p)
                let hop = abs(sin(t * 2.2 * p)) * -7
                let hitNow = bullets.contains { $0.hit && (0...0.18).contains(t - ($0.t0 + Self.flight)) }
                ZStack {
                    StarsBackground()
                    if let img = monsterImage(b.monster) {
                        Image(nsImage: img).resizable().scaledToFit()
                            .frame(width: size, height: size)
                            .scaleEffect(x: 2 - breath, y: breath, anchor: .bottom)
                            .rotationEffect(.degrees(b.isAlive ? sway : 18))
                            .colorMultiply(hitNow ? Color(red: 1, green: 0.45, blue: 0.45) : .white)
                            .offset(x: hitNow ? CGFloat.random(in: -6...6) : 0)
                            .saturation(b.status == "defeated" ? 0 : 1)
                            .opacity(b.status == "defeated" ? 0.35 : 1)
                            .position(x: b.isAlive ? mx : w / 2, y: monsterY + (b.isAlive ? hop : 0))
                    }
                    // bullets and hits
                    Canvas { ctx, _ in
                        for bl in bullets {
                            let k = (t - bl.t0) / Self.flight
                            if k < 0 { continue }
                            if bl.hit && k >= 1 {
                                // a hit: burst + "-1" floating up
                                let e = (t - bl.t0 - Self.flight) / 0.5
                                guard e < 1 else { continue }
                                let hx = monsterX(b, left, at: bl.t0 + Self.flight) * w
                                let r = 8 + 18 * e
                                ctx.fill(Path(ellipseIn: CGRect(x: hx - r, y: monsterY - r, width: r * 2, height: r * 2)),
                                         with: .color(.orange.opacity(0.7 * (1 - e))))
                                ctx.draw(Text("-1").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.yellow.opacity(1 - e)),
                                         at: CGPoint(x: hx + 18, y: monsterY - 20 - 30 * e))
                                continue
                            }
                            // flying (misses keep going off the top)
                            let y = shipY - 30 - (shipY - monsterY) * k
                            if y < -20 { continue }
                            let x = bl.x * w
                            ctx.fill(Path(roundedRect: CGRect(x: x - 2.5, y: y - 9, width: 5, height: 18), cornerRadius: 2.5),
                                     with: .linearGradient(Gradient(colors: [.yellow, .orange]), startPoint: CGPoint(x: x, y: y - 9), endPoint: CGPoint(x: x, y: y + 9)))
                        }
                    }
                    .allowsHitTesting(false)
                    // the jet
                    if let ship = PlanetPainter.bundleImage("fighter") {
                        Image(nsImage: ship).resizable().scaledToFit().frame(width: 96, height: 96)
                            .rotationEffect(.degrees(Double((shipX - 0.5) * 10)))
                            .position(x: shipX * w, y: shipY)
                    }
                    if b.isAlive && ammo == 0 {
                        Text("Out of bullets — study to reload 📚").font(.callout.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(.black.opacity(0.6)))
                            .position(x: w / 2, y: h / 2)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }   // clicking the arena gives the keyboard back to the game
            .onAppear { arenaSize = geo.size }
            .onChange(of: geo.size) { _, s in arenaSize = s }
        }
        .clipped()
    }

    private func footer(_ b: Boss, ammo: Int) -> some View {
        let people = fc.fighters(of: b).filter { $0.damage > 0 }.sorted { $0.damage > $1.damage }
        let total = max(1, fc.damageDone(b) + pendingHits)
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.fill").foregroundStyle(.yellow)
                    Text("\(ammo) bullets").font(.headline.monospacedDigit())
                    Text("· 1 per minute studied since it appeared").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 2) {
                    ForEach(0..<30, id: \.self) { i in
                        Capsule().fill(i < min(30, ammo) ? Color.yellow : Color.white.opacity(0.1)).frame(width: 5, height: 16)
                    }
                    if ammo > 30 { Text("+\(ammo - 30)").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(b.isAlive ? "Hold ← → (or A D) to fly  ·  Space to fire (hold for rapid fire)  ·  only hits count" : "This fight is over.")
                    .font(.caption).foregroundStyle(.secondary)
                if let e = fc.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("Damage · prize \(b.pool) 🚀").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                if people.isEmpty && pendingHits == 0 { Text("No hits yet").font(.caption).foregroundStyle(.tertiary) }
                ForEach(people.prefix(5), id: \.user_id) { f in
                    let isMe = f.user_id == friends.me?.id
                    let name = isMe ? "You" : (friends.people[f.user_id]?.profile.name ?? "Member")
                    let dmg = f.damage + (isMe ? pendingHits : 0)
                    HStack {
                        Text(name).lineLimit(1)
                        Spacer()
                        Text("\(dmg) · ~\(b.pool * dmg / total) 🚀").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption).frame(width: 220)
                }
            }
        }
        .padding(16)
    }

    // MARK: Shooting

    private func shoot(_ b: Boss, ammo: Int, left: Int) {
        guard b.isAlive, ammo > 0, left > 0 else { return }
        let t = now
        let w = arenaSize.width
        // where the monster will be when the bullet gets there
        let target = monsterX(b, left, at: t + Self.flight) * w
        let hit = abs(shipX * w - target) < monsterSize(b) * 0.32
        bullets.append(Bullet(x: shipX, t0: t, hit: hit))
        pendingShots += 1
        if hit { pendingHits += 1 }
        // forget old bullets
        bullets.removeAll { now - $0.t0 > 2.5 }
    }

    /// Send what was fired since the last flush
    private func flush(_ b: Boss) async {
        guard !flushing, pendingShots > 0 else { return }
        flushing = true
        let shots = pendingShots, hits = pendingHits
        pendingShots = 0; pendingHits = 0
        await fc.fire(b, shots: shots, hits: hits)
        flushing = false
    }
}

/// Fight Club page: invitations and your fights
struct FightClubPage: View {
    @Environment(FightClubService.self) private var fc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    if let img = monsterImage(5) { Image(nsImage: img).resizable().scaledToFit().frame(width: 76, height: 76) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fight Club").font(.largeTitle.weight(.bold))
                        Text("Summon a monster for a study goal. Study to earn bullets, fire them from your ship, and share the rockets when it falls.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let ship = PlanetPainter.bundleImage("fighter") { Image(nsImage: ship).resizable().scaledToFit().frame(width: 70, height: 70) }
                }
                FightInvitesCard()
                FightClubCard()
                if let e = fc.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .padding(24)
        }
        .navigationTitle("Fight Club")
        .task { await fc.load() }
    }
}
