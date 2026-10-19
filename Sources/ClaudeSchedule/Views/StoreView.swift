import SwiftUI

/// The planet store: spend rockets earned by studying on 20 special planets
struct StoreView: View {
    @Environment(AppStore.self) private var store
    @State private var rarity: Rarity?
    @State private var opened: PlanetDef?

    private var items: [PlanetDef] {
        PlanetCatalog.store.filter { rarity == nil || $0.rarity == rarity }.sorted { $0.price < $1.price }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                wallet
                HStack {
                    Text("Planet Store").font(.title2.weight(.bold))
                    Spacer()
                    Picker("", selection: $rarity) {
                        Text("All").tag(Rarity?.none)
                        ForEach(Rarity.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 380)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    ForEach(items) { p in
                        StoreCard(planet: p).onTapGesture { opened = p }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Store")
        .sheet(item: $opened) { StoreDetail(planet: $0) }
    }

    // MARK: Wallet

    private var wallet: some View {
        let bonuses = store.weekBonuses()
        let week = store.galaxyProgress().weekHours
        let nextTier = [10.0, 15, 20, 25, 30, 30.01].first { week < $0 }
        return HStack(alignment: .top, spacing: 20) {
            HStack(spacing: 14) {
                RocketIcon(size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your rockets").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(store.rocketBalance.formatted()).font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit()
                        RocketIcon(size: 22)
                    }
                    Text("\(store.rocketsFromStudy.formatted()) from study · \(store.rocketsFromBonuses.formatted()) weekly bonuses · \(store.rocketsSpent.formatted()) spent")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label("\(AppStore.rocketsPerHour) rockets for every hour you study", systemImage: "clock")
                    .font(.callout.weight(.medium))
                Text("Weekly bonus when Friday ends:").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(AppStore.bonusTiers, id: \.hours) { t in
                        VStack(spacing: 1) {
                            Text(t.hours).font(.caption2.weight(.bold))
                            Text("+\(t.rockets)").font(.caption2.monospacedDigit())
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                    }
                }
                Text("This week: \(String(format: "%.1f", week))h"
                     + (nextTier.map { $0 > 30 ? " · study past 30h for +200" : " · \(String(format: "%.1f", $0 - week))h more for +\(AppStore.weeklyBonus(hours: $0))" }
                        ?? " · top bonus reached 🎉")
                     + (bonuses.last.map { " · last week +\($0.rockets)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#1E1B4B"), Color(hex: "#0F172A")], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}

/// One planet in the store grid
private struct StoreCard: View {
    @Environment(AppStore.self) private var store
    let planet: PlanetDef
    @State private var hovering = false

    var body: some View {
        let owned = store.ownedCount(planet.id)
        let affordable = store.rocketBalance >= planet.price
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !hovering)) { t in
                    PlanetView(planet: planet, size: 150, phase: t.date.timeIntervalSinceReferenceDate / 12)
                }
                .frame(maxWidth: .infinity)
                if owned > 0 {
                    Text("Owned ×\(owned)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.85)))
                }
            }
            Text(planet.name).font(.headline)
            HStack {
                Text(planet.rarity.title.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(planet.rarity.color.opacity(0.25)))
                    .foregroundStyle(planet.rarity.color)
                Spacer()
                HStack(spacing: 4) {
                    RocketIcon(size: 16)
                    Text(planet.price.formatted()).font(.callout.weight(.bold).monospacedDigit())
                }
                .opacity(affordable || owned > 0 ? 1 : 0.55)
            }
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RadialGradient(colors: [planet.rarity.color.opacity(hovering ? 0.35 : 0.22), Color(hex: "#0B1020")],
                                     center: .top, startRadius: 10, endRadius: 220))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(planet.rarity.color.opacity(hovering ? 0.8 : 0.35)))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(duration: 0.25), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

/// Planet details, buying and placing
private struct StoreDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planet: PlanetDef
    @State private var systemID: UUID?
    @State private var message: String?

    var body: some View {
        let balance = store.rocketBalance
        let owned = store.ownedCount(planet.id)
        let unplaced = store.unplacedCount(planet.id)
        HStack(alignment: .top, spacing: 24) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                PlanetView(planet: planet, size: 260, phase: t.date.timeIntervalSinceReferenceDate / 10)
            }
            .frame(width: 280, height: 280)
            .background(Circle().fill(RadialGradient(colors: [planet.rarity.color.opacity(0.3), .clear], center: .center, startRadius: 20, endRadius: 150)))

            VStack(alignment: .leading, spacing: 12) {
                Text(planet.rarity.title.uppercased())
                    .font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(planet.rarity.color)
                Text(planet.name).font(.largeTitle.weight(.bold))
                Text(planet.blurb).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    RocketIcon(size: 24)
                    Text(planet.price.formatted()).font(.title2.weight(.bold).monospacedDigit())
                    Text("· you have \(balance.formatted())").foregroundStyle(.secondary)
                }
                if owned > 0 {
                    Label("You own \(owned)\(unplaced > 0 ? " · \(unplaced) not in your galaxy" : "")", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                Picker("Add to", selection: $systemID) {
                    Text("First system with room").tag(UUID?.none)
                    ForEach(store.solarSystems) { s in
                        Text("\(s.name) (\(store.planets(in: s).count)/\(SolarSystem.capacity))").tag(Optional(s.id))
                    }
                }
                .frame(maxWidth: 320)

                HStack {
                    if unplaced > 0 {
                        Button("Add to Galaxy (owned)") {
                            message = store.placeOwned(planet.id, into: systemID) ? "Added to your galaxy ✨" : "That solar system is full."
                        }
                    }
                    Button {
                        if store.buyPlanet(planet.id, into: systemID) {
                            message = "\(planet.name) is yours! It's now in your galaxy 🎉"
                        } else {
                            message = store.rocketBalance < planet.price ? "Not enough rockets yet." : "That solar system is full. Pick another one."
                        }
                    } label: {
                        Label(balance >= planet.price ? (owned > 0 ? "Buy Another" : "Buy") : "Need \((planet.price - balance).formatted()) more",
                              systemImage: balance >= planet.price ? "cart.fill" : "lock.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(balance < planet.price || !store.hasRoom(in: systemID))
                    if owned > 0 {
                        Button(store.avatarPlanet == planet.id ? "Your Profile Picture" : "Use as Profile Picture") {
                            store.avatarPlanet = planet.id
                        }
                        .disabled(store.avatarPlanet == planet.id)
                    }
                }
                if !store.hasRoom(in: systemID) {
                    Text("Your solar systems are full. Create a new one in My Galaxy.").font(.caption).foregroundStyle(.orange)
                }
                if let message { Text(message).font(.callout.weight(.medium)).foregroundStyle(Color.accentColor) }
                Spacer()
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(28)
        .frame(width: 760, height: 400)
    }
}
