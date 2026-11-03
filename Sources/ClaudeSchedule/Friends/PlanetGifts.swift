import SwiftUI

// Gifting a store planet to a friend. The sender picks a planet and a gift box and pays the planet's price; the friend gets the
// box as a little window in the middle of the screen, taps it, and the planet pops out. If the friend already owns that planet,
// the server gives them its price in rockets instead (decided when the box is opened). Rules run on the server (supabase/planet_gifts.sql).

struct PlanetGift: Decodable, Identifiable, Hashable {
    let id: UUID
    let from_name: String
    let planet_id: String?
    var rockets: Int? = nil
    let box: String
    let note: String?
    let created_at: Date
}

struct GiftOpened: Decodable, Hashable {
    let result: String      // "planet" or "rockets"
    let planet: String?
    let amount: Int
}

@MainActor @Observable
final class PlanetGiftService {
    static let shared = PlanetGiftService()

    /// Boxes waiting for me
    private(set) var pending: [PlanetGift] = []
    @ObservationIgnored var store: AppStore?
    @ObservationIgnored private var testShown = false
    @ObservationIgnored private let client = SupabaseClient.shared

    private func message(_ error: Error) -> String { (error as? SupabaseClient.APIError)?.message ?? error.localizedDescription }

    func refresh() async {
        // Developer tool: CS_TEST_GIFT=1 shows a pretend gift box (nothing is sent or received)
        if ProcessInfo.processInfo.environment["CS_TEST_GIFT"] != nil {
            if pending.isEmpty && !testShown {
                testShown = true
                let rockets = ProcessInfo.processInfo.environment["CS_TEST_GIFT_ROCKETS"].flatMap(Int.init)
                pending = [PlanetGift(id: UUID(), from_name: "sara", planet_id: rockets == nil ? "s6_rocketkitty" : nil, rockets: rockets, box: ProcessInfo.processInfo.environment["CS_TEST_GIFT"] ?? "starry",
                                      note: "Good luck with the exams!", created_at: Date())]
            }
            return
        }
        guard await client.userID != nil,
              let data = try? await client.rpc("my_planet_gifts", [String: String]()),
              let rows = try? SupabaseClient.decoder.decode([PlanetGift].self, from: data) else { return }
        if rows.map(\.id) != pending.map(\.id) { pending = rows }
    }

    /// nil = sent; otherwise what went wrong
    func send(to friend: UUID, planet: String, box: String, note: String) async -> String? {
        struct Body: Encodable { let recipient: String; let planet: String; let box: String; let note: String? }
        do {
            let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await client.rpc("send_planet_gift", Body(recipient: friend.uuidString, planet: planet, box: box, note: n.isEmpty ? nil : n))
            await store?.walletRefresh()
            return nil
        } catch { return message(error) }
    }

    func sendRockets(to friend: UUID, amount: Int, box: String, note: String) async -> String? {
        struct Body: Encodable { let recipient: String; let amount: Int; let box: String; let note: String? }
        do {
            let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await client.rpc("send_rocket_gift", Body(recipient: friend.uuidString, amount: amount, box: box, note: n.isEmpty ? nil : n))
            await store?.walletRefresh()
            return nil
        } catch { return message(error) }
    }

    func open(_ gift: PlanetGift) async -> GiftOpened? {
        struct Body: Encodable { let gift: String }
        if ProcessInfo.processInfo.environment["CS_TEST_GIFT"] != nil {
            return gift.planet_id == nil ? GiftOpened(result: "rocketbox", planet: nil, amount: gift.rockets ?? 0) : GiftOpened(result: "planet", planet: gift.planet_id, amount: 0)
        }
        let data: Data
        do { data = try await client.rpc("open_planet_gift", Body(gift: gift.id.uuidString)) }
        catch {
            // already opened somewhere else, or taken back: it is gone, don't keep it on screen
            let m = message(error)
            if m.contains("Already opened") || m.contains("Gift not found") { finish(gift) }
            return nil
        }
        guard let opened = try? SupabaseClient.decoder.decode(GiftOpened.self, from: data) else { return nil }
        await store?.walletRefresh()
        return opened
    }

    /// The popup is done with this box
    func finish(_ gift: PlanetGift) { pending.removeAll { $0.id == gift.id } }

    /// The box to show now: it stays until it has been opened
    var next: PlanetGift? { pending.first }
}

// MARK: - Gift boxes

enum GiftBoxStyle: String, CaseIterable, Identifiable {
    case starry, royal, rose, balloon, treasure

