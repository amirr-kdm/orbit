import SwiftUI

/// Study groups, in the sidebar: the groups I'm in, and one group's page with its members and its challenges
struct GroupsPage: View {
    @Environment(FriendsService.self) private var friends
    @Environment(ChallengeService.self) private var service
    @Environment(TimerEngine.self) private var timer
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var selected: UUID?
    @State private var newName = ""
    @State private var joinCode = ""
    @State private var note: String?
    @State private var viewingGalaxy: FriendCard?

    private var accent: Color { store.settings.template.style.accent }

    var body: some View {
        Group {
            if !SupabaseConfig.isConfigured {
                ContentUnavailableView("Groups need a server", systemImage: "person.3.slash",
                                       description: Text("This build has no Supabase project."))
            } else if !friends.isSetUp {
                ContentUnavailableView("Set up your profile first", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("Open Friends and create your profile — then come back to make or join a group."))
            } else if let id = selected, let g = friends.groups.first(where: { $0.id == id }) {
                GroupDetailView(group: g, accent: accent, onBack: { selected = nil }, openGalaxy: { viewingGalaxy = $0 })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list
            }
        }
        .animation(.spring(duration: 0.35), value: selected)
        .navigationTitle("Groups")
        .task {
            await friends.syncNow()
            while !Task.isCancelled {
                await friends.refresh()
                await service.load()
                try? await Task.sleep(for: .seconds(45))
            }
        }
        .onAppear(perform: takeRequestedGroup)
        .onChange(of: router.openGroup) { _, _ in takeRequestedGroup() }
        .sheet(item: $viewingGalaxy) { FriendGalaxySheet(card: $0) }
    }

    private func takeRequestedGroup() {
        if let id = router.openGroup { selected = id; router.openGroup = nil }
    }

    // MARK: The list

    private var list: some View {
        let mine = friends.myCard(timer: timer)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let prize = friends.groupPrize {
                    HStack {
                        Text(prize).font(.headline)
                        Spacer()
                        Button("Nice!") { friends.groupPrize = nil }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.18)))
                }
                // header
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "person.3.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ChallengeType.group.gradient))
                        .shadow(color: ChallengeType.group.tint.opacity(0.4), radius: 12, y: 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Groups").font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text("Study with your class or friends. See each other's hours, and run challenges just for the group.")
                            .font(.callout).foregroundStyle(.secondary)
                        Label("Each week, whoever studies the most in a group wins \(AppStore.groupWinRockets) rockets (paid after Friday).", systemImage: "trophy")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [ChallengeType.group.tint.opacity(0.2), Color(hex: "#EC4899").opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)))

                HStack(alignment: .top, spacing: 14) {
                    Card(title: "New group", systemImage: "person.3") {
                        HStack {
                            TextField("Group name, e.g. IELTS crew", text: $newName).textFieldStyle(.roundedBorder).onSubmit(create)
                            Button("Create", action: create).buttonStyle(.borderedProminent)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Text("You'll get a code to share. Everyone who joins sees each other's study time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "Join a group", systemImage: "rectangle.and.pencil.and.ellipsis") {
                        HStack {
                            TextField("Group code", text: $joinCode).textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced)).onSubmit(join)
                            Button("Join", action: join).buttonStyle(.borderedProminent)
                                .disabled(joinCode.trimmingCharacters(in: .whitespaces).count < 4)
                        }
                        Text(note ?? "Ask a friend for their group's code.")
                            .font(.caption).foregroundStyle(note == nil ? Color.secondary : accent)
                    }
                }

                if friends.groups.isEmpty {
                    ContentUnavailableView("No groups yet", systemImage: "person.3",
                                           description: Text("Create a group for your class or study buddies, or join one with a code."))
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Your groups · \(friends.groups.count)", systemImage: "person.3.fill").font(.headline).foregroundStyle(ChallengeType.group.tint)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                        ForEach(friends.groups) { g in
                            GroupCard(group: g, mine: mine) { selected = g.id }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func create() {
        let n = newName
        newName = ""
        Task { await friends.createGroup(name: n) }
    }

    private func join() {
        let c = joinCode
        Task {
            if let name = await friends.joinGroup(code: c) {
                joinCode = ""
                note = "You joined \(name) 🎉"
                if let g = friends.groups.first(where: { $0.name == name }) { selected = g.id }
            }
        }
    }
}

