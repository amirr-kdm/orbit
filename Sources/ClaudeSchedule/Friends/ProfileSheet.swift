import SwiftUI

/// Who a profile window is about (for `.sheet(item:)`)
struct ProfileTarget: Identifiable, Hashable { let id: UUID }

/// A member's profile: planet, name, level, streak and the World Bosses they helped beat — for anyone.
/// Friends also see their study this week, subjects and what they're studying right now.
struct OrbiterProfileSheet: View {
    let userID: UUID
    @Environment(FriendsService.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var info: FriendsService.OrbiterProfile?
    @State private var loaded = false

    var body: some View {
        let card = friends.people[userID]
        let isFriend = friends.isFriend(userID)
        let isMe = userID == friends.me?.id
        let name = info?.name ?? card?.profile.name ?? "Orbiter"
        VStack(spacing: 0) {
            // header
            VStack(spacing: 10) {
                Avatar(name: name, color: .accentColor, size: 96, planet: info?.avatar ?? card?.profile.avatar)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                Text(name).font(.title.weight(.bold))
                HStack(spacing: 8) {
                    if let lv = info?.level ?? card?.profile.level { pill("LV \(lv)", .accentColor) }
                    if isMe { pill("You", .orange) } else if isFriend { pill("Friend", .green) }
                }
            }
            .padding(.top, 28).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 16) {
                // public facts
                HStack(spacing: 12) {
                    fact {
                        StreakIcon(size: 26)
                    } value: { "\(info?.streak ?? card?.streak ?? 0)" } label: { "day streak" }
                    fact {
                        Group {
                            if let img = PlanetPainter.bundleImage("badge-slayer") {
                                Image(nsImage: img).resizable().scaledToFit()
                            } else { Image(systemName: "flame.fill").foregroundStyle(.orange) }
                        }
                        .frame(width: 26, height: 26)
                        .saturation((info?.slain ?? 0) > 0 ? 1 : 0).opacity((info?.slain ?? 0) > 0 ? 1 : 0.4)
                    } value: { "\(info?.slain ?? 0)" } label: { "World Bosses beaten" }
                    fact {
                        Image(systemName: "calendar").font(.title2).foregroundStyle(.secondary)
                    } value: { info?.joined.map { Fmt.date($0, "MMM y", .persian) } ?? "—" } label: { "joined" }
                }

                // friends only
                if isFriend || isMe, let card {
                    Divider()
                    HStack {
                        Label("This week", systemImage: "clock.fill").font(.headline)
                        Spacer()
                        Text(Fmt.duration(TimeInterval(card.weekMinutes * 60))).font(.headline.monospacedDigit())
                    }
                    if let now = card.studyingNow {
                        Label("Studying \(now) right now", systemImage: "dot.radiowaves.left.and.right")
                            .font(.callout).foregroundStyle(.green)
                    }
                    let subjects = card.weekSubjects.prefix(5)
                    let top = max(1, subjects.first?.minutes ?? 1)
                    ForEach(Array(subjects), id: \.name) { s in
                        HStack {
                            Circle().fill(Color(hex: s.color)).frame(width: 8, height: 8)
                            Text(s.name).lineLimit(1)
                            ProgressView(value: Double(s.minutes), total: Double(top)).tint(Color(hex: s.color))
                            Text(Fmt.shortDuration(TimeInterval(s.minutes * 60))).font(.caption.monospacedDigit()).frame(width: 46, alignment: .trailing)
                        }
                    }
                } else if !isMe {
                    Divider()
                    Label("Study time and subjects are shared with friends only.", systemImage: "lock.fill")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    if !isMe { friendAction }
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(width: 420)
        .task {
            info = await friends.profile(of: userID)
            loaded = true
        }
    }

    @ViewBuilder
    private var friendAction: some View {
        if friends.isFriend(userID) {
            Label("Friends", systemImage: "person.fill.checkmark").foregroundStyle(.green)
        } else if friends.incoming.contains(userID) {
            Button("Accept request") { Task { await friends.respond(to: userID, accept: true) } }.buttonStyle(.borderedProminent)
        } else if friends.outgoing.contains(userID) {
            Button("Requested ✕") { Task { await friends.cancelRequest(to: userID) } }
        } else {
            Button { Task { await friends.sendRequest(to: userID) } } label: { Label("Add Friend", systemImage: "person.badge.plus") }
                .buttonStyle(.borderedProminent)
        }
    }

    private func pill(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.caption.weight(.heavy))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.22)))
    }

    private func fact<Icon: View>(@ViewBuilder _ icon: () -> Icon, value: () -> String, label: () -> String) -> some View {
        VStack(spacing: 6) {
            icon()
            Text(value()).font(.title3.weight(.bold).monospacedDigit())
            Text(label()).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
