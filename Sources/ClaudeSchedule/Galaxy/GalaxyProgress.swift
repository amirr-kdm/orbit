import Foundation

/// One planet placed in a solar system of my galaxy
struct PlacedPlanet: Codable, Identifiable, Hashable {
    var id = UUID()
    var planetID: String
    var addedAt = Date()
    var systemID: UUID?
}

/// Kinds of star at the centre of a solar system (unlock with level)
enum SunType: String, Codable, CaseIterable, Identifiable {
    case yellow, red, blue, white, binary, pulsar

    var id: String { rawValue }
    var name: String {
        switch self {
        case .yellow: "Yellow Sun"
        case .red: "Red Giant"
        case .blue: "Blue Star"
        case .white: "White Dwarf"
        case .binary: "Twin Stars"
        case .pulsar: "Pulsar"
        }
    }
    var level: Int {
        switch self {
        case .yellow: 1
        case .red: 6
        case .blue: 16
        case .white: 21
        case .binary: 31
        case .pulsar: 41
        }
    }
    /// core → mid → glow
    var colors: [String] {
        switch self {
        case .yellow: ["#FFFBEB", "#FDE047", "#F97316"]
        case .red: ["#FEE2E2", "#F87171", "#991B1B"]
        case .blue: ["#EFF6FF", "#60A5FA", "#1D4ED8"]
        case .white: ["#FFFFFF", "#E0E7FF", "#818CF8"]
        case .binary: ["#FFFBEB", "#FDBA74", "#F43F5E"]
        case .pulsar: ["#ECFEFF", "#22D3EE", "#7C3AED"]
        }
    }
    /// Every kind of star is drawn at the same size, so a new sun matches the ones you already have and the
    /// "Sun size" slider (which sizes all suns together) can always make them equal. (Red giants used to be
    /// 35% bigger and white dwarfs 30% smaller than the slider value, so they could never be matched.)
    var scale: Double { 1 }
}

struct SolarSystem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var sun: SunType = .yellow
    /// Where it sits on the galaxy map (world coordinates); nil = its place on the spiral
    var x: Double?
    var y: Double?

    /// Planets one solar system can hold
    /// No limit on planets around a sun (the system view shrinks to fit)
    static let capacity = Int.max
    static let names = ["Home System", "Nova Reach", "Amber Drift", "Cobalt Veil", "Starfall", "Moonwake",
                        "Echo Nebula", "Solace", "Crimson Arc", "Halcyon", "Lumen Gate", "Zephyr Belt"]
}

/// Level and planet credits, all derived from study time
struct GalaxyProgress {
    static let maxLevel = 60
    /// Every 3 hours of study (in total) is one level
    static let hoursPerLevel: Double = 3

    let level: Int
    let totalHours: Double
    let weekHours: Double
    /// Planets you may still add (one per level reached)
    let credits: Int
    let placed: Int

    var isMaxLevel: Bool { level >= Self.maxLevel }
    /// Progress towards the next level (0…1)
    var levelProgress: Double { isMaxLevel ? 1 : (totalHours - Double(level - 1) * Self.hoursPerLevel) / Self.hoursPerLevel }
    /// Hours of study left until the next level
    var hoursToNext: Double { isMaxLevel ? 0 : max(0, Double(level) * Self.hoursPerLevel - totalHours) }
    var unlockedCount: Int { PlanetCatalog.unlocked(at: level).count }
}

extension AppStore {
    /// One level for every 3 hours studied in total (max 60). Level-ups happen straight away.
    func galaxyProgress(now: Date = Date()) -> GalaxyProgress {
        let total = sessions.filter { !$0.isManual }.reduce(0) { $0 + $1.duration } / 3600
        let currentWeek = Cal.weekStart(now)
        let weekHours = rewardTime(in: DateInterval(start: currentWeek, end: now.addingTimeInterval(1))) / 3600
        let level = min(GalaxyProgress.maxLevel, 1 + Int(total / GalaxyProgress.hoursPerLevel))
        // One planet spot per level, shared by collection and store planets
        return GalaxyProgress(level: level, totalHours: total, weekHours: weekHours,
                              credits: max(0, level - galaxy.count), placed: galaxy.count)
    }

    func planets(in system: SolarSystem) -> [PlacedPlanet] {
        galaxy.filter { $0.systemID == system.id }
    }

    /// Adds a planet to a system (the given one, or the first that still has room)
    func addPlanet(_ id: String, to systemID: UUID? = nil) {
        ensureHomeSystem()
        let progress = galaxyProgress()
        guard progress.credits > 0, let p = PlanetCatalog.planet(id), p.unlockLevel <= progress.level else { return }
        let chosen = systemID.flatMap { sid in solarSystems.first { $0.id == sid } }
        let target = chosen ?? solarSystems.first { planets(in: $0).count < SolarSystem.capacity }
        guard let target, planets(in: target).count < SolarSystem.capacity else { return }
        galaxy.append(PlacedPlanet(planetID: id, systemID: target.id))
    }

    func removePlanet(_ id: UUID) {
        galaxy.removeAll { $0.id == id }
    }

    /// Start a new solar system and return it
    @discardableResult
    func createSystem(sun: SunType) -> SolarSystem {
        ensureHomeSystem()
        let name = SolarSystem.names[solarSystems.count % SolarSystem.names.count]
        let system = SolarSystem(name: name, sun: sun)
        solarSystems.append(system)
        return system
    }

    func updateSystem(_ id: UUID, _ change: (inout SolarSystem) -> Void) {
        guard let i = solarSystems.firstIndex(where: { $0.id == id }) else { return }
        change(&solarSystems[i])
    }

    /// Removes a system (the last one can't be removed); its planets move to systems with room
    func deleteSystem(_ id: UUID) {
        guard solarSystems.count > 1 else { return }
        solarSystems.removeAll { $0.id == id }
        for i in galaxy.indices where galaxy[i].systemID == id { galaxy[i].systemID = nil }
        ensureHomeSystem()
    }

    /// Make sure there is at least one system and every planet belongs to one
    func ensureHomeSystem() {
        if solarSystems.isEmpty { solarSystems = [SolarSystem(name: SolarSystem.names[0])] }
        var systems = solarSystems
        var fixed = galaxy
        var changed = false
        for i in fixed.indices {
            let ids = Set(systems.map(\.id))
            if let sid = fixed[i].systemID, ids.contains(sid) { continue }
            let open = systems.first { s in fixed.filter { $0.systemID == s.id }.count < SolarSystem.capacity }
            let target: SolarSystem
            if let open {
                target = open
            } else {
                target = SolarSystem(name: SolarSystem.names[systems.count % SolarSystem.names.count])
                systems.append(target)
            }
            fixed[i].systemID = target.id
            changed = true
        }
        if changed {
            solarSystems = systems
            galaxy = fixed
        }
    }
}