    var id: String { rawValue }
    var name: String {
        switch self {
        case .starry: "Starry"
        case .royal: "Royal"
        case .rose: "Rosy"
        case .balloon: "Balloons"
        case .treasure: "Treasure"
        }
    }
    /// left face, right face, top, ribbon
    var colors: (left: String, right: String, top: String, ribbon: String, ribbonDark: String) {
        switch self {
        case .starry: ("#2563EB", "#1E40AF", "#14B8A6", "#FB923C", "#C2410C")
        case .royal: ("#38BDF8", "#0284C7", "#22D3EE", "#C084FC", "#7E22CE")
        case .rose: ("#F5F3FF", "#DDD6FE", "#FAF5FF", "#EC4899", "#9D174D")
        case .balloon: ("#10B981", "#047857", "#34D399", "#FACC15", "#A16207")
        case .treasure: ("#B45309", "#78350F", "#D97706", "#FBBF24", "#92400E")
        }
    }
    var hasBow: Bool { self != .treasure }
    var hasBalloons: Bool { self == .balloon }
    var pattern: Pattern {
        switch self {
        case .starry, .royal, .balloon: .stars
        case .rose: .dots
        case .treasure: .planks
        }
    }
    enum Pattern { case stars, dots, planks }
}

enum GiftBoxPart { case body, lid }

/// One gift box, drawn in code. `lift` raises the lid (0…1); the body and the lid are separate layers so a planet can rise between them.
struct GiftBoxLayer: View {
    let style: GiftBoxStyle
    let part: GiftBoxPart
    var lift: Double = 0
    var time: Double = 0

    var body: some View {
        Canvas { ctx, size in Self.draw(style, part, lift: lift, time: time, ctx: &ctx, size: size) }
    }

    static func draw(_ style: GiftBoxStyle, _ part: GiftBoxPart, lift: Double, time: Double, ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height) * (style.hasBalloons ? 0.37 : 0.46)
        let cx = size.width / 2, yb = size.height * 0.8
        let h = s * 0.56
        let col = style.colors
        func C(_ hex: String) -> Color { Color(hex: hex) }
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

