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
}

enum ScheduleTemplate: String, Codable, CaseIterable, Identifiable {
    case aurora, glass, pastel, neon, paper, sunset, forest, classic

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
                    base.opacity(scheme == .dark ? (style.fill == .neon ? 1 : 0.06) : (style.fill == .neon ? 0.04 : 1))
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
