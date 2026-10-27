import SwiftUI

/// The Level Pass: one long line of levels with a ship showing where you are.
/// Under every level waits a reward (25 rockets — 75 from level 10, 125 from level 20 … — plus a special planet on levels 10, 20 … 60) that you click to take.
struct LevelPassView: View {
    /// Study hours before the session that opened this (the ship flies from there); nil = no flight
    var fromHours: Double?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Where the ship is drawn, in levels (1.0 = level 1, 1.5 = halfway to level 2)
    @State private var shipAt: Double = 1
    @State private var justClaimed: Int?
    /// Level whose planet is being previewed
    @State private var preview: Int?
    /// How far the user moved the view away from the ship
    @State private var look: CGFloat = 0
    /// The level the view is centred on
    @State private var cameraAt: Double = 1
    @GestureState private var dragging: CGFloat = 0
    @State private var hovering = false
    @State private var monitor: Any?

    private func clampLook(_ x: CGFloat) -> CGFloat {
        let ship = Self.spacing * CGFloat(cameraAt - 1)
        return min(ship + 300, max(ship - Self.spacing * CGFloat(Self.maxLevel - 1) - 300, x))
    }

    static let spacing: CGFloat = 132
    private static let maxLevel = GalaxyProgress.maxLevel

    private var progress: GalaxyProgress { store.galaxyProgress() }

    /// Total hours → position on the line
    private static func position(hours: Double) -> Double {
        min(Double(maxLevel), 1 + hours / GalaxyProgress.hoursPerLevel)
    }

    /// Which of the three ships you fly (your choice, kept on this Mac)
    @AppStorage("passShip") private var ship = 1
    static func shipImage(_ n: Int) -> String { "pass_ship\(min(3, max(1, n)))" }

