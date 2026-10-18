import SwiftUI

/// What a galaxy looks like — used for my own galaxy and for viewing a friend's
struct GalaxyData: Codable, Hashable {
    struct System: Codable, Hashable, Identifiable {
        var id: UUID
        var name: String
        var sun: SunType
        var planets: [String]
    }
    var systems: [System]
}

extension AppStore {
    var galaxyData: GalaxyData {
        GalaxyData(systems: solarSystems.map { s in
            GalaxyData.System(id: s.id, name: s.name, sun: s.sun, planets: planets(in: s).map(\.planetID))
        })
    }
}

/// My Galaxy: profile (avatar planet + level), the galaxy map of solar systems, and the 50-planet collection.
struct GalaxyPage: View {
    @Environment(AppStore.self) private var store
    @Environment(FriendsService.self) private var friends
    @State private var selectedPlanet: String?
    @State private var focusedSystem: UUID?
    @State private var targetSystem: UUID?
    @State private var toast: String?
    @State private var zoom = 0.62

    private var accent: Color { store.settings.template.style.accent }

    var body: some View {
        let progress = store.galaxyProgress()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileCard(progress)
                galaxyPanel(progress)
                collection(progress)
            }
            .padding(24)
        }
        .navigationTitle("My Galaxy")
        .onAppear { store.ensureHomeSystem() }
    }

    // MARK: Profile

    private func profileCard(_ p: GalaxyProgress) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.black.opacity(0.85)).frame(width: 96, height: 96)
                if let avatar = PlanetCatalog.planet(store.avatarPlanet) {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                        PlanetView(planet: avatar, size: 96, phase: t.date.timeIntervalSinceReferenceDate / 10)
                    }
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 34)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .overlay(Circle().strokeBorder(accent.gradient, lineWidth: 3))
            .help("Your profile picture — choose any unlocked planet below")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(friends.me?.name ?? "You").font(.title.weight(.bold))
                    LevelBadge(level: p.level)
                }
                if p.isMaxLevel {
                    Text("Max level reached — every planet is yours 🏆").foregroundStyle(.secondary)
                } else {
                    Text("This week: \(String(format: "%.1f", p.weekHours))h of \(Int(GalaxyProgress.levelUpHours))h — reach it before Friday ends to level up (20h = +2 levels)")
                        .font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: p.weekProgress).tint(accent).frame(maxWidth: 420)
                }
                HStack(spacing: 16) {
                    Label("\(String(format: "%.1f", p.totalHours))h studied", systemImage: "clock")
                    Label("\(p.unlockedCount) of \(PlanetCatalog.all.count) planets unlocked", systemImage: "lock.open")
                    Label("\(store.solarSystems.count) solar system\(store.solarSystems.count == 1 ? "" : "s")", systemImage: "sun.max")
                    Label(p.credits > 0 ? "\(p.credits) planet\(p.credits == 1 ? "" : "s") ready to add" : (p.isMaxLevel ? "All planets placed" : "Next planet at level \(p.level + 1)"),
                          systemImage: "sparkles")
                        .foregroundStyle(p.credits > 0 ? accent : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
    }


    // MARK: Galaxy

    private func galaxyPanel(_ progress: GalaxyProgress) -> some View {
        let data = store.galaxyData
        let focused = focusedSystem.flatMap { id in data.systems.first { $0.id == id } }

        return ZStack(alignment: .topLeading) {
            if let focused {
                SolarSystemView(system: focused, large: true)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                GalaxyMapView(data: data, zoom: zoom) { id in
                    withAnimation(.spring(duration: 0.5)) { focusedSystem = id }
                }
                .transition(.opacity)
            }

            // Overlay: title + controls
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let focused {
                        Button {
                            withAnimation(.spring(duration: 0.5)) { focusedSystem = nil }
                        } label: {
                            Label("Galaxy", systemImage: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.8))
                        Text(focused.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text("\(focused.sun.name) · \(focused.planets.count)/\(SolarSystem.capacity) planets")
                            .font(.callout).foregroundStyle(.white.opacity(0.75))
                    } else {
                        Text("MY GALAXY").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(.white.opacity(0.7))
                        Text("\(data.systems.count) solar system\(data.systems.count == 1 ? "" : "s") · \(store.galaxy.count) planets")
                            .font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text("Click a solar system to fly in")
                            .font(.callout).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    if let focused {
                        systemMenu(focused, progress)
                    } else {
                        HStack(spacing: 4) {
                            Button { withAnimation { zoom = max(0.35, zoom - 0.12) } } label: { Image(systemName: "minus.magnifyingglass") }
                            Slider(value: $zoom, in: 0.35...1.3).frame(width: 110)
                            Button { withAnimation { zoom = min(1.3, zoom + 0.12) } } label: { Image(systemName: "plus.magnifyingglass") }
                        }
                        .buttonStyle(.plain)
                        newSystemMenu(progress)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.ultraThinMaterial))
                .environment(\.colorScheme, .dark)
            }
            .padding(18)

            if let toast {
                Text(toast)
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func newSystemMenu(_ progress: GalaxyProgress) -> some View {
        Menu {
            Section("Choose its star") {
                ForEach(SunType.allCases) { sun in
                    Button {
                        let s = store.createSystem(sun: sun)
                        targetSystem = s.id
                        withAnimation(.spring(duration: 0.5)) { focusedSystem = s.id }
                        showToast("✨ \(s.name) was born!")
                    } label: {
                        Text(sun.level <= progress.level ? sun.name : "\(sun.name) — level \(sun.level)")
                    }
                    .disabled(sun.level > progress.level)
                }
            }
        } label: {
            Label("New Solar System", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func systemMenu(_ system: GalaxyData.System, _ progress: GalaxyProgress) -> some View {
        Menu {
            Section("Star") {
                ForEach(SunType.allCases) { sun in
                    Button(sun.level <= progress.level ? sun.name : "\(sun.name) — level \(sun.level)") {
                        store.updateSystem(system.id) { $0.sun = sun }
                    }
                    .disabled(sun.level > progress.level)
                }
            }
            Section("Name") {
                ForEach(SolarSystem.names, id: \.self) { name in
                    Button(name) { store.updateSystem(system.id) { $0.name = name } }
                }
            }
            if system.planets.isEmpty && store.solarSystems.count > 1 {
                Divider()
                Button("Delete Empty System", role: .destructive) {
                    store.deleteSystem(system.id)
                    withAnimation { focusedSystem = nil }
                }
            }
        } label: {
            Label("Customize", systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func showToast(_ text: String) {
        withAnimation(.spring) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toast = nil }
        }
    }

    // MARK: Collection

    private func collection(_ progress: GalaxyProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Planet Collection").font(.title2.weight(.bold))
                Text("\(progress.unlockedCount)/\(PlanetCatalog.all.count)").foregroundStyle(.secondary)
                Spacer()
            }

            if let id = selectedPlanet, let planet = PlanetCatalog.planet(id) {
                selectedPanel(planet, progress)
            }

            ForEach(1...10, id: \.self) { group in
                let planets = PlanetCatalog.all.filter { $0.level == group }
                let level = PlanetCatalog.unlockLevel(group: group)
                let unlocked = level <= progress.level
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        LevelBadge(level: level, dimmed: !unlocked)
                        Text(unlocked ? levelTitle(group) : "\(levelTitle(group)) — unlocks at level \(level)")
                            .font(.headline)
                            .foregroundStyle(unlocked ? .primary : .secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(planets) { planet in
                            PlanetTile(planet: planet, unlocked: unlocked,
                                       isSelected: selectedPlanet == planet.id,
                                       isAvatar: store.avatarPlanet == planet.id,
                                       count: store.galaxy.filter { $0.planetID == planet.id }.count)
                                .onTapGesture { withAnimation(.spring(duration: 0.3)) { selectedPlanet = planet.id } }
                        }
                    }
                }
            }
        }
    }

    private func selectedPanel(_ planet: PlanetDef, _ progress: GalaxyProgress) -> some View {
        let unlocked = planet.unlockLevel <= progress.level
        let systems = store.solarSystems
        let target = targetSystem.flatMap { id in systems.first { $0.id == id } }
            ?? focusedSystem.flatMap { id in systems.first { $0.id == id } }
            ?? systems.first { store.planets(in: $0).count < SolarSystem.capacity }
        let targetFull = target.map { store.planets(in: $0).count >= SolarSystem.capacity } ?? true

        return HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.88))
                TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                    PlanetView(planet: planet, size: 130,
                               phase: t.date.timeIntervalSinceReferenceDate / 8,
                               locked: !unlocked)
                }
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(planet.name).font(.title2.weight(.bold))
                    LevelBadge(level: planet.unlockLevel, dimmed: !unlocked)
                }
                Text(planet.blurb).foregroundStyle(.secondary)
                if unlocked {
                    HStack {
                        Picker("Add to", selection: Binding(get: { target?.id }, set: { targetSystem = $0 })) {
                            ForEach(systems) { s in
                                Text("\(s.name) (\(store.planets(in: s).count)/\(SolarSystem.capacity))").tag(Optional(s.id))
                            }
                        }
                        .frame(width: 230)

                        Button {
                            store.addPlanet(planet.id, to: target?.id)
                            showToast("🎉 \(planet.name) joined \(target?.name ?? "your galaxy")!")
                        } label: {
                            Label(progress.credits == 0 ? "Reach level \(progress.level + 1) for a new planet" : (targetFull ? "System is full" : "Add Planet"),
                                  systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(progress.credits == 0 || targetFull)
                    }
                    HStack {
                        Button {
                            store.avatarPlanet = planet.id
                        } label: {
                            Label(store.avatarPlanet == planet.id ? "Your Profile Picture" : "Use as Profile Picture",
                                  systemImage: store.avatarPlanet == planet.id ? "checkmark.circle.fill" : "person.crop.circle")
                        }
                        .disabled(store.avatarPlanet == planet.id)

                        if let last = store.galaxy.last(where: { $0.planetID == planet.id }) {
                            Button(role: .destructive) { store.removePlanet(last.id) } label: {
                                Label("Remove One", systemImage: "minus.circle")
                            }
                            .help("Take one \(planet.name) out of your galaxy (you get the credit back)")
                        }
                    }
                } else {
                    Label("Reach level \(planet.unlockLevel) to unlock — study \(Int(GalaxyProgress.levelUpHours))h in a week to level up",
                          systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { withAnimation { selectedPlanet = nil } } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.3)))
    }

    private func levelTitle(_ group: Int) -> String {
        ["Starter Worlds", "Explorer", "Wild Worlds", "Shapes & Snacks", "Deep Space",
         "Creatures", "Spooky & Bright", "Cosmic Wonders", "Royal Orbit", "Legendary"][group - 1]
    }
}

// MARK: - Galaxy map

/// A big spiral galaxy; each solar system sits on one of its arms. Drag to explore, zoom with the slider.
struct GalaxyMapView: View {
    let data: GalaxyData
    var zoom: Double = 0.62
    var onSelect: ((UUID) -> Void)?

    @State private var pan: CGSize = .zero
    @State private var flyZoom: Double?
    @GestureState private var dragging: CGSize = .zero

    static let worldSize = CGSize(width: 2600, height: 1700)

    var body: some View {
        GeometryReader { geo in
            let zoom = flyZoom ?? self.zoom
            let w = Self.worldSize.width * zoom, h = Self.worldSize.height * zoom
            let offset = CGSize(width: pan.width + dragging.width, height: pan.height + dragging.height)
            ZStack {
                GalaxyBackdrop()
                    .frame(width: w, height: h)
                    .drawingGroup()

                ForEach(Array(data.systems.enumerated()), id: \.element.id) { i, system in
                    let pos = Self.position(i)
                    SolarSystemView(system: system, large: false)
                        .frame(width: 330, height: 260)
                        .scaleEffect(zoom * 1.1)
                        .frame(width: 330 * zoom * 1.1, height: 260 * zoom * 1.1)
                        .contentShape(Ellipse())
                        .onTapGesture { flyIn(to: i, id: system.id) }
                        .position(x: pos.x * zoom, y: pos.y * zoom)
                        .help("Open \(system.name)")
                }
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragging) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                        // keep some of the galaxy on screen
                        pan.width = max(-w / 2, min(w / 2, pan.width))
                        pan.height = max(-h / 2, min(h / 2, pan.height))
                    }
            )
        }
        .clipped()
        // Clipping is only visual — also limit clicks/drags to the visible map, so the big
        // galaxy underneath can't swallow clicks on buttons around it
        .contentShape(Rectangle())
        .background(Color(hex: "#020617"))
        .environment(\.colorScheme, .dark)
        .onChange(of: zoom) { old, new in
            pan = CGSize(width: pan.width * new / old, height: pan.height * new / old)
        }
    }

    /// Camera glides to the system and zooms in, then the close-up opens
    private func flyIn(to index: Int, id: UUID) {
        let target = 2.2
        let p = Self.position(index)
        let dx = (p.x - Self.worldSize.width / 2) * target
        let dy = (p.y - Self.worldSize.height / 2) * target
        withAnimation(.easeInOut(duration: 0.75)) {
            flyZoom = target
            pan = CGSize(width: -dx, height: -dy)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            onSelect?(id)
            try? await Task.sleep(for: .milliseconds(400))
            flyZoom = nil
            pan = .zero
        }
    }

    /// Systems alternate between two spiral arms, moving outward
    static func position(_ i: Int) -> CGPoint {
        let c = CGPoint(x: worldSize.width / 2, y: worldSize.height / 2)
        if i == 0 { return CGPoint(x: c.x + 260, y: c.y - 60) }
        let k = Double((i + 1) / 2)
        let arm = i % 2 == 0 ? 0.0 : .pi
        let angle = arm + 0.25 + k * 1.05
        let radius = 300 + k * 190
        return CGPoint(x: c.x + cos(angle) * radius * 1.25, y: c.y + sin(angle) * radius * 0.78)
    }
}

