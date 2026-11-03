import SwiftUI

// MARK: - Planet definition

/// Everything needed to draw one planet. All 50 are drawn in code (no images).
struct PlanetDef: Identifiable, Hashable {
    enum Shape: Hashable {
        case circle, heart, star, cube, donut, diamond
        case hexagon, egg, cloud, flower, ghost, mushroom, crescent, gear, pyramid, burst
    }
    enum Pattern: Hashable {
        case plain, bands, spots, craters, swirl, cracks, checker, stripes, dots, waves
        case clouds, polarCaps, hexgrid, snowflakes, rainbow, mountains, pepperoni, sprinkles
    }
    enum Feature: Hashable {
        case catEars, whiskers, face, spikes, crown, leaf, eye, horns
        case wings, antenna, tentacles, bow, tree, flag, sunglasses, unicornHorn, volcanoes, halo, stem, fireWings
    }

    struct Ring: Hashable {
        var color: String
        var tilt: Double = -18
        var width: Double = 0.16
        var double = false
    }

    let id: String
    let name: String
    /// Level needed to unlock (1…10)
    let level: Int
    let blurb: String
    var shape: Shape = .circle
    /// Light → mid → dark
    let colors: [String]
    var pattern: Pattern = .plain
    /// Pattern / glow colour
    var accent: String = "#FFFFFF"
    var ring: Ring?
    var moons = 0
    var emoji: String?
    var features: [Feature] = []
    var glow = false
    /// Spacecraft orbiting it (store planets)
    var crafts: [Craft] = []
    /// Rocket price; 0 = a level planet (not sold in the store)
    var price = 0
    /// A picture (PNG in the app bundle) shown instead of a drawn planet
    var image: String?
    /// Little creatures / vehicles (emoji) walking back and forth on top of the planet
    var walkers: [String] = []
    /// Things standing on the planet (emoji): buildings, trees, castles…
    var landmarks: [String] = []

    /// Groups unlock every 5 levels: group 1 → level 1, group 2 → level 6, … group 10 → level 46
    var unlockLevel: Int { PlanetCatalog.unlockLevel(group: level) }
}

enum PlanetCatalog {
    static func planet(_ id: String?) -> PlanetDef? {
        guard let id else { return nil }
        return byID[id]
    }

    static let byID: [String: PlanetDef] = Dictionary(uniqueKeysWithValues: (all + store + rewards + gifts).map { ($0.id, $0) })

    static func unlocked(at level: Int) -> [PlanetDef] { all.filter { $0.unlockLevel <= level } }

    static func unlockLevel(group: Int) -> Int { 1 + (group - 1) * 5 }