    var body: some View {
        let p = progress
        let claimable = (1...p.level).filter { store.canClaim(level: $0) }
        VStack(spacing: 0) {
            header(p, claimable: claimable)
            // The camera follows the ship; drag, scroll wheel or trackpad to look along the line
            GeometryReader { geo in
                track(p)
                    .offset(x: geo.size.width / 2 - Self.spacing * CGFloat(cameraAt - 1) + look + dragging)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 4)
                        .updating($dragging) { v, s, _ in s = v.translation.width }
                        .onEnded { v in look = clampLook(look + v.translation.width) })
            }
            .clipped()
            .frame(height: 330)
            .onHover { hovering = $0 }
            .onAppear {
                let target = Self.position(hours: p.totalHours)
                let start = fromHours.map(Self.position(hours:)) ?? target
                shipAt = start
                // The view holds between start and finish (so you see the ship fly), then settles on the ship
                cameraAt = abs(target - start) <= 5 ? (start + target) / 2 : start
                withAnimation(.easeInOut(duration: 2.4).delay(0.9)) { shipAt = target }
                if abs(target - start) > 5 {
                    withAnimation(.easeInOut(duration: 2.4).delay(1.1)) { cameraAt = target }
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
                    guard hovering else { return e }
                    let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
                    look = clampLook(look + d * (e.hasPreciseScrollingDeltas ? 1 : 12))
                    return nil
                }
            }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
            .background(StarsBackground())
        }
        .frame(width: 900)
        .background(Color(hex: "#0B1020"))
        .environment(\.colorScheme, .dark)
    }

    private func header(_ p: GalaxyProgress, claimable: [Int]) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LEVEL PASS").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(.orange)
                HStack(spacing: 8) {
                    Text("Level \(p.level)").font(.title.weight(.bold))
                    if !p.isMaxLevel {
                        Text("· \(String(format: "%.1f", p.hoursToNext))h to level \(p.level + 1)").font(.title3).foregroundStyle(.secondary)
                    }
                }
                Text("Every 3 hours of study is a level. Click a reward to take it.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // pick your ship
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { n in
                    Button { withAnimation(.spring(duration: 0.3)) { ship = n } } label: {
                        Group {
                            if let img = PlanetPainter.bundleImage(Self.shipImage(n)) { Image(nsImage: img).resizable() } else { Text("🛸") }
                        }
                        .frame(width: 34, height: 34)
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ship == n ? Color.orange.opacity(0.25) : Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ship == n ? Color.orange : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .help("Fly ship \(n)")
                }
            }
            HStack(spacing: 6) {
                RocketIcon(size: 18)
                Text(store.rocketBalance.formatted()).font(.title3.weight(.bold).monospacedDigit())
            }
            if !claimable.isEmpty {
                Button("Claim All (\(claimable.count))") {
                    Task { for lv in claimable { await store.walletClaim(level: lv) } }
                }
                .buttonStyle(.borderedProminent).tint(.orange)
            }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func track(_ p: GalaxyProgress) -> some View {
        let width = Self.spacing * CGFloat(Self.maxLevel - 1)
        let shipX = Self.spacing * CGFloat(shipAt - 1)
        return ZStack(alignment: .topLeading) {
            // the line: done part glows
            Capsule().fill(Color.white.opacity(0.12)).frame(width: width, height: 6).offset(y: 118)
            Capsule().fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(6, shipX), height: 6).offset(y: 118)
                .shadow(color: .orange.opacity(0.6), radius: 6)

            ForEach(1...Self.maxLevel, id: \.self) { lv in
                levelNode(lv, reached: lv <= p.level)
                    .frame(width: Self.spacing)
                    .offset(x: Self.spacing * CGFloat(lv - 1) - Self.spacing / 2, y: 104)
                    .id(lv)
            }

            // the ship hovers above where you are
            TimelineView(.animation(minimumInterval: 1 / 30, paused: AppActivity.paused)) { tl in
                let bob = sin(tl.date.timeIntervalSinceReferenceDate * 2.2) * 4
                VStack(spacing: 2) {
                    if let img = PlanetPainter.bundleImage(Self.shipImage(ship)) {
                        Image(nsImage: img).resizable().interpolation(.high).frame(width: 78, height: 78)
                    } else {
                        Text("🛸").font(.system(size: 44))
                    }
                    Text("You").font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(.orange))
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(.orange)
                }
                .offset(x: shipX - 39, y: 4 + bob)
            }
        }
        .frame(width: width, height: 320, alignment: .topLeading)
    }

    private func levelNode(_ lv: Int, reached: Bool) -> some View {
        let claimed = store.claimedLevels.contains(lv)
        let canTake = reached && !claimed
        let planet = AppStore.levelPlanet(lv).flatMap(PlanetCatalog.planet)
        return VStack(spacing: 8) {
            Text("\(lv)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .frame(width: 30, height: 30)
                .background(Circle().fill(reached ? Color.orange : Color.white.opacity(0.12)))
                .overlay(Circle().strokeBorder(Color.white.opacity(reached ? 0.6 : 0.15), lineWidth: 1.5))
            // reward card
            Button {
                if canTake {
                    Task { await store.walletClaim(level: lv); withAnimation(.spring(duration: 0.4)) { justClaimed = lv } }
                } else if planet != nil {
                    preview = lv   // locked (or taken) planet: show a preview
                }
            } label: {
                VStack(spacing: 6) {
                    if let planet {
                        TimelineView(.animation(minimumInterval: 1 / 8, paused: AppActivity.paused)) { _ in
                            PlanetView(planet: planet, size: 70, phase: 0.2)
                        }
                    }
                    HStack(spacing: 3) {
                        RocketIcon(size: 14)
                        Text("+\(AppStore.rocketsForLevel(lv))").font(.caption.weight(.bold).monospacedDigit())
                    }
                    Text(claimed ? "Taken ✓" : canTake ? "Claim" : "Locked")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(claimed ? .green : canTake ? .orange : .secondary)
                }
                .frame(width: 104, height: planet == nil ? 64 : 136)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(canTake ? Color.orange.opacity(0.18) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(canTake ? Color.orange : planet != nil ? Color.purple.opacity(0.6) : Color.white.opacity(0.08),
                                  lineWidth: canTake ? 2 : 1))
                .shadow(color: canTake ? .orange.opacity(0.5) : .clear, radius: 8)
                .scaleEffect(justClaimed == lv ? 1.08 : 1)
                .opacity(reached || planet != nil ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .disabled(!canTake && planet == nil)
            .popover(isPresented: Binding(get: { preview == lv }, set: { if !$0 { preview = nil } }), arrowEdge: .bottom) {
                if let planet { PlanetPreview(planet: planet, level: lv, reached: reached, claimed: claimed) }
            }
            .help(planet.map { "Level \(lv): \(AppStore.rocketsForLevel(lv)) rockets + \($0.name)" } ?? "Level \(lv): \(AppStore.rocketsForLevel(lv)) rockets")
        }
    }
}

/// A big, moving look at a Level Pass planet
private struct PlanetPreview: View {
    let planet: PlanetDef
    let level: Int
    let reached: Bool
    let claimed: Bool

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1 / 12, paused: AppActivity.paused)) { tl in
                PlanetView(planet: planet, size: 200, phase: tl.date.timeIntervalSinceReferenceDate / 8)
            }
            .frame(width: 220, height: 220)
            Text(planet.name).font(.title3.weight(.bold))
            Text(planet.blurb).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: 240)
            Label(claimed ? "Yours ✓" : reached ? "Ready to claim" : "Unlocks at level \(level)",
                  systemImage: claimed ? "checkmark.seal.fill" : reached ? "gift.fill" : "lock.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(claimed ? .green : reached ? .orange : .secondary)
        }
        .padding(18)
        .environment(\.colorScheme, .dark)
    }
}
