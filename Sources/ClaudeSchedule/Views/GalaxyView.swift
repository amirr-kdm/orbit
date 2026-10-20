import SwiftUI

/// What a galaxy looks like — used for my own galaxy and for viewing a friend's
struct GalaxyData: Codable, Hashable {
    struct System: Codable, Hashable, Identifiable {
        var id: UUID
        var name: String
        var sun: SunType
        var planets: [String]
        var x: Double?
        var y: Double?
    }
    var systems: [System]
}

extension AppStore {
    /// Saves where a solar system was dragged to on the map
    func moveSystem(_ id: UUID, to p: CGPoint) {
        guard let i = solarSystems.firstIndex(where: { $0.id == id }) else { return }
        solarSystems[i].x = p.x
        solarSystems[i].y = p.y
    }

    var galaxyData: GalaxyData {
        GalaxyData(systems: solarSystems.map { s in
            GalaxyData.System(id: s.id, name: s.name, sun: s.sun, planets: planets(in: s).map(\.planetID), x: s.x, y: s.y)
        })
    }
}

/// My Galaxy: profile (avatar planet + level), the galaxy map of solar systems, and the 50-planet collection.
struct GalaxyPage: View {
    @Environment(AppStore.self) private var store
    @Environment(FriendsService.self) private var friends
    @State private var selectedPlanet: String?
    /// A bought planet opened on the Your Store Planets shelf
    @State private var selectedStore: String?
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
                    Text("\(String(format: "%.1f", p.hoursToNext))h of study to level \(p.level + 1) · every \(Int(GalaxyProgress.hoursPerLevel))h studied = +1 level")
                        .font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: p.levelProgress).tint(accent).frame(maxWidth: 420)
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
            // One continuous map: opening a system is just the camera zooming in on it
            GalaxyMapView(data: data, zoom: zoom, focused: focusedSystem, onMove: { id, p in store.moveSystem(id, to: p) }) { id in focusedSystem = id }

            // Overlay: title + controls
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let focused {
                        Button {
                            focusedSystem = nil
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

    /// Planets bought in the Store wait here until you place them
    private var storeShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Your Store Planets").font(.title2.weight(.bold))
                RocketIcon(size: 20)
                Spacer()
                Picker("Place in", selection: $targetSystem) {
                    Text("First system with room").tag(UUID?.none)
                    ForEach(store.solarSystems) { s in
                        Text("\(s.name) (\(store.planets(in: s).count)/\(SolarSystem.capacity))").tag(Optional(s.id))
                    }
                }
                .frame(width: 280)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.ownedStorePlanets) { p in
                        let waiting = store.unplacedCount(p.id), placed = store.placedCount(p.id)
                        VStack(spacing: 6) {
                            PlanetView(planet: p, size: 96, phase: 0.15)
                            Text(p.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Text(waiting > 0 ? "\(waiting) waiting · \(placed) placed" : "All \(placed) placed")
                                .font(.caption2).foregroundStyle(.secondary)
                            if store.avatarPlanet == p.id {
                                Text("Profile").font(.caption2.weight(.semibold)).foregroundStyle(accent)
                            }
                        }
                        .frame(width: 130)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#0B1020")))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selectedStore == p.id ? accent : p.rarity.color.opacity(0.5), lineWidth: selectedStore == p.id ? 2.5 : 1))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { selectedStore = selectedStore == p.id ? nil : p.id } }
                    }
                }
            }
            if let id = selectedStore, let p = PlanetCatalog.planet(id), store.ownedCount(id) > 0 { storePanel(p) }
            Text("Click a planet to place, move or remove it. Placing uses one of your planet spots (one per level — \(store.galaxyProgress().credits) free now). Removing a store planet from a system keeps it on this shelf.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Place, move, remove or use as profile — for a bought planet
    private func storePanel(_ planet: PlanetDef) -> some View {
        let progress = store.galaxyProgress()
        let systems = store.solarSystems
        let target = targetSystem.flatMap { id in systems.first { $0.id == id } }
            ?? systems.first { store.planets(in: $0).count < SolarSystem.capacity }
        let targetFull = target.map { store.planets(in: $0).count >= SolarSystem.capacity } ?? true
        let placed = store.galaxy.filter { $0.planetID == planet.id }
        let waiting = store.unplacedCount(planet.id)

        return HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.88))
                TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                    PlanetView(planet: planet, size: 130, phase: t.date.timeIntervalSinceReferenceDate / 8)
                }
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(planet.name).font(.title2.weight(.bold))
                    Text(planet.rarity.title.uppercased()).font(.caption2.weight(.heavy)).tracking(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(planet.rarity.color.opacity(0.25))).foregroundStyle(planet.rarity.color)
                }
                Text(planet.blurb).foregroundStyle(.secondary)

                if waiting > 0 {
                    HStack {
                        Picker("Add to", selection: Binding(get: { target?.id }, set: { targetSystem = $0 })) {
                            ForEach(systems) { s in
                                Text("\(s.name) (\(store.planets(in: s).count)/\(SolarSystem.capacity))").tag(Optional(s.id))
                            }
                        }
                        .frame(width: 230)
                        Button {
                            if store.placeOwned(planet.id, into: target?.id) {
                                showToast("🎉 \(planet.name) joined \(target?.name ?? "your galaxy")!")
                            }
                        } label: {
                            Label(progress.credits == 0 ? "Reach level \(progress.level + 1) for a free spot"
                                  : (targetFull ? "System is full" : "Place (\(waiting) waiting)"),
                                  systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(progress.credits == 0 || targetFull)
                    }
                }

                ForEach(placed) { copy in
                    let here = systems.first { $0.id == copy.systemID }
                    HStack(spacing: 10) {
                        Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                        Text("In \(here?.name ?? "your galaxy")")
                        Menu("Move to") {
                            ForEach(systems.filter { $0.id != copy.systemID }) { s in
                                let full = store.planets(in: s).count >= SolarSystem.capacity
                                Button("\(s.name) (\(store.planets(in: s).count)/\(SolarSystem.capacity))") {
                                    if store.movePlaced(copy.id, to: s.id) { showToast("\(planet.name) moved to \(s.name)") }
                                }
                                .disabled(full)
                            }
                        }
                        .fixedSize()
                        .disabled(systems.count < 2)
                        Button(role: .destructive) {
                            store.removePlanet(copy.id)
                            showToast("\(planet.name) is back on your shelf")
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                        .help("Take it out of the galaxy. You still own it and get the spot back.")
                    }
                    .font(.callout)
                }

                Button {
                    store.avatarPlanet = planet.id
                } label: {
                    Label(store.avatarPlanet == planet.id ? "Your Profile Picture" : "Use as Profile Picture",
                          systemImage: store.avatarPlanet == planet.id ? "checkmark.circle.fill" : "person.crop.circle")
                }
                .disabled(store.avatarPlanet == planet.id)
            }
            Spacer()
            Button { withAnimation { selectedStore = nil } } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.3)))
    }

    private func collection(_ progress: GalaxyProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.ownedStorePlanets.isEmpty { storeShelf.padding(.bottom, 10) }
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
                    Label("Reach level \(planet.unlockLevel) to unlock — every \(Int(GalaxyProgress.hoursPerLevel))h of study is +1 level",
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
    /// The open solar system: the camera zooms in on it (nil = whole galaxy)
    var focused: UUID? = nil
    /// Set to let the user drag solar systems around (their own galaxy only)
    var onMove: ((UUID, CGPoint) -> Void)? = nil
    var onSelect: ((UUID) -> Void)?

    @State private var pan: CGSize = .zero
    @State private var flyZoom: Double?
    @GestureState private var dragging: CGSize = .zero
    /// Trackpad pinch on top of the slider's zoom
    @State private var userScale = 1.0
    @State private var hovering = false
    @State private var monitor: Any?
    @State private var viewSize = CGSize(width: 900, height: 600)

    private var baseZoom: Double { min(1.8, max(0.25, zoom * userScale)) }

    static let worldSize = CGSize(width: 2600, height: 1700)

    var body: some View {
        GeometryReader { geo in
            let zoom = flyZoom ?? baseZoom
            let w = Self.worldSize.width * zoom, h = Self.worldSize.height * zoom
            let offset = CGSize(width: pan.width + dragging.width, height: pan.height + dragging.height)
            ZStack {
                // Endless starfield (drawn for the visible area only) — the galaxy has no edge
                // (world origin on screen = o; the canvas covers exactly the visible area)
                let o = CGSize(width: geo.size.width / 2 + offset.width - w / 2, height: geo.size.height / 2 + offset.height - h / 2)
                InfiniteStars(offset: o, zoom: zoom)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .position(x: -o.width + geo.size.width / 2, y: -o.height + geo.size.height / 2)
                    .allowsHitTesting(false)
                // The backdrop is rendered once at the normal zoom and scaled for close-ups (keeps memory low)
                GalaxyBackdrop()
                    .frame(width: Self.worldSize.width * baseZoom, height: Self.worldSize.height * baseZoom)
                    .drawingGroup()
                    // fade the spiral's rectangle into the endless starfield (no visible edge)
                    .mask(EllipticalGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.62),
                                                     .init(color: .clear, location: 1)], center: .center))
                    .scaleEffect(zoom / baseZoom)
                    .frame(width: w, height: h)

                ForEach(Array(data.systems.enumerated()), id: \.element.id) { i, system in
                    let base = Self.position(of: system, index: i)
                    let isOpen = focused == system.id
                    MapSystemTile(system: system, zoom: zoom, showName: focused == nil, canMove: focused == nil && onMove != nil,
                                  onTap: { if focused == nil { onSelect?(system.id) } },
                                  onDrop: { t in onMove?(system.id, CGPoint(x: base.x + t.width / zoom, y: base.y + t.height / zoom)) })
                        .opacity(focused == nil || isOpen ? 1 : 0)
                        .position(x: base.x * zoom, y: base.y * zoom)
                        .help(focused == nil ? "Open \(system.name)" : "")
                }
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height)
            .contentShape(Rectangle())   // drag anywhere, even beyond the spiral
            .gesture(
                DragGesture(minimumDistance: focused == nil ? 4 : 10_000)
                    .updating($dragging) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                    }
            )
        }
        .clipped()
        // Clipping is only visual — also limit clicks/drags to the visible map, so the big
        // galaxy underneath can't swallow clicks on buttons around it
        .contentShape(Rectangle())
        .background(Color(hex: "#020617"))
        .environment(\.colorScheme, .dark)
        .background(GeometryReader { g in Color.clear.onAppear { viewSize = g.size }.onChange(of: g.size) { _, s in viewSize = s } })
        .onHover { hovering = $0 }
        .onAppear { startTrackpad(); if focused != nil { camera(to: focused, animated: false) } }
        .onChange(of: focused) { _, id in camera(to: id, animated: true) }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        .onChange(of: zoom) { old, new in
            pan = CGSize(width: pan.width * new / old, height: pan.height * new / old)
        }
    }

    /// Trackpad: pinch to zoom, two fingers to move around (a mouse wheel zooms)
    private func startTrackpad() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { e in
            guard hovering, focused == nil, flyZoom == nil else { return e }
            if e.type == .magnify {
                rescale(by: 1 + e.magnification)
            } else if e.hasPreciseScrollingDeltas {
                pan.width += e.scrollingDeltaX
                pan.height += e.scrollingDeltaY
            } else {
                rescale(by: 1 + e.scrollingDeltaY * 0.03)
            }
            return nil
        }
    }

    private func rescale(by k: Double) {
        let before = baseZoom
        userScale = min(1.8 / max(zoom, 0.01), max(0.25 / max(zoom, 0.01), userScale * k))
        let ratio = baseZoom / before
        pan = CGSize(width: pan.width * ratio, height: pan.height * ratio)
    }

    /// Zoom at which one solar system fills the view — the close-up opens from exactly there
    private var flyTarget: Double { max(1.5, min(viewSize.width / (330 * 1.1), viewSize.height / (260 * 1.1)) * 0.95) }

    /// Pan that centres system `index` at zoom `z`
    private static func centre(on index: Int, zoom z: Double) -> CGSize {
        let p = position(index)
        return CGSize(width: -(p.x - worldSize.width / 2) * z, height: -(p.y - worldSize.height / 2) * z)
    }

    @State private var flight: Task<Void, Never>?

    /// Zooms the camera onto a system (fills the view) or back out to the whole galaxy.
    /// Zoom and position move together (zoom on a log scale, the system gliding on screen),
    /// so the camera never swings through empty space on the way.
    private func camera(to id: UUID?, animated: Bool) {
        let target = id ?? focusedBefore
        guard let target, let i = data.systems.firstIndex(where: { $0.id == target }) else { flyZoom = nil; return }
        let p = Self.position(of: data.systems[i], index: i)
        let rel = CGSize(width: p.x - Self.worldSize.width / 2, height: p.y - Self.worldSize.height / 2)
        let z0 = flyZoom ?? baseZoom
        let z1 = id != nil ? flyTarget : baseZoom
        // where the system sits on screen (relative to the centre), now and at the end
        let s0 = CGSize(width: pan.width + rel.width * z0, height: pan.height + rel.height * z0)
        let s1 = id != nil ? .zero : CGSize(width: s0.width * 0.4 + rel.width * z1 * 0.0, height: s0.height * 0.4)
        focusedBefore = id
        flight?.cancel()
        func apply(_ t: Double) {
            let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2   // ease in-out
            let z = exp(log(z0) + (log(z1) - log(z0)) * e)
            let sx = s0.width + (s1.width - s0.width) * e, sy = s0.height + (s1.height - s0.height) * e
            flyZoom = z
            pan = CGSize(width: sx - rel.width * z, height: sy - rel.height * z)
        }
        guard animated else { apply(1); if id == nil { flyZoom = nil }; return }
        flight = Task { @MainActor in
            let start = Date(), duration = 0.85
            while !Task.isCancelled {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                apply(t)
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
            if id == nil && !Task.isCancelled { flyZoom = nil }
        }
    }
    @State private var focusedBefore: UUID?

    /// A system's place: where it was dragged to, or its spot on the spiral
    static func position(of s: GalaxyData.System, index i: Int) -> CGPoint {
        if let x = s.x, let y = s.y { return CGPoint(x: x, y: y) }
        return position(i)
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
    /// Map tiles: draw the 330×260 layout scaled up to this factor (sharp at any zoom)
    var paintScale: CGFloat = 1
    var showName = true

    var body: some View {
        TimelineView(.animation(minimumInterval: large ? 1 / 30 : 1 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                if large { StarsBackground.paint(&ctx, size: size) }
                ctx.scaleBy(x: paintScale, y: paintScale)
                Self.paint(system, in: &ctx, size: CGSize(width: size.width / paintScale, height: size.height / paintScale),
                           time: t, large: large, showName: showName)
            }
        }
        .background(large ? Color.black : Color.clear)
    }

    struct Slot { let radius: Double; let offset: Double; let speed: Double }

    /// One planet per orbit, inner orbits are faster
    static func layout(count: Int) -> [Slot] {
        (0..<count).map { i in
            let radius = 100 + Double(i) * 32   // first orbit clears the (bigger) sun
            let speed = 0.35 / sqrt(Double(i + 1)) * (i % 3 == 2 ? -1 : 1)
            return Slot(radius: radius, offset: Double(i) * 2.1, speed: speed)
        }
    }

    static func paint(_ system: GalaxyData.System, in ctx: inout GraphicsContext, size: CGSize, time t: Double, large: Bool, showName: Bool = true) {
        let slots = layout(count: system.planets.count)
        let maxR = slots.map(\.radius).max() ?? 60
        let scale = min(large ? 1.6 : 1.0, (min(size.width, size.height * 1.5) / 2 - 20) / (maxR + 30))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let planetSize = (large ? 42 : 30) * max(scale, 0.7)   // planets stay small next to their star

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
                         radius: (large ? 46 : 30) * system.sun.scale * max(scale, 0.75), time: t)
        for item in placed where item.2 >= 0 { drawPlanet(item) }

        if !large && showName {
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

        /// A star that reads as a real sun: wide soft corona, slow rays, a limb-darkened disc and drifting granules
        func star(at p: CGPoint, radius: CGFloat) {
            func disc(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
            // outer haze and corona
            ctx.fill(disc(radius * 3.4 * pulse), with: .radialGradient(Gradient(colors: [colors[2].opacity(0.28), colors[2].opacity(0)]),
                                                                        center: p, startRadius: radius, endRadius: radius * 3.4 * pulse))
            ctx.fill(disc(radius * 1.8), with: .radialGradient(Gradient(colors: [colors[1].opacity(0.75), colors[2].opacity(0)]),
                                                                center: p, startRadius: radius * 0.9, endRadius: radius * 1.8))
            // soft rays turning slowly
            var rays = ctx
            rays.opacity = 0.22
            for k in 0..<12 {
                let a = Double(k) / 12 * .pi * 2 + time * 0.05
                let len = radius * (1.9 + 0.35 * sin(time * 0.9 + Double(k) * 1.7))
                var ray = Path()
                ray.move(to: CGPoint(x: p.x + cos(a - 0.09) * radius * 0.9, y: p.y + sin(a - 0.09) * radius * 0.9))
                ray.addLine(to: CGPoint(x: p.x + cos(a) * len, y: p.y + sin(a) * len))
                ray.addLine(to: CGPoint(x: p.x + cos(a + 0.09) * radius * 0.9, y: p.y + sin(a + 0.09) * radius * 0.9))
                ray.closeSubpath()
                rays.fill(ray, with: .linearGradient(Gradient(colors: [colors[0], colors[1].opacity(0)]),
                                                     startPoint: p, endPoint: CGPoint(x: p.x + cos(a) * len, y: p.y + sin(a) * len)))
            }
            // the disc: bright centre, darker at the edge (limb darkening)
            ctx.fill(disc(radius), with: .radialGradient(Gradient(stops: [
                .init(color: colors[0], location: 0), .init(color: colors[1], location: 0.62),
                .init(color: colors[2], location: 1)]),
                center: p, startRadius: 0, endRadius: radius))
            // granules drifting across the surface
            var surface = ctx
            surface.clip(to: disc(radius))
            surface.opacity = 0.25
            for k in 0..<9 {
                let a = Double(k) * 2.4 + time * 0.12
                let d = radius * (0.25 + 0.55 * Double((k * 37) % 10) / 10)
                let g = radius * (0.16 + 0.06 * sin(time + Double(k)))
                let q = CGPoint(x: p.x + cos(a) * d, y: p.y + sin(a) * d * 0.9)
                surface.fill(Path(ellipseIn: CGRect(x: q.x - g, y: q.y - g, width: g * 2, height: g * 2)),
                             with: .radialGradient(Gradient(colors: [k % 3 == 0 ? colors[2] : .white, .clear]), center: q, startRadius: 0, endRadius: g))
            }
            // thin bright rim
            ctx.stroke(disc(radius), with: .color(colors[0].opacity(0.5)), lineWidth: max(1, radius * 0.04))
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

extension AnyTransition {
    /// Opening a solar system: it grows out of the galaxy; closing shrinks it back in
    static var systemZoom: AnyTransition {
        // The map has already zoomed right into the system, so a soft cross-fade finishes the move
        .asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity))
    }
}

private extension CGSize {
    func applying(_ k: Double) -> CGSize { CGSize(width: width * k, height: height * k) }
}

/// Stars that go on forever: each 400×400 world cell gets the same random stars every time,
/// and only the cells on screen are drawn
struct InfiniteStars: View {
    /// Screen offset of the world origin
    let offset: CGSize
    let zoom: Double

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#020617")))
            let cell = 400.0 * zoom
            let x0 = Int(floor(-offset.width / cell)), x1 = Int(floor((size.width - offset.width) / cell))
            let y0 = Int(floor(-offset.height / cell)), y1 = Int(floor((size.height - offset.height) / cell))
            guard (x1 - x0) * (y1 - y0) < 900 else { return }
            for cx in x0...x1 { for cy in y0...y1 {
                var seed = UInt64(bitPattern: Int64(cx &* 73856093 ^ cy &* 19349663)) | 1
                func rnd() -> Double { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Double(seed % 10_000) / 10_000 }
                for _ in 0..<14 {
                    let x = offset.width + (Double(cx) + rnd()) * cell, y = offset.height + (Double(cy) + rnd()) * cell
                    let r = (rnd() < 0.9 ? 0.8 : 1.6) * max(0.6, min(1.6, zoom * 1.4))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.25 + rnd() * 0.5)))
                }
            } }
        }
    }
}

/// One solar system on the map. Dragging only moves this tile (its own gesture state),
/// so the rest of the map isn't redrawn on every mouse move.
private struct MapSystemTile: View {
    let system: GalaxyData.System
    let zoom: Double
    let showName: Bool
    let canMove: Bool
    let onTap: () -> Void
    let onDrop: (CGSize) -> Void
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        // Painted at the real on-screen size, so it stays sharp when zoomed in
        SolarSystemView(system: system, large: false, paintScale: zoom * 1.1, showName: showName)
            .frame(width: 330 * zoom * 1.1, height: 260 * zoom * 1.1)
            .contentShape(Ellipse())
            .offset(drag)
            .onTapGesture(perform: onTap)
            // Measured in window coordinates: the tile itself moves while dragging
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .updating($drag) { v, state, _ in state = v.translation }
                .onEnded { v in onDrop(v.translation) },
                including: canMove ? .all : .none)
            .zIndex(drag == .zero ? 0 : 1)
            .help(showName ? "Open \(system.name) · drag to move it" : "")
    }
}
