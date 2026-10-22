import Charts
import SwiftUI

/// Study together: see friends' study time, streaks and what they're studying right now.
struct FriendsView: View {
    @Environment(FriendsService.self) private var friends
    @Environment(TimerEngine.self) private var timer
    @Environment(AppStore.self) private var store

    @State private var name = ""
    @State private var code = ""
    @State private var added: String?
    @State private var copied = false
    @State private var confirmRemove: FriendCard?
    @State private var renaming = false
    @State private var confirmDelete = false
    @State private var viewingGalaxy: FriendCard?
    @State private var promising: FriendCard?
    @State private var expandedRow: UUID?
    /// 0 = friends, 1 = groups
    @AppStorage("friendsTab") private var tab = 0

    private var accent: Color { store.settings.template.style.accent }

    var body: some View {
        Group {
            if !SupabaseConfig.isConfigured {
                ContentUnavailableView {
                    Label("Friends isn't set up", systemImage: "person.2.slash")
                } description: {
                    Text("This build has no Supabase project. Create a free project at supabase.com, run supabase/schema.sql in its SQL editor, enable anonymous sign-ins, then copy Resources/Supabase.example.plist to Resources/Supabase.plist with your URL and publishable key and rebuild.")
                }
            } else if friends.isSetUp {
                main
            } else {
                onboarding
            }
        }
        .navigationTitle("Friends")
        .task {
            await friends.syncNow()
            while !Task.isCancelled {
                await friends.refresh()
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    // MARK: Onboarding

    private var onboarding: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(accent.gradient).frame(width: 96, height: 96)
                    .shadow(color: accent.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "person.2.fill").font(.system(size: 40)).foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text("Study together").font(.largeTitle.weight(.bold))
                Text("See how much your friends study, their streaks, and who's studying right now.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: 460)

            HStack {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(width: 240)
                    .onSubmit(create)
                Button(action: create) {
                    if friends.isLoading { ProgressView().controlSize(.small) } else { Text("Create My Profile") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || friends.isLoading)
            }

            if let error = friends.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            }

            privacyNote.frame(maxWidth: 460)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }

    private func create() {
        Task { await friends.createProfile(name: name) }
    }

    private var privacyNote: some View {
        Label {
            Text("Every Orbiter sees only your name, planet, level and hours this week. Friends and groups also see to-dos done, top subjects and what you're studying right now. Your schedule, tasks and notes stay on this Mac.")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Main

    private var main: some View {
        let mine = friends.myCard(timer: timer)
        let everyone = ([mine].compactMap { $0 } + friends.friends).sorted { $0.weekMinutes > $1.weekMinutes }
        let studying = friends.friends.filter { $0.studyingNow != nil }

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    myCodeCard
                    addFriendCard
                }

                if let error = friends.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.callout)
                }

                if !friends.incoming.isEmpty { FriendRequestsCard() }
                PromisesCard()

                Picker("", selection: $tab) {
                    Text("All Orbiters").tag(2)
                    Text("Friends (\(friends.friends.count))").tag(0)
                    Text("Groups (\(friends.groups.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 420)

                if tab == 2 {
                    AllOrbitersSection()
                } else if tab == 1 {
                    GroupsSection(mine: mine, accent: accent) { viewingGalaxy = $0 }
                } else {
                if !studying.isEmpty {
                    Card(title: "Studying right now", systemImage: "dot.radiowaves.left.and.right") {
                        ForEach(studying) { f in
                            HStack {
                                Avatar(name: f.profile.name, color: .green, size: 28)
                                Text(f.profile.name).font(.headline)
                                Text("is studying").foregroundStyle(.secondary)
                                Text(f.studyingNow ?? "").font(.headline).foregroundStyle(.green)
                                Spacer()
                                if let start = f.live?.started_at {
                                    Text("for " + Fmt.duration(Date().timeIntervalSince(start)))
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }

                Card(title: "This week's leaderboard", systemImage: "trophy") {
                    if friends.friends.isEmpty {
                        Text("Add a friend with their code to start comparing. Share yours: **\(friends.me?.friend_code ?? "")**")
                            .foregroundStyle(.secondary)
                    }
                    let top = max(1, everyone.map(\.weekMinutes).max() ?? 1)
                    ForEach(Array(everyone.enumerated()), id: \.element.id) { i, f in
                        HStack(alignment: .top, spacing: 8) {
                            LeaderboardRow(rank: i + 1, card: f, maxMinutes: top, accent: accent,
                                           expanded: expandedRow == f.id,
                                           onToggle: { withAnimation(.spring(duration: 0.3)) { expandedRow = expandedRow == f.id ? nil : f.id } },
                                           onOpenGalaxy: { viewingGalaxy = f })
                            if !f.isMe {
                                Button { promising = f } label: { Image(systemName: "hand.raised.fingers.spread") }
                                    .buttonStyle(.borderless)
                                    .padding(.top, 10)
                                    .help("Promise \(f.profile.name) you'll study — with rockets at stake")
                            }
                        }
                        .contextMenu {
                            if !f.isMe {
                                Button("Make a Promise…") { promising = f }
                                Divider()
                                Button("Remove Friend", role: .destructive) { confirmRemove = f }
                            }
                        }
                        if f.id != everyone.last?.id { Divider() }
                    }
                }

                }

                HStack {
                    privacyNote
                    Spacer()
                    if let last = friends.lastSync {
                        Text("Synced \(Fmt.time(last))").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(24)
        }
        .toolbar {
            Menu {
                Button("Change Name…") { renaming = true }
                Divider()
                Button("Delete My Profile…", role: .destructive) { confirmDelete = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            Button {
                Task {
                    await friends.syncNow()
                    await friends.refresh()
                }
            } label: {
                if friends.isLoading { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            .help("Refresh friends")
        }
        .confirmationDialog("Remove \(confirmRemove?.profile.name ?? "")?",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let f = confirmRemove { Task { await friends.removeFriend(f.id) } }
                confirmRemove = nil
            }
        } message: {
            Text("You'll stop seeing each other's progress.")
        }
        .confirmationDialog("Delete your Friends profile?", isPresented: $confirmDelete) {
            Button("Delete Profile", role: .destructive) { Task { await friends.deleteProfile() } }
        } message: {
            Text("Your shared stats and friendships are removed from the server. Your schedule and tasks on this Mac are not affected.")
        }
        .sheet(isPresented: $renaming) { RenameSheet(current: friends.me?.name ?? "") }
        .sheet(item: $viewingGalaxy) { FriendGalaxySheet(card: $0) }
        .sheet(item: $promising) { PromiseSheet(friend: $0) }
    }

    private var myCodeCard: some View {
        HStack(spacing: 14) {
            Avatar(name: friends.me?.name ?? "?", color: accent, size: 56, planet: store.avatarPlanet)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(friends.me?.name ?? "").font(.title3.weight(.semibold))
                    Button { renaming = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).help("Change name")
                }
                Text("Your friend code").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(friends.me?.friend_code ?? "")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(friends.me?.friend_code ?? "", forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.3)))
    }

    private var addFriendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Add a friend", systemImage: "person.badge.plus").font(.headline)
            HStack {
                TextField("Friend's code, e.g. 4F9A2C", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(addFriend)
                Button("Add", action: addFriend)
                    .buttonStyle(.borderedProminent)
                    .disabled(code.trimmingCharacters(in: .whitespaces).count < 4 || friends.isLoading)
            }
            if let added {
                Label("You and \(added) are now friends 🎉", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            } else {
                Text("Ask your friend for their code from this page in their app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func addFriend() {
        let c = code
        Task {
            if let name = await friends.addFriend(code: c) {
                added = name
                code = ""
            } else {
                added = nil
            }
        }
    }
}

// MARK: - Pieces

struct Avatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 36
    var planet: String? = nil

    var body: some View {
        if let p = PlanetCatalog.planet(planet) {
            PlanetView(planet: p, size: size * 1.25)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.85)).frame(width: size, height: size))
                .clipShape(Circle().scale(1.25))
        } else {
            initial
        }
    }

    private var initial: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let card: FriendCard
    let maxMinutes: Int
    let accent: Color
    var expanded = false
    var onToggle: () -> Void = {}
    var onOpenGalaxy: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
                .help(expanded ? "Hide details" : "Show what \(card.isMe ? "you" : card.profile.name) studied")
            if expanded {
                StudyBreakdown(card: card, accent: accent, onOpenGalaxy: onOpenGalaxy)
                    .padding(.leading, 42)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
            Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "\(rank)")
                .font(rank <= 3 ? .title3 : .headline)
                .frame(width: 30)
            Avatar(name: card.profile.name, color: card.isMe ? accent : .gray, size: 34, planet: card.profile.avatar)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(card.profile.name + (card.isMe ? " (you)" : "")).font(.headline)
                    LevelBadge(level: card.profile.level ?? 1)
                    if card.studyingNow != nil {
                        Circle().fill(.green).frame(width: 7, height: 7).help("Studying now")
                    }
                    Spacer()
                    if card.streak > 0 { StreakBadge(days: card.streak).help("Day streak") }
                    if let rockets = card.profile.rockets {
                        HStack(spacing: 3) {
                            RocketIcon(size: 15)
                            Text(rockets.formatted()).font(.callout.monospacedDigit())
                        }
                        .help("Rockets")
                    }
                    Text(Fmt.duration(TimeInterval(card.weekMinutes * 60)))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                GeometryReader { geo in
                    Capsule().fill(Color.primary.opacity(0.07))
                        .overlay(alignment: .leading) {
                            Capsule().fill((card.isMe ? accent : Color.gray).gradient)
                                .frame(width: geo.size.width * Double(card.weekMinutes) / Double(maxMinutes))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FriendDetailCard: View {
    let card: FriendCard
    let accent: Color
    var onOpenGalaxy: (() -> Void)?
    var onPromise: (() -> Void)? = nil

    private struct Bar: Identifiable {
        let id: Int
        let label: String
        let minutes: Int
        let isToday: Bool
    }

    var body: some View {
        let week = Cal.persian.days(in: Cal.persian.dateInterval(of: .weekOfYear, for: Date())!)
        let bars = week.enumerated().map { i, d in
            Bar(id: i, label: Cal.weekdayShort[i], minutes: card.minutes(on: d), isToday: Cal.persian.isDateInToday(d))
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Avatar(name: card.profile.name, color: accent, size: 44, planet: card.profile.avatar)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.profile.name).font(.headline)
                        LevelBadge(level: card.profile.level ?? 1)
                    }
                    if let now = card.studyingNow {
                        Label("Studying \(now)", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(.green).labelStyle(CompactLabelStyle())
                    } else {
                        Label { Text(card.streak > 0 ? "\(card.streak)-day streak" : "No streak yet") } icon: { StreakIcon(size: 13) }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let onPromise {
                    Button(action: onPromise) { Label("Promise", systemImage: "hand.raised.fingers.spread") }
                        .controlSize(.small)
                        .help("Promise \(card.profile.name) you'll study — with rockets at stake")
                }
                if let onOpenGalaxy {
                    Button(action: onOpenGalaxy) { Label("Galaxy", systemImage: "sparkles") }
                        .controlSize(.small)
                        .help("See \(card.profile.name)'s galaxy")
                }
            }

            HStack(spacing: 0) {
                stat(Fmt.duration(TimeInterval(card.todayMinutes * 60)), "Today")
                stat(Fmt.duration(TimeInterval(card.weekMinutes * 60)), "This week")
                stat(card.today.map { "\($0.todos_done)/\($0.todos_total)" } ?? "—", "To-dos today")
                stat(card.profile.rockets.map { "🚀 \($0.formatted())" } ?? "—", "Rockets")
            }

            Chart(bars) { b in
                BarMark(x: .value("Day", b.label), y: .value("Minutes", b.minutes))
                    .foregroundStyle(b.isToday ? accent : accent.opacity(0.45))
                    .cornerRadius(3)
            }
            .chartYAxis(.hidden)
            .frame(height: 70)

            if !card.weekSubjects.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.weekSubjects.prefix(3), id: \.name) { s in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: s.color)).frame(width: 7, height: 7)
                            Text(s.name).lineLimit(1)
                            Text(Fmt.shortDuration(TimeInterval(s.minutes * 60))).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RenameSheet: View {
    let current: String
    @Environment(FriendsService.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your name").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 280)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { await friends.rename(name); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear { name = current }
    }
}

/// A friend's (or my) galaxy in a sheet: map first, click a system to fly in
struct FriendGalaxySheet: View {
    let card: FriendCard
    @Environment(\.dismiss) private var dismiss
    @State private var focused: UUID?

    var body: some View {
        let data = card.profile.galaxy ?? GalaxyData(systems: [])
        let system = focused.flatMap { id in data.systems.first { $0.id == id } }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Avatar(name: card.profile.name, color: .gray, size: 44, planet: card.profile.avatar)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(card.isMe ? "Your galaxy" : "\(card.profile.name)'s galaxy").font(.title2.weight(.bold))
                        LevelBadge(level: card.profile.level ?? 1)
                    }
                    Text("\(data.systems.count) solar system\(data.systems.count == 1 ? "" : "s") · \(data.systems.reduce(0) { $0 + $1.planets.count }) planets · ⚡️ \(card.streak)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if system != nil {
                    Button { focused = nil } label: { Label("Galaxy", systemImage: "chevron.left") }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .zIndex(1)

            ZStack {
                if data.systems.allSatisfy({ $0.planets.isEmpty }) {
                    ZStack {
                        StarsBackground()
                        Text("No planets yet — \(card.isMe ? "study" : "they need to study") an hour to add one ✨")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    GalaxyMapView(data: data, zoom: 0.5, focused: focused, onSelect: { id in focused = id })
                        .overlay(alignment: .topLeading) {
                            if let system {
                                Text("\(system.name) · \(system.sun.name)").font(.headline).foregroundStyle(.white).padding(14)
                            }
                        }
                }
            }
            .frame(width: 900, height: 560)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding([.horizontal, .bottom], 16)
        }
        // A fixed size stops the sheet window from re-measuring itself on every animation frame
        .frame(width: 932, height: 668)
        .fixedSize()
    }
}

/// Everything someone studied: this week by subject, today by subject, and day by day
struct StudyBreakdown: View {
    let card: FriendCard
    let accent: Color
    var onOpenGalaxy: () -> Void

    var body: some View {
        let week = card.weekSubjects
        let weekTotal = max(1, week.reduce(0) { $0 + $1.minutes })
        let today = card.today?.subjects.sorted { $0.minutes > $1.minutes } ?? []
        let days = Cal.persian.days(in: Cal.persian.dateInterval(of: .weekOfYear, for: Date())!)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This week").font(.subheadline.weight(.semibold))
                    if week.isEmpty {
                        Text("Nothing logged yet this week.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(week, id: \.name) { s in
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: s.color)).frame(width: 9, height: 9)
                            Text(s.name).lineLimit(1).frame(width: 150, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(Color.primary.opacity(0.06))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color(hex: s.color).gradient)
                                            .frame(width: geo.size.width * Double(s.minutes) / Double(weekTotal))
                                    }
                            }
                            .frame(height: 6)
                            Text(Fmt.duration(TimeInterval(s.minutes * 60)))
                                .font(.callout.monospacedDigit()).frame(width: 70, alignment: .trailing)
                            Text("\(Int((Double(s.minutes) / Double(weekTotal) * 100).rounded()))%")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today").font(.subheadline.weight(.semibold))
                    if today.isEmpty {
                        Text("Nothing yet today.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(today, id: \.name) { s in
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: s.color)).frame(width: 8, height: 8)
                            Text(s.name).lineLimit(1)
                            Spacer()
                            Text(Fmt.duration(TimeInterval(s.minutes * 60))).font(.callout.monospacedDigit())
                        }
                    }
                    if let t = card.today, t.todos_total > 0 {
                        Label("\(t.todos_done)/\(t.todos_total) to-dos done", systemImage: "checklist")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let now = card.studyingNow {
                        Label("Studying \(now) now", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(.green).labelStyle(CompactLabelStyle())
                    }
                }
                .frame(width: 220)
            }

            // day by day
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let m = card.minutes(on: d)
                    let isToday = Cal.persian.isDateInToday(d)
                    VStack(spacing: 3) {
                        Text(Cal.weekdayShort[Cal.weekdayIndex(d)]).font(.caption2).foregroundStyle(.secondary)
                        Text(m > 0 ? Fmt.shortDuration(TimeInterval(m * 60)) : "—")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(isToday ? accent.opacity(0.15) : Color.primary.opacity(m > 0 ? 0.06 : 0.02)))
                    .help((card.stats[Cal.dayKey(d)]?.subjects ?? []).map { "\($0.name) \(Fmt.duration(TimeInterval($0.minutes * 60)))" }
                        .joined(separator: ", "))
                }
                Button(action: onOpenGalaxy) { Label("Galaxy", systemImage: "sparkles") }
                    .controlSize(.small)
                    .padding(.leading, 6)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}


/// Every Orbit member's study time this week. Only names, planets, levels and hours —
/// what someone studies stays private until you're friends.
private struct AllOrbitersSection: View {
    @Environment(FriendsService.self) private var friends
    @Environment(AppStore.self) private var store

    var body: some View {
        let list = friends.orbiters
        let top = max(1, list.first?.minutes ?? 1)
        let me = friends.me?.id
        Card(title: "All Orbiters · this week", systemImage: "globe.americas.fill") {
            Text("Everyone using Orbit, ranked by study time this week. You see hours only — add someone as a friend to see what they study.")
                .font(.caption).foregroundStyle(.secondary)
            if list.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, o in
                HStack(spacing: 12) {
                    Text(i < 3 ? ["🥇", "🥈", "🥉"][i] : "\(i + 1)")
                        .font(i < 3 ? .title3 : .callout.weight(.bold).monospacedDigit())
                        .frame(width: 30)
                    Avatar(name: o.name, color: .accentColor, size: 34, planet: o.avatar)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(o.id == me ? "\(o.name) (you)" : o.name).font(.headline).lineLimit(1)
                            if let lv = o.level {
                                Text("LV \(lv)").font(.caption2.weight(.heavy))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            }
                        }
                        ProgressView(value: Double(o.minutes), total: Double(top))
                            .tint(o.id == me ? .orange : .accentColor)
                    }
                    Text(o.minutes > 0 ? Fmt.duration(TimeInterval(o.minutes * 60)) : "—")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .frame(width: 70, alignment: .trailing)
                    friendButton(o.id, me: me).frame(width: 130, alignment: .trailing)
                }
                .padding(.vertical, 4)
                if i < list.count - 1 { Divider() }
            }
        }
        .task { await friends.loadOrbiters() }
    }

    @ViewBuilder
    private func friendButton(_ id: UUID, me: UUID?) -> some View {
        if id == me {
            EmptyView()
        } else if friends.isFriend(id) {
            Label("Friend", systemImage: "person.fill.checkmark").font(.caption).foregroundStyle(.green)
        } else if friends.incoming.contains(id) {
            HStack(spacing: 4) {
                Button("Accept") { Task { await friends.respond(to: id, accept: true) } }.buttonStyle(.borderedProminent)
                Button("Decline") { Task { await friends.respond(to: id, accept: false) } }
            }
            .controlSize(.small)
        } else if friends.outgoing.contains(id) {
            Button("Requested ✕") { Task { await friends.cancelRequest(to: id) } }
                .controlSize(.small).help("Cancel the request")
        } else {
            Button { Task { await friends.sendRequest(to: id) } } label: { Label("Add Friend", systemImage: "person.badge.plus") }
                .controlSize(.small)
        }
    }
}