// MARK: - A group in the list

struct GroupCard: View {
    let group: StudyGroup
    let mine: FriendCard?
    var onOpen: () -> Void
    @Environment(FriendsService.self) private var friends
    @Environment(ChallengeService.self) private var service

    var body: some View {
        let myID = friends.me?.id
        let cards: [FriendCard] = group.members.compactMap { $0 == myID ? mine : friends.people[$0] }
        let totalMinutes = cards.reduce(0) { $0 + $1.weekMinutes }
        let studying = cards.filter { !$0.isMe && $0.studyingNow != nil }.count
        let live = service.challenges(inGroup: group.id).filter { $0.isLive() }.count
        let top = cards.max { $0.weekMinutes < $1.weekMinutes }

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name).font(.title3.weight(.bold)).lineLimit(1)
                    Text("\(group.members.count) member\(group.members.count == 1 ? "" : "s")\(group.owner == myID ? " · you created it" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                HStack(spacing: -9) {
                    ForEach(Array(cards.prefix(6).enumerated()), id: \.element.id) { i, f in
                        Avatar(name: f.profile.name, color: .purple, size: 30, planet: f.profile.avatar)
                            .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                            .zIndex(Double(6 - i))
                    }
                }
                if group.members.count > 6 { Text("+\(group.members.count - 6)").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
            }
            HStack(spacing: 16) {
                stat("clock.fill", Fmt.duration(TimeInterval(totalMinutes * 60)), "this week")
                if studying > 0 { stat("dot.radiowaves.left.and.right", "\(studying)", "studying now", tint: .green) }
                if live > 0 { stat("flame.fill", "\(live)", "live challenge\(live == 1 ? "" : "s")", tint: .orange) }
            }
            if let top, top.weekMinutes > 0 {
                Label("Leading: \(top.isMe ? "you" : top.profile.name)", systemImage: "trophy.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(18)
        .background(
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ChallengeType.group.tint.opacity(0.07))
                Rectangle().fill(ChallengeType.group.gradient).frame(height: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(ChallengeType.group.tint.opacity(0.28)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture(perform: onOpen)
    }

    private func stat(_ icon: String, _ value: String, _ label: String, tint: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(value, systemImage: icon).font(.callout.weight(.semibold)).foregroundStyle(tint == .secondary ? Color.primary : tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - One group

struct GroupDetailView: View {
    let group: StudyGroup
    let accent: Color
    var onBack: () -> Void
    var openGalaxy: (FriendCard) -> Void

    @Environment(FriendsService.self) private var friends
    @Environment(ChallengeService.self) private var service
    @Environment(TimerEngine.self) private var timer
    @State private var copied = false
    @State private var confirmLeave = false
    @State private var expanded: UUID?
    @State private var makingChallenge = false
    @State private var selectedChallenge: UUID?

    var body: some View {
        if let id = selectedChallenge, let c = service.challenges.first(where: { $0.id == id }) {
            ChallengeDetailView(challenge: c, backTitle: group.name) { selectedChallenge = nil }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            page
        }
    }

    private var page: some View {
        let g = group
        let myID = friends.me?.id
        let mine = friends.myCard(timer: timer)
        let cards: [FriendCard] = g.members.compactMap { id in id == myID ? mine : friends.people[id] }
            .sorted { $0.weekMinutes > $1.weekMinutes }
        let top = max(1, cards.map(\.weekMinutes).max() ?? 1)
        let studying = cards.filter { !$0.isMe && $0.studyingNow != nil }
        let challenges = service.challenges(inGroup: g.id).sorted { $0.starts_at > $1.starts_at }
        let now = Date()

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button(action: onBack) { Label("Groups", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).controlSize(.large)

                // header
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.name).font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            Text("\(g.members.count) member\(g.members.count == 1 ? "" : "s")\(g.owner == myID ? " · you created it" : "")")
                                .font(.callout).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("Code").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                                Text(g.code).font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(.white)
                                Button(copied ? "Copied" : "Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(g.code, forType: .string)
                                    copied = true
                                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                                }
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.22)))
                            Button("Leave group", role: .destructive) { confirmLeave = true }.controlSize(.small)
                        }
                    }
                    if !studying.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text(studying.map { "\($0.profile.name): \($0.studyingNow ?? "")" }.joined(separator: "   ·   "))
                                .lineLimit(2)
                        }
                        .font(.callout.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.45)))
                    }
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ChallengeType.group.gradient))
                .shadow(color: ChallengeType.group.tint.opacity(0.35), radius: 18, y: 8)

                // challenges of the group
                HStack {
                    Label("Group challenges · \(challenges.count)", systemImage: "flag.checkered").font(.headline)
                    Spacer()
                    Button { makingChallenge = true } label: { Label("New group challenge", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(ChallengeType.group.tint)
                }
                if challenges.isEmpty {
                    Text("No challenges for this group yet. Start one — only members of \(g.name) can join it.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(22)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                        ForEach(challenges) { c in ChallengeCard(challenge: c, now: now) { selectedChallenge = c.id } }
                    }
                }

                // members
                Card(title: "This week in \(g.name)", systemImage: "trophy") {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, f in
                        HStack(alignment: .top, spacing: 8) {
                            LeaderboardRow(rank: i + 1, card: f, maxMinutes: top, accent: accent,
                                           expanded: expanded == f.id,
                                           onToggle: { withAnimation(.spring(duration: 0.3)) { expanded = expanded == f.id ? nil : f.id } },
                                           onOpenGalaxy: { openGalaxy(f) })
                            if !f.isMe { friendButton(f.id) }
                        }
                        if f.id != cards.last?.id { Divider() }
                    }
                }
                if let e = service.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .padding(24)
        }
        .sheet(isPresented: $makingChallenge) {
            NewChallengeSheet(presetType: .group, presetGroup: g.id) { id in selectedChallenge = id }
        }
        .confirmationDialog("Leave \(g.name)?", isPresented: $confirmLeave) {
            Button("Leave Group", role: .destructive) { Task { await friends.leaveGroup(g.id); onBack() } }
        } message: {
            Text("You can join again later with the code. Friends you made stay your friends.")
        }
    }

    /// Friend status of a group member, with the right action
    @ViewBuilder
    private func friendButton(_ id: UUID) -> some View {
        if friends.isFriend(id) {
            Label("Friend", systemImage: "person.fill.checkmark").font(.caption).foregroundStyle(.green)
                .frame(width: 120, alignment: .trailing)
        } else if friends.incoming.contains(id) {
            HStack(spacing: 4) {
                Button("Accept") { Task { await friends.respond(to: id, accept: true) } }.buttonStyle(.borderedProminent)
                Button("Decline") { Task { await friends.respond(to: id, accept: false) } }
            }
            .controlSize(.small)
        } else if friends.outgoing.contains(id) {
            Button("Requested ✕") { Task { await friends.cancelRequest(to: id) } }
                .controlSize(.small)
                .help("Cancel the request")
                .frame(width: 120, alignment: .trailing)
        } else {
            Button {
                Task { await friends.sendRequest(to: id) }
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
            }
            .controlSize(.small)
            .frame(width: 120, alignment: .trailing)
        }
    }
}

/// People who asked to be your friend
struct FriendRequestsCard: View {
    @Environment(FriendsService.self) private var friends

    var body: some View {
        Card(title: "Friend requests", systemImage: "person.crop.circle.badge.questionmark") {
            ForEach(friends.incoming, id: \.self) { id in
                let card = friends.people[id]
                HStack(spacing: 10) {
                    Avatar(name: card?.profile.name ?? "?", color: .orange, size: 30, planet: card?.profile.avatar)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card?.profile.name ?? "Someone").font(.headline)
                        if let g = friends.groups.first(where: { $0.members.contains(id) }) {
                            Text("From your group \(g.name)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Accept") { Task { await friends.respond(to: id, accept: true) } }.buttonStyle(.borderedProminent)
                    Button("Decline") { Task { await friends.respond(to: id, accept: false) } }
                }
            }
        }
    }
}