    static let all: [PlanetDef] = [
        // Level 1 — Starter Worlds
        PlanetDef(id: "terra", name: "Terra Nova", level: 1, blurb: "Blue oceans, green lands, fluffy clouds.",
                  colors: ["#7DD3FC", "#2563EB", "#1E3A8A"], pattern: .clouds, accent: "#22C55E", moons: 1),
        PlanetDef(id: "ember", name: "Ember", level: 1, blurb: "Rivers of lava and two smoking volcanoes.",
                  colors: ["#78350F", "#451A03", "#1C0A00"], pattern: .cracks, accent: "#FB923C",
                  features: [.volcanoes], glow: true),
        PlanetDef(id: "frost", name: "Frostbite", level: 1, blurb: "Snowflakes fall forever here.",
                  colors: ["#F0F9FF", "#BAE6FD", "#38BDF8"], pattern: .snowflakes, accent: "#FFFFFF"),
        PlanetDef(id: "saturnella", name: "Saturnella", level: 1, blurb: "Sandy bands and an elegant ring.",
                  colors: ["#FDE68A", "#D97706", "#92400E"], pattern: .bands, accent: "#FEF3C7",
                  ring: .init(color: "#FCD34D")),
        PlanetDef(id: "lunaris", name: "Lunaris", level: 1, blurb: "A sleepy grey crescent full of craters.",
                  shape: .crescent, colors: ["#F1F5F9", "#9CA3AF", "#4B5563"], pattern: .craters, accent: "#374151"),

        // Level 2 — Explorer
        PlanetDef(id: "bubblegum", name: "Bubblegum", level: 2, blurb: "A fluffy pink cloud with a bow on top.",
                  shape: .cloud, colors: ["#FBCFE8", "#F472B6", "#9D174D"], pattern: .swirl, accent: "#FDF2F8",
                  features: [.bow]),
        PlanetDef(id: "jade", name: "Jade Jungle", level: 2, blurb: "One giant tree holds the whole world together.",
                  colors: ["#86EFAC", "#16A34A", "#14532D"], pattern: .mountains, accent: "#052E16", features: [.tree]),
        PlanetDef(id: "neptuno", name: "Neptuno", level: 2, blurb: "Wild blue storms and two loyal moons.",
                  colors: ["#93C5FD", "#1D4ED8", "#172554"], pattern: .bands, accent: "#BFDBFE", moons: 2),
        PlanetDef(id: "rust", name: "Rust Rover", level: 2, blurb: "Red dust, dry valleys — someone planted a flag.",
                  colors: ["#FDBA74", "#C2410C", "#7C2D12"], pattern: .craters, accent: "#431407", moons: 1, features: [.flag]),
        PlanetDef(id: "citrus", name: "Citrus", level: 2, blurb: "Smells like oranges. Probably.",
                  colors: ["#FED7AA", "#F97316", "#C2410C"], pattern: .dots, accent: "#FFEDD5", features: [.leaf]),

        // Level 3 — Wild Worlds
        PlanetDef(id: "dino", name: "Dino Prime", level: 3, blurb: "A dinosaur egg the size of a planet. It's hatching!",
                  shape: .egg, colors: ["#ECFCCB", "#A3E635", "#4D7C0F"], pattern: .spots, accent: "#3F6212", emoji: "art:dino"),
        PlanetDef(id: "donut", name: "Donut World", level: 3, blurb: "A planet with a hole. Sprinkles included.",
                  shape: .donut, colors: ["#FBCFE8", "#F472B6", "#BE185D"], pattern: .sprinkles, accent: "#FDE047"),
        PlanetDef(id: "choco", name: "Choco Moon", level: 3, blurb: "A chocolate mushroom with candy spots.",
                  shape: .mushroom, colors: ["#D6A06B", "#78350F", "#3B1A08"], pattern: .spots, accent: "#FDE68A"),
        PlanetDef(id: "aurora", name: "Aurora", level: 3, blurb: "Northern lights dance under a golden halo.",
                  colors: ["#A78BFA", "#6D28D9", "#2E1065"], pattern: .waves, accent: "#6EE7B7", features: [.halo], glow: true),
        PlanetDef(id: "honey", name: "Honeycomb", level: 3, blurb: "A hexagon hive, buzzing and golden.",
                  shape: .hexagon, colors: ["#FEF08A", "#EAB308", "#854D0E"], pattern: .hexgrid, accent: "#713F12", emoji: "art:bee"),

        // Level 4 — Shapes & Snacks
        PlanetDef(id: "kitty", name: "Kitty Planet", level: 4, blurb: "Purrs when you study.",
                  colors: ["#FED7AA", "#FB923C", "#9A3412"], pattern: .stripes, accent: "#7C2D12",
                  features: [.catEars, .face, .whiskers]),
        PlanetDef(id: "pizza", name: "Pizza Planet", level: 4, blurb: "Extra cheese, extra gravity.",
                  colors: ["#FEF08A", "#FBBF24", "#B45309"], pattern: .pepperoni, accent: "#DC2626",
                  ring: .init(color: "#D97706", tilt: -8, width: 0.2)),
        PlanetDef(id: "cube9", name: "Cube-9", level: 4, blurb: "Scientists still argue about this one.",
                  shape: .cube, colors: ["#A5F3FC", "#0891B2", "#164E63"], pattern: .checker, accent: "#CFFAFE", moons: 1),
        PlanetDef(id: "heartbeat", name: "Heartbeat", level: 4, blurb: "A flying heart. Made of pure motivation.",
                  shape: .heart, colors: ["#FDA4AF", "#E11D48", "#881337"], accent: "#FFE4E6", features: [.wings], glow: true),
        PlanetDef(id: "starforge", name: "Starforge", level: 4, blurb: "A star that decided to be a planet.",
                  shape: .star, colors: ["#FEF9C3", "#FACC15", "#A16207"], accent: "#FDE047", features: [.face], glow: true),

        // Level 5 — Deep Space
        PlanetDef(id: "melon", name: "Watermelon", level: 5, blurb: "Juicy stripes from pole to pole.",
                  colors: ["#86EFAC", "#15803D", "#14532D"], pattern: .stripes, accent: "#052E16", moons: 1, features: [.stem]),
        PlanetDef(id: "disco", name: "Disco Ball", level: 5, blurb: "Every night is party night. Shades on.",
                  colors: ["#F8FAFC", "#94A3B8", "#334155"], pattern: .checker, accent: "#E0E7FF",
                  features: [.sunglasses], glow: true),
        PlanetDef(id: "oceaneye", name: "Ocean Eye", level: 5, blurb: "It's watching you study. Good.",
                  colors: ["#99F6E4", "#0D9488", "#134E4A"], pattern: .waves, accent: "#CCFBF1", features: [.eye]),
        PlanetDef(id: "spiral", name: "Spiral", level: 5, blurb: "A tiny galaxy wrapped in a planet.",
                  colors: ["#C4B5FD", "#7C3AED", "#1E1B4B"], pattern: .swirl, accent: "#F0ABFC",
                  ring: .init(color: "#E9D5FF", tilt: 30, width: 0.1, double: true)),
        PlanetDef(id: "coral", name: "Coral Bloom", level: 5, blurb: "A flower world where fish swim in the petals.",
                  shape: .flower, colors: ["#FECDD3", "#FB7185", "#BE123C"], pattern: .dots, accent: "#FEF3C7", emoji: "art:fish"),

        // Level 6 — Creatures
        PlanetDef(id: "trex", name: "Stego Rock", level: 6, blurb: "Rocky, spiky, and very old.",
                  colors: ["#D6D3D1", "#78716C", "#292524"], pattern: .craters, accent: "#1C1917", emoji: "art:stego", features: [.spikes]),
        PlanetDef(id: "octo", name: "Octo World", level: 6, blurb: "Eight arms, one ocean, many hugs.",
                  colors: ["#C4B5FD", "#8B5CF6", "#4C1D95"], pattern: .spots, accent: "#DDD6FE",
                  features: [.tentacles, .face]),
        PlanetDef(id: "mushroom", name: "Mushroom Kingdom", level: 6, blurb: "Red cap, white spots, good vibes.",
                  shape: .mushroom, colors: ["#FCA5A5", "#DC2626", "#7F1D1D"], pattern: .spots, accent: "#FFFFFF", features: [.face]),
        PlanetDef(id: "candycane", name: "Candy Cane", level: 6, blurb: "Peppermint fresh, all year long.",
                  colors: ["#FFFFFF", "#FECACA", "#F87171"], pattern: .stripes, accent: "#DC2626",
                  ring: .init(color: "#86EFAC", tilt: -25, width: 0.1), features: [.bow]),
        PlanetDef(id: "crystal", name: "Crystal Shard", level: 6, blurb: "Shines in every colour of light.",
                  shape: .diamond, colors: ["#CFFAFE", "#22D3EE", "#0E7490"], pattern: .rainbow, accent: "#FFFFFF", glow: true),

        // Level 7 — Spooky & Bright
        PlanetDef(id: "robo", name: "Robo Core", level: 7, blurb: "Beep boop. Fully automated.",
                  shape: .cube, colors: ["#E2E8F0", "#64748B", "#1E293B"], pattern: .checker, accent: "#38BDF8",
                  emoji: "art:robot", features: [.antenna]),
        PlanetDef(id: "ghost", name: "Ghostly", level: 7, blurb: "Boo! (It's friendly.)",
                  shape: .ghost, colors: ["#FFFFFF", "#E0E7FF", "#A5B4FC"], accent: "#C7D2FE", features: [.face], glow: true),
        PlanetDef(id: "pumpkin", name: "Pumpkin", level: 7, blurb: "Spooky season, forever.",
                  colors: ["#FDBA74", "#EA580C", "#7C2D12"], pattern: .bands, accent: "#9A3412", features: [.face, .stem]),
        PlanetDef(id: "twinvolcano", name: "Twin Volcano", level: 7, blurb: "A lava pyramid with two moons and zero chill.",
                  shape: .pyramid, colors: ["#57534E", "#292524", "#0C0A09"], pattern: .cracks, accent: "#EF4444",
                  moons: 2, glow: true),
        PlanetDef(id: "rainbow", name: "Rainbow", level: 7, blurb: "All the colours, all the time.",
                  colors: ["#FFFFFF", "#E0F2FE", "#BAE6FD"], pattern: .rainbow, accent: "#FFFFFF",
                  ring: .init(color: "#FFFFFF", tilt: 12, width: 0.08), features: [.face]),

        // Level 8 — Cosmic Wonders
        PlanetDef(id: "blackhole", name: "Black Hole", level: 8, blurb: "Swallows distractions whole.",
                  colors: ["#1F2937", "#030712", "#000000"], accent: "#F59E0B",
                  ring: .init(color: "#FB923C", tilt: -10, width: 0.24, double: true), glow: true),
        PlanetDef(id: "snowglobe", name: "Snow Globe", level: 8, blurb: "A snowman lives inside. He's very happy.",
                  colors: ["#F0F9FF", "#BAE6FD", "#38BDF8"], pattern: .polarCaps, accent: "#FFFFFF", emoji: "art:snowman"),
        PlanetDef(id: "dragonegg", name: "Dragon Egg", level: 8, blurb: "Something with wings is about to hatch…",
                  shape: .egg, colors: ["#6EE7B7", "#059669", "#064E3B"], pattern: .hexgrid, accent: "#FDE047",
                  features: [.spikes, .wings], glow: true),
        PlanetDef(id: "whale", name: "Cosmic Whale", level: 8, blurb: "Swims through space, singing.",
                  colors: ["#BFDBFE", "#3B82F6", "#1E3A8A"], pattern: .waves, accent: "#DBEAFE", moons: 1, emoji: "art:whale"),
        PlanetDef(id: "goldchild", name: "Golden Gear", level: 8, blurb: "The clockwork that keeps time moving.",
                  shape: .gear, colors: ["#FEF3C7", "#F59E0B", "#78350F"], pattern: .swirl, accent: "#FFFBEB", glow: true),

        // Level 9 — Royal Orbit
        PlanetDef(id: "royale", name: "Saturn Royale", level: 9, blurb: "Rings fit for a king.",
                  colors: ["#E9D5FF", "#A855F7", "#581C87"], pattern: .bands, accent: "#F3E8FF",
                  ring: .init(color: "#FDE047", tilt: -16, width: 0.14, double: true), features: [.crown]),
        PlanetDef(id: "neongrid", name: "Neon Pyramid", level: 9, blurb: "Straight out of a synthwave song.",
                  shape: .pyramid, colors: ["#312E81", "#1E1B4B", "#020617"], pattern: .checker, accent: "#F0ABFC", glow: true),
        PlanetDef(id: "cheese", name: "Moon Cheese", level: 9, blurb: "The rumours were true.",
                  shape: .crescent, colors: ["#FEF08A", "#FACC15", "#CA8A04"], pattern: .craters, accent: "#A16207",
                  features: [.face]),
        PlanetDef(id: "alien", name: "Alien Hive", level: 9, blurb: "We come in peace. Mostly.",
                  colors: ["#BBF7D0", "#22C55E", "#14532D"], pattern: .dots, accent: "#DCFCE7", emoji: "art:alien", features: [.antenna]),
        PlanetDef(id: "ufo", name: "UFO Station", level: 9, blurb: "Parking spot for flying saucers.",
                  colors: ["#E2E8F0", "#94A3B8", "#475569"], pattern: .bands, accent: "#22D3EE",
                  ring: .init(color: "#67E8F9", tilt: 0, width: 0.1), emoji: "art:ufo"),

        // Level 10 — Legendary
        PlanetDef(id: "phoenix", name: "Phoenix", level: 10, blurb: "Reborn from fire every week.",
                  colors: ["#FDE047", "#F97316", "#991B1B"], pattern: .swirl, accent: "#FEF08A",
                  emoji: "art:flame", features: [.fireWings], glow: true),
        PlanetDef(id: "unicorn", name: "Unicorn Dream", level: 10, blurb: "A pastel cloud with a magic horn.",
                  shape: .cloud, colors: ["#FBCFE8", "#C4B5FD", "#93C5FD"], pattern: .rainbow, accent: "#FFFFFF",
                  features: [.unicornHorn, .face], glow: true),
        PlanetDef(id: "diamondheart", name: "Diamond Heart", level: 10, blurb: "Unbreakable, like your focus.",
                  shape: .heart, colors: ["#E0F2FE", "#7DD3FC", "#0369A1"], pattern: .checker, accent: "#FFFFFF",
                  features: [.crown], glow: true),
        PlanetDef(id: "infinity", name: "Infinity Loop", level: 10, blurb: "Study, sleep, repeat.",
                  shape: .donut, colors: ["#F0ABFC", "#A855F7", "#3B0764"], pattern: .swirl, accent: "#FDF4FF",
                  moons: 2, features: [.halo], glow: true),
        PlanetDef(id: "claude", name: "Claude's Cosmos", level: 10, blurb: "The final reward. ✨",
                  shape: .burst, colors: ["#FED7AA", "#D97757", "#7C2D12"], pattern: .swirl, accent: "#FFEDD5",
                  ring: .init(color: "#FED7AA", tilt: -20, width: 0.12, double: true), moons: 3, features: [.face], glow: true),
    ]
}