        // body corners
        let B = pt(cx, yb), BL = pt(cx - s * 0.5, yb - s * 0.25), BR = pt(cx + s * 0.5, yb - s * 0.25)
        func up(_ p: CGPoint, _ d: Double) -> CGPoint { CGPoint(x: p.x, y: p.y - d) }
        func quad(_ a: CGPoint, _ b: CGPoint, _ c2: CGPoint, _ d: CGPoint) -> Path {
            var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: c2); p.addLine(to: d); p.closeSubpath(); return p
        }

        // a face given its origin and two edge vectors: point(u, v)
        struct Face {
            let o: CGPoint, a: CGPoint, b: CGPoint
            func at(_ u: Double, _ v: Double) -> CGPoint { CGPoint(x: o.x + a.x * u + b.x * v, y: o.y + a.y * u + b.y * v) }
            func rect(_ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double) -> Path {
                var p = Path(); p.move(to: at(u0, v0)); p.addLine(to: at(u1, v0)); p.addLine(to: at(u1, v1)); p.addLine(to: at(u0, v1)); p.closeSubpath(); return p
            }
        }

        func star(_ c2: CGPoint, _ r: Double) -> Path {
            var p = Path()
            for i in 0..<10 {
                let a = Double(i) / 10 * .pi * 2 - .pi / 2, rr = i % 2 == 0 ? r : r * 0.45
                let q = CGPoint(x: c2.x + cos(a) * rr, y: c2.y + sin(a) * rr)
                i == 0 ? p.move(to: q) : p.addLine(to: q)
            }
            p.closeSubpath(); return p
        }

        /// Pattern on a body face (clipped to it)
        func decorate(_ face: Face, _ path: Path, light: Bool) {
            ctx.drawLayer { l in
                l.clip(to: path)
                switch style.pattern {
                case .stars:
                    for (u, v, r) in [(0.18, 0.3, 0.09), (0.74, 0.22, 0.07), (0.35, 0.72, 0.1), (0.85, 0.7, 0.08), (0.58, 0.45, 0.06)] {
                        l.fill(star(face.at(u, v), s * r), with: .color(.white.opacity(light ? 0.28 : 0.2)))
                    }
                case .dots:
                    for u in stride(from: 0.12, through: 0.9, by: 0.2) { for v in stride(from: 0.15, through: 0.9, by: 0.25) {
                        l.fill(Path(ellipseIn: CGRect(x: face.at(u, v).x - s * 0.02, y: face.at(u, v).y - s * 0.02, width: s * 0.04, height: s * 0.04)),
                               with: .color(Color(hex: "#C4B5FD").opacity(0.9)))
                    } }
                case .planks:
                    for v in [0.33, 0.66] { l.stroke(Path { p in p.move(to: face.at(0, v)); p.addLine(to: face.at(1, v)) }, with: .color(.black.opacity(0.25)), lineWidth: s * 0.012) }
                }
            }
        }

        let lidRise = lift * s * 1.1

        if part == .body {
            // inside of the box (seen once the lid is off)
            let inner = quad(up(BL, h), up(B, h), up(BR, h), up(pt(cx, yb - s * 0.5), h))
            // left and right faces
            let left = Face(o: BL, a: CGPoint(x: B.x - BL.x, y: B.y - BL.y), b: CGPoint(x: 0, y: -h))
            let right = Face(o: B, a: CGPoint(x: BR.x - B.x, y: BR.y - B.y), b: CGPoint(x: 0, y: -h))
            ctx.fill(inner, with: .color(C(col.right).opacity(0.55)))
            ctx.fill(inner, with: .color(.black.opacity(0.5)))
            let lp = left.rect(0, 1, 0, 1), rp = right.rect(0, 1, 0, 1)
            ctx.fill(lp, with: .linearGradient(Gradient(colors: [C(col.left), C(col.left).opacity(0.85)]), startPoint: BL, endPoint: B))
            ctx.fill(rp, with: .linearGradient(Gradient(colors: [C(col.right), C(col.right).opacity(0.85)]), startPoint: B, endPoint: BR))
            decorate(left, lp, light: true); decorate(right, rp, light: false)
            // ribbon down both faces
            ctx.fill(left.rect(0.43, 0.57, 0, 1), with: .color(C(col.ribbon)))
            ctx.fill(right.rect(0.43, 0.57, 0, 1), with: .color(C(col.ribbonDark)))
            if !style.hasBow {
                // a chest: a second strap and a lock on the front corner
                ctx.fill(left.rect(0.05, 0.14, 0, 1), with: .color(C(col.ribbon))); ctx.fill(right.rect(0.86, 0.95, 0, 1), with: .color(C(col.ribbonDark)))
            }
            ctx.stroke(lp, with: .color(.black.opacity(0.25)), lineWidth: s * 0.015)
            ctx.stroke(rp, with: .color(.black.opacity(0.25)), lineWidth: s * 0.015)
            // the soft shadow on the ground
            var g = ctx; g.addFilter(.blur(radius: s * 0.06))
            g.fill(Path(ellipseIn: CGRect(x: cx - s * 0.62, y: yb + s * 0.02, width: s * 1.24, height: s * 0.2)), with: .color(.black.opacity(0.28)))
            return
        }

        // ----- the lid (with the bow, and the balloons) -----
        let k = 1.07                                    // the lid is a little wider than the box
        let lidH = s * 0.2
        let base = h - s * 0.04 + lidRise
        let tb = up(B, base + lidH), tl = up(BL, base + lidH), tr = up(BR, base + lidH)
        let tk = up(pt(cx, yb - s * 0.5), base + lidH)
        func grow(_ p: CGPoint) -> CGPoint { CGPoint(x: cx + (p.x - cx) * k, y: (yb - s * 0.25 - base - lidH) + (p.y - (yb - s * 0.25 - base - lidH)) * k) }
        let Tb = grow(tb), Tl = grow(tl), Tr = grow(tr), Tk = grow(tk)
        // skirt faces go DOWN from the lid top
        let sl = quad(Tl, Tb, CGPoint(x: Tb.x, y: Tb.y + lidH), CGPoint(x: Tl.x, y: Tl.y + lidH))
        let sr = quad(Tb, Tr, CGPoint(x: Tr.x, y: Tr.y + lidH), CGPoint(x: Tb.x, y: Tb.y + lidH))
        let top = quad(Tl, Tb, Tr, Tk)
        ctx.fill(sl, with: .color(C(col.left))); ctx.fill(sr, with: .color(C(col.right)))
        ctx.stroke(sl, with: .color(.black.opacity(0.25)), lineWidth: s * 0.012); ctx.stroke(sr, with: .color(.black.opacity(0.25)), lineWidth: s * 0.012)
        ctx.fill(top, with: .linearGradient(Gradient(colors: [C(col.top), C(col.top).opacity(0.8)]), startPoint: Tk, endPoint: Tb))
        ctx.stroke(top, with: .color(.white.opacity(0.35)), lineWidth: s * 0.012)
        // ribbon crossing the lid
        let tf = Face(o: Tl, a: CGPoint(x: Tb.x - Tl.x, y: Tb.y - Tl.y), b: CGPoint(x: Tk.x - Tl.x, y: Tk.y - Tl.y))
        ctx.fill(tf.rect(0.43, 0.57, 0, 1), with: .color(C(col.ribbon)))
        ctx.fill(tf.rect(0, 1, 0.43, 0.57), with: .color(C(col.ribbon)))
        let sf = Face(o: Tl, a: CGPoint(x: Tb.x - Tl.x, y: Tb.y - Tl.y), b: CGPoint(x: 0, y: lidH))
        ctx.fill(sf.rect(0.43, 0.57, 0, 1), with: .color(C(col.ribbon)))
        let sf2 = Face(o: Tb, a: CGPoint(x: Tr.x - Tb.x, y: Tr.y - Tb.y), b: CGPoint(x: 0, y: lidH))
        ctx.fill(sf2.rect(0.43, 0.57, 0, 1), with: .color(C(col.ribbonDark)))

        let mid = tf.at(0.5, 0.5)
        if style.hasBow {
            // two loops and a knot
            for dir in [-1.0, 1.0] {
                var g = ctx
                g.translateBy(x: mid.x, y: mid.y); g.rotate(by: .degrees(dir * 28)); g.translateBy(x: -mid.x, y: -mid.y)
                let loop = Path(ellipseIn: CGRect(x: mid.x + (dir > 0 ? 0 : -s * 0.36), y: mid.y - s * 0.34, width: s * 0.36, height: s * 0.28))
                let hole = Path(ellipseIn: CGRect(x: mid.x + (dir > 0 ? s * 0.07 : -s * 0.29), y: mid.y - s * 0.3, width: s * 0.22, height: s * 0.17))
                var both = loop; both.addPath(hole)
                g.fill(both, with: .linearGradient(Gradient(colors: [C(col.ribbon), C(col.ribbonDark)]), startPoint: CGPoint(x: mid.x, y: mid.y - s * 0.35), endPoint: mid), style: FillStyle(eoFill: true))
                g.stroke(loop, with: .color(.black.opacity(0.2)), lineWidth: s * 0.012)
            }
            for dir in [-1.0, 1.0] {   // the two tails
                var tail = Path()
                tail.move(to: mid); tail.addLine(to: CGPoint(x: mid.x + dir * s * 0.22, y: mid.y + s * 0.2)); tail.addLine(to: CGPoint(x: mid.x + dir * s * 0.08, y: mid.y + s * 0.16)); tail.closeSubpath()
                ctx.fill(tail, with: .color(C(col.ribbonDark)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: mid.x - s * 0.07, y: mid.y - s * 0.07, width: s * 0.14, height: s * 0.12)), with: .color(C(col.ribbon)))
            ctx.stroke(Path(ellipseIn: CGRect(x: mid.x - s * 0.07, y: mid.y - s * 0.07, width: s * 0.14, height: s * 0.12)), with: .color(.black.opacity(0.2)), lineWidth: s * 0.01)
        } else {
            // a chest's clasp
            let clasp = Path(roundedRect: CGRect(x: Tb.x - s * 0.07, y: Tb.y + lidH * 0.1, width: s * 0.14, height: s * 0.2), cornerRadius: s * 0.03)
            ctx.fill(clasp, with: .color(C(col.ribbon))); ctx.stroke(clasp, with: .color(C(col.ribbonDark)), lineWidth: s * 0.015)
            ctx.fill(Path(ellipseIn: CGRect(x: Tb.x - s * 0.02, y: Tb.y + lidH * 0.1 + s * 0.06, width: s * 0.04, height: s * 0.04)), with: .color(C(col.ribbonDark)))
        }

        if style.hasBalloons {
            let sway = sin(time * 1.6) * s * 0.03
            let anchor = CGPoint(x: mid.x, y: mid.y - s * 0.12)
            let floatUp = lift * s * 2.6
            let balloons: [(Double, Double, Double, String)] = [(-0.34, -0.7, 0.2, "#A855F7"), (0.0, -0.95, 0.22, "#D946EF"), (0.34, -0.72, 0.2, "#C084FC"), (-0.12, -0.74, 0.19, "#E879F9"), (0.18, -0.8, 0.18, "#A78BFA")]
            for (dx, dy, br, hex) in balloons {
                let p = CGPoint(x: anchor.x + s * dx + sway, y: anchor.y + s * dy - floatUp)
                var string = Path(); string.move(to: anchor); string.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s * br * 1.2), control: CGPoint(x: (p.x + anchor.x) / 2 - sway, y: (p.y + anchor.y) / 2))
                ctx.stroke(string, with: .color(.white.opacity(0.55)), lineWidth: s * 0.01)
                let body = Path(ellipseIn: CGRect(x: p.x - s * br * 0.82, y: p.y - s * br, width: s * br * 1.64, height: s * br * 2))
                ctx.fill(body, with: .radialGradient(Gradient(colors: [C(hex).opacity(0.75), C(hex)]), center: CGPoint(x: p.x - s * br * 0.3, y: p.y - s * br * 0.4), startRadius: 0, endRadius: s * br * 1.4))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * br * 0.5, y: p.y - s * br * 0.7, width: s * br * 0.4, height: s * br * 0.6)), with: .color(.white.opacity(0.4)))
            }
        }
    }
}