/// Spiral arms of dust and stars with a glowing core
struct GalaxyBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = size.width / GalaxyMapView.worldSize.width
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [Color(hex: "#1E1B4B"), Color(hex: "#0B1023"), Color(hex: "#020617")]),
                                           center: c, startRadius: 0, endRadius: max(size.width, size.height) * 0.6))
            // nebula clouds
            var rng = SeededRandom(seed: "nebula")
            let nebula = ["#7C3AED", "#DB2777", "#0EA5E9", "#14B8A6"]
            for i in 0..<14 {
                let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
                let r = (120 + rng.next() * 260) * scale
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4)),
                         with: .radialGradient(Gradient(colors: [Color(hex: nebula[i % 4]).opacity(0.18), .clear]),
                                               center: p, startRadius: 0, endRadius: r))
            }
            // spiral arms
            var arm = SeededRandom(seed: "arms")
            for a in 0..<2 {
                for j in 0..<1400 {
                    let t = Double(j) / 1400 * 4.2
                    let angle = Double(a) * .pi + t * 1.25 + 0.25
                    let radius = (60 + t * 290) * scale
                    let spread = (14 + t * 26) * scale
                    let x = c.x + cos(angle) * radius * 1.25 + (arm.next() - 0.5) * spread * 2
                    let y = c.y + sin(angle) * radius * 0.78 + (arm.next() - 0.5) * spread * 2
                    let d = (arm.next() < 0.92 ? 1.0 : 2.4) * max(0.6, scale * 1.4)
                    let hue = arm.next()
                    let color: Color = hue < 0.15 ? Color(hex: "#F9A8D4") : (hue < 0.3 ? Color(hex: "#93C5FD") : .white)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)),
                             with: .color(color.opacity(0.35 + arm.next() * 0.55)))
                }
            }
            // background stars
            var stars = SeededRandom(seed: "bgstars")
            for _ in 0..<700 {
                let p = CGPoint(x: stars.next() * size.width, y: stars.next() * size.height)
                let d = stars.next() < 0.95 ? 0.8 : 1.8
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: d, height: d)), with: .color(.white.opacity(0.2 + stars.next() * 0.5)))
            }
        }
    }
}