// MARK: - Renderer

/// Draws a planet from its definition. `phase` turns the moons (0…1).
struct PlanetView: View {
    let planet: PlanetDef
    var size: CGFloat = 64
    var phase: Double = 0
    var locked = false

    var body: some View {
        Canvas { ctx, canvasSize in
            PlanetPainter.draw(planet, in: &ctx, size: canvasSize, phase: phase)
        }
        .frame(width: size, height: size)
        .saturation(locked ? 0 : 1)
        .opacity(locked ? 0.35 : 1)
        .overlay {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
        }
    }
}

enum PlanetPainter {
    static func draw(_ p: PlanetDef, in ctx: inout GraphicsContext, size: CGSize, phase: Double) {
        let s = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = s * 0.3
        if let name = p.image, let img = bundleImage(name) {
            drawPicture(img, p: p, ctx: &ctx, c: c, r: r, phase: phase)
            return
        }
        var rng = SeededRandom(seed: p.id)
        let accent = Color(hex: p.accent)
        let c0 = Color(hex: p.colors[0]), c1 = Color(hex: p.colors[1]), c2 = Color(hex: p.colors[2])
        let eo = FillStyle(eoFill: p.shape == .donut)

        if p.glow {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                     with: .radialGradient(Gradient(colors: [accent.opacity(0.45), accent.opacity(0)]),
                                           center: c, startRadius: r * 0.8, endRadius: r * 1.6))
        }
        if let ring = p.ring { drawRing(ring, ctx: &ctx, c: c, r: r, front: false, phase: phase) }

        for f in p.features { drawBehind(f, ctx: &ctx, c: c, r: r, c1: c1, accent: accent) }

