import SwiftUI

/// A group challenge or a promise to a friend (rules and payouts run on the server — see supabase/challenges.sql)
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

    var isPromise: Bool { kind == "promise" }
    var isOpen: Bool { status == "open" }
    func started(_ now: Date = Date()) -> Bool { now >= starts_at }
    func ended(_ now: Date = Date()) -> Bool { now >= ends_at }
    /// Apps can still report minutes for this long after the end; then it pays out
    static let grace: TimeInterval = 3600
}

struct ChallengeMember: Decodable, Hashable {
    let challenge_id: UUID
    let user_id: UUID
    let minutes: Int
}

@MainActor @Observable
final class ChallengeService {
    private(set) var challenges: [Challenge] = []
    private(set) var members: [UUID: [ChallengeMember]] = [:]
    var error: String?
    var busy = false

    @ObservationIgnored private let client = SupabaseClient.shared
    @ObservationIgnored private let store: AppStore
    /// Called after rockets moved (entry fee, refund, payout) so the balance updates right away
    @ObservationIgnored var onRocketsMoved: (() async -> Void)?

    init(store: AppStore) { self.store = store }

    func members(of c: Challenge) -> [ChallengeMember] { members[c.id] ?? [] }
    func joined(_ c: Challenge, me: UUID?) -> Bool { members(of: c).contains { $0.user_id == me } }
    func challenges(inGroup g: UUID) -> [Challenge] { challenges.filter { $0.group_id == g } }
    var promises: [Challenge] { challenges.filter(\.isPromise) }