// MARK: - Solar system

/// A star with planets on animated orbits, painted in one Canvas (cheap to animate).
/// `large` = the full-size focused view.
struct SolarSystemView: View {
    let system: GalaxyData.System
    var large = false

    var body: some View {
        TimelineView(.animation(minimumInterval: large ? 1 / 30 : 1 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                if large { StarsBackground.paint(&ctx, size: size) }
                Self.paint(system, in: &ctx, size: size, time: t, large: large)
            }
        }
        .background(large ? Color.black : Color.clear)
    }

    struct Slot { let radius: Double; let offset: Double; let speed: Double }

    /// One planet per orbit, inner orbits are faster
    static func layout(count: Int) -> [Slot] {
        (0..<count).map { i in
            let radius = 70 + Double(i) * 30
            let speed = 0.9 / sqrt(Double(i + 1)) * (i % 3 == 2 ? -1 : 1)
            return Slot(radius: radius, offset: Double(i) * 2.1, speed: speed)
        }
    }

    static func paint(_ system: GalaxyData.System, in ctx: inout GraphicsContext, size: CGSize, time t: Double, large: Bool) {
        let slots = layout(count: system.planets.count)
        let maxR = slots.map(\.radius).max() ?? 60
        let scale = min(large ? 1.6 : 1.0, (min(size.width, size.height * 1.5) / 2 - 20) / (maxR + 30))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let planetSize = (large ? 64 : 44) * max(scale, 0.7)

        // orbits
        for slot in slots {
            let r = slot.radius * scale
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.55, width: r * 2, height: r * 1.1)),
                       with: .color(.white.opacity(large ? 0.12 : 0.16)), lineWidth: 1)
        }

        // planets behind the star, the star, then planets in front
        var placed: [(PlanetDef, CGPoint, Double, Int)] = []
        for (i, id) in system.planets.enumerated() where i < slots.count {
            guard let planet = PlanetCatalog.planet(id) else { continue }
            let angle = slots[i].offset + t * slots[i].speed
            let p = CGPoint(x: center.x + cos(angle) * slots[i].radius * scale,
                            y: center.y + sin(angle) * slots[i].radius * scale * 0.55)
            placed.append((planet, p, sin(angle), i))
        }
        func drawPlanet(_ item: (PlanetDef, CGPoint, Double, Int)) {
            var sub = ctx
            sub.translateBy(x: item.1.x - planetSize / 2, y: item.1.y - planetSize / 2)
            PlanetPainter.draw(item.0, in: &sub, size: CGSize(width: planetSize, height: planetSize),
                               phase: t / 7 + Double(item.3) * 0.13)
        }
        for item in placed where item.2 < 0 { drawPlanet(item) }
        SunPainter.paint(system.sun, in: &ctx, center: center,
                         radius: (large ? 24 : 14) * system.sun.scale * max(scale, 0.75), time: t)
        for item in placed where item.2 >= 0 { drawPlanet(item) }

        if !large {
            ctx.draw(Text(system.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.9)),
                     at: CGPoint(x: center.x, y: size.height - 12))
        }
    }
}

