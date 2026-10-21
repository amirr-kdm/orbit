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

    /// Same as the server: 30 rockets per hour of the goal, +15% per monster level above 1
    var pool: Int { Int((Double(hp) / 60 * 30 * (1 + 0.15 * Double(monster - 1))).rounded(.down)) }
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

    /// Fire bullets; returns the damage actually done
    func fire(_ b: Boss, shots: Int) async -> Int {
        struct Report: Encodable { let b: String; let mins: Int }
        struct Fire: Encodable { let b: String; let shots: Int }
        let before = healthLeft(b)
        do {
            // make sure the server knows about my latest study first
            _ = try await client.rpc("report_boss", Report(b: b.id.uuidString, mins: earned(b)))
            _ = try await client.rpc("fire_boss", Fire(b: b.id.uuidString, shots: shots))
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
            }
        }
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

/// Invite friends one by one, or a whole group at once
struct InviteMenu: View {
    let boss: Boss
    @Environment(FightClubService.self) private var fc
    @Environment(FriendsService.self) private var friends
    @State private var sent: String?

    var body: some View {
        let fighting = Set(fc.fighters(of: boss).map(\.user_id))
        let invited = Set(fc.invited(to: boss).map(\.user_id))
        Menu {
            Section("Friends") {
                ForEach(friends.friends) { f in
                    Button {
                        Task { await fc.invite(boss, friend: f.id); sent = "Invite sent to \(f.profile.name)" }
                    } label: {
                        Text(f.profile.name + (fighting.contains(f.id) ? " — fighting" : invited.contains(f.id) ? " — invited" : ""))
                    }
                    .disabled(fighting.contains(f.id) || invited.contains(f.id))
                }
                if friends.friends.isEmpty { Text("No friends yet") }
            }
            Section("Whole group") {
                ForEach(friends.groups) { g in
                    Button("\(g.name) (\(g.members.count))") { Task { await fc.invite(boss, group: g.id); sent = "Everyone in \(g.name) was invited" } }
                }
                if friends.groups.isEmpty { Text("No groups yet") }
            }
        } label: {
            Label(sent ?? "Invite", systemImage: "person.badge.plus")
        }
        .fixedSize()
    }
}

struct NewBossSheet: View {
    var onCreated: (UUID) -> Void = { _ in }
    @Environment(FightClubService.self) private var fc
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hours = 5.0
    @State private var deadline = Date().addingTimeInterval(3 * 86400)

    private var level: Int { let m = hours * 60; return m <= 300 ? 1 : m <= 600 ? 2 : m <= 1200 ? 3 : m <= 2400 ? 4 : 5 }
    private var pool: Int { Int(hours * 30 * (1 + 0.15 * Double(level - 1))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Summon a monster", systemImage: "burst.fill").font(.title3.weight(.bold))
            HStack(alignment: .top, spacing: 16) {
                if let img = monsterImage(level) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(width: 70 + CGFloat(level) * 14, height: 70 + CGFloat(level) * 14)
                        .animation(.spring(duration: 0.3), value: level)
                }
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Goal, e.g. Finish chapter 5", text: $title).textFieldStyle(.roundedBorder)
                    Stepper("It takes \(hm(Int(hours * 60))) of study", value: $hours, in: 0.5...100, step: 0.5)
                    DatePicker("Deadline", selection: $deadline, in: Date().addingTimeInterval(1800)..., displayedComponents: [.date, .hourAndMinute])
                    Text("Monster level \(level) · \(hm(Int(hours * 60))) of health · prize \(pool) 🚀 shared by damage").font(.callout.weight(.semibold))
                }
            }
            Text("You can fight alone, or invite friends or a whole group from the battle screen. Each minute studied after it appears is one bullet. If the deadline passes first, it escapes and nobody wins.")
                .font(.caption).foregroundStyle(.secondary)
            if let e = fc.error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Summon") {
                    Task { if let id = await fc.create(title: title.isEmpty ? "Study goal" : title, minutes: Int(hours * 60), deadline: deadline) { onCreated(id) } }
                }
                .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.defaultAction).disabled(fc.busy)
            }
        }
        .padding(20).frame(width: 520)
    }
}