/// The box with its lid, for small previews
struct GiftBoxPreview: View {
    let style: GiftBoxStyle
    var size: CGFloat = 96
    var body: some View {
        ZStack {
            GiftBoxLayer(style: style, part: .body)
            GiftBoxLayer(style: style, part: .lid, time: 0.4)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Receiving a gift

/// The little window in the middle of the screen: tap the box and the planet comes out
struct GiftPopup: View {
    let gift: PlanetGift
    @Environment(AppStore.self) private var store
    @State private var gifts = PlanetGiftService.shared
    @State private var openedAt: Date?
    @State private var result: GiftOpened?
    @State private var failed = false
    @State private var appear = false

    private var planet: PlanetDef? { PlanetCatalog.planet(gift.planet_id) }
    private var isRockets: Bool { gift.planet_id == nil }
    private var style: GiftBoxStyle { GiftBoxStyle(rawValue: gift.box) ?? .starry }

    private func ease(_ t: Double) -> Double { let x = min(1, max(0, t)); return 1 - pow(1 - x, 3) }
    private func back(_ t: Double) -> Double { let x = min(1, max(0, t)); let c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { }
            VStack(spacing: 10) {
                Text(result == nil ? "🎁 A gift for you!" : (result?.result == "rockets" ? "You already had it!" : "It's yours! 🎉"))
                    .font(.title2.weight(.heavy)).foregroundStyle(.white)
                Text("from @\(gift.from_name)").font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                if let note = gift.note, !note.isEmpty {
                    Text("“\(note)”").font(.callout).italic().foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                stage
                footer
            }
            .padding(.vertical, 24).padding(.horizontal, 20)
            .frame(width: 430)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#3B1D78"), Color(hex: "#1B0F44"), Color(hex: "#0B0720")], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
                    .shadow(color: Color(hex: "#7C3AED").opacity(0.5), radius: 40)
            )
            .environment(\.colorScheme, .dark)
            .scaleEffect(appear ? 1 : 0.85).opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.45)) { appear = true } }
    }

