import SwiftUI

// MARK: - Store planets

/// How rare a store planet is (sets its price range and badge colour)
enum Rarity: String, CaseIterable, Identifiable {
    case common, rare, epic, legendary

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .common: Color(hex: "#94A3B8")
        case .rare: Color(hex: "#38BDF8")
        case .epic: Color(hex: "#A855F7")
        case .legendary: Color(hex: "#F59E0B")
        }
    }

    static func of(price: Int) -> Rarity {
        switch price {
        case ..<300: .common
        case ..<550: .rare
        case ..<850: .epic
        default: .legendary
        }
    }
}

/// Spacecraft that orbit a store planet
enum Craft: Hashable {
    case rocket, ufo, station, satellite, shuttle, comet
}

extension PlanetDef {
    var rarity: Rarity { Rarity.of(price: price) }
    var isStoreItem: Bool { price > 0 }
}

extension PlanetCatalog {
    /// 20 planets you buy with rockets. Kept apart from the 50 level planets.
    static let store: [PlanetDef] = [
        // Common
        PlanetDef(id: "s_lemondrop", name: "Lemon Drop", level: 1, blurb: "Sour, sunny and a little bit sticky.",
                  colors: ["#FEF9C3", "#FACC15", "#A16207"], pattern: .dots, accent: "#FFFBEB", features: [.leaf], price: 100),
        PlanetDef(id: "s_comet", name: "Comet Tail", level: 1, blurb: "An icy world with a comet that never leaves.",
                  colors: ["#E0F2FE", "#7DD3FC", "#0369A1"], pattern: .craters, accent: "#0C4A6E",
                  crafts: [.comet], price: 150),
        PlanetDef(id: "s_mint", name: "Mint Orbit", level: 1, blurb: "Fresh mint bands and a tiny busy satellite.",
                  colors: ["#D1FAE5", "#34D399", "#065F46"], pattern: .bands, accent: "#ECFDF5",
                  crafts: [.satellite], price: 160),
        PlanetDef(id: "s_launchpad", name: "Launch Pad", level: 1, blurb: "Pixel rockets take off from here every hour.",
                  colors: ["#E2E8F0", "#64748B", "#1E293B"], pattern: .checker, accent: "#CBD5E1",
                  crafts: [.rocket], price: 200),
        PlanetDef(id: "s_cottoncandy", name: "Cotton Candy", level: 1, blurb: "Pink and blue fluff. Do not eat the clouds.",
                  shape: .cloud, colors: ["#FCE7F3", "#C4B5FD", "#7C3AED"], pattern: .swirl, accent: "#BAE6FD", price: 240),

        // Rare
        PlanetDef(id: "s_sakura", name: "Sakura", level: 1, blurb: "Cherry blossoms drifting in low gravity.",
                  shape: .flower, colors: ["#FFE4E6", "#FDA4AF", "#BE123C"], pattern: .dots, accent: "#FFFFFF", price: 300),
        PlanetDef(id: "s_moonbase", name: "Moonbase", level: 1, blurb: "Flag planted, rocket parked, coffee brewing.",
                  shape: .crescent, colors: ["#F8FAFC", "#94A3B8", "#334155"], pattern: .craters, accent: "#1E293B",
                  features: [.flag], crafts: [.rocket], price: 330),
        PlanetDef(id: "s_neongrid", name: "Neon Grid", level: 1, blurb: "A cyber cube humming with synthwave.",
                  shape: .cube, colors: ["#F0ABFC", "#C026D3", "#3B0764"], pattern: .hexgrid, accent: "#22D3EE", glow: true,
                  price: 380),
        PlanetDef(id: "s_station", name: "Station Alpha", level: 1, blurb: "A golden ring and a space station on patrol.",
                  colors: ["#FEF3C7", "#F59E0B", "#78350F"], pattern: .bands, accent: "#FFFBEB",
                  ring: .init(color: "#FDE68A", tilt: -14, width: 0.12), crafts: [.station], price: 420),
        PlanetDef(id: "s_ufo", name: "Close Encounter", level: 1, blurb: "Two little green friends came to say hi.",
                  colors: ["#C7D2FE", "#6366F1", "#1E1B4B"], pattern: .craters, accent: "#312E81",
                  crafts: [.ufo], price: 480),

        // Epic
        PlanetDef(id: "s_crystal", name: "Crystal Fortress", level: 1, blurb: "A diamond citadel under a holy halo.",
                  shape: .diamond, colors: ["#ECFEFF", "#67E8F9", "#155E75"], pattern: .rainbow, accent: "#FFFFFF",
                  features: [.halo], glow: true, price: 580),
        PlanetDef(id: "s_solarsail", name: "Solar Sail", level: 1, blurb: "Sun-powered, with a station and a satellite.",
                  colors: ["#FFEDD5", "#FB923C", "#9A3412"], pattern: .waves, accent: "#FEF3C7",
                  crafts: [.station, .satellite], price: 620),
        PlanetDef(id: "s_rally", name: "Rocket Rally", level: 1, blurb: "Two rockets racing around a double ring.",
                  colors: ["#FECACA", "#EF4444", "#7F1D1D"], pattern: .stripes, accent: "#FEE2E2",
                  ring: .init(color: "#F8FAFC", tilt: 22, width: 0.08, double: true), crafts: [.rocket, .rocket], price: 680),
        PlanetDef(id: "s_dragonegg", name: "Dragon Egg", level: 1, blurb: "Warm to the touch. Something is moving inside.",
                  shape: .egg, colors: ["#BBF7D0", "#22C55E", "#14532D"], pattern: .hexgrid, accent: "#052E16",
                  features: [.fireWings], glow: true, price: 740),
        PlanetDef(id: "s_mothership", name: "Mothership", level: 1, blurb: "The whole UFO fleet calls this place home.",
                  colors: ["#BEF264", "#4D7C0F", "#1A2E05"], pattern: .spots, accent: "#D9F99D", moons: 1,
                  glow: true, crafts: [.ufo, .ufo], price: 800),

        // Legendary
        PlanetDef(id: "s_blackhole", name: "Event Horizon", level: 1, blurb: "Light bends around it. So does time.",
                  colors: ["#475569", "#0F172A", "#000000"], pattern: .swirl, accent: "#F472B6",
                  ring: .init(color: "#FB923C", tilt: -10, width: 0.22, double: true), glow: true, crafts: [.comet],
                  price: 860),
        PlanetDef(id: "s_captain", name: "Captain Whiskers", level: 1, blurb: "The coolest cat in the fleet flies his own rocket.",
                  colors: ["#FDE68A", "#F59E0B", "#92400E"], pattern: .stripes, accent: "#78350F",
                  features: [.catEars, .sunglasses, .whiskers], crafts: [.rocket], price: 900),
        PlanetDef(id: "s_odyssey", name: "Starship Odyssey", level: 1, blurb: "A shuttle, a rocket and a station on one long voyage.",
                  colors: ["#DBEAFE", "#3B82F6", "#1E3A8A"], pattern: .clouds, accent: "#E0F2FE",
                  ring: .init(color: "#93C5FD", tilt: 18, width: 0.1), moons: 1, glow: true,
                  crafts: [.shuttle, .rocket, .station], price: 950),
        PlanetDef(id: "s_royal", name: "Royal Nebula", level: 1, blurb: "A crowned world wrapped in violet starlight.",
                  colors: ["#F5D0FE", "#A855F7", "#3B0764"], pattern: .waves, accent: "#FDE047",
                  ring: .init(color: "#E9D5FF", tilt: -24, width: 0.14), moons: 2, features: [.crown], glow: true,
                  crafts: [.satellite], price: 970),
        PlanetDef(id: "s_infinity", name: "Infinity Core", level: 1, blurb: "Every colour, every orbit — the rarest world of all.",
                  shape: .burst, colors: ["#FEF9C3", "#F472B6", "#4C1D95"], pattern: .rainbow, accent: "#FFFFFF",
                  ring: .init(color: "#FDE68A", tilt: 12, width: 0.12, double: true), moons: 3,
                  features: [.halo], glow: true, crafts: [.comet, .shuttle], price: 1000),
        PlanetDef(id: "s_aliens", name: "Alien Visitors", level: 1, blurb: "Two little green friends dropped by in their pixel saucer.",
                  colors: ["#BEF264", "#4ADE80", "#14532D"], accent: "#86EFAC", glow: true, price: 990, image: "ufo"),
    ]
}