/// Animated star: glowing core and corona; twin stars orbit each other, pulsars sweep beams
enum SunPainter {
    static func paint(_ sun: SunType, in ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat, time: Double) {
        let colors = sun.colors.map(Color.init(hex:))
        let pulse = 1 + sin(time * 2) * 0.05

        func star(at p: CGPoint, radius: CGFloat) {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius * 2.2, y: p.y - radius * 2.2, width: radius * 4.4, height: radius * 4.4)),
                     with: .radialGradient(Gradient(colors: [colors[2].opacity(0.55), colors[2].opacity(0)]),
                                           center: p, startRadius: radius * 0.8, endRadius: radius * 2.2 * pulse))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [colors[0], colors[1], colors[2]]),
                                           center: CGPoint(x: p.x - radius * 0.2, y: p.y - radius * 0.2), startRadius: 0, endRadius: radius * 1.1))
        }

        switch sun {
        case .binary:
            let a = time * 0.8
            star(at: CGPoint(x: c.x + cos(a) * r * 0.9, y: c.y + sin(a) * r * 0.45), radius: r * 0.7)
            star(at: CGPoint(x: c.x - cos(a) * r * 0.9, y: c.y - sin(a) * r * 0.45), radius: r * 0.55)
        case .pulsar:
            for k in [0.0, .pi] {
                let a = time * 1.6 + k
                var beam = Path()
                beam.move(to: c)
                beam.addLine(to: CGPoint(x: c.x + cos(a - 0.08) * r * 4, y: c.y + sin(a - 0.08) * r * 4))
                beam.addLine(to: CGPoint(x: c.x + cos(a + 0.08) * r * 4, y: c.y + sin(a + 0.08) * r * 4))
                beam.closeSubpath()
                ctx.fill(beam, with: .linearGradient(Gradient(colors: [colors[1].opacity(0.8), .clear]),
                                                     startPoint: c, endPoint: CGPoint(x: c.x + cos(a) * r * 4, y: c.y + sin(a) * r * 4)))
            }
            star(at: c, radius: r * 0.65)
        default:
            star(at: c, radius: r)
        }
    }
}