    private var stage: some View {
        TimelineView(.animation(paused: AppActivity.paused)) { t in
            let now = t.date.timeIntervalSinceReferenceDate
            let p = openedAt.map { min(1.3, t.date.timeIntervalSince($0) / 2.1) } ?? 0
            let lift = ease((p - 0.2) / 0.28)
            let rise = back((p - 0.38) / 0.5)
            let idleBob = openedAt == nil ? sin(now * 2.2) * 5 : 0
            let shake = openedAt != nil && p < 0.2 ? sin(p * 140) * 3 * (1 - p / 0.2) : 0
            ZStack {
                // twinkling background stars
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: "gift-stars")
                    for k in 0..<26 {
                        let x = rng.next() * size.width, y = rng.next() * size.height, r = 1 + rng.next() * 2.4
                        let a = 0.25 + 0.55 * (0.5 + 0.5 * sin(now * (0.8 + rng.next()) + Double(k)))
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(a)))
                    }
                    // the burst when the lid comes off
                    if p > 0.22 {
                        let c = CGPoint(x: size.width / 2, y: size.height * 0.55)
                        let t2 = (p - 0.22) / 0.9
                        for i in 0..<14 {
                            let a = Double(i) / 14 * .pi * 2 + now * 0.4
                            var ray = Path(); ray.move(to: c)
                            let len = size.width * (0.18 + 0.4 * min(1, t2))
                            ray.addLine(to: CGPoint(x: c.x + cos(a - 0.06) * len, y: c.y + sin(a - 0.06) * len))
                            ray.addLine(to: CGPoint(x: c.x + cos(a + 0.06) * len, y: c.y + sin(a + 0.06) * len)); ray.closeSubpath()
                            ctx.fill(ray, with: .color(Color(hex: "#FDE68A").opacity(max(0, 0.3 - 0.25 * t2))))
                        }
                        var rng2 = SeededRandom(seed: "gift-confetti")
                        for _ in 0..<34 {
                            let a = rng2.next() * .pi * 2, sp = 0.35 + rng2.next() * 0.9
                            let d = size.width * sp * min(1, t2) * 0.62
                            let px = c.x + cos(a) * d, py = c.y + sin(a) * d + t2 * t2 * 30
                            let colors = ["#FDE047", "#F472B6", "#38BDF8", "#A78BFA", "#4ADE80"]
                            let rect = CGRect(x: px - 3, y: py - 3, width: 6, height: 9)
                            var g = ctx; g.translateBy(x: px, y: py); g.rotate(by: .degrees(a * 180 / .pi + t2 * 360)); g.translateBy(x: -px, y: -py)
                            g.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color(hex: colors[Int(rng2.next() * 5) % 5]).opacity(max(0, 1 - max(0, t2 - 0.6) * 2.4))))
                        }
                    }
                }
                GiftBoxLayer(style: style, part: .body, time: now)
                    .offset(x: shake, y: idleBob)
                if isRockets, openedAt != nil {
                    ZStack {
                        // a fountain of little rockets
                        ForEach(0..<12, id: \.self) { i in
                            let a = -Double.pi / 2 + (Double(i) - 5.5) / 11 * 2.3
                            let d = 60 + Double((i * 37) % 70)
                            let t = min(1, max(0, (p - 0.34 - Double(i) * 0.012) / 0.7))
                            RocketIcon(size: 26 + CGFloat(i % 3) * 7)
                                .rotationEffect(.radians(a + .pi / 2))
                                .offset(x: cos(a) * d * ease(t) * 1.7, y: sin(a) * d * ease(t) * 1.7 + t * t * 55)
                                .opacity(t > 0 && t < 1 ? 1 : 0)
                        }
                        VStack(spacing: 4) {
                            RocketIcon(size: 110)
                                .rotationEffect(.degrees(sin(now * 3) * 4))
                            Text("+\(Int(Double(gift.rockets ?? 0) * ease((p - 0.5) / 0.6)).formatted())")
                                .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: "#FDE68A")).monospacedDigit()
                        }
                    }
                    .scaleEffect(0.25 + 0.8 * rise)
                    .offset(y: 70 - 150 * rise + idleBob)
                    .opacity(min(1, max(0, (p - 0.36) * 8)))
                    .shadow(color: Color(hex: "#FDE047").opacity(0.5 * rise), radius: 24)
                } else if let planet, openedAt != nil {
                    PlanetView(planet: planet, size: 190, phase: now / 8)
                        .scaleEffect(0.25 + 0.8 * rise)
                        .offset(y: 70 - 175 * rise + idleBob)
                        .opacity(min(1, max(0, (p - 0.36) * 8)))
                        .shadow(color: .white.opacity(0.4 * rise), radius: 22)
                }
                GiftBoxLayer(style: style, part: .lid, lift: lift, time: now)
                    .offset(x: shake + lift * 70, y: idleBob - lift * 20)
                    .rotationEffect(.degrees(lift * 24))
                    .opacity(1 - max(0, (p - 0.5) * 3))
            }
            .frame(width: 330, height: 330)
            .contentShape(Rectangle())
            .onTapGesture { open() }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let result, result.result == "rocketbox" {
                HStack(spacing: 6) { Text("You got"); RocketIcon(size: 18); Text("\(result.amount.formatted()) rockets").bold(); Text("from @\(gift.from_name)") }
                    .font(.callout).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
                Button("Done") { gifts.finish(gift) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else if let result, let planet {
                if result.result == "rockets" {
                    HStack(spacing: 6) { Text("\(planet.name) was already yours, so you got"); RocketIcon(size: 18); Text("\(result.amount.formatted()) 🚀").bold() }
                        .font(.callout).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
                } else {
                    Text("\(planet.name) is waiting on your shelf: My Galaxy → Your Store Planets.")
                        .font(.callout).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
                }
                Button("Done") { gifts.finish(gift) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else if failed {
                Text("Couldn't open it right now. Check your connection and tap the box again.").font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else if openedAt == nil {
                Label("Tap the box to open it", systemImage: "hand.tap.fill").font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.8)).buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.5))
            } else {
                Text("…").foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(minHeight: 70)
    }

    private func open() {
        guard openedAt == nil || failed, result == nil else { return }
        failed = false
        openedAt = Date()
        Task {
            if let r = await gifts.open(gift) {
                // let the planet finish popping out before the text appears
                try? await Task.sleep(for: .milliseconds(1700))
                withAnimation(.easeOut(duration: 0.3)) { result = r }
            } else {
                openedAt = nil; failed = true
            }
        }
    }
}