        let body = shapePath(p.shape, c: c, r: r)
        if p.shape == .mushroom {
            let stem = Path(roundedRect: CGRect(x: c.x - r * 0.32, y: c.y + r * 0.05, width: r * 0.64, height: r * 0.85),
                            cornerRadius: r * 0.2)
            ctx.fill(stem, with: .linearGradient(Gradient(colors: [Color(hex: "#FEF3C7"), Color(hex: "#D6D3D1")]),
                                                 startPoint: CGPoint(x: c.x - r * 0.3, y: c.y), endPoint: CGPoint(x: c.x + r * 0.3, y: c.y)))
        }
        ctx.fill(body, with: .radialGradient(Gradient(colors: [c0, c1, c2]),
                                            center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4),
                                            startRadius: 0, endRadius: r * 1.5), style: eo)

        ctx.drawLayer { layer in
            layer.clip(to: body, style: eo)
            drawPattern(p.pattern, ctx: &layer, c: c, r: r, accent: accent, rng: &rng)
            layer.fill(body, with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.5)]),
                                                  center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35),
                                                  startRadius: r * 0.5, endRadius: r * 1.6), style: eo)
            layer.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.72, width: r * 0.55, height: r * 0.35)),
                       with: .color(.white.opacity(0.28)))
        }

        if let emoji = p.emoji, emoji.hasPrefix("art:") {
            drawArt(String(emoji.dropFirst(4)), ctx: &ctx, c: c, r: r, phase: phase)
        } else if let emoji = p.emoji {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.58, width: r * 1.24, height: r * 1.24)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.45), .white.opacity(0)]),
                                           center: c, startRadius: 0, endRadius: r * 0.65))
            var e = ctx
            e.addFilter(.shadow(color: .black.opacity(0.45), radius: r * 0.06, y: r * 0.03))
            e.draw(Text(emoji).font(.system(size: r * 1.15)), at: CGPoint(x: c.x, y: c.y + r * 0.05))
        }

        for f in p.features { drawFront(f, ctx: &ctx, c: c, r: r, accent: accent, shape: p.shape) }

        if !p.landmarks.isEmpty || !p.walkers.isEmpty { drawSurface(p, ctx: &ctx, c: c, r: r, phase: phase) }

        if let ring = p.ring { drawRing(ring, ctx: &ctx, c: c, r: r, front: true, phase: phase) }

        if !p.crafts.isEmpty { drawCrafts(p.crafts, ctx: &ctx, c: c, r: r, phase: phase) }

        for i in 0..<p.moons {
            let a = (Double(i) / Double(max(1, p.moons)) + phase) * .pi * 2 + 0.6
            let mp = CGPoint(x: c.x + cos(a) * r * 1.45, y: c.y + sin(a) * r * 0.55 - r * 0.2)
            let mr = r * (0.16 + 0.04 * Double(i % 2))
            ctx.fill(Path(ellipseIn: CGRect(x: mp.x - mr, y: mp.y - mr, width: mr * 2, height: mr * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: "#F1F5F9"), Color(hex: "#64748B")]),
                                           center: CGPoint(x: mp.x - mr * 0.4, y: mp.y - mr * 0.4),
                                           startRadius: 0, endRadius: mr * 1.6))
        }
    }

    private static func pt(_ c: CGPoint, _ radius: CGFloat, _ a: Double) -> CGPoint {
        CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
    }

    private static func polygon(_ c: CGPoint, _ points: [(CGFloat, Double)]) -> Path {
        var p = Path()
        for (i, (rad, a)) in points.enumerated() {
            i == 0 ? p.move(to: pt(c, rad, a)) : p.addLine(to: pt(c, rad, a))
        }
        p.closeSubpath()
        return p
    }

    /// Regular polygon / star: points alternate between outer and inner radius
    private static func regular(_ c: CGPoint, count: Int, outer: CGFloat, inner: CGFloat, start: Double = 0) -> Path {
        var pts: [(CGFloat, Double)] = []
        for i in 0..<count {
            let radius: CGFloat = i % 2 == 0 ? outer : inner
            let angle: Double = Double(i) / Double(count) * .pi * 2 + start
            pts.append((radius, angle))
        }
        return polygon(c, pts)
    }

    // MARK: Shapes

    static func shapePath(_ shape: PlanetDef.Shape, c: CGPoint, r: CGFloat) -> Path {
        switch shape {
        case .circle:
            return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        case .donut:
            var p = Path(ellipseIn: CGRect(x: c.x - r * 1.05, y: c.y - r * 1.05, width: r * 2.1, height: r * 2.1))
            p.addEllipse(in: CGRect(x: c.x - r * 0.4, y: c.y - r * 0.4, width: r * 0.8, height: r * 0.8))
            return p
        case .cube:
            return Path(roundedRect: CGRect(x: c.x - r * 0.88, y: c.y - r * 0.88, width: r * 1.76, height: r * 1.76),
                        cornerRadius: r * 0.3)
        case .diamond:
            return polygon(c, [(r * 1.15, -.pi / 2), (r * 0.92, -0.2), (r * 1.15, .pi / 2), (r * 0.92, .pi + 0.2)])
        case .hexagon:
            return regular(c, count: 6, outer: r * 1.05, inner: r * 1.05)
        case .pyramid:
            return polygon(c, [(r * 1.2, -.pi / 2), (r * 1.15, .pi / 6), (r * 1.15, .pi * 5 / 6)])
        case .star:
            return regular(c, count: 10, outer: r * 1.2, inner: r * 0.62, start: -.pi / 2)
        case .burst:
            return regular(c, count: 24, outer: r * 1.15, inner: r * 0.82)
        case .gear:
            var pts: [(CGFloat, Double)] = []
            for i in 0..<10 {
                let a = Double(i) / 10 * .pi * 2
                pts += [(r * 0.88, a - 0.2), (r * 1.12, a - 0.12), (r * 1.12, a + 0.12), (r * 0.88, a + 0.2)]
            }
            return polygon(c, pts)
        case .egg:
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - r * 1.2))
            p.addCurve(to: CGPoint(x: c.x, y: c.y + r * 0.95), control1: CGPoint(x: c.x + r * 1.15, y: c.y - r * 1.2),
                       control2: CGPoint(x: c.x + r * 1.15, y: c.y + r * 0.95))
            p.addCurve(to: CGPoint(x: c.x, y: c.y - r * 1.2), control1: CGPoint(x: c.x - r * 1.15, y: c.y + r * 0.95),
                       control2: CGPoint(x: c.x - r * 1.15, y: c.y - r * 1.2))
            return p
        case .cloud:
            var p = Path()
            for (dx, dy, rr) in [(-0.55, 0.15, 0.6), (0.0, -0.25, 0.75), (0.55, 0.1, 0.62), (-0.1, 0.35, 0.62), (0.35, 0.38, 0.5)] {
                p.addEllipse(in: CGRect(x: c.x + r * (dx - rr), y: c.y + r * (dy - rr), width: r * rr * 2, height: r * rr * 2))
            }
            return p
        case .flower:
            var p = Path()
            for i in 0..<6 {
                let pc = pt(c, r * 0.6, Double(i) / 6 * .pi * 2)
                p.addEllipse(in: CGRect(x: pc.x - r * 0.52, y: pc.y - r * 0.52, width: r * 1.04, height: r * 1.04))
            }
            p.addEllipse(in: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: r * 1.2, height: r * 1.2))
            return p
        case .ghost:
            var p = Path()
            p.move(to: CGPoint(x: c.x - r * 0.9, y: c.y + r * 1.05))
            p.addLine(to: CGPoint(x: c.x - r * 0.9, y: c.y - r * 0.1))
            p.addArc(center: CGPoint(x: c.x, y: c.y - r * 0.1), radius: r * 0.9, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: c.x + r * 0.9, y: c.y + r * 1.05))
            for k in 0..<4 {
                let x0 = c.x + r * 0.9 - Double(k) * r * 0.45
                p.addQuadCurve(to: CGPoint(x: x0 - r * 0.45, y: c.y + r * 1.05), control: CGPoint(x: x0 - r * 0.225, y: c.y + r * 0.7))
            }
            p.closeSubpath()
            return p
        case .mushroom:
            var p = Path()
            p.move(to: CGPoint(x: c.x - r * 1.15, y: c.y + r * 0.15))
            p.addCurve(to: CGPoint(x: c.x + r * 1.15, y: c.y + r * 0.15), control1: CGPoint(x: c.x - r * 1.15, y: c.y - r * 1.35),
                       control2: CGPoint(x: c.x + r * 1.15, y: c.y - r * 1.35))
            p.addQuadCurve(to: CGPoint(x: c.x - r * 1.15, y: c.y + r * 0.15), control: CGPoint(x: c.x, y: c.y + r * 0.4))
            return p
        case .crescent:
            let full = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let bite = Path(ellipseIn: CGRect(x: c.x - r * 0.25, y: c.y - r * 1.2, width: r * 1.9, height: r * 1.9))
            return full.subtracting(bite)
        case .heart:
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y + r * 1.0))
            p.addCurve(to: CGPoint(x: c.x - r * 1.1, y: c.y - r * 0.35), control1: CGPoint(x: c.x - r * 0.55, y: c.y + r * 0.55),
                       control2: CGPoint(x: c.x - r * 1.15, y: c.y + r * 0.15))
            p.addArc(center: CGPoint(x: c.x - r * 0.55, y: c.y - r * 0.4), radius: r * 0.56,
                     startAngle: .degrees(185), endAngle: .degrees(0), clockwise: false)
            p.addArc(center: CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.4), radius: r * 0.56,
                     startAngle: .degrees(180), endAngle: .degrees(355), clockwise: false)
            p.addCurve(to: CGPoint(x: c.x, y: c.y + r * 1.0), control1: CGPoint(x: c.x + r * 1.15, y: c.y + r * 0.15),
                       control2: CGPoint(x: c.x + r * 0.55, y: c.y + r * 0.55))
            return p
        }
    }

    // MARK: Features

    private static func drawBehind(_ f: PlanetDef.Feature, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                   c1: Color, accent: Color) {
        switch f {
        case .catEars:
            for d in [-1.0, 1.0] {
                var ear = Path()
                ear.move(to: CGPoint(x: c.x + d * r * 0.25, y: c.y - r * 0.85))
                ear.addLine(to: CGPoint(x: c.x + d * r * 0.85, y: c.y - r * 1.35))
                ear.addLine(to: CGPoint(x: c.x + d * r * 0.9, y: c.y - r * 0.45))
                ear.closeSubpath()
                ctx.fill(ear, with: .color(c1))
            }
        case .spikes:
            for i in 0..<12 {
                let a = Double(i) / 12 * .pi * 2
                ctx.fill(polygon(c, [(r * 0.9, a - 0.18), (r * 1.32, a), (r * 0.9, a + 0.18)]), with: .color(accent.opacity(0.9)))
            }
        case .horns, .antenna:
            for d in [-1.0, 1.0] {
                var h = Path()
                h.move(to: CGPoint(x: c.x + d * r * 0.35, y: c.y - r * 0.8))
                h.addQuadCurve(to: CGPoint(x: c.x + d * r * 0.7, y: c.y - r * 1.45), control: CGPoint(x: c.x + d * r * 0.2, y: c.y - r * 1.35))
                ctx.stroke(h, with: .color(f == .antenna ? Color(hex: "#94A3B8") : c1),
                           style: StrokeStyle(lineWidth: r * 0.09, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + d * r * 0.7 - r * 0.12, y: c.y - r * 1.57, width: r * 0.24, height: r * 0.24)),
                         with: .color(f == .antenna ? Color(hex: "#F43F5E") : accent))
            }
        case .wings, .fireWings:
            for d in [-1.0, 1.0] {
                var w = Path()
                w.move(to: CGPoint(x: c.x + d * r * 0.6, y: c.y - r * 0.1))
                w.addCurve(to: CGPoint(x: c.x + d * r * 1.75, y: c.y - r * 0.9),
                           control1: CGPoint(x: c.x + d * r * 1.0, y: c.y - r * 0.9), control2: CGPoint(x: c.x + d * r * 1.4, y: c.y - r * 1.2))
                w.addCurve(to: CGPoint(x: c.x + d * r * 0.7, y: c.y + r * 0.4),
                           control1: CGPoint(x: c.x + d * r * 1.7, y: c.y - r * 0.1), control2: CGPoint(x: c.x + d * r * 1.3, y: c.y + r * 0.5))
                w.closeSubpath()
                let colors: [Color] = f == .fireWings ? [Color(hex: "#FDE047"), Color(hex: "#EF4444")] : [.white, Color(hex: "#E0E7FF")]
                ctx.fill(w, with: .linearGradient(Gradient(colors: colors), startPoint: c,
                                                  endPoint: CGPoint(x: c.x + d * r * 1.7, y: c.y - r * 0.9)))
                for k in 1...2 {
                    var feather = Path()
                    feather.move(to: CGPoint(x: c.x + d * r * 0.75, y: c.y))
                    feather.addLine(to: CGPoint(x: c.x + d * r * (1.0 + 0.25 * Double(k)), y: c.y - r * (0.35 + 0.15 * Double(k))))
                    ctx.stroke(feather, with: .color(.black.opacity(0.12)), lineWidth: r * 0.04)
                }
            }
        case .tentacles:
            for i in 0..<6 {
                let x = c.x - r * 0.75 + Double(i) * r * 0.3
                var t = Path()
                t.move(to: CGPoint(x: x, y: c.y + r * 0.6))
                t.addCurve(to: CGPoint(x: x + (i % 2 == 0 ? -1 : 1) * r * 0.25, y: c.y + r * 1.45),
                           control1: CGPoint(x: x + r * 0.3, y: c.y + r * 0.95), control2: CGPoint(x: x - r * 0.3, y: c.y + r * 1.15))
                ctx.stroke(t, with: .color(c1), style: StrokeStyle(lineWidth: r * 0.17, lineCap: .round))
            }
        case .tree:
            // the whole tree has to fit inside the picture (the top edge is 1.67 r above the centre)
            ctx.fill(Path(roundedRect: CGRect(x: c.x - r * 0.08, y: c.y - r * 1.28, width: r * 0.16, height: r * 0.4), cornerRadius: r * 0.04),
                     with: .color(Color(hex: "#78350F")))
            for (dx, dy, rr) in [(0.0, -1.36, 0.27), (-0.2, -1.22, 0.2), (0.2, -1.22, 0.2)] {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + r * (dx - rr), y: c.y + r * (dy - rr), width: r * rr * 2, height: r * rr * 2)),
                         with: .color(Color(hex: "#22C55E")))
            }
        case .volcanoes:
            for (dx, h) in [(-0.45, 0.45), (0.35, 0.6)] {
                let base = CGPoint(x: c.x + dx * r, y: c.y - r * 0.8)
                ctx.fill(polygon(base, [(r * 0.35, .pi), (r * h, -.pi / 2), (r * 0.35, 0)]), with: .color(Color(hex: "#44403C")))
                ctx.fill(Path(ellipseIn: CGRect(x: base.x - r * 0.1, y: base.y - r * h - r * 0.12, width: r * 0.2, height: r * 0.16)),
                         with: .color(Color(hex: "#F97316")))
            }
        case .halo:
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.65, y: c.y - r * 1.42, width: r * 1.3, height: r * 0.36)),
                       with: .color(Color(hex: "#FDE047")), lineWidth: r * 0.1)
        case .unicornHorn:
            var h = Path()
            h.move(to: CGPoint(x: c.x - r * 0.18, y: c.y - r * 0.75))
            h.addLine(to: CGPoint(x: c.x + r * 0.05, y: c.y - r * 1.7))
            h.addLine(to: CGPoint(x: c.x + r * 0.22, y: c.y - r * 0.75))
            h.closeSubpath()
            ctx.fill(h, with: .linearGradient(Gradient(colors: [Color(hex: "#FDE68A"), Color(hex: "#F472B6")]),
                                             startPoint: CGPoint(x: c.x, y: c.y - r * 1.7), endPoint: CGPoint(x: c.x, y: c.y - r * 0.75)))
        case .stem:
            ctx.fill(Path(roundedRect: CGRect(x: c.x - r * 0.08, y: c.y - r * 1.3, width: r * 0.16, height: r * 0.45), cornerRadius: r * 0.05),
                     with: .color(Color(hex: "#65A30D")))
        default:
            break
        }
    }

    private static func drawFront(_ f: PlanetDef.Feature, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                  accent: Color, shape: PlanetDef.Shape) {
        let fy = shape == .mushroom ? c.y - r * 0.3 : c.y
        switch f {
        case .face:
            for d in [-1.0, 1.0] {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + d * r * 0.32 - r * 0.09, y: fy - r * 0.25, width: r * 0.18, height: r * 0.26)),
                         with: .color(.black.opacity(0.75)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + d * r * 0.55 - r * 0.12, y: fy + r * 0.05, width: r * 0.24, height: r * 0.14)),
                         with: .color(Color(hex: "#F472B6").opacity(0.45)))
            }
            var smile = Path()
            smile.addArc(center: CGPoint(x: c.x, y: fy + r * 0.05), radius: r * 0.26,
                         startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            ctx.stroke(smile, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: r * 0.07, lineCap: .round))
        case .whiskers:
            for d in [-1.0, 1.0] {
                for k in -1...1 {
                    var w = Path()
                    w.move(to: CGPoint(x: c.x + d * r * 0.4, y: c.y + r * 0.12))
                    w.addLine(to: CGPoint(x: c.x + d * r * 1.05, y: c.y + r * (0.12 + 0.13 * Double(k))))
                    ctx.stroke(w, with: .color(.black.opacity(0.5)), lineWidth: r * 0.035)
                }
            }
        case .eye:
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.3, width: r, height: r * 0.6)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.22, y: c.y - r * 0.22, width: r * 0.44, height: r * 0.44)), with: .color(accent))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.1, y: c.y - r * 0.1, width: r * 0.2, height: r * 0.2)), with: .color(.black))
        case .crown:
            var crown = Path()
            let y = c.y - r * 0.85, w = r * 0.9
            crown.move(to: CGPoint(x: c.x - w / 2, y: y))
            for (dx, dy) in [(-0.5, -0.4), (-0.25, -0.18), (0, -0.5), (0.25, -0.18), (0.5, -0.4), (0.5, 0)] {
                crown.addLine(to: CGPoint(x: c.x + w * dx, y: y + r * dy))
            }
            crown.closeSubpath()
            ctx.fill(crown, with: .linearGradient(Gradient(colors: [Color(hex: "#FDE047"), Color(hex: "#CA8A04")]),
                                                  startPoint: CGPoint(x: c.x, y: y - r * 0.5), endPoint: CGPoint(x: c.x, y: y)))
        case .leaf:
            var leaf = Path()
            let base = CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.95)
            leaf.move(to: base)
            leaf.addQuadCurve(to: CGPoint(x: c.x + r * 0.75, y: c.y - r * 1.35), control: CGPoint(x: c.x + r * 0.35, y: c.y - r * 1.45))
            leaf.addQuadCurve(to: base, control: CGPoint(x: c.x + r * 0.7, y: c.y - r * 0.95))
            ctx.fill(leaf, with: .color(Color(hex: "#22C55E")))
        case .bow:
            let center = CGPoint(x: c.x, y: c.y - r * 0.92)
            ctx.fill(polygon(center, [(0, 0), (r * 0.5, .pi + 0.45), (r * 0.5, .pi - 0.45)]), with: .color(Color(hex: "#F43F5E")))
            ctx.fill(polygon(center, [(0, 0), (r * 0.5, -0.45), (r * 0.5, 0.45)]), with: .color(Color(hex: "#F43F5E")))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.1, y: center.y - r * 0.1, width: r * 0.2, height: r * 0.2)),
                     with: .color(Color(hex: "#BE123C")))
        case .flag:
            let pole = CGPoint(x: c.x + r * 0.35, y: c.y - r * 0.9)
            var p = Path()
            p.move(to: pole)
            p.addLine(to: CGPoint(x: pole.x, y: pole.y - r * 0.75))
            ctx.stroke(p, with: .color(Color(hex: "#E5E7EB")), lineWidth: r * 0.05)
            var flag = Path()
            flag.move(to: CGPoint(x: pole.x, y: pole.y - r * 0.75))
            flag.addLine(to: CGPoint(x: pole.x + r * 0.5, y: pole.y - r * 0.62))
            flag.addLine(to: CGPoint(x: pole.x, y: pole.y - r * 0.48))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(Color(hex: "#FACC15")))
        case .sunglasses:
            for d in [-1.0, 1.0] {
                ctx.fill(Path(roundedRect: CGRect(x: c.x + d * r * 0.36 - r * 0.28, y: c.y - r * 0.28, width: r * 0.56, height: r * 0.34),
                              cornerRadius: r * 0.1), with: .color(.black.opacity(0.88)))
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: c.x - r * 0.1, y: c.y - r * 0.16))
            bridge.addLine(to: CGPoint(x: c.x + r * 0.1, y: c.y - r * 0.16))
            ctx.stroke(bridge, with: .color(.black), lineWidth: r * 0.06)
        default:
            break
        }
    }

    // MARK: Ring & patterns

    /// The ring is drawn in two halves (behind / in front of the planet). Dashes and particles
    /// move with `phase`, so the ring visibly spins around the planet.
    private static func drawRing(_ ring: PlanetDef.Ring, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                 front: Bool, phase: Double) {
        ctx.drawLayer { layer in
            layer.translateBy(x: c.x, y: c.y)
            layer.rotate(by: .degrees(ring.tilt))
            layer.clip(to: Path(CGRect(x: -r * 3, y: front ? 0 : -r * 3, width: r * 6, height: r * 3)))
            let color = Color(hex: ring.color)
            for (i, k) in (ring.double ? [1.55, 1.85] : [1.65]).enumerated() {
                let rect = CGRect(x: -r * k, y: -r * k * 0.28, width: r * k * 2, height: r * k * 0.56)
                let width = r * ring.width * (ring.double ? 0.7 : 1)
                let circumference = Double.pi * r * k * 1.3
                let direction = i % 2 == 0 ? 1.0 : -0.7
                // faint solid base
                layer.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.45)), lineWidth: width)
                // moving bright segments
                layer.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.95)),
                             style: StrokeStyle(lineWidth: width * 0.8, lineCap: .round,
                                                dash: [r * 0.5, r * 0.22],
                                                dashPhase: -phase * circumference * direction))
                // small particles orbiting along the ring
                for j in 0..<6 {
                    let a = (Double(j) / 6 + phase * direction) * .pi * 2
                    let pp = CGPoint(x: cos(a) * r * k, y: sin(a) * r * k * 0.28)
                    let d = width * 0.55
                    layer.fill(Path(ellipseIn: CGRect(x: pp.x - d / 2, y: pp.y - d / 2, width: d, height: d)),
                               with: .color(.white.opacity(0.9)))
                }
            }
        }
    }

    private static func drawPattern(_ pattern: PlanetDef.Pattern, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                    accent: Color, rng: inout SeededRandom) {
        let box = CGRect(x: c.x - r * 1.3, y: c.y - r * 1.3, width: r * 2.6, height: r * 2.6)
        switch pattern {
        case .plain:
            break
        case .bands:
            let n = 7
            for k in stride(from: 0, to: n, by: 2) {
                let y = box.minY + box.height * Double(k) / Double(n)
                var band = Path()
                band.move(to: CGPoint(x: box.minX, y: y))
                for x in stride(from: box.minX, through: box.maxX, by: r * 0.2) {
                    band.addLine(to: CGPoint(x: x, y: y + sin(x / r * 3) * r * 0.05))
                }
                band.addLine(to: CGPoint(x: box.maxX, y: y + box.height / Double(n)))
                band.addLine(to: CGPoint(x: box.minX, y: y + box.height / Double(n)))
                band.closeSubpath()
                ctx.fill(band, with: .color(accent.opacity(0.32)))
            }
        case .spots:
            for _ in 0..<7 {
                let w = r * (0.25 + rng.next() * 0.5)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r + rng.next() * r * 1.6, y: c.y - r + rng.next() * r * 1.6,
                                                width: w, height: w * (0.6 + rng.next() * 0.5))),
                         with: .color(accent.opacity(0.7)))
            }
        case .craters:
            for _ in 0..<8 {
                let w = r * (0.15 + rng.next() * 0.35)
                let rect = CGRect(x: c.x - r + rng.next() * r * 1.7, y: c.y - r + rng.next() * r * 1.7, width: w, height: w)
                ctx.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.35)))
                ctx.stroke(Path(ellipseIn: rect.offsetBy(dx: w * 0.06, dy: w * 0.06)), with: .color(.white.opacity(0.18)),
                           lineWidth: max(0.5, w * 0.08))
            }
        case .swirl:
            for k in 0..<4 {
                var arc = Path()
                arc.addArc(center: CGPoint(x: c.x + r * 0.2, y: c.y + r * 0.1), radius: r * (0.35 + Double(k) * 0.28),
                           startAngle: .degrees(Double(k) * 50), endAngle: .degrees(Double(k) * 50 + 200), clockwise: false)
                ctx.stroke(arc, with: .color(accent.opacity(0.45)), style: StrokeStyle(lineWidth: r * 0.13, lineCap: .round))
            }
        case .cracks:
            var glow = ctx
            glow.addFilter(.shadow(color: accent, radius: r * 0.12))
            for _ in 0..<5 {
                var crack = Path()
                var p = CGPoint(x: c.x - r + rng.next() * r * 2, y: c.y - r + rng.next() * r * 0.4)
                crack.move(to: p)
                for _ in 0..<5 {
                    p = CGPoint(x: p.x + (rng.next() - 0.5) * r * 0.6, y: p.y + r * (0.2 + rng.next() * 0.25))
                    crack.addLine(to: p)
                }
                glow.stroke(crack, with: .color(accent), style: StrokeStyle(lineWidth: max(1, r * 0.07), lineCap: .round, lineJoin: .round))
            }
        case .checker:
            let step = r * 0.42
            for (i, y) in stride(from: box.minY, to: box.maxY, by: step).enumerated() {
                for (j, x) in stride(from: box.minX, to: box.maxX, by: step).enumerated() {
                    ctx.fill(Path(CGRect(x: x, y: y, width: step, height: step)),
                             with: .color((i + j) % 2 == 0 ? accent.opacity(0.3) : .black.opacity(0.12)))
                }
            }
        case .stripes:
            ctx.drawLayer { l in
                l.translateBy(x: c.x, y: c.y)
                l.rotate(by: .degrees(-30))
                for k in stride(from: -6, through: 6, by: 2) {
                    l.fill(Path(CGRect(x: Double(k) * r * 0.22, y: -r * 2, width: r * 0.22, height: r * 4)), with: .color(accent.opacity(0.4)))
                }
            }
        case .dots:
            let step = r * 0.32
            for y in stride(from: box.minY, to: box.maxY, by: step) {
                for x in stride(from: box.minX, to: box.maxX, by: step) {
                    let d = r * 0.09
                    ctx.fill(Path(ellipseIn: CGRect(x: x + rng.next() * step * 0.4, y: y + rng.next() * step * 0.4, width: d, height: d)),
                             with: .color(accent.opacity(0.75)))
                }
            }
        case .waves:
            for k in 0..<6 {
                var w = Path()
                let y0 = box.minY + box.height * Double(k + 1) / 7
                w.move(to: CGPoint(x: box.minX, y: y0))
                for x in stride(from: box.minX, through: box.maxX, by: r * 0.1) {
                    w.addLine(to: CGPoint(x: x, y: y0 + sin(x / r * 4 + Double(k)) * r * 0.12))
                }
                ctx.stroke(w, with: .color(accent.opacity(0.4)), lineWidth: r * 0.07)
            }
        case .clouds:
            for _ in 0..<5 {
                let w = r * (0.35 + rng.next() * 0.45)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r + rng.next() * r * 1.5, y: c.y - r + rng.next() * r * 1.5, width: w, height: w * 0.7)),
                         with: .color(accent.opacity(0.8)))
            }
            for _ in 0..<6 {
                let w = r * (0.3 + rng.next() * 0.5)
                ctx.fill(Path(roundedRect: CGRect(x: c.x - r * 1.1 + rng.next() * r * 1.8, y: c.y - r + rng.next() * r * 1.8,
                                                  width: w, height: w * 0.25), cornerRadius: w * 0.12),
                         with: .color(.white.opacity(0.6)))
            }
        case .polarCaps:
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.9, y: c.y - r * 1.25, width: r * 1.8, height: r * 0.7)), with: .color(.white.opacity(0.9)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y + r * 0.65, width: r * 1.6, height: r * 0.6)), with: .color(.white.opacity(0.85)))
        case .hexgrid:
            let s = r * 0.26
            for (row, y) in stride(from: box.minY, to: box.maxY, by: s * 1.5).enumerated() {
                for x in stride(from: box.minX + (row % 2 == 0 ? 0 : s * 0.87), to: box.maxX, by: s * 1.73) {
                    let hex = regular(CGPoint(x: x, y: y), count: 6, outer: s, inner: s, start: .pi / 6)
                    ctx.stroke(hex, with: .color(accent.opacity(0.5)), lineWidth: max(0.6, r * 0.04))
                }
            }
        case .snowflakes:
            for _ in 0..<9 {
                let p = CGPoint(x: c.x - r + rng.next() * r * 2, y: c.y - r + rng.next() * r * 2)
                let s = r * (0.08 + rng.next() * 0.1)
                for k in 0..<3 {
                    var l = Path()
                    let a = Double(k) / 3 * .pi
                    l.move(to: CGPoint(x: p.x - cos(a) * s, y: p.y - sin(a) * s))
                    l.addLine(to: CGPoint(x: p.x + cos(a) * s, y: p.y + sin(a) * s))
                    ctx.stroke(l, with: .color(accent.opacity(0.9)), lineWidth: max(0.6, r * 0.03))
                }
            }
        case .rainbow:
            let colors = ["#EF4444", "#F97316", "#FACC15", "#22C55E", "#3B82F6", "#8B5CF6"]
            for (i, hex) in colors.enumerated() {
                var arc = Path()
                arc.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.9), radius: r * (1.5 - Double(i) * 0.16),
                           startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                ctx.stroke(arc, with: .color(Color(hex: hex).opacity(0.75)), lineWidth: r * 0.16)
            }
        case .mountains:
            var m = Path()
            m.move(to: CGPoint(x: box.minX, y: c.y + r * 1.2))
            var x = box.minX
            while x < box.maxX {
                m.addLine(to: CGPoint(x: x + r * 0.2, y: c.y + r * (0.05 + rng.next() * 0.35)))
                x += r * 0.4
                m.addLine(to: CGPoint(x: x, y: c.y + r * 0.6))
            }
            m.addLine(to: CGPoint(x: box.maxX, y: c.y + r * 1.2))
            m.closeSubpath()
            ctx.fill(m, with: .color(accent.opacity(0.55)))
        case .pepperoni:
            for _ in 0..<8 {
                let w = r * 0.32
                let rect = CGRect(x: c.x - r * 0.85 + rng.next() * r * 1.4, y: c.y - r * 0.85 + rng.next() * r * 1.4, width: w, height: w)
                ctx.fill(Path(ellipseIn: rect), with: .color(accent))
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: w * 0.3, dy: w * 0.3).offsetBy(dx: -w * 0.08, dy: -w * 0.08)),
                         with: .color(.white.opacity(0.25)))
            }
        case .sprinkles:
            let colors = ["#FDE047", "#60A5FA", "#34D399", "#FFFFFF", "#A78BFA"]
            for i in 0..<26 {
                let p = CGPoint(x: c.x - r + rng.next() * r * 2, y: c.y - r + rng.next() * r * 2)
                let a = rng.next() * .pi
                var l = Path()
                l.move(to: CGPoint(x: p.x - cos(a) * r * 0.07, y: p.y - sin(a) * r * 0.07))
                l.addLine(to: CGPoint(x: p.x + cos(a) * r * 0.07, y: p.y + sin(a) * r * 0.07))
                ctx.stroke(l, with: .color(Color(hex: colors[i % colors.count])), style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round))
            }
        }
    }
}

