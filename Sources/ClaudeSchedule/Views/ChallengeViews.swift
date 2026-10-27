import SwiftUI

// MARK: - Small helpers shared by the challenge screens

extension ChallengeService {
    func displayName(_ id: UUID, me: UUID?, friends: FriendsService) -> String {
        if id == me { return "You" }
        return friends.people[id]?.profile.name ?? people[id]?.name ?? "Member"
    }
    func planet(_ id: UUID, friends: FriendsService) -> String? {
        people[id]?.avatar ?? friends.people[id]?.profile.avatar
    }
}

/// "Starts in 3 hours", "Live · ends tomorrow" … and its colour
func challengeState(_ c: Challenge, now: Date = Date()) -> (text: String, color: Color, symbol: String) {
    if c.status == "cancelled" { return ("Cancelled", .gray, "xmark.circle.fill") }
    if c.status == "settled" { return ("Finished", .green, "checkmark.seal.fill") }
    if !c.started(now) { return ("Starts \(c.starts_at.formatted(.relative(presentation: .named)))", .blue, "calendar.badge.clock") }
    if !c.ended(now) { return ("Live · ends \(c.ends_at.formatted(.relative(presentation: .named)))", .orange, "flame.fill") }
    return ("Paying out soon", .purple, "hourglass")
}

struct StatePill: View {
    let text: String
    let color: Color
    var symbol: String?
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct TypePill: View {
    let type: ChallengeType
    var onDark = false
    var body: some View {
        Label(type.title, systemImage: type.icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(onDark ? Color.white : type.tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(onDark ? Color.white.opacity(0.22) : type.tint.opacity(0.15)))
    }
}

/// Overlapping planets of the people in a challenge
struct AvatarStack: View {
    @Environment(ChallengeService.self) private var service
    @Environment(FriendsService.self) private var friends
    let ids: [UUID]
    var size: CGFloat = 28
    var limit = 5

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(ids.prefix(limit).enumerated()), id: \.element) { i, id in
                Avatar(name: service.displayName(id, me: friends.me?.id, friends: friends), color: .accentColor, size: size,
                       planet: service.planet(id, friends: friends))
                    .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                    .zIndex(Double(limit - i))
            }
            if ids.count > limit {
                Text("+\(ids.count - limit)").font(.caption2.weight(.bold))
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.primary.opacity(0.12)))
                    .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
            }
        }
    }
}

private func fact(_ icon: String, _ value: String, _ label: String, tint: Color = .secondary) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        Label(value, systemImage: icon).font(.callout.weight(.semibold)).labelStyle(.titleAndIcon)
        Text(label).font(.caption2).foregroundStyle(tint)
    }
}

// MARK: - The Challenges page

