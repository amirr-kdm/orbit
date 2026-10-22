import Foundation

/// Rockets live on the server (supabase/wallet.sql): the balance, owned planets, refunds and claimed
/// Level Pass levels come from there, and buying / refunds / rewards are server calls — so editing the
/// data file can't change rockets and two devices can't spend the same rockets twice.
/// Until a member's wallet exists (the first time this app runs online it's moved over once), the old
/// local reckoning still counts.
extension AppStore {
    private var client: SupabaseClient { SupabaseClient.shared }

    private struct WalletState: Decodable {
        struct Owned: Decodable { let id: UUID; let planet: String; let price: Int; let at: Date }
        let started: Bool
        let balance: Int?
        let refunds_left: Int
        let levels: [Int]?
        let planets: [Owned]
    }

    /// Fetch the wallet (moving the local balance over the first time) and take in what it says
    func walletRefresh() async {
        guard SupabaseConfig.isConfigured, accountReady else { return }
        // offline: show the last balance the server gave this account
        if walletBalance == nil, let uid = await client.userID, let cached = UserDefaults.standard.object(forKey: "wallet|\(uid)") as? Int {
            walletBalance = cached
        }
        guard var state = await fetchWallet() else { return }
        if !state.started {
            // once: this app's balance, planets, claimed levels and used refunds become the opening wallet
            struct Start: Encodable {
                struct P: Encodable { let planetID: String; let price: Int; let date: String }
                let balance: Int; let planets: [P]; let levels: [Int]; let refunds_used: Int
            }
            let f = ISO8601DateFormatter()
            let body = Start(balance: rocketBalance,
                             planets: purchases.map { .init(planetID: $0.planetID, price: $0.price, date: f.string(from: $0.date)) },
                             levels: claimedLevels, refunds_used: refundsUsed)
            guard (try? await client.rpc("wallet_start", body)) != nil, let s = await fetchWallet() else { return }
            state = s
        }
        apply(state)
        // finished weeks' bonuses (the server works them out from your study and pays each once)
        var paid = false
        for back in 1...3 {
            guard let week = Cal.persian.date(byAdding: .day, value: -7 * back, to: Cal.weekStart(Date())) else { continue }
            struct W: Encodable { let week_start: String }
            if let data = try? await client.rpc("claim_week_bonus", W(week_start: Cal.dayKey(week))),
               let n = try? JSONDecoder().decode(Int.self, from: data), n > 0 { paid = true }
        }
        if paid, let s = await fetchWallet() { apply(s) }
    }

    private func fetchWallet() async -> WalletState? {
        guard let data = try? await client.rpc("my_wallet", [String: String]()) else { return nil }
        return try? SupabaseClient.decoder.decode(WalletState.self, from: data)
    }

    private func apply(_ s: WalletState) {
        guard s.started, let balance = s.balance else { return }
        walletBalance = balance
        walletRefundsLeft = s.refunds_left
        Task { if let uid = await client.userID { UserDefaults.standard.set(balance, forKey: "wallet|\(uid)") } }
        let owned = s.planets.map { Purchase(id: $0.id, planetID: $0.planet, price: $0.price, date: $0.at) }
        if owned.map(\.id) != purchases.map(\.id) { purchases = owned }
        let levels = Array(Set(s.levels ?? [])).sorted()
        if levels != claimedLevels.sorted() { claimedLevels = levels }
    }

    /// Whether rockets are handled by the server for this account
    var walletLive: Bool { walletBalance != nil }

    /// Buy a store planet. Returns an error message, or nil when it worked.
    func walletBuy(_ planetID: String) async -> String? {
        guard walletLive else { return buyPlanet(planetID) ? nil : "Not enough rockets yet." }
        do {
            _ = try await client.rpc("buy_planet", ["planet": planetID])
            await walletRefresh()
            return nil
        } catch {
            return (error as? SupabaseClient.APIError)?.message ?? "Connect to the internet to buy planets."
        }
    }

    /// Give one bought copy back for its full price (uses a refund ticket)
    func walletRefund(_ planetID: String) async -> String? {
        guard walletLive else { return refund(planetID) ? nil : "No refund tickets left." }
        guard let p = purchases.last(where: { $0.planetID == planetID && $0.price > 0 }) else { return "Nothing to refund." }
        do {
            _ = try await client.rpc("refund_planet", ["purchase": p.id.uuidString])
            if placedCount(planetID) > ownedCount(planetID) - 1, let j = galaxy.lastIndex(where: { $0.planetID == planetID }) {
                galaxy.remove(at: j)
            }
            await walletRefresh()
            if avatarPlanet == planetID && ownedCount(planetID) == 0 { avatarPlanet = nil }
            return nil
        } catch {
            return (error as? SupabaseClient.APIError)?.message ?? "Connect to the internet to refund."
        }
    }

    /// Take a Level Pass level's rewards
    func walletClaim(level: Int) async {
        guard walletLive else { claim(level: level); return }
        guard canClaim(level: level) else { return }
        // the server checks your level: make sure it has the latest
        if let uid = await client.userID {
            _ = try? await client.update("profiles?id=eq.\(uid.uuidString)", ["level": galaxyProgress().level])
        }
        struct L: Encodable { let lvl: Int }
        _ = try? await client.rpc("claim_level", L(lvl: level))
        await walletRefresh()
    }

    /// Last week's group prize, worked out by the server. True when it was paid now.
    func walletGroupWin(group: UUID, weekStart: Date) async -> Bool {
        guard walletLive else { return recordGroupWin(group: group, weekStart: weekStart) }
        struct G: Encodable { let g: String; let week_start: String }
        guard let data = try? await client.rpc("claim_group_win", G(g: group.uuidString, week_start: Cal.dayKey(weekStart))),
              (try? JSONDecoder().decode(Bool.self, from: data)) == true else { return false }
        await walletRefresh()
        return true
    }
}
