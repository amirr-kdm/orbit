import Foundation

/// A store planet bought with rockets
struct Purchase: Codable, Identifiable, Hashable {
    var id = UUID()
    var planetID: String
    var price: Int
    var date = Date()
}

/// The bonus earned for one finished week (Saturday → Friday)
struct WeekBonus: Identifiable {
    let weekStart: Date
    let hours: Double
    let rockets: Int
    var id: Date { weekStart }
}

/// Rockets 🚀 — the store currency.
/// Earned: 10 per hour studied, plus a bonus when a week ends (after Friday).
/// The balance is always worked out from your study history, minus what you spent.
extension AppStore {
    static let rocketsPerHour = 10

    /// Bonus for a finished week's study hours
    static func weeklyBonus(hours: Double) -> Int {
        switch hours {
        case let h where h > 30: 200
        case 30...: 150
        case 25...: 120
        case 20...: 100
        case 15...: 70
        case 10...: 50
        default: 0
        }
    }

    /// Bonus tiers, for showing the rules
    static let bonusTiers: [(hours: String, rockets: Int)] = [
        ("10h", 50), ("15h", 70), ("20h", 100), ("25h", 120), ("30h", 150), ("30h+", 200),
    ]

    /// Every finished week since you started, with its bonus
    func weekBonuses(now: Date = Date()) -> [WeekBonus] {
        guard let first = sessions.first?.start else { return [] }
        let current = Cal.weekStart(now)
        var week = Cal.weekStart(first)
        var out: [WeekBonus] = []
        while week < current {
            let next = Cal.persian.date(byAdding: .day, value: 7, to: week) ?? current
            let hours = studyTime(in: DateInterval(start: week, end: next)) / 3600
            out.append(WeekBonus(weekStart: week, hours: hours, rockets: Self.weeklyBonus(hours: hours)))
            week = next
        }
        return out
    }

    var rocketsFromStudy: Int { Int(sessions.reduce(0) { $0 + $1.duration } / 3600 * Double(Self.rocketsPerHour)) }
    var rocketsFromBonuses: Int { weekBonuses().reduce(0) { $0 + $1.rockets } }
    var rocketsSpent: Int { purchases.reduce(0) { $0 + $1.price } }
    var rocketBalance: Int { rocketsFromStudy + rocketsFromBonuses - rocketsSpent }

    func ownedCount(_ planetID: String) -> Int { purchases.filter { $0.planetID == planetID }.count }
    func placedCount(_ planetID: String) -> Int { galaxy.filter { $0.planetID == planetID }.count }
    /// Bought copies not currently in the galaxy (removed ones can be added back for free)
    func unplacedCount(_ planetID: String) -> Int { max(0, ownedCount(planetID) - placedCount(planetID)) }

    /// A solar system with room: the chosen one, or the first that isn't full
    private func systemWithRoom(_ systemID: UUID?) -> SolarSystem? {
        ensureHomeSystem()
        let chosen = systemID.flatMap { sid in solarSystems.first { $0.id == sid } }
        let target = chosen ?? solarSystems.first { planets(in: $0).count < SolarSystem.capacity }
        guard let target, planets(in: target).count < SolarSystem.capacity else { return nil }
        return target
    }

    /// Spend rockets on a store planet and put it in a solar system
    @discardableResult
    func buyPlanet(_ planetID: String, into systemID: UUID?) -> Bool {
        guard let p = PlanetCatalog.planet(planetID), p.isStoreItem, rocketBalance >= p.price,
              let target = systemWithRoom(systemID) else { return false }
        purchases.append(Purchase(planetID: planetID, price: p.price))
        galaxy.append(PlacedPlanet(planetID: planetID, systemID: target.id))
        return true
    }

    /// Put an already-bought planet back into the galaxy (free)
    @discardableResult
    func placeOwned(_ planetID: String, into systemID: UUID?) -> Bool {
        guard unplacedCount(planetID) > 0, let target = systemWithRoom(systemID) else { return false }
        galaxy.append(PlacedPlanet(planetID: planetID, systemID: target.id))
        return true
    }

    func hasRoom(in systemID: UUID?) -> Bool { systemWithRoomNoFix(systemID) }

    private func systemWithRoomNoFix(_ systemID: UUID?) -> Bool {
        let chosen = systemID.flatMap { sid in solarSystems.first { $0.id == sid } }
        if let chosen { return planets(in: chosen).count < SolarSystem.capacity }
        return solarSystems.contains { planets(in: $0).count < SolarSystem.capacity }
    }
}
