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
/// Earned: 25 per hour studied, plus a bonus when a week ends (after Friday).
/// The balance is always worked out from your study history, minus what you spent.
extension AppStore {
    static let rocketsPerHour = 25
    /// Everyone starts with this many rockets
    static let startingRockets = 200

    /// Bonus for a finished week's study hours
    static func weeklyBonus(hours: Double) -> Int {
        switch hours {
        case let h where h > 30: 400
        case 30...: 300
        case 25...: 240
        case 20...: 200
        case 15...: 140
        case 10...: 100
        default: 0
        }
    }

    /// Bonus tiers, for showing the rules
    static let bonusTiers: [(hours: String, rockets: Int)] = [
        ("10h", 100), ("15h", 140), ("20h", 200), ("25h", 240), ("30h", 300), ("30h+", 400),
    ]

    /// Every finished week since you started, with its bonus
    func weekBonuses(now: Date = Date()) -> [WeekBonus] {
        guard let first = sessions.first?.start else { return [] }
        let current = Cal.weekStart(now)
        var week = Cal.weekStart(first)
        var out: [WeekBonus] = []
        while week < current {
            let next = Cal.persian.date(byAdding: .day, value: 7, to: week) ?? current
            let hours = rewardTime(in: DateInterval(start: week, end: next)) / 3600
            out.append(WeekBonus(weekStart: week, hours: hours, rockets: Self.weeklyBonus(hours: hours)))
            week = next
        }
        return out
    }

    /// Until this day rockets came automatically for every hour studied; since then they come from the Level Pass
    static let levelPassStart = Cal.persian.date(from: DateComponents(calendar: Cal.persian, year: 1405, month: 7, day: 29)) ?? Date()
    var rocketsFromStudy: Int {
        Int(sessions.filter { $0.start < Self.levelPassStart }.reduce(0) { $0 + $1.duration } / 3600 * Double(Self.rocketsPerHour))
    }
    /// Rockets claimed on the Level Pass (25 per level)
    static let rocketsPerLevel = 25
    var rocketsFromLevels: Int { claimedLevels.count * Self.rocketsPerLevel }

    /// Levels 10, 20 … 60 also give a special planet
    static func levelPlanet(_ level: Int) -> String? { level % 10 == 0 && level > 0 ? "lv_t\(level / 10)" : nil }

    func canClaim(level: Int) -> Bool { level >= 1 && level <= galaxyProgress().level && !claimedLevels.contains(level) }

    /// Take a level's rewards: 25 rockets, plus a planet on every 10th level
    func claim(level: Int) {
        guard canClaim(level: level) else { return }
        claimedLevels.append(level)
        if let p = Self.levelPlanet(level) { purchases.append(Purchase(planetID: p, price: 0)) }
    }
    var rocketsFromBonuses: Int { weekBonuses().reduce(0) { $0 + $1.rockets } }
    var rocketsSpent: Int { purchases.reduce(0) { $0 + $1.price } }
    /// Prize for studying the most in a group in a finished week
    static let groupWinRockets = 100
    var rocketsFromGroups: Int { groupWins.count * Self.groupWinRockets }

    var rocketBalance: Int {
        Self.startingRockets + rocketGrant + rocketsFromStudy + rocketsFromLevels + rocketsFromBonuses + rocketsFromGroups - rocketsSpent
    }

    /// Record a weekly group win once; returns true if it's new
    @discardableResult
    func recordGroupWin(group: UUID, weekStart: Date) -> Bool {
        let key = "\(group.uuidString)|\(Cal.dayKey(weekStart))"
        guard !groupWins.contains(key) else { return false }
        groupWins.append(key)
        return true
    }

    /// Developer tool: make the balance exactly `target` (stored as a one-off grant)
    func setRocketBalance(_ target: Int) {
        rocketGrant += target - rocketBalance
    }

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

    /// Spend rockets on a store planet. It waits in My Galaxy → Your Store Planets until you place it.
    @discardableResult
    func buyPlanet(_ planetID: String) -> Bool {
        guard let p = PlanetCatalog.planet(planetID), p.isStoreItem, rocketBalance >= p.price else { return false }
        purchases.append(Purchase(planetID: planetID, price: p.price))
        return true
    }

    static let refundTickets = 3
    var refundTicketsLeft: Int { max(0, Self.refundTickets - refundsUsed) }

    /// Give one bought copy back for its full price (uses a refund ticket).
    /// If every copy is in the galaxy, one is taken out.
    @discardableResult
    func refund(_ planetID: String) -> Bool {
        guard refundTicketsLeft > 0, PlanetCatalog.planet(planetID)?.isStoreItem == true,
              let i = purchases.lastIndex(where: { $0.planetID == planetID }) else { return false }
        purchases.remove(at: i)
        refundsUsed += 1
        if placedCount(planetID) > ownedCount(planetID), let j = galaxy.lastIndex(where: { $0.planetID == planetID }) {
            galaxy.remove(at: j)
        }
        if avatarPlanet == planetID && ownedCount(planetID) == 0 { avatarPlanet = nil }
        return true
    }

    /// Store planets you own, for the My Galaxy shelf
    var ownedStorePlanets: [PlanetDef] {
        (PlanetCatalog.rewards + PlanetCatalog.store).filter { ownedCount($0.id) > 0 }
    }

    /// Put an already-bought planet back into the galaxy (free)
    @discardableResult
    func placeOwned(_ planetID: String, into systemID: UUID?) -> Bool {
        guard unplacedCount(planetID) > 0, galaxyProgress().credits > 0,
              let target = systemWithRoom(systemID) else { return false }
        galaxy.append(PlacedPlanet(planetID: planetID, systemID: target.id))
        return true
    }

    /// Move a placed planet to another solar system (if it has room)
    @discardableResult
    func movePlaced(_ id: UUID, to systemID: UUID) -> Bool {
        guard let i = galaxy.firstIndex(where: { $0.id == id }),
              let target = solarSystems.first(where: { $0.id == systemID }),
              planets(in: target).count < SolarSystem.capacity else { return false }
        galaxy[i].systemID = systemID
        return true
    }

    func hasRoom(in systemID: UUID?) -> Bool { systemWithRoomNoFix(systemID) }

    private func systemWithRoomNoFix(_ systemID: UUID?) -> Bool {
        let chosen = systemID.flatMap { sid in solarSystems.first { $0.id == sid } }
        if let chosen { return planets(in: chosen).count < SolarSystem.capacity }
        return solarSystems.contains { planets(in: $0).count < SolarSystem.capacity }
    }
}
