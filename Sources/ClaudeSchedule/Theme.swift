import AppKit
import SwiftUI

// MARK: - Appearance (light / dark)

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Fonts

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    case avenir, futura, helvetica, gillSans, optima, georgia, baskerville, typewriter, chalkboard

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System (SF Pro)"
        case .rounded: "SF Rounded"
        case .serif: "New York (Serif)"
        case .mono: "SF Mono"
        case .avenir: "Avenir Next"
        case .futura: "Futura"
        case .helvetica: "Helvetica Neue"
        case .gillSans: "Gill Sans"
        case .optima: "Optima"
        case .georgia: "Georgia"
        case .baskerville: "Baskerville"
        case .typewriter: "American Typewriter"
        case .chalkboard: "Chalkboard"
        }
    }

    /// The built-in system designs apply to the whole app
    var design: Font.Design? {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        default: nil
        }
    }

    /// Font family name for the named fonts
    var family: String? {
        switch self {
        case .avenir: "Avenir Next"
        case .futura: "Futura"
        case .helvetica: "Helvetica Neue"
        case .gillSans: "Gill Sans"
        case .optima: "Optima"
        case .georgia: "Georgia"
        case .baskerville: "Baskerville"
        case .typewriter: "American Typewriter"
        case .chalkboard: "Chalkboard SE"
        default: nil
        }
    }

    var isSystemDesign: Bool { design != nil }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let design { return .system(size: size, weight: weight, design: design) }
        return .custom(family ?? "Helvetica Neue", size: size).weight(weight)
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let design {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let nsDesign: NSFontDescriptor.SystemDesign = switch design {
            case .rounded: .rounded
            case .serif: .serif
            case .monospaced: .monospaced
            default: .default
            }
            if let d = base.fontDescriptor.withDesign(nsDesign) { return NSFont(descriptor: d, size: size) ?? base }
            return base
        }
        let nsWeight = weight == .regular ? 5 : (weight == .medium ? 6 : 8)
        return NSFontManager.shared.font(withFamily: family ?? "Helvetica Neue", traits: [], weight: nsWeight, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Templates

/// How filled cells are painted
enum CellFill {
    /// Vivid gradient, white or dark text depending on the colour
    case gradient
    /// Soft wash of the colour, normal text
    case tint
    /// Coloured outline with a glow, coloured text
    case neon
    /// Card with a coloured bar on the leading edge
    case card
    /// Frosted glass tinted with the colour
    case glass
    /// Flat tint inside a hard grid (the original look)
    case grid
    /// A sheet of ruled notebook paper with a coloured margin line
    case paper
    /// Thin coloured frame on the page, plain text (for the all-black theme)
    case outline
}

struct TemplateStyle {
    let accent: Color
    let fill: CellFill
    let corner: CGFloat
    let spacing: CGFloat
    let shadow: Bool
    /// Soft colour blobs behind the page; empty = plain background
    let blobs: [Color]
    /// Optional base tint for the page background
    let baseTint: Color?
    /// Time-slot headers drawn as capsules
    let pillHeaders: Bool
    /// How strongly `baseTint` covers the page in light and dark mode (nil: the original rule)
    var baseOpacity: (light: Double, dark: Double)? = nil
}

extension ScheduleTemplate {
    /// Page colour in light mode: a soft warm off-white with a breath of the template's accent, never plain white
    var lightPage: Color {
        let cream = NSColor(srgbRed: 0.965, green: 0.958, blue: 0.938, alpha: 1)
        let accent = NSColor(style.accent).usingColorSpace(.sRGB) ?? cream
        let k: CGFloat = 0.02
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a * (1 - k) + b * k }
        return Color(nsColor: NSColor(srgbRed: mix(cream.redComponent, accent.redComponent), green: mix(cream.greenComponent, accent.greenComponent),
                                      blue: mix(cream.blueComponent, accent.blueComponent), alpha: 1))
    }
}