/// The fight: the monster up top, your ship below, bullets fly up
struct BattleView: View {
    let bossID: UUID
    @Environment(FightClubService.self) private var fc
    @Environment(FriendsService.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var shots: [Shot] = []
    @State private var hits: [Hit] = []
    @State private var shake = false
    @State private var firing = false

    struct Shot: Identifiable { let id = UUID(); let x: CGFloat; let delay: Double }
    struct Hit: Identifiable { let id = UUID(); let text: String; let x: CGFloat }

    var body: some View {
        if let b = fc.bosses.first(where: { $0.id == bossID }) {
            let mine = fc.me(b, friends.me?.id)
            let ammo = max(0, max(fc.earned(b), mine?.minutes ?? 0) - (mine?.damage ?? 0))
            let left = fc.healthLeft(b)
            VStack(spacing: 0) {
                header(b, left: left)
                arena(b, left: left)
                controls(b, ammo: ammo, left: left)
            }
            .frame(width: 760, height: 640)
            .background(Color(hex: "#070B1A"))
            .environment(\.colorScheme, .dark)
        } else {
            Text("Loading…").frame(width: 300, height: 200).task { await fc.load() }
        }
    }

    private func header(_ b: Boss, left: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(b.title).font(.title2.weight(.bold))
                Text("LV \(b.monster)").font(.caption.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.red.opacity(0.3)))
                Spacer()
                Text(b.status == "defeated" ? "Defeated 🏆" : b.status == "escaped" ? "Escaped 💨" : "Escapes \(b.deadline.formatted(.relative(presentation: .named)))")
                    .font(.callout).foregroundStyle(.secondary)
                if b.isAlive { InviteMenu(boss: b) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                ProgressView(value: Double(left), total: Double(b.hp)).tint(.red)
                Text("\(left) / \(b.hp)").font(.callout.monospacedDigit().weight(.semibold))
            }
        }
        .padding(16)
    }

    private func arena(_ b: Boss, left: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let size = min(h * 0.62, 150 + CGFloat(b.monster) * 30)
            ZStack {
                StarsBackground()
                // the monster
                if let img = monsterImage(b.monster) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(width: size, height: size)
                        .saturation(b.status == "defeated" ? 0 : 1)
                        .opacity(b.status == "defeated" ? 0.35 : 1)
                        .rotationEffect(.degrees(b.status == "defeated" ? 18 : 0))
                        .offset(x: shake ? 9 : 0)
                        .colorMultiply(shake ? Color(red: 1, green: 0.55, blue: 0.55) : .white)
                        .position(x: w / 2, y: size / 2 + 14)
                }
                // damage numbers
                ForEach(hits) { hit in
                    Text(hit.text).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.yellow)
                        .shadow(color: .red, radius: 6)
                        .position(x: w / 2 + hit.x, y: size * 0.4)
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                }
                // bullets
                ForEach(shots) { s in
                    BulletView(from: CGPoint(x: w / 2 + s.x, y: h - 90), to: CGPoint(x: w / 2 + s.x * 0.3, y: size * 0.55), delay: s.delay)
                }
                // my ship
                if let ship = PlanetPainter.bundleImage("fighter") {
                    Image(nsImage: ship).resizable().scaledToFit().frame(width: 110, height: 110)
                        .position(x: w / 2, y: h - 60)
                        .offset(y: firing ? 4 : 0)
                }
            }
            .clipped()
        }
    }

    private func controls(_ b: Boss, ammo: Int, left: Int) -> some View {
        let people = fc.fighters(of: b).filter { $0.damage > 0 }.sorted { $0.damage > $1.damage }
        let total = max(1, fc.damageDone(b))
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.fill").foregroundStyle(.yellow)
                    Text("\(ammo) bullets").font(.headline.monospacedDigit())
                    Text("· 1 per minute studied since it appeared").font(.caption).foregroundStyle(.secondary)
                }
                // magazine
                HStack(spacing: 2) {
                    ForEach(0..<30, id: \.self) { i in
                        Capsule().fill(i < min(30, ammo) ? Color.yellow : Color.white.opacity(0.1)).frame(width: 5, height: 16)
                    }
                    if ammo > 30 { Text("+\(ammo - 30)").font(.caption2).foregroundStyle(.secondary) }
                }
                if b.isAlive {
                    HStack {
                        ForEach([1, 10, 60], id: \.self) { n in
                            Button("Fire \(n)") { fire(b, n) }.disabled(ammo < 1 || firing)
                        }
                        Button("Fire all (\(min(ammo, left)))") { fire(b, min(ammo, left)) }
                            .buttonStyle(.borderedProminent).tint(.red).disabled(ammo < 1 || firing)
                    }
                    .controlSize(.large)
                }
                if let e = fc.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("Damage · prize \(b.pool) 🚀").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                if people.isEmpty { Text("No hits yet").font(.caption).foregroundStyle(.tertiary) }
                ForEach(people.prefix(5), id: \.user_id) { f in
                    let name = f.user_id == friends.me?.id ? "You" : (friends.people[f.user_id]?.profile.name ?? "Member")
                    HStack {
                        Text(name).lineLimit(1)
                        Spacer()
                        Text("\(f.damage) · ~\(b.pool * f.damage / total) 🚀").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption).frame(width: 220)
                }
            }
        }
        .padding(16)
    }

    private func fire(_ b: Boss, _ n: Int) {
        firing = true
        // a volley: up to 12 bullets on screen whatever the count
        let count = min(12, max(1, n))
        withAnimation(.none) { shots = (0..<count).map { i in Shot(x: CGFloat.random(in: -30...30), delay: Double(i) * 0.07) } }
        Task {
            let dealt = await fc.fire(b, shots: n)
            try? await Task.sleep(for: .milliseconds(450))
            if dealt > 0 {
                withAnimation(.spring(duration: 0.15)) { shake = true }
                withAnimation(.spring(duration: 0.4)) { hits.append(Hit(text: "-\(dealt)", x: CGFloat.random(in: -60...60))) }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(duration: 0.3)) { shake = false }
            }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation { hits.removeAll(); shots.removeAll() }
            firing = false
        }
    }
}

/// One bullet flying from the ship to the monster
private struct BulletView: View {
    let from: CGPoint
    let to: CGPoint
    let delay: Double
    @State private var gone = false

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            .frame(width: 5, height: 18)
            .shadow(color: .orange, radius: 6)
            .position(gone ? to : from)
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeIn(duration: 0.45).delay(delay)) { gone = true } }
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