/// Deterministic random numbers so each planet always looks the same
struct SeededRandom {
    private var state: UInt64
    init(seed: String) {
        state = seed.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(1 << 31)
    }
}

/// Developer contact sheet of every planet
@MainActor
enum PlanetSheet {
    /// `store: true` renders the 20 store planets by rarity instead
    static func render(to url: URL, store: Bool = false) {
        // rows of at most 12 planets: (label, planets)
        var rows: [(String, [PlanetDef])] = []
        for level in 1...(store ? Rarity.allCases.count : 10) {
            let label = store ? String(Rarity.allCases[level - 1].title.prefix(1)) : "L\(level)"
            let list = store ? PlanetCatalog.storeAvailable.filter { $0.rarity == Rarity.allCases[level - 1] } : PlanetCatalog.all.filter { $0.level == level }
            for (i, start) in stride(from: 0, to: max(list.count, 1), by: 12).enumerated() {
                rows.append((i == 0 ? label : "", Array(list[start..<min(start + 12, list.count)])))
            }
        }
        let view = VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Text(rows[i].0).font(.headline).foregroundStyle(.white).frame(width: 34)
                    ForEach(rows[i].1) { p in
                        VStack(spacing: 2) {
                            PlanetView(planet: p, size: 130, phase: 0.1)
                            Text(p.name).font(.caption).foregroundStyle(.white)
                        }
                        .frame(width: 140)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#0B1020"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}


// MARK: - Hand-drawn creatures
//
// Planets with a little character on them are drawn here in code (instead of a system emoji), in the same flat style as the
// rest of the planets. Coordinates are in units of the planet radius, measured from its centre.

extension PlanetPainter {
    static func drawArt(_ key: String, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + r * x, y: c.y + r * y) }
        func ell(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
            Path(ellipseIn: CGRect(x: c.x + r * (x - rx), y: c.y + r * (y - ry), width: r * rx * 2, height: r * ry * 2))
        }
        func tri(_ a: (Double, Double), _ b: (Double, Double), _ d: (Double, Double)) -> Path {
            var p = Path(); p.move(to: P(a.0, a.1)); p.addLine(to: P(b.0, b.1)); p.addLine(to: P(d.0, d.1)); p.closeSubpath(); return p
        }
        let ink = Color.black.opacity(0.38), lw = r * 0.035
        func solid(_ path: Path, _ fill: Color, line: Bool = true) {
            ctx.fill(path, with: .color(fill))
            if line { ctx.stroke(path, with: .color(ink), lineWidth: lw) }
        }
        func dot(_ x: Double, _ y: Double, _ rad: Double, _ color: Color) { ctx.fill(ell(x, y, rad, rad), with: .color(color)) }
        func line(_ pts: [(Double, Double)], _ color: Color, _ width: Double) {
            var p = Path(); p.move(to: P(pts[0].0, pts[0].1)); for q in pts.dropFirst() { p.addLine(to: P(q.0, q.1)) }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: r * width, lineCap: .round, lineJoin: .round))
        }
        func spun(_ build: (inout GraphicsContext) -> Void, deg: Double, about x: Double = 0, _ y: Double = 0) {
            var g = ctx
            g.translateBy(x: c.x + r * x, y: c.y + r * y); g.rotate(by: .degrees(deg)); g.translateBy(x: -(c.x + r * x), y: -(c.y + r * y))
            build(&g)
        }