// MARK: - Spacecraft drawing

extension PlanetPainter {
    /// Craft fly on an orbit around the planet; `phase` (0…1) moves them
    static func drawCrafts(_ crafts: [Craft], ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        for (i, craft) in crafts.enumerated() {
            let a = (Double(i) / Double(max(1, crafts.count)) + phase * (craft == .comet ? 0.6 : 1)) * .pi * 2 + 2.2
            let orbitX = r * (craft == .comet ? 1.55 : 1.42), orbitY = r * 0.62
            let p = CGPoint(x: c.x + cos(a) * orbitX, y: c.y + sin(a) * orbitY - r * 0.1)
            // Direction of travel along the ellipse
            let heading = atan2(cos(a) * orbitY, -sin(a) * orbitX)
            var g = ctx
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(craft == .ufo || craft == .station || craft == .satellite ? 0 : heading))
            let u = r * (craft == .comet ? 0.26 : 0.33)
            switch craft {
            case .rocket: rocket(&g, u)
            case .ufo: ufo(&g, u)
            case .station: station(&g, u, spin: phase)
            case .satellite: satellite(&g, u * 0.85)
            case .shuttle: shuttle(&g, u)
            case .comet: comet(&g, u)
            }
        }
    }

    /// White body, red fins, blue window and a flame (like the rocket currency icon)
    private static func rocket(_ g: inout GraphicsContext, _ u: CGFloat) {
        var flame = Path()
        flame.move(to: CGPoint(x: -u * 1.0, y: -u * 0.28))
        flame.addQuadCurve(to: CGPoint(x: -u * 1.0, y: u * 0.28), control: CGPoint(x: -u * 2.1, y: 0))
        g.fill(flame, with: .linearGradient(Gradient(colors: [Color(hex: "#FDE047"), Color(hex: "#22D3EE"), Color(hex: "#2563EB").opacity(0)]),
                                            startPoint: CGPoint(x: -u, y: 0), endPoint: CGPoint(x: -u * 2.1, y: 0)))
        var fins = Path()
        fins.move(to: CGPoint(x: -u * 0.5, y: -u * 0.3)); fins.addLine(to: CGPoint(x: -u * 1.05, y: -u * 0.75)); fins.addLine(to: CGPoint(x: -u * 0.95, y: -u * 0.2))
        fins.move(to: CGPoint(x: -u * 0.5, y: u * 0.3)); fins.addLine(to: CGPoint(x: -u * 1.05, y: u * 0.75)); fins.addLine(to: CGPoint(x: -u * 0.95, y: u * 0.2))
        g.fill(fins, with: .color(Color(hex: "#F05252")))
        var body = Path()
        body.move(to: CGPoint(x: u * 1.1, y: 0))
        body.addQuadCurve(to: CGPoint(x: -u, y: -u * 0.36), control: CGPoint(x: u * 0.5, y: -u * 0.55))
        body.addLine(to: CGPoint(x: -u, y: u * 0.36))
        body.addQuadCurve(to: CGPoint(x: u * 1.1, y: 0), control: CGPoint(x: u * 0.5, y: u * 0.55))
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(hex: "#F8FAFC"), Color(hex: "#CBD5E1")]),
                                           startPoint: CGPoint(x: 0, y: -u * 0.4), endPoint: CGPoint(x: 0, y: u * 0.4)))
        var nose = Path()
        nose.move(to: CGPoint(x: u * 1.1, y: 0))
        nose.addQuadCurve(to: CGPoint(x: u * 0.55, y: -u * 0.33), control: CGPoint(x: u * 0.9, y: -u * 0.25))
        nose.addLine(to: CGPoint(x: u * 0.55, y: u * 0.33))
        nose.addQuadCurve(to: CGPoint(x: u * 1.1, y: 0), control: CGPoint(x: u * 0.9, y: u * 0.25))
        g.fill(nose, with: .color(Color(hex: "#F05252")))
        let w = CGRect(x: u * 0.05, y: -u * 0.17, width: u * 0.34, height: u * 0.34)
        g.fill(Path(ellipseIn: w.insetBy(dx: -u * 0.05, dy: -u * 0.05)), with: .color(Color(hex: "#475569")))
        g.fill(Path(ellipseIn: w), with: .linearGradient(Gradient(colors: [Color(hex: "#7DD3FC"), Color(hex: "#0284C7")]),
                                                        startPoint: CGPoint(x: w.minX, y: w.minY), endPoint: CGPoint(x: w.maxX, y: w.maxY)))
    }

    /// Flying saucer with a glass dome and two little green aliens
    private static func ufo(_ g: inout GraphicsContext, _ u: CGFloat) {
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.55, y: u * 0.15, width: u * 1.1, height: u * 1.1)),
               with: .linearGradient(Gradient(colors: [Color(hex: "#BEF264").opacity(0.45), .clear]),
                                     startPoint: CGPoint(x: 0, y: u * 0.2), endPoint: CGPoint(x: 0, y: u * 1.3)))
        let dome = CGRect(x: -u * 0.6, y: -u * 0.75, width: u * 1.2, height: u * 1.0)
        g.fill(Path(ellipseIn: dome), with: .color(Color(hex: "#1E293B").opacity(0.9)))
        for dx in [-0.25, 0.25] {
            let head = CGRect(x: u * (dx - 0.13), y: -u * 0.55, width: u * 0.26, height: u * 0.3)
            g.fill(Path(ellipseIn: head), with: .color(Color(hex: "#4ADE80")))
            g.fill(Path(ellipseIn: CGRect(x: head.minX + u * 0.04, y: head.minY + u * 0.1, width: u * 0.07, height: u * 0.08)), with: .color(.black))
            g.fill(Path(ellipseIn: CGRect(x: head.maxX - u * 0.11, y: head.minY + u * 0.1, width: u * 0.07, height: u * 0.08)), with: .color(.black))
        }
        g.stroke(Path(ellipseIn: dome), with: .color(.white.opacity(0.35)), lineWidth: max(0.6, u * 0.05))
        g.fill(Path(ellipseIn: CGRect(x: -u * 1.15, y: -u * 0.28, width: u * 2.3, height: u * 0.55)),
               with: .linearGradient(Gradient(colors: [Color(hex: "#E5E7EB"), Color(hex: "#9CA3AF")]),
                                     startPoint: CGPoint(x: 0, y: -u * 0.3), endPoint: CGPoint(x: 0, y: u * 0.3)))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.75, y: u * 0.05, width: u * 1.5, height: u * 0.35)), with: .color(Color(hex: "#A78BFA")))
        for k in -2...2 {
            g.fill(Path(ellipseIn: CGRect(x: CGFloat(k) * u * 0.28 - u * 0.05, y: u * 0.17, width: u * 0.1, height: u * 0.1)),
                   with: .color(Color(hex: "#FBCFE8")))
        }
    }

    /// A small station: hub, ring and two solar panels
    private static func station(_ g: inout GraphicsContext, _ u: CGFloat, spin: Double) {
        g.rotate(by: .radians(spin * .pi * 2 * 0.5))
        for side in [-1.0, 1.0] {
            let panel = CGRect(x: side < 0 ? -u * 1.35 : u * 0.45, y: -u * 0.28, width: u * 0.9, height: u * 0.56)
            g.fill(Path(panel), with: .linearGradient(Gradient(colors: [Color(hex: "#60A5FA"), Color(hex: "#1D4ED8")]),
                                                      startPoint: CGPoint(x: panel.minX, y: panel.minY), endPoint: CGPoint(x: panel.maxX, y: panel.maxY)))
            g.stroke(Path(panel), with: .color(.white.opacity(0.5)), lineWidth: max(0.5, u * 0.04))
        }
        g.fill(Path(CGRect(x: -u * 0.5, y: -u * 0.05, width: u, height: u * 0.1)), with: .color(Color(hex: "#CBD5E1")))
        g.stroke(Path(ellipseIn: CGRect(x: -u * 0.45, y: -u * 0.45, width: u * 0.9, height: u * 0.9)),
                 with: .color(Color(hex: "#E2E8F0")), lineWidth: max(0.8, u * 0.12))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.22, y: -u * 0.22, width: u * 0.44, height: u * 0.44)), with: .color(Color(hex: "#F8FAFC")))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.08, y: -u * 0.08, width: u * 0.16, height: u * 0.16)), with: .color(Color(hex: "#F43F5E")))
    }

    private static func satellite(_ g: inout GraphicsContext, _ u: CGFloat) {
        g.rotate(by: .degrees(-25))
        for side in [-1.0, 1.0] {
            let panel = CGRect(x: side < 0 ? -u * 1.2 : u * 0.4, y: -u * 0.22, width: u * 0.8, height: u * 0.44)
            g.fill(Path(panel), with: .color(Color(hex: "#3B82F6")))
        }
        g.fill(Path(roundedRect: CGRect(x: -u * 0.35, y: -u * 0.3, width: u * 0.7, height: u * 0.6), cornerRadius: u * 0.1),
               with: .color(Color(hex: "#FBBF24")))
        var dish = Path()
        dish.addArc(center: CGPoint(x: 0, y: -u * 0.55), radius: u * 0.3, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        g.stroke(dish, with: .color(Color(hex: "#E5E7EB")), lineWidth: max(0.8, u * 0.1))
    }

    private static func shuttle(_ g: inout GraphicsContext, _ u: CGFloat) {
        var wing = Path()
        wing.move(to: CGPoint(x: u * 0.2, y: 0)); wing.addLine(to: CGPoint(x: -u * 0.8, y: -u * 0.8))
        wing.addLine(to: CGPoint(x: -u * 0.9, y: u * 0.8)); wing.closeSubpath()
        g.fill(wing, with: .color(Color(hex: "#CBD5E1")))
        g.fill(Path(roundedRect: CGRect(x: -u * 1.0, y: -u * 0.24, width: u * 2.0, height: u * 0.48), cornerRadius: u * 0.24),
               with: .linearGradient(Gradient(colors: [Color.white, Color(hex: "#E2E8F0")]),
                                     startPoint: CGPoint(x: 0, y: -u * 0.25), endPoint: CGPoint(x: 0, y: u * 0.25)))
        g.fill(Path(roundedRect: CGRect(x: u * 0.55, y: -u * 0.24, width: u * 0.45, height: u * 0.48), cornerRadius: u * 0.24),
               with: .color(Color(hex: "#1F2937")))
        g.fill(Path(ellipseIn: CGRect(x: -u * 1.35, y: -u * 0.15, width: u * 0.4, height: u * 0.3)), with: .color(Color(hex: "#FB923C")))
    }

    private static func comet(_ g: inout GraphicsContext, _ u: CGFloat) {
        var tail = Path()
        tail.move(to: CGPoint(x: 0, y: -u * 0.35))
        tail.addQuadCurve(to: CGPoint(x: -u * 3.2, y: 0), control: CGPoint(x: -u * 1.4, y: -u * 0.4))
        tail.addQuadCurve(to: CGPoint(x: 0, y: u * 0.35), control: CGPoint(x: -u * 1.4, y: u * 0.4))
        g.fill(tail, with: .linearGradient(Gradient(colors: [Color(hex: "#A5F3FC").opacity(0.85), Color(hex: "#A5F3FC").opacity(0)]),
                                           startPoint: .zero, endPoint: CGPoint(x: -u * 3.2, y: 0)))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.6, y: -u * 0.6, width: u * 1.2, height: u * 1.2)),
               with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), Color(hex: "#67E8F9").opacity(0)]),
                                     center: .zero, startRadius: 0, endRadius: u * 0.6))
        g.fill(Path(ellipseIn: CGRect(x: -u * 0.26, y: -u * 0.26, width: u * 0.52, height: u * 0.52)), with: .color(.white))
    }
}

