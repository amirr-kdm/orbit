import SwiftUI

/// Study groups: create one, share its code, see everyone's progress, and send friend requests
struct GroupsSection: View {
    @Environment(FriendsService.self) private var friends
    let mine: FriendCard?
    let accent: Color
    var openGalaxy: (FriendCard) -> Void

    @AppStorage("selectedGroup") private var selectedRaw = ""
    @State private var newName = ""
    @State private var joinCode = ""
    @State private var note: String?
    @State private var copied = false
    @State private var confirmLeave: StudyGroup?
    @State private var expanded: UUID?

    private var selected: StudyGroup? {
        friends.groups.first { $0.id.uuidString == selectedRaw } ?? friends.groups.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let prize = friends.groupPrize {
                HStack {
                    Text(prize).font(.headline)
                    Spacer()
                    Button("Nice!") { friends.groupPrize = nil }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.18)))
            }
            Label("Each week, whoever studies the most in a group wins \(AppStore.groupWinRockets) rockets (paid after Friday).",
                  systemImage: "trophy")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 14) {
                Card(title: "New group", systemImage: "person.3") {
                    HStack {
                        TextField("Group name, e.g. IELTS crew", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(create)
                        Button("Create", action: create)
                            .buttonStyle(.borderedProminent)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("You'll get a code to share. Everyone who joins sees each other's study time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Card(title: "Join a group", systemImage: "rectangle.and.pencil.and.ellipsis") {
                    HStack {
                        TextField("Group code", text: $joinCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit(join)
                        Button("Join", action: join)
                            .buttonStyle(.borderedProminent)
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
                // Group chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(friends.groups) { g in
                            let on = g.id == selected?.id
                            Button { selectedRaw = g.id.uuidString } label: {
                                Label("\(g.name) · \(g.members.count)", systemImage: "person.3.fill")
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(on ? AnyShapeStyle(accent.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.5))))
                                    .foregroundStyle(on ? accent : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let g = selected { groupPanel(g) }
            }
        }
        .confirmationDialog("Leave \(confirmLeave?.name ?? "")?", isPresented: Binding(get: { confirmLeave != nil }, set: { if !$0 { confirmLeave = nil } })) {
            Button("Leave Group", role: .destructive) {
                if let g = confirmLeave { Task { await friends.leaveGroup(g.id) } }
                confirmLeave = nil
            }
        } message: {
            Text("You can join again later with the code. Friends you made stay your friends.")
        }
    }

    // MARK: One group

    private func groupPanel(_ g: StudyGroup) -> some View {
        let myID = friends.me?.id
        let cards: [FriendCard] = g.members.compactMap { id in id == myID ? mine : friends.people[id] }
            .sorted { $0.weekMinutes > $1.weekMinutes }
        let top = max(1, cards.map(\.weekMinutes).max() ?? 1)
        let studying = cards.filter { !$0.isMe && $0.studyingNow != nil }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.name).font(.title2.weight(.bold))
                    Text("\(g.members.count) member\(g.members.count == 1 ? "" : "s")\(g.owner == myID ? " · you created it" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(g.code).font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(3)
                Button(copied ? "Copied" : "Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(g.code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                Button("Leave", role: .destructive) { confirmLeave = g }
            }

            if !studying.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green)
                    ForEach(studying) { f in
                        Text("\(f.profile.name): \(f.studyingNow ?? "")").font(.callout.weight(.medium))
                    }
                }
            }

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
                if let g = friends.groups.first(where: { $0.name == name }) { selectedRaw = g.id.uuidString }
            }
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