enum ScheduleTemplate: String, Codable, CaseIterable, Identifiable {
    case aurora, glass, pastel, neon, paper, sunset, forest, classic
    case latte, notebook, midnight, matcha, lavender, ocean, ember, sakura
    case slate, graphite, mocha, espresso, sand, parchment, nordic, olive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: "Aurora"
        case .glass: "Frosted Glass"
        case .pastel: "Pastel"
        case .neon: "Neon"
        case .paper: "Paper"
        case .sunset: "Sunset"
        case .forest: "Forest"
        case .classic: "Classic Grid"
        case .latte: "Latte"
        case .notebook: "Notebook"
        case .midnight: "Midnight Black"
        case .matcha: "Matcha"
        case .lavender: "Lavender Dusk"
        case .ocean: "Deep Ocean"
        case .ember: "Ember"
        case .sakura: "Sakura"
        case .slate: "Slate"
        case .graphite: "Graphite"
        case .mocha: "Mocha"
        case .espresso: "Espresso"
        case .sand: "Desert Sand"
        case .parchment: "Parchment"
        case .nordic: "Nordic"
        case .olive: "Olive Grove"
        }
    }

    var subtitle: String {
        switch self {
        case .aurora: "Vivid gradient cells, soft northern-lights glow"
        case .glass: "Frosted translucent cells over colour"
        case .pastel: "Gentle tints, big rounded corners"
        case .neon: "Glowing outlines — best in dark mode"
        case .paper: "Clean cards with a colour edge"
        case .sunset: "Warm oranges and pinks"
        case .forest: "Calm greens, earthy tones"
        case .classic: "The simple timetable grid"
        case .latte: "Warm cream and coffee, cosy and calm"
        case .notebook: "Ruled paper with a coloured margin line"
        case .midnight: "Pure black, thin glowing frames"
        case .matcha: "Soft sage greens, quiet and calm"
        case .lavender: "Dusky purples over frosted glass"
        case .ocean: "Deep blues, calm like the sea at night"
        case .ember: "Glowing coals on a warm dark page"
        case .sakura: "Cherry-blossom pinks, light and gentle"
        case .slate: "Cool greys, quiet and focused"
        case .graphite: "Charcoal greys with silver frames"
        case .mocha: "Milk chocolate and caramel"
        case .espresso: "Dark roast browns, warm and deep"
        case .sand: "Sun-warmed beige and terracotta"
        case .parchment: "Old paper, sepia ink"
        case .nordic: "Frosty blue-greys, calm like snow"
        case .olive: "Olive greens and warm stone"
        }
    }

    var style: TemplateStyle {
        switch self {
        case .aurora:
            TemplateStyle(accent: Color(hex: "#5B7CFA"), fill: .gradient, corner: 12, spacing: 8, shadow: true,
                          blobs: [Color(hex: "#5B7CFA"), Color(hex: "#A855F7"), Color(hex: "#22D3EE")],
                          baseTint: nil, pillHeaders: true)
        case .glass:
            TemplateStyle(accent: Color(hex: "#0EA5E9"), fill: .glass, corner: 14, spacing: 8, shadow: true,
                          blobs: [Color(hex: "#F472B6"), Color(hex: "#60A5FA"), Color(hex: "#34D399")],
                          baseTint: nil, pillHeaders: true)
        case .pastel:
            TemplateStyle(accent: Color(hex: "#E879F9"), fill: .tint, corner: 16, spacing: 10, shadow: false,
                          blobs: [Color(hex: "#FBCFE8"), Color(hex: "#BFDBFE"), Color(hex: "#FDE68A")],
                          baseTint: nil, pillHeaders: true)
        case .neon:
            TemplateStyle(accent: Color(hex: "#22D3EE"), fill: .neon, corner: 10, spacing: 8, shadow: false,
                          blobs: [Color(hex: "#22D3EE"), Color(hex: "#F0ABFC")],
                          baseTint: Color(hex: "#0B1020"), pillHeaders: true)
        case .paper:
            TemplateStyle(accent: Color(hex: "#C2410C"), fill: .card, corner: 8, spacing: 6, shadow: true,
                          blobs: [], baseTint: Color(hex: "#F5EFE6"), pillHeaders: false)
        case .sunset:
            TemplateStyle(accent: Color(hex: "#F97316"), fill: .gradient, corner: 12, spacing: 8, shadow: true,
                          blobs: [Color(hex: "#F97316"), Color(hex: "#EC4899"), Color(hex: "#FACC15")],
                          baseTint: nil, pillHeaders: true)
        case .forest:
            TemplateStyle(accent: Color(hex: "#16A34A"), fill: .tint, corner: 10, spacing: 8, shadow: false,
                          blobs: [Color(hex: "#16A34A"), Color(hex: "#84CC16"), Color(hex: "#0D9488")],
                          baseTint: nil, pillHeaders: true)
        case .classic:
            TemplateStyle(accent: .accentColor, fill: .grid, corner: 0, spacing: 0, shadow: false,
                          blobs: [], baseTint: nil, pillHeaders: false)
        case .latte:
            TemplateStyle(accent: Color(hex: "#A0522D"), fill: .tint, corner: 14, spacing: 9, shadow: false,
                          blobs: [Color(hex: "#D4A373"), Color(hex: "#E9C46A"), Color(hex: "#F4A261")],
                          baseTint: Color(hex: "#F3E9DC"), pillHeaders: true, baseOpacity: (1, 0.07))
        case .notebook:
            TemplateStyle(accent: Color(hex: "#2563EB"), fill: .paper, corner: 4, spacing: 7, shadow: true,
                          blobs: [], baseTint: Color(hex: "#FBF8F1"), pillHeaders: false, baseOpacity: (1, 0.04))
        case .midnight:
            TemplateStyle(accent: Color(hex: "#71717A"), fill: .outline, corner: 10, spacing: 8, shadow: false,
                          blobs: [], baseTint: .black, pillHeaders: true, baseOpacity: (0, 1))
        case .matcha:
            TemplateStyle(accent: Color(hex: "#6B8F4E"), fill: .tint, corner: 12, spacing: 9, shadow: false,
                          blobs: [Color(hex: "#A3B18A"), Color(hex: "#DAD7CD"), Color(hex: "#588157")],
                          baseTint: Color(hex: "#F1F3EC"), pillHeaders: true, baseOpacity: (1, 0.05))
        case .lavender:
            TemplateStyle(accent: Color(hex: "#8B5CF6"), fill: .glass, corner: 16, spacing: 9, shadow: true,
                          blobs: [Color(hex: "#C4B5FD"), Color(hex: "#F9A8D4"), Color(hex: "#A5B4FC")],
                          baseTint: nil, pillHeaders: true)
        case .ocean:
            TemplateStyle(accent: Color(hex: "#0284C7"), fill: .gradient, corner: 12, spacing: 8, shadow: true,
                          blobs: [Color(hex: "#0EA5E9"), Color(hex: "#1E3A8A"), Color(hex: "#14B8A6")],
                          baseTint: Color(hex: "#06142B"), pillHeaders: true, baseOpacity: (0.04, 1))
        case .ember:
            TemplateStyle(accent: Color(hex: "#DC2626"), fill: .gradient, corner: 12, spacing: 8, shadow: true,
                          blobs: [Color(hex: "#B91C1C"), Color(hex: "#F59E0B"), Color(hex: "#7C2D12")],
                          baseTint: Color(hex: "#1A0F0A"), pillHeaders: true, baseOpacity: (0.03, 1))
        case .sakura:
            TemplateStyle(accent: Color(hex: "#EC4899"), fill: .tint, corner: 16, spacing: 10, shadow: false,
                          blobs: [Color(hex: "#FBCFE8"), Color(hex: "#FECDD3"), Color(hex: "#FDE68A")],
                          baseTint: Color(hex: "#FFF5F7"), pillHeaders: true, baseOpacity: (1, 0.05))
        case .slate:
            TemplateStyle(accent: Color(hex: "#475569"), fill: .tint, corner: 12, spacing: 8, shadow: false,
                          blobs: [Color(hex: "#94A3B8"), Color(hex: "#CBD5E1"), Color(hex: "#64748B")],
                          baseTint: Color(hex: "#EEF1F5"), pillHeaders: true, baseOpacity: (1, 0.05))
        case .graphite:
            TemplateStyle(accent: Color(hex: "#6B7280"), fill: .outline, corner: 10, spacing: 8, shadow: false,
                          blobs: [Color(hex: "#4B5563"), Color(hex: "#9CA3AF")],
                          baseTint: Color(hex: "#18181B"), pillHeaders: true, baseOpacity: (0.04, 1))
        case .mocha:
            TemplateStyle(accent: Color(hex: "#8B5E3C"), fill: .gradient, corner: 12, spacing: 8, shadow: true,
                          blobs: [Color(hex: "#A47148"), Color(hex: "#D4A373"), Color(hex: "#6F4E37")],
                          baseTint: Color(hex: "#F2E8DF"), pillHeaders: true, baseOpacity: (1, 0.06))
        case .espresso:
            TemplateStyle(accent: Color(hex: "#B07D4F"), fill: .gradient, corner: 12, spacing: 8, shadow: true,
                          blobs: [Color(hex: "#6F4E37"), Color(hex: "#3E2723"), Color(hex: "#C08552")],
                          baseTint: Color(hex: "#1C1410"), pillHeaders: true, baseOpacity: (0.03, 1))
        case .sand:
            TemplateStyle(accent: Color(hex: "#C2703D"), fill: .tint, corner: 14, spacing: 9, shadow: false,
                          blobs: [Color(hex: "#E9C46A"), Color(hex: "#F4A261"), Color(hex: "#E76F51")],
                          baseTint: Color(hex: "#F6EEDC"), pillHeaders: true, baseOpacity: (1, 0.06))
        case .parchment:
            TemplateStyle(accent: Color(hex: "#8B5A2B"), fill: .card, corner: 6, spacing: 7, shadow: true,
                          blobs: [],
                          baseTint: Color(hex: "#EFE3C8"), pillHeaders: false, baseOpacity: (1, 0.05))
        case .nordic:
            TemplateStyle(accent: Color(hex: "#5E81AC"), fill: .glass, corner: 14, spacing: 9, shadow: true,
                          blobs: [Color(hex: "#88C0D0"), Color(hex: "#81A1C1"), Color(hex: "#D8DEE9")],
                          baseTint: Color(hex: "#ECEFF4"), pillHeaders: true, baseOpacity: (1, 0.05))
        case .olive:
            TemplateStyle(accent: Color(hex: "#6B7B3A"), fill: .tint, corner: 12, spacing: 8, shadow: false,
                          blobs: [Color(hex: "#9CA36B"), Color(hex: "#C2B280"), Color(hex: "#556B2F")],
                          baseTint: Color(hex: "#F2F0E4"), pillHeaders: true, baseOpacity: (1, 0.05))
        }
    }

    /// Default cell colour (used when a cell has no colour picked)
    var defaultCellColor: String {
        switch self {
        case .aurora: "#5B7CFA"
        case .glass: "#0EA5E9"
        case .pastel: "#C084FC"
        case .neon: "#22D3EE"
        case .paper: "#C2410C"
        case .sunset: "#F97316"
        case .forest: "#16A34A"
        case .classic: "#8E8E93"
        case .latte: "#A0522D"
        case .notebook: "#2563EB"
        case .midnight: "#A1A1AA"
        case .matcha: "#6B8F4E"
        case .lavender: "#8B5CF6"
        case .ocean: "#0284C7"
        case .ember: "#DC2626"
        case .sakura: "#EC4899"
        case .slate: "#64748B"
        case .graphite: "#9CA3AF"
        case .mocha: "#8B5E3C"
        case .espresso: "#9C6644"
        case .sand: "#C2703D"
        case .parchment: "#8B5A2B"
        case .nordic: "#5E81AC"
        case .olive: "#6B7B3A"
        }
    }
}

/// Soft colour blobs behind a page, following the current template
struct AmbientBackground: View {
    let style: TemplateStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let base = style.baseTint {
                    // Paper is warm in light mode; Neon is deep navy in dark mode
                    if let o = style.baseOpacity { base.opacity(scheme == .dark ? o.dark : o.light) }
                    else { base.opacity(scheme == .dark ? (style.fill == .neon ? 1 : 0.06) : (style.fill == .neon ? 0.04 : 1)) }
                }
                ForEach(Array(style.blobs.enumerated()), id: \.offset) { i, color in
                    let positions: [CGPoint] = [CGPoint(x: 0.12, y: 0.08), CGPoint(x: 0.92, y: 0.9), CGPoint(x: 0.75, y: 0.1)]
                    let p = positions[i % positions.count]
                    Circle()
                        .fill(color.opacity(scheme == .dark ? 0.22 : 0.28))
                        .frame(width: geo.size.width * 0.55, height: geo.size.width * 0.55)
                        .position(x: geo.size.width * p.x, y: geo.size.height * p.y)
                        .blur(radius: max(12, geo.size.width * 0.09))
                }
            }
        }
        .ignoresSafeArea()
    }
}