// MARK: - Bits

struct PlanetTile: View {
    let planet: PlanetDef
    let unlocked: Bool
    let isSelected: Bool
    let isAvatar: Bool
    let count: Int
    @State private var hovering = false
    @Environment(AppStore.self) private var store

    var body: some View {
        let accent = store.settings.template.style.accent
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                PlanetView(planet: planet, size: 84, locked: !unlocked)
                    .scaleEffect(hovering && unlocked ? 1.08 : 1)
                    .animation(.spring(duration: 0.3), value: hovering)
                if count > 0 {
                    Text("×\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(.white)
                }
            }
            Text(planet.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(unlocked ? .primary : .secondary)
            if isAvatar {
                Text("Profile").font(.caption2).foregroundStyle(accent)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(unlocked ? 0.82 : 0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isSelected ? accent : Color.white.opacity(0.06), lineWidth: isSelected ? 2.5 : 1))
        .environment(\.colorScheme, .dark)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

struct LevelBadge: View {
    let level: Int
    var dimmed = false

    var body: some View {
        Text("LV \(level)")
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(dimmed ? AnyShapeStyle(Color.gray.opacity(0.5)) : AnyShapeStyle(Self.color(level).gradient)))
    }

    static func color(_ level: Int) -> Color {
        let colors = ["#64748B", "#22C55E", "#14B8A6", "#3B82F6", "#6366F1",
                      "#8B5CF6", "#D946EF", "#EC4899", "#F97316", "#EAB308"]
        return Color(hex: colors[max(0, min(9, (level - 1) / 5))])
    }
}

/// Twinkly star field
struct StarsBackground: View {
    var body: some View {
        Canvas { ctx, size in Self.paint(&ctx, size: size) }
    }

    static func paint(_ ctx: inout GraphicsContext, size: CGSize) {
        do {
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [Color(hex: "#1E1B4B"), Color(hex: "#020617")]),
                                           center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: 0, endRadius: max(size.width, size.height) * 0.7))
            var rng = SeededRandom(seed: "stars")
            for _ in 0..<260 {
                let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
                let r = rng.next() < 0.9 ? 0.7 : 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r, height: r)),
                         with: .color(.white.opacity(0.3 + rng.next() * 0.6)))
            }
        }
    }
}