        switch key {
        case "dino":
            // a baby dinosaur hatching out of the egg
            for x in [-0.3, 0.0, 0.3] { solid(tri((x - 0.13, -0.42), (x, -0.8), (x + 0.13, -0.42)), Color(hex: "#15803D")) }
            solid(ell(0, -0.02, 0.64, 0.5), Color(hex: "#65A30D"))
            solid(ell(0, 0.22, 0.46, 0.26), Color(hex: "#84CC16"))
            for x in [-0.28, 0.28] { dot(x, -0.14, 0.15, .white); dot(x + (x < 0 ? 0.03 : -0.03), -0.12, 0.075, Color(hex: "#1C1917")) }
            dot(-0.12, 0.14, 0.035, Color(hex: "#365314")); dot(0.12, 0.14, 0.035, Color(hex: "#365314"))
            var smile = Path(); smile.move(to: P(-0.22, 0.28)); smile.addQuadCurve(to: P(0.22, 0.28), control: P(0, 0.42))
            ctx.stroke(smile, with: .color(Color(hex: "#365314")), style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round))
            line([(-0.9, 0.55), (-0.62, 0.42), (-0.42, 0.62), (-0.2, 0.44), (0.0, 0.62), (0.2, 0.44), (0.42, 0.62), (0.62, 0.42), (0.9, 0.55)],
                 .white.opacity(0.85), 0.05)   // the cracked shell
        case "bee":
            spun({ g in
                func fillStroke(_ p: Path, _ col: Color) { g.fill(p, with: .color(col)); g.stroke(p, with: .color(ink), lineWidth: lw) }
                fillStroke(ell(-0.08, -0.42, 0.2, 0.34), Color.white.opacity(0.85))
                fillStroke(ell(0.22, -0.48, 0.2, 0.34), Color.white.opacity(0.85))
                let body = ell(0.02, 0.06, 0.58, 0.36)
                g.fill(body, with: .color(Color(hex: "#FACC15")))
                g.drawLayer { l in
                    l.clip(to: body)
                    for x in [-0.18, 0.14, 0.44] { l.fill(Path(roundedRect: CGRect(x: c.x + r * (x - 0.07), y: c.y - r * 0.4, width: r * 0.14, height: r * 0.9), cornerRadius: r * 0.02), with: .color(Color(hex: "#1F2937"))) }
                }
                g.stroke(body, with: .color(ink), lineWidth: lw)
                fillStroke(ell(-0.56, 0.06, 0.22, 0.22), Color(hex: "#1F2937"))
                g.fill(ell(-0.62, 0.0, 0.06, 0.07), with: .color(.white)); g.fill(ell(-0.5, 0.0, 0.06, 0.07), with: .color(.white))
                fillStroke(tri((0.58, 0.0), (0.88, 0.07), (0.58, 0.14)), Color(hex: "#1F2937"))
                var ant = Path(); ant.move(to: P(-0.6, -0.14)); ant.addQuadCurve(to: P(-0.78, -0.42), control: P(-0.7, -0.2))
                g.stroke(ant, with: .color(Color(hex: "#1F2937")), style: StrokeStyle(lineWidth: r * 0.04, lineCap: .round))
            }, deg: -16)
        case "fish":
            let hop = sin(phase * .pi * 2) * 0.04
            solid(tri((0.36, hop), (0.82, -0.3 + hop), (0.82, 0.3 + hop)), Color(hex: "#F97316"))
            solid(tri((-0.25, -0.28 + hop), (0.05, -0.55 + hop), (0.22, -0.26 + hop)), Color(hex: "#F97316"))
            let body = ell(-0.06, hop, 0.54, 0.36)
            ctx.fill(body, with: .color(Color(hex: "#FB923C")))
            ctx.drawLayer { l in
                l.clip(to: body)
                for x in [-0.12, 0.2] { l.fill(Path(roundedRect: CGRect(x: c.x + r * (x - 0.05), y: c.y - r * 0.4, width: r * 0.1, height: r * 0.8), cornerRadius: r * 0.03), with: .color(.white.opacity(0.85))) }
            }
            ctx.stroke(body, with: .color(ink), lineWidth: lw)
            dot(-0.34, -0.07 + hop, 0.085, .white); dot(-0.36, -0.07 + hop, 0.04, Color(hex: "#1C1917"))
            for (bx, by, br) in [(-0.7, -0.4, 0.08), (-0.82, -0.62, 0.05), (-0.62, -0.7, 0.04)] {
                ctx.stroke(ell(bx, by + hop, br, br), with: .color(.white.opacity(0.9)), lineWidth: r * 0.03)
            }
        case "stego":
            for (i, x) in [-0.5, -0.28, -0.06, 0.16, 0.38].enumerated() {
                let h = 0.34 - 0.04 * abs(Double(i) - 2)
                solid(tri((x - 0.12, -0.05), (x, -0.05 - h - 0.1), (x + 0.12, -0.05)), Color(hex: "#F59E0B"))
            }
            for x in [-0.44, -0.14, 0.24, 0.52] { solid(ell(x, 0.55, 0.11, 0.2), Color(hex: "#57534E")) }
            solid(tri((-0.62, 0.0), (-1.05, 0.3), (-0.6, 0.3)), Color(hex: "#57534E"))
            for (x, y) in [(-0.9, 0.12), (-0.78, 0.2)] { solid(tri((x - 0.05, y + 0.06), (x, y - 0.12), (x + 0.05, y + 0.06)), Color(hex: "#F59E0B"), line: false) }
            solid(ell(0.0, 0.22, 0.7, 0.36), Color(hex: "#6B665F"))
            solid(ell(0.78, 0.24, 0.22, 0.16), Color(hex: "#6B665F"))
            dot(0.84, 0.2, 0.04, .white); dot(0.85, 0.2, 0.02, Color(hex: "#1C1917"))
        case "robot":
            solid(Path(roundedRect: CGRect(x: c.x - r * 0.9, y: c.y - r * 0.18, width: r * 0.2, height: r * 0.4), cornerRadius: r * 0.05), Color(hex: "#94A3B8"))
            solid(Path(roundedRect: CGRect(x: c.x + r * 0.7, y: c.y - r * 0.18, width: r * 0.2, height: r * 0.4), cornerRadius: r * 0.05), Color(hex: "#94A3B8"))
            solid(Path(roundedRect: CGRect(x: c.x - r * 0.72, y: c.y - r * 0.6, width: r * 1.44, height: r * 1.2), cornerRadius: r * 0.24), Color(hex: "#E2E8F0"))
            for x in [-0.3, 0.3] {
                let eye = Path(roundedRect: CGRect(x: c.x + r * (x - 0.17), y: c.y - r * 0.32, width: r * 0.34, height: r * 0.34), cornerRadius: r * 0.08)
                var glow = ctx; glow.addFilter(.blur(radius: r * 0.06)); glow.fill(eye, with: .color(Color(hex: "#22D3EE").opacity(0.8)))
                solid(eye, Color(hex: "#0891B2"))
                dot(x + 0.04, -0.2, 0.06, .white)
            }
            solid(Path(roundedRect: CGRect(x: c.x - r * 0.34, y: c.y + r * 0.18, width: r * 0.68, height: r * 0.24), cornerRadius: r * 0.06), Color(hex: "#334155"))
            for x in [-0.17, 0, 0.17] { line([(x, 0.22), (x, 0.38)], Color(hex: "#CBD5E1"), 0.035) }
            for (x, y) in [(-0.58, -0.46), (0.58, -0.46), (-0.58, 0.46), (0.58, 0.46)] { dot(x, y, 0.045, Color(hex: "#94A3B8")) }
        case "snowman":
            solid(ell(0, 0.82, 0.78, 0.17), Color(hex: "#E0F2FE"), line: false)
            solid(ell(0, 0.46, 0.38, 0.36), .white)
            solid(ell(0, 0.0, 0.29, 0.28), .white)
            solid(ell(0, -0.4, 0.21, 0.21), .white)
            solid(Path(roundedRect: CGRect(x: c.x - r * 0.15, y: c.y - r * 0.9, width: r * 0.3, height: r * 0.3), cornerRadius: r * 0.03), Color(hex: "#1F2937"))
            solid(ell(0, -0.6, 0.27, 0.06), Color(hex: "#1F2937"))
            solid(Path(roundedRect: CGRect(x: c.x - r * 0.22, y: c.y - r * 0.2, width: r * 0.44, height: r * 0.09), cornerRadius: r * 0.04), Color(hex: "#DC2626"))
            solid(tri((0.02, -0.4), (0.34, -0.35), (0.02, -0.3)), Color(hex: "#F97316"))
            dot(-0.08, -0.46, 0.028, Color(hex: "#1F2937")); dot(0.1, -0.46, 0.028, Color(hex: "#1F2937"))
            for y in [0.06, 0.2, 0.38] { dot(0, y, 0.03, Color(hex: "#1F2937")) }
            line([(-0.28, 0.0), (-0.66, -0.2)], Color(hex: "#78350F"), 0.04); line([(0.28, 0.0), (0.66, -0.2)], Color(hex: "#78350F"), 0.04)
            for (x, y) in [(-0.7, -0.5), (0.65, -0.62), (-0.55, 0.2), (0.72, 0.1), (-0.3, -0.8), (0.4, -0.35)] { dot(x, y, 0.035, .white.opacity(0.9)) }
        case "whale":
            let sway = sin(phase * .pi * 2) * 0.03
            solid(tri((-0.5, 0.12), (-0.98, -0.24 + sway), (-0.72, 0.18)), Color(hex: "#BAE6FD"))
            solid(tri((-0.5, 0.18), (-1.0, 0.1 + sway), (-0.6, 0.34)), Color(hex: "#BAE6FD"))
            let body = ell(0.02, 0.18, 0.72, 0.4)
            ctx.fill(body, with: .color(Color(hex: "#DBEAFE")))
            ctx.drawLayer { l in l.clip(to: body); l.fill(ell(0.06, 0.4, 0.8, 0.26), with: .color(.white.opacity(0.9))) }
            ctx.stroke(body, with: .color(ink), lineWidth: lw)
            dot(0.42, 0.08, 0.05, Color(hex: "#1E3A8A"))
            var smile = Path(); smile.move(to: P(0.5, 0.26)); smile.addQuadCurve(to: P(0.24, 0.3), control: P(0.4, 0.34))
            ctx.stroke(smile, with: .color(Color(hex: "#1E3A8A")), style: StrokeStyle(lineWidth: r * 0.03, lineCap: .round))
            for dx in [-1.0, 1.0] {
                var w = Path(); w.move(to: P(0.18, -0.2)); w.addQuadCurve(to: P(0.18 + dx * 0.34, -0.62), control: P(0.18 + dx * 0.06, -0.62))
                ctx.stroke(w, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round))
                dot(0.18 + dx * 0.36, -0.55, 0.04, .white)
            }
        case "alien":
            let head = ell(0, -0.04, 0.6, 0.66).union(ell(0, 0.3, 0.38, 0.42))
            solid(head, Color(hex: "#BEF264"))
            for x in [-1.0, 1.0] {
                let eye = Path(ellipseIn: CGRect(x: c.x + r * (x * 0.28 - 0.25), y: c.y - r * 0.2, width: r * 0.5, height: r * 0.28))
                var g = ctx
                g.translateBy(x: c.x + r * x * 0.28, y: c.y - r * 0.06); g.rotate(by: .degrees(-22 * x)); g.translateBy(x: -(c.x + r * x * 0.28), y: -(c.y - r * 0.06))
                g.fill(eye, with: .color(Color(hex: "#0F172A")))
                g.fill(Path(ellipseIn: CGRect(x: c.x + r * (x * 0.28 - 0.14), y: c.y - r * 0.15, width: r * 0.1, height: r * 0.07)), with: .color(.white.opacity(0.8)))
            }
            dot(-0.04, 0.2, 0.018, Color(hex: "#365314")); dot(0.04, 0.2, 0.018, Color(hex: "#365314"))
            var mouth = Path(); mouth.move(to: P(-0.1, 0.42)); mouth.addQuadCurve(to: P(0.1, 0.42), control: P(0, 0.47))
            ctx.stroke(mouth, with: .color(Color(hex: "#365314")), style: StrokeStyle(lineWidth: r * 0.035, lineCap: .round))
        case "ufo":
            let bob = sin(phase * .pi * 2) * 0.05
            ctx.fill(tri((-0.22, 0.2 + bob), (0.22, 0.2 + bob), (0.6, 0.95)), with: .linearGradient(
                Gradient(colors: [Color(hex: "#67E8F9").opacity(0.45), Color(hex: "#67E8F9").opacity(0)]), startPoint: P(0, 0.2), endPoint: P(0, 0.95)))
            solid(ell(0, -0.1 + bob, 0.3, 0.3), Color(hex: "#A5F3FC").opacity(0.9))
            dot(0, -0.1 + bob, 0.1, Color(hex: "#86EFAC")); dot(-0.04, -0.13 + bob, 0.02, Color(hex: "#0F172A")); dot(0.04, -0.13 + bob, 0.02, Color(hex: "#0F172A"))
            solid(ell(0, 0.2 + bob, 0.46, 0.14), Color(hex: "#64748B"))
            solid(ell(0, 0.1 + bob, 0.78, 0.2), Color(hex: "#CBD5E1"))
            for (i, x) in [-0.5, -0.25, 0.0, 0.25, 0.5].enumerated() {
                let on = Int(phase * 6 + Double(i)) % 2 == 0
                dot(x, 0.1 + bob, 0.04, on ? Color(hex: "#FDE047") : Color(hex: "#F472B6"))
            }
        case "flame":
            func flame(_ k: Double, _ y0: Double) -> Path {
                var p = Path()
                p.move(to: P(0, y0 + 0.62 * k))
                p.addCurve(to: P(-0.5 * k, y0 + 0.02 * k), control1: P(-0.36 * k, y0 + 0.62 * k), control2: P(-0.62 * k, y0 + 0.34 * k))
                p.addCurve(to: P(-0.05 * k, y0 - 0.85 * k), control1: P(-0.46 * k, y0 - 0.36 * k), control2: P(-0.08 * k, y0 - 0.46 * k))
                p.addCurve(to: P(0.5 * k, y0 + 0.08 * k), control1: P(0.1 * k, y0 - 0.4 * k), control2: P(0.46 * k, y0 - 0.26 * k))
                p.addCurve(to: P(0, y0 + 0.62 * k), control1: P(0.62 * k, y0 + 0.4 * k), control2: P(0.34 * k, y0 + 0.62 * k))
                return p
            }
            let flick = 1 + sin(phase * .pi * 4) * 0.04
            let outer = flame(flick, 0)
            var glow = ctx; glow.addFilter(.blur(radius: r * 0.12)); glow.fill(outer, with: .color(Color(hex: "#FDE047").opacity(0.7)))
            ctx.fill(outer, with: .linearGradient(Gradient(colors: [Color(hex: "#B91C1C"), Color(hex: "#F97316")]), startPoint: P(0, -0.85), endPoint: P(0, 0.62)))
            ctx.stroke(outer, with: .color(ink), lineWidth: lw)
            ctx.fill(flame(0.68 * flick, 0.2), with: .linearGradient(Gradient(colors: [Color(hex: "#F97316"), Color(hex: "#FACC15")]), startPoint: P(0, -0.4), endPoint: P(0, 0.62)))
            ctx.fill(flame(0.36 * flick, 0.36), with: .linearGradient(Gradient(colors: [Color(hex: "#FDE047"), .white]), startPoint: P(0, -0.1), endPoint: P(0, 0.6)))
        default:
            break
        }
    }
}