struct ChallengesPage: View {
    @Environment(ChallengeService.self) private var service
    @Environment(FriendsService.self) private var friends
    @Environment(Router.self) private var router
    @State private var creating = false
    @State private var filter: Filter = .all
    @State private var code = ""
    @State private var codeNote: String?
    @State private var selected: UUID?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", mine = "Joined", `public` = "Public", group = "Groups", `private` = "Private"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let id = selected, let c = service.challenges.first(where: { $0.id == id }) {
                ChallengeDetailView(challenge: c, backTitle: "Challenges") { selected = nil }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list
            }
        }
        .animation(.spring(duration: 0.35), value: selected)
        .navigationTitle("Challenges")
        .task { await service.load() }
        .onAppear(perform: takeRequestedChallenge)
        .onChange(of: router.openChallenge) { _, _ in takeRequestedChallenge() }
        .sheet(isPresented: $creating) {
            NewChallengeSheet { id in selected = id }
        }
    }

    private func takeRequestedChallenge() {
        if let id = router.openChallenge { selected = id; router.openChallenge = nil }
    }

    private func matches(_ c: Challenge) -> Bool {
        let me = friends.me?.id
        switch filter {
        case .all: return true
        case .mine: return service.joined(c, me: me)
        case .public: return c.type == .public
        case .group: return c.type == .group
        case .private: return c.type == .private
        }
    }

    private var list: some View {
        let all = service.all.filter(matches)
        return TimelineView(.periodic(from: .now, by: 30)) { tl in
            let now = tl.date
            let live = all.filter { $0.isLive(now) }
            let upcoming = all.filter { $0.isOpen && !$0.started(now) }
            let done = all.filter { !$0.isOpen || $0.ended(now) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    HStack(spacing: 12) { codeField; Spacer(minLength: 0) }
                    filterBar
                    if all.isEmpty {
                        emptyState
                    }
                    section("Live now", "flame.fill", .orange, live, now)
                    section("Starting soon", "calendar.badge.clock", .blue, upcoming, now)
                    section("Finished", "checkmark.seal.fill", .green, done, now)
                    if let e = service.error { Text(e).font(.caption).foregroundStyle(.red) }
                }
                .padding(24)
            }
        }
    }

    // MARK: Pieces

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#F97316"), Color(hex: "#EC4899")], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: Color(hex: "#F97316").opacity(0.45), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Challenges").font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("Bet rockets on your own focus. Everyone pays the entry fee; finish the hours and you win it back, and more.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    rule("clock", "\(ChallengeRules.minHours)h+ of study")
                    rule("person.2", "\(ChallengeRules.minPeople)+ people, or everyone is refunded")
                    rule("gift", "all finish → fee back + bonus up to 100 🚀/h")
                    rule("lock.open", "join any time until the end")
                }
            }
            Spacer(minLength: 12)
            Button { creating = true } label: { Label("New Challenge", systemImage: "plus").font(.headline).padding(.horizontal, 6) }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Color(hex: "#F97316"))
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#F97316").opacity(0.20), Color(hex: "#EC4899").opacity(0.14), Color(hex: "#8B5CF6").opacity(0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private var codeField: some View {
        HStack(spacing: 8) {
            Image(systemName: "ticket.fill").foregroundStyle(ChallengeType.private.tint)
            TextField("Have an invite code?", text: $code)
                .textFieldStyle(.plain).font(.system(.callout, design: .monospaced))
                .frame(width: 170)
                .onSubmit(joinWithCode)
            Button("Join", action: joinWithCode)
                .controlSize(.small).buttonStyle(.borderedProminent).tint(ChallengeType.private.tint)
                .disabled(code.trimmingCharacters(in: .whitespaces).count < 4 || service.busy)
            if let codeNote { Text(codeNote).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func joinWithCode() {
        let c = code
        Task {
            if let id = await service.join(code: c) { code = ""; codeNote = nil; selected = id }
            else { codeNote = service.error }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { f in
                let on = filter == f
                Button { withAnimation(.spring(duration: 0.25)) { filter = f } } label: {
                    Text(f.rawValue).font(.callout.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(Capsule().fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07))))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.checkered").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text(filter == .all ? "No challenges yet" : "Nothing here").font(.headline)
            Text("Start one with New Challenge — public for everyone, private with an invite code, or just for a group.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    private func section(_ title: String, _ icon: String, _ tint: Color, _ list: [Challenge], _ now: Date) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("\(title) · \(list.count)", systemImage: icon).font(.headline).foregroundStyle(tint)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(list) { c in ChallengeCard(challenge: c, now: now) { selected = c.id } }
                }
            }
        }
    }
}

// MARK: - A challenge card

struct ChallengeCard: View {
    let challenge: Challenge
    var now: Date = Date()
    var onOpen: () -> Void
    @Environment(ChallengeService.self) private var service
    @Environment(FriendsService.self) private var friends