    /// Open ones, plus anything finished in the last week
    func load() async {
        guard await client.userID != nil else { return }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86400))
        do {
            let list = try await client.select("challenges?or=(status.eq.open,ends_at.gt.\(since))&order=starts_at.desc", as: [Challenge].self)
            var byID: [UUID: [ChallengeMember]] = [:]
            if !list.isEmpty {
                let ids = list.map { $0.id.uuidString.lowercased() }.joined(separator: ",")
                let rows = try await client.select("challenge_members?challenge_id=in.(\(ids))&select=challenge_id,user_id,minutes", as: [ChallengeMember].self)
                for r in rows { byID[r.challenge_id, default: []].append(r) }
            }
            challenges = list
            members = byID
        } catch {
            // offline: keep what we have
        }
    }

    /// Every minute: report my study minutes in running challenges, and pay out finished ones
    func tick() async {
        guard let me = await client.userID else { return }
        await load()
        let now = Date()
        var settled = false
        for c in challenges where c.isOpen && joined(c, me: me) && c.started(now) && now <= c.ends_at.addingTimeInterval(Challenge.grace) {
            let minutes = Int(store.studyTime(in: DateInterval(start: c.starts_at, end: min(now, c.ends_at))) / 60)
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

    func create(group: UUID, title: String, minutes: Int, fee: Int, start: Date, end: Date) async -> Bool {
        struct Body: Encodable { let g: String; let title: String; let target_minutes: Int; let fee: Int; let starts_at: String; let ends_at: String }
        return await perform(cost: fee) {
            _ = try await self.client.rpc("create_challenge", Body(g: group.uuidString, title: title, target_minutes: minutes, fee: fee,
                                                                    starts_at: Self.iso(start), ends_at: Self.iso(end)))
        }
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

// MARK: - Views

/// Duration like "6h" or "1h 30m"
private func hm(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
}

/// Challenges of one study group: create, join, leave, cancel, live progress
struct GroupChallengesCard: View {
    let group: StudyGroup
    @Environment(ChallengeService.self) private var service
    @Environment(FriendsService.self) private var friends
    @Environment(AppStore.self) private var store
    @State private var creating = false
    @State private var confirmCancel: Challenge?

    var body: some View {
        let list = service.challenges(inGroup: group.id)
        Card(title: "Challenges", systemImage: "flag.checkered") {
            HStack {
                Text("Everyone pays the entry fee. All finish → fees doubled. Missed → that fee is shared by those who finished.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { creating = true } label: { Label("New Challenge", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            if list.isEmpty {
                Text("No challenges yet — start one!").font(.callout).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 30)) { tl in
                VStack(spacing: 10) {
                    ForEach(list) { c in row(c, now: tl.date) }
                }
            }
            if let e = service.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .sheet(isPresented: $creating) { NewChallengeSheet(group: group) }
        .confirmationDialog("Cancel “\(confirmCancel?.title ?? "")”?", isPresented: Binding(get: { confirmCancel != nil }, set: { if !$0 { confirmCancel = nil } })) {
            Button("Cancel Challenge", role: .destructive) { if let c = confirmCancel { Task { await service.cancel(c) } } }
        } message: { Text("Everyone gets their entry fee back.") }
    }

    private func row(_ c: Challenge, now: Date) -> some View {
        let me = friends.me?.id
        let mine = service.joined(c, me: me)
        let people = service.members(of: c).sorted { $0.minutes > $1.minutes }
        let state: (String, Color) = c.status == "cancelled" ? ("Cancelled", .gray)
            : c.status == "settled" ? ("Finished", .green)
            : !c.started(now) ? ("Starts \(c.starts_at.formatted(.relative(presentation: .named)))", .blue)
            : !c.ended(now) ? ("Live · ends \(c.ends_at.formatted(.relative(presentation: .named)))", .orange)
            : ("Paying out soon", .purple)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.title).font(.headline)
                Text(state.0).font(.caption.weight(.semibold)).foregroundStyle(state.1)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(state.1.opacity(0.15)))
                Spacer()
                Label("\(c.fee)", systemImage: "airplane").labelStyle(RocketLabel())
            }
            Text("Study \(hm(c.target_minutes)) between \(c.starts_at.formatted(date: .abbreviated, time: .shortened)) and \(c.ends_at.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(people, id: \.user_id) { m in
                let name = m.user_id == me ? "You" : (friends.people[m.user_id]?.profile.name ?? "Member")
                HStack(spacing: 8) {
                    Text(name).font(.callout).frame(width: 110, alignment: .leading).lineLimit(1)
                    ProgressView(value: min(1, Double(m.minutes) / Double(max(1, c.target_minutes))))
                        .tint(m.minutes >= c.target_minutes ? .green : .accentColor)
                    Text("\(hm(m.minutes)) / \(hm(c.target_minutes))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            if c.isOpen {
                HStack {
                    if !c.started(now) {
                        if mine {
                            if c.creator != me { Button("Leave (refund)") { Task { await service.leave(c) } } }
                        } else {
                            Button("Join for \(c.fee) 🚀") { Task { await service.join(c) } }.buttonStyle(.borderedProminent)
                        }
                    } else if !mine {
                        Text("Started — joining is closed").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.creator == me { Button("Cancel…", role: .destructive) { confirmCancel = c } }
                }
                .disabled(service.busy)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
    }
}

/// Shows the rocket icon in front of an amount
private struct RocketLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { RocketIcon(size: 15); configuration.title.font(.callout.weight(.bold).monospacedDigit()) }
    }
}

struct NewChallengeSheet: View {
    let group: StudyGroup
    @Environment(ChallengeService.self) private var service
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hours = 6.0
    @State private var fee = 50
    @State private var startMode = 0
    @State private var startDate = Date().addingTimeInterval(3600)
    @State private var lengthHours = 24.0

    private var start: Date {
        switch startMode {
        case 0: Date()
        case 1: Date().addingTimeInterval(3600)
        default: startDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("New challenge in \(group.name)", systemImage: "flag.checkered").font(.title3.weight(.bold))
            TextField("Name, e.g. Weekend sprint", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                Text("Study")
                Stepper("\(hm(Int(hours * 60)))", value: $hours, in: 0.5...72, step: 0.5)
                Text("within")
                Stepper("\(Int(lengthHours))h", value: $lengthHours, in: 1...168, step: 1)
            }
            Picker("Starts", selection: $startMode) {
                Text("Now").tag(0); Text("In 1 hour").tag(1); Text("At…").tag(2)
            }
            .pickerStyle(.segmented)
            if startMode == 2 {
                DatePicker("Start", selection: $startDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            }
            HStack {
                Text("Entry fee")
                TextField("", value: $fee, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
                RocketIcon(size: 16)
                Text("· you have \(store.rocketBalance)").font(.caption).foregroundStyle(.secondary)
            }
            Text("You join too and pay the fee. Others can join or leave for a refund until it starts. Only you can cancel it (everyone is refunded).")
                .font(.caption).foregroundStyle(.secondary)
            if let e = service.error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create & Pay \(fee) 🚀") {
                    Task {
                        let s = start
                        if await service.create(group: group.id, title: title.isEmpty ? "Challenge" : title, minutes: Int(hours * 60),
                                                fee: max(0, fee), start: s, end: s.addingTimeInterval(lengthHours * 3600)) { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(service.busy || fee < 0 || hours * 60 > lengthHours * 60)
            }
        }
        .padding(20).frame(width: 460)
        .onAppear { service.error = nil }
    }
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