// MARK: - Sending a gift

struct GiftSendSheet: View {
    /// Opened from a friend's profile: the friend is fixed, pick the planet. Opened from a planet: the planet is fixed, pick the friend.
    var friendID: UUID?
    var friendName: String = ""
    var planet: PlanetDef?

    init(friendID: UUID, friendName: String) { self.friendID = friendID; self.friendName = friendName; self.planet = nil }
    init(planet: PlanetDef) { self.planet = planet; self.friendID = nil }

    @Environment(AppStore.self) private var store
    @Environment(FriendsService.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var gifts = PlanetGiftService.shared
    @State private var planetID: String?
    @State private var rocketMode = false
    @State private var amount = 100
    @State private var toFriend: UUID?
    @State private var box: GiftBoxStyle = .starry
    @State private var note = ""
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false

    private var planets: [PlanetDef] { PlanetCatalog.storeAvailable.sorted { $0.price < $1.price } }
    private var chosen: PlanetDef? { planet ?? planetID.flatMap { PlanetCatalog.planet($0) } }
    private var canSend: Bool { recipient != nil && !sending && (rocketMode ? (amount >= 10 && amount <= store.rocketBalance) : chosen != nil) }
    private var recipient: UUID? { friendID ?? toFriend }
    private var recipientName: String {
        if let friendID { return friendName.isEmpty ? (friends.people[friendID]?.profile.name ?? "friend") : friendName }
        return toFriend.flatMap { id in friends.friends.first { $0.id == id }?.profile.name } ?? "a friend"
    }

    private var alreadyOwnsNote: String {
        let who = planet != nil ? "your friend" : "@" + friendName
        if rocketMode { return "The rockets leave your balance now and go to \(who) when they open the box." }
        return "If \(who) already has this planet, they get its price in rockets instead."
    }

    private var title: String { planet != nil ? "Gift \(planet?.name ?? "")" : (rocketMode ? "Gift rockets to @\(friendName)" : "Gift a planet to @\(friendName)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sent {
                VStack(spacing: 12) {
                    GiftBoxPreview(style: box, size: 150)
                    Text("Sent! 🎁").font(.title.weight(.heavy))
                    Text("@\(recipientName) will see the box the next time they open Orbit.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                HStack {
                    Label(title, systemImage: "gift.fill").font(.title3.weight(.bold))
                    Spacer()
                    HStack(spacing: 4) { RocketIcon(size: 16); Text(store.rocketBalance.formatted()).font(.callout.weight(.semibold).monospacedDigit()) }
                        .foregroundStyle(.secondary)
                }
                if friendID != nil {
                    Picker("", selection: $rocketMode) { Text("Planet").tag(false); Text("Rockets").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
                if let planet {
                    HStack(spacing: 12) {
                        PlanetView(planet: planet, size: 70, phase: 0.1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planet.name).font(.headline)
                            HStack(spacing: 4) { RocketIcon(size: 13); Text(planet.price.formatted()).font(.callout.weight(.bold).monospacedDigit()) }
                        }
                    }
                    Text("1 · Pick a friend").font(.headline)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                            ForEach(friends.friends, id: \.id) { f in
                                HStack(spacing: 8) {
                                    Avatar(name: f.profile.name, color: .gray, size: 30, planet: f.profile.avatar)
                                    Text(f.profile.name).font(.callout.weight(.semibold)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(toFriend == f.id ? 0.14 : 0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(toFriend == f.id ? Color.accentColor : .clear, lineWidth: 2))
                                .contentShape(Rectangle())
                                .onTapGesture { toFriend = f.id }
                            }
                        }
                        .padding(2)
                    }
                    .frame(height: 130)
                } else if rocketMode {
                    Text("1 · How many rockets?").font(.headline)
                    HStack(spacing: 8) {
                        TextField("Amount", value: $amount, format: .number).textFieldStyle(.roundedBorder).frame(width: 120)
                        RocketIcon(size: 20)
                        ForEach([50, 100, 250, 500, 1000], id: \.self) { n in Button("\(n)") { amount = n }.controlSize(.small) }
                    }
                    if amount > store.rocketBalance { Text("You only have \(store.rocketBalance.formatted()) rockets.").font(.caption).foregroundStyle(.orange) }
                    else if amount < 10 { Text("At least 10 rockets.").font(.caption).foregroundStyle(.orange) }
                    Spacer(minLength: 0)
                } else {
                    Text("1 · Pick a planet").font(.headline)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                            ForEach(planets) { p in
                                let ok = store.rocketBalance >= p.price
                                VStack(spacing: 4) {
                                    PlanetView(planet: p, size: 74, phase: 0.1)
                                    Text(p.name).font(.caption.weight(.semibold)).lineLimit(1)
                                    HStack(spacing: 3) { RocketIcon(size: 11); Text(p.price.formatted()).font(.caption2.weight(.bold).monospacedDigit()) }
                                }
                                .frame(maxWidth: .infinity).padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(planetID == p.id ? 0.14 : 0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(planetID == p.id ? Color.accentColor : .clear, lineWidth: 2))
                                .opacity(ok ? 1 : 0.4)
                                .contentShape(Rectangle())
                                .onTapGesture { if ok { planetID = p.id } }
                                .help(ok ? p.blurb : "You need \((p.price - store.rocketBalance).formatted()) more rockets")
                            }
                        }
                        .padding(2)
                    }
                    .frame(height: 230)
                }

                Text("2 · Pick a gift box").font(.headline)
                HStack(spacing: 8) {
                    ForEach(GiftBoxStyle.allCases) { s in
                        VStack(spacing: 2) {
                            GiftBoxPreview(style: s, size: 78)
                            Text(s.name).font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(box == s ? 0.14 : 0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(box == s ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture { box = s }
                    }
                }
                TextField("Add a short note (optional)", text: $note).textFieldStyle(.roundedBorder)
                Label(alreadyOwnsNote, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button {
                        guard let to = recipient, rocketMode || chosen != nil else { return }
                        sending = true; error = nil
                        Task {
                            let e: String?
                            if rocketMode { e = await gifts.sendRockets(to: to, amount: amount, box: box.rawValue, note: String(note.prefix(120))) }
                            else { e = await gifts.send(to: to, planet: chosen!.id, box: box.rawValue, note: String(note.prefix(120))) }
                            if let e { error = e }
                            else { withAnimation { sent = true } }
                            sending = false
                        }
                    } label: {
                        if rocketMode { Label("Send · \(amount.formatted()) 🚀", systemImage: "paperplane.fill") }
                        else if let p = chosen, recipient != nil { Label("Send · \(p.price.formatted()) 🚀", systemImage: "paperplane.fill") }
                        else { Text(planet != nil ? "Pick a friend" : "Pick a planet") }
                    }
                    .buttonStyle(.borderedProminent).disabled(!canSend).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

/// Developer tool: CS_RENDER_GIFT=/path.png draws every gift box, closed and opening
@MainActor
enum GiftSheet {
    static func render(to url: URL) {
        let planet = PlanetCatalog.planet("s6_rocketkitty") ?? PlanetCatalog.all[0]
        let view = VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(GiftBoxStyle.allCases) { s in
                    VStack { GiftBoxPreview(style: s, size: 170); Text(s.name).font(.caption).foregroundStyle(.white) }
                }
            }
            HStack(spacing: 6) {
                ForEach([(0.0, 0.0), (0.4, 0.0), (0.8, 0.45), (1.0, 0.9), (1.0, 1.0)], id: \.0) { lift, rise in
                    ZStack {
                        GiftBoxLayer(style: .balloon, part: .body)
                        PlanetView(planet: planet, size: 120).scaleEffect(0.3 + 0.7 * rise).offset(y: 40 - 100 * rise).opacity(rise > 0 ? 1 : 0)
                        GiftBoxLayer(style: .balloon, part: .lid, lift: lift).offset(x: lift * 40, y: -lift * 10).rotationEffect(.degrees(lift * 24)).opacity(1 - rise * 0.3)
                    }.frame(width: 170, height: 170)
                }
            }
        }
        .padding(16).background(Color(hex: "#1B0F44")).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