// MARK: - Picture planets

extension PlanetPainter {
    private static var imageCache: [String: NSImage] = [:]

    static func bundleImage(_ name: String) -> NSImage? {
        if let img = imageCache[name] { return img }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) else { return nil }
        imageCache[name] = img
        return img
    }

    /// A picture item (like the pixel UFO): glow, a soft shadow and a gentle bob
    static func drawPicture(_ img: NSImage, p: PlanetDef, ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, phase: Double) {
        let accent = Color(hex: p.accent)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                 with: .radialGradient(Gradient(colors: [accent.opacity(0.45), accent.opacity(0)]),
                                       center: c, startRadius: r * 0.3, endRadius: r * 1.6))
        let bob = sin(phase * .pi * 2) * r * 0.08
        let side = r * 3.3
        let rect = CGRect(x: c.x - side / 2, y: c.y - side / 2 + bob, width: side, height: side)
        // Tractor beam
        var beam = Path()
        beam.move(to: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.25 + bob))
        beam.addLine(to: CGPoint(x: c.x + r * 0.35, y: c.y + r * 0.25 + bob))
        beam.addLine(to: CGPoint(x: c.x + r * 0.7, y: c.y + r * 1.3))
        beam.addLine(to: CGPoint(x: c.x - r * 0.7, y: c.y + r * 1.3))
        beam.closeSubpath()
        ctx.fill(beam, with: .linearGradient(Gradient(colors: [accent.opacity(0.5), accent.opacity(0)]),
                                             startPoint: CGPoint(x: c.x, y: c.y + r * 0.25), endPoint: CGPoint(x: c.x, y: c.y + r * 1.3)))
        ctx.draw(Image(nsImage: img).interpolation(.none), in: rect)
    }
}

// MARK: - Rocket currency icon

/// The rocket currency icon (from Resources/rocket.png in the app bundle)
struct RocketIcon: View {
    var size: CGFloat = 18

    static let image: NSImage? = Bundle.main.url(forResource: "rocket", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let img = Self.image {
                Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fill)
            } else {
                Text("🚀").font(.system(size: size * 0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