    var body: some View {
        let c = challenge
        let me = friends.me?.id
        let people = service.members(of: c).sorted { $0.minutes > $1.minutes }
        let mine = people.first { $0.user_id == me }
        let state = challengeState(c, now: now)
        let canJoin = service.canJoin(c, me: me, now: now, myGroups: Set(friends.groups.map(\.id)))
        let groupName = c.group_id.flatMap { g in friends.groups.first { $0.id == g }?.name }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TypePill(type: c.type)
                if let groupName { Text(groupName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                StatePill(text: state.text, color: state.color)
            }
            Text(c.title).font(.title3.weight(.bold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 18) {
                fact("clock.fill", hm(c.target_minutes), "goal")
                fact("ticket.fill", "\(c.fee) 🚀", "entry")
                fact("gift.fill", "+\(ChallengeRules.bonus(fee: c.fee, minutes: c.target_minutes)) 🚀", "if all finish")
            }
            HStack(spacing: 10) {
                AvatarStack(ids: people.map(\.user_id))
                Text("\(people.count) joined").font(.caption).foregroundStyle(.secondary)
                if people.count < ChallengeRules.minPeople && c.isOpen {
                    Text("· needs \(ChallengeRules.minPeople)").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
            }
            if let mine {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Your progress").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(hm(mine.minutes)) / \(hm(c.target_minutes))").font(.caption.monospacedDigit().weight(.semibold))
                    }
                    ProgressView(value: min(1, Double(mine.minutes) / Double(max(1, c.target_minutes))))
                        .tint(mine.minutes >= c.target_minutes ? .green : c.type.tint)
                }
            } else if canJoin {
                Button { Task { await service.join(c) } } label: {
                    Label("Join for \(c.fee) 🚀", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(c.type.tint).disabled(service.busy)
            }
        }
        .padding(16)
        .background(
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(c.type.tint.opacity(0.07))
                Rectangle().fill(c.type.gradient).frame(height: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.type.tint.opacity(0.28)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture(perform: onOpen)
    }
}

// MARK: - One challenge: who's in and how much they studied

struct ChallengeDetailView: View {
    let challenge: Challenge
    var backTitle = "Challenges"
    var onBack: () -> Void
    @Environment(ChallengeService.self) private var service
    @Environment(FriendsService.self) private var friends
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @State private var confirmCancel = false
    @State private var copied = false
    @State private var showing: ProfileTarget?

    var body: some View {
        let c = challenge
        let me = friends.me?.id
        let people = service.members(of: c).sorted { $0.minutes > $1.minutes }
        let mine = people.first { $0.user_id == me }
        let finished = people.filter { $0.minutes >= c.target_minutes }.count
        let bonus = ChallengeRules.bonus(fee: c.fee, minutes: c.target_minutes)
        let myGroups = Set(friends.groups.map(\.id))
        let groupName = c.group_id.flatMap { g in friends.groups.first { $0.id == g }?.name }

        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            let state = challengeState(c, now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button(action: onBack) { Label(backTitle, systemImage: "chevron.left") }
                        .buttonStyle(.borderless).controlSize(.large)

                    // hero
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            TypePill(type: c.type, onDark: true)
                            if let groupName { Text(groupName).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.9)) }
                            Spacer()
                            StatePill(text: state.text, color: .white, symbol: state.symbol)
                        }
                        Text(c.title).font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text("by \(service.displayName(c.creator, me: me, friends: friends))")
                            Text("·")
                            Text("\(c.starts_at.formatted(date: .abbreviated, time: .shortened)) → \(c.ends_at.formatted(date: .abbreviated, time: .shortened))")
                        }
                        .font(.callout).foregroundStyle(.white.opacity(0.85))
                        if c.type == .private, let code = c.invite_code, mine != nil {
                            HStack(spacing: 10) {
                                Image(systemName: "ticket.fill")
                                Text("Invite code").font(.caption.weight(.semibold)).opacity(0.85)
                                Text(code).font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(3)
                                Button(copied ? "Copied" : "Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(code, forType: .string)
                                    copied = true
                                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                                }
                                .controlSize(.small)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.22)))
                        }
                        countdown(c, now: now)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(c.type.gradient))
                    .shadow(color: c.type.tint.opacity(0.35), radius: 18, y: 8)

                    // numbers
                    HStack(spacing: 14) {
                        StatTile(title: "Goal", value: hm(c.target_minutes), subtitle: "of study", systemImage: "clock.fill", tint: .blue)
                        StatTile(title: "Entry fee", value: "\(c.fee) 🚀", subtitle: "pot now \(people.count * c.fee) 🚀", systemImage: "ticket.fill", tint: .orange)
                        StatTile(title: "If all finish", value: "+\(bonus) 🚀", subtitle: "each, on top of the fee", systemImage: "gift.fill", tint: .pink)
                        StatTile(title: "Finished", value: "\(finished) / \(people.count)", subtitle: "reached the goal", systemImage: "checkmark.seal.fill", tint: .green)
                    }

                    // actions
                    actions(c, me: me, mine: mine, myGroups: myGroups, now: now)

                    // people
                    Card(title: "Participants · \(people.count)", systemImage: "person.3.fill") {
                        if people.count < ChallengeRules.minPeople && c.isOpen {
                            Label("Needs at least \(ChallengeRules.minPeople) people by the end — otherwise everyone is refunded.", systemImage: "person.badge.clock")
                                .font(.callout).foregroundStyle(.orange)
                        }
                        ForEach(Array(people.enumerated()), id: \.element.user_id) { i, m in
                            participantRow(i, m, c: c, me: me)
                            if i < people.count - 1 { Divider() }
                        }
                    }

                    // how it pays
                    Card(title: "How it pays out", systemImage: "info.circle") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• Everyone pays the \(c.fee) 🚀 entry fee. Only study timed with the timer counts (manual logs don't).")
                            Text("• Everyone finishes → each gets the fee back plus \(bonus) 🚀.")
                            Text("• Some miss → their fees are shared by those who finished (who also get their own fee back).")
                            Text("• Joining stays open until the end; someone who joins late only counts study from the moment they joined.")
                            Text("• Fewer than \(ChallengeRules.minPeople) people at the end → everyone is refunded.")
                        }
                        .font(.callout).foregroundStyle(.secondary)
                    }
                    if let e = service.error { Text(e).font(.caption).foregroundStyle(.red) }
                }
                .padding(24)
            }
        }
        .sheet(item: $showing) { OrbiterProfileSheet(userID: $0.id) }
        .confirmationDialog("Cancel “\(c.title)”?", isPresented: $confirmCancel) {
            Button("Cancel Challenge", role: .destructive) { Task { await service.cancel(c); onBack() } }
        } message: { Text("Everyone gets their entry fee back.") }
    }

    private func countdown(_ c: Challenge, now: Date) -> some View {
        let target = !c.started(now) ? c.starts_at : c.ends_at
        let left = max(0, Int(target.timeIntervalSince(now)))
        let label = !c.started(now) ? "Starts in" : (!c.ended(now) ? "Ends in" : "Ended")
        return Group {
            if c.isOpen && !c.ended(now) {
                HStack(spacing: 8) {
                    Text(label).font(.callout).foregroundStyle(.white.opacity(0.85))
                    ForEach([(left / 86400, "d"), ((left % 86400) / 3600, "h"), ((left % 3600) / 60, "m"), (left % 60, "s")], id: \.1) { v, u in
                        Text("\(v)\(u)").font(.system(.callout, design: .monospaced).weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.22)))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ c: Challenge, me: UUID?, mine: ChallengeMember?, myGroups: Set<UUID>, now: Date) -> some View {
        HStack(spacing: 12) {
            if mine == nil {
                if service.canJoin(c, me: me, now: now, myGroups: myGroups) {
                    Button { Task { await service.join(c) } } label: {
                        Label(c.started(now) ? "Join now for \(c.fee) 🚀" : "Join for \(c.fee) 🚀", systemImage: "plus.circle.fill").font(.headline).padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(c.type.tint).disabled(service.busy)
                } else if c.isOpen && !c.ended(now) {
                    Label(c.type == .private ? "Private — ask the creator for the invite code" : "Only group members can join", systemImage: "lock.fill")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Label(c.creator == me ? "You made this challenge" : "You're in", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(.green)
                if c.isOpen && !c.started(now) && c.creator != me {
                    Button("Leave (refund)") { Task { await service.leave(c); onBack() } }.disabled(service.busy)
                }
            }
            Spacer()
            if c.creator == me && c.isOpen {
                Button("Cancel Challenge…", role: .destructive) { confirmCancel = true }.disabled(service.busy)
            }
        }
    }

    /// What someone studied during the challenge: me from my own sessions; friends and group-mates from the daily
    /// summaries they share with me (everyone else shares hours only)
    private func studied(_ m: ChallengeMember, c: Challenge, me: UUID?) -> [SubjectStat] {
        let from = max(c.starts_at, m.joined_at ?? c.starts_at), to = min(Date(), c.ends_at)
        guard to > from else { return [] }
        var totals: [String: SubjectStat] = [:]
        if m.user_id == me {
            for s in store.sessions(in: DateInterval(start: from, end: to)) where !s.isManual {
                let name = store.subject(of: s).name
                totals[name, default: SubjectStat(name: name, minutes: 0, color: store.subjectHex(of: s))].minutes += Int(s.duration / 60)
            }
        } else if let card = friends.people[m.user_id] {
            var day = Cal.persian.startOfDay(for: from)
            while day <= to {
                for s in card.stats[Cal.dayKey(day)]?.subjects ?? [] {
                    totals[s.name, default: SubjectStat(name: s.name, minutes: 0, color: s.color)].minutes += s.minutes
                }
                day = Cal.persian.date(byAdding: .day, value: 1, to: day) ?? to.addingTimeInterval(86400)
            }
        }
        return totals.values.filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }
    }

    private func participantRow(_ i: Int, _ m: ChallengeMember, c: Challenge, me: UUID?) -> some View {
        let name = service.displayName(m.user_id, me: me, friends: friends)
        let done = m.minutes >= c.target_minutes
        let late = (m.joined_at ?? c.starts_at) > c.starts_at.addingTimeInterval(300)
        let isMe = m.user_id == me
        let sees = isMe || friends.people[m.user_id] != nil
        let subjects = studied(m, c: c, me: me)
        let liveNow = isMe ? friends.myCard(timer: timer)?.studyingNow : friends.people[m.user_id]?.studyingNow
        return HStack(spacing: 12) {
            Text(i < 3 ? ["🥇", "🥈", "🥉"][i] : "\(i + 1)")
                .font(i < 3 ? .title3 : .callout.weight(.bold).monospacedDigit()).frame(width: 28)
            Button { if m.user_id != me { showing = ProfileTarget(id: m.user_id) } } label: {
                Avatar(name: name, color: .accentColor, size: 38, planet: service.planet(m.user_id, friends: friends))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(name).font(.headline).lineLimit(1)
                    if let lv = service.people[m.user_id]?.level ?? friends.people[m.user_id]?.profile.level { LevelBadge(level: lv) }
                    if m.user_id == c.creator { Text("creator").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                    if late { Text("joined later").font(.caption2).foregroundStyle(.tertiary) }
                }
                ProgressView(value: min(1, Double(m.minutes) / Double(max(1, c.target_minutes)))).tint(done ? .green : c.type.tint)
                // what they studied, and what they're studying right now
                HStack(spacing: 6) {
                    if let liveNow {
                        Label("Studying \(liveNow) now", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption2.weight(.bold)).foregroundStyle(.green)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                    ForEach(Array(subjects.prefix(3).enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: s.color)).frame(width: 7, height: 7)
                            Text("\(s.name) \(hm(s.minutes))").font(.caption2).lineLimit(1)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    if subjects.count > 3 { Text("+\(subjects.count - 3) more").font(.caption2).foregroundStyle(.secondary) }
                    if !sees {
                        Label("Hours only — add as a friend to see what they study", systemImage: "lock.fill")
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else if subjects.isEmpty && liveNow == nil {
                        Text("Nothing logged yet").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(hm(m.minutes)).font(.headline.monospacedDigit())
                Text(done ? "goal reached ✓" : "of \(hm(c.target_minutes))").font(.caption).foregroundStyle(done ? Color.green : Color.secondary)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Making a challenge

struct NewChallengeSheet: View {
    var presetType: ChallengeType = .public
    var presetGroup: UUID?
    var onCreated: (UUID) -> Void = { _ in }
    @Environment(ChallengeService.self) private var service
    @Environment(FriendsService.self) private var friends
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var type: ChallengeType = .public
    @State private var group: UUID?
    @State private var hours = ChallengeRules.minHours
    @State private var lengthHours = 24
    @State private var fee = ChallengeRules.minFee(hours: ChallengeRules.minHours)
    @State private var startMode = 0   // 0 now, 1 in an hour, 2 custom
    @State private var dayOffset = 0
    @State private var customTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()

    private var minFee: Int { ChallengeRules.minFee(hours: hours) }
    private var kind: CalendarKind { store.settings.primaryCalendar }

    private var customStart: Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: Date())) ?? Date()
        let t = cal.dateComponents([.hour, .minute], from: customTime)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }
    private var start: Date {
        switch startMode {
        case 0: Date()
        case 1: Date().addingTimeInterval(3600)
        default: max(customStart, Date())
        }
    }
    private var customInPast: Bool { startMode == 2 && customStart < Date().addingTimeInterval(-60) }

    private func dayLabel(_ i: Int) -> String {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: Date())) ?? Date()
        let main = i == 0 ? "Today" : (i == 1 ? "Tomorrow" : Fmt.date(d, "EEE d MMM", kind))
        return "\(main) · \(Fmt.date(d, "d MMM", kind.other))"
    }

    private var needsGroup: Bool { type == .group && group == nil }
    private var valid: Bool {
        !service.busy && fee >= minFee && fee <= store.rocketBalance && hours <= lengthHours && !needsGroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered").font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(type.gradient))
                VStack(alignment: .leading) {
                    Text("New challenge").font(.title2.weight(.bold))
                    Text(type.subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            TextField("Name, e.g. Weekend sprint", text: $title).textFieldStyle(.roundedBorder).controlSize(.large)

            // who can join
            HStack(spacing: 10) {
                ForEach(ChallengeType.allCases) { t in
                    let on = type == t
                    Button { withAnimation(.spring(duration: 0.25)) { type = t } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.icon).font(.title3)
                            Text(t.title).font(.callout.weight(.semibold))
                            Text(t.subtitle).font(.caption2).multilineTextAlignment(.center).opacity(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .padding(8)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(on ? AnyShapeStyle(t.gradient) : AnyShapeStyle(Color.primary.opacity(0.06))))
                    }
                    .buttonStyle(.plain)
                }
            }
            if type == .group {
                if friends.groups.isEmpty {
                    Label("You're not in any group yet — create or join one in Groups first.", systemImage: "person.3").font(.callout).foregroundStyle(.orange)
                } else {
                    Picker("Group", selection: $group) {
                        Text("Choose a group").tag(UUID?.none)
                        ForEach(friends.groups) { g in Text(g.name).tag(Optional(g.id)) }
                    }
                }
            } else if type == .private {
                Label("An invite code is made for it. Only people who have the code can join.", systemImage: "ticket.fill").font(.callout).foregroundStyle(.secondary)
            }

            Divider()
            HStack(spacing: 8) {
                Text("Study")
                HourField(value: $hours, range: ChallengeRules.minHours...168)
                Text("hours within")
                HourField(value: $lengthHours, range: max(ChallengeRules.minHours, hours)...720)
                Text("hours")
            }
            // when it starts
            VStack(alignment: .leading, spacing: 8) {
                Picker("Starts", selection: $startMode) {
                    Text("Now").tag(0); Text("In 1 hour").tag(1); Text("Pick a time…").tag(2)
                }
                .pickerStyle(.segmented)
                if startMode == 2 {
                    HStack(spacing: 10) {
                        Picker("Day", selection: $dayOffset) {
                            ForEach(0..<60, id: \.self) { i in Text(dayLabel(i)).tag(i) }
                        }
                        .labelsHidden().frame(width: 230)
                        DatePicker("", selection: $customTime, displayedComponents: .hourAndMinute).labelsHidden()
                        Spacer()
                        Text(start.formatted(date: .abbreviated, time: .shortened)).font(.callout.weight(.semibold)).foregroundStyle(type.tint)
                    }
                    if customInPast {
                        Text("That time has already passed — it will start right now.").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                Text("Entry fee")
                TextField("", value: $fee, format: .number).textFieldStyle(.roundedBorder).frame(width: 90)
                RocketIcon(size: 16)
                Text("· at least \(minFee) · you have \(store.rocketBalance)").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("• At least \(ChallengeRules.minHours) hours, and the fee is at least 50 🚀 per hour (\(hours)h → \(minFee) 🚀).")
                Text("• Anyone allowed can join any time until the end. Needs at least \(ChallengeRules.minPeople) people by the end — otherwise everyone gets their fee back.")
                Text("• Everyone finishes → fee back + \(ChallengeRules.bonus(fee: fee, minutes: hours * 60)) 🚀 bonus each (at most 100 🚀 per hour). Some miss → their fees go to those who finished.")
                Text("• Only you can cancel it — everyone is refunded.")
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if fee < minFee { Text("The entry fee must be at least \(minFee) 🚀 for \(hours) hours.").font(.caption).foregroundStyle(.orange) }
            if fee > store.rocketBalance { Text("You don't have enough rockets.").font(.caption).foregroundStyle(.orange) }
            if let e = service.error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create & Pay \(fee) 🚀") {
                    Task {
                        let s = start
                        if let id = await service.create(title: title.isEmpty ? "Challenge" : title, minutes: hours * 60, fee: fee, start: s,
                                                         end: s.addingTimeInterval(Double(lengthHours) * 3600), type: type,
                                                         group: type == .group ? group : nil) {
                            dismiss(); onCreated(id)
                        }
                    }
                }
                .buttonStyle(.borderedProminent).tint(type.tint).keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(22).frame(width: 600)
        .onAppear {
            service.error = nil
            type = presetType
            group = presetGroup ?? friends.groups.first?.id
        }
        .onChange(of: hours) { _, h in
            fee = max(fee, ChallengeRules.minFee(hours: h))
            lengthHours = max(lengthHours, h)
        }
    }
}

/// Whole hours: type a number or step one hour at a time
struct HourField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 56).multilineTextAlignment(.center)
            Stepper("", value: $value, in: range, step: 1).labelsHidden()
        }
    }
}
