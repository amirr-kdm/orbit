import SwiftUI

/// The sun / moon switch for light and dark mode. Pressing it plays the little animation, then the app changes mode.
struct DayNightToggle: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    /// While a switch animation plays: which way it goes and when it started
    @State private var move: (toDark: Bool, start: Date)?

    // pictures in the cut: day idle 0…41 (12.5 fps), → night 42…51, night idle 52…87 (12.5 fps), → day 88…98 (25 fps)
    private static let frames = PlanetPainter.frames("modetoggle")

    var body: some View {
        Button { flip() } label: {
            // (25 pictures a second while it moves, 12 while it rests; paused when the app is in the background)
            TimelineView(.animation(minimumInterval: move == nil ? 1 / 12.5 : 1 / 25, paused: AppActivity.paused)) { ctx in
                picture(at: ctx.date)
                    .frame(width: 132, height: 59)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(.black.opacity(0.18), lineWidth: 1))
                    .shadow(color: (scheme == .dark ? Color.indigo : Color.orange).opacity(0.35), radius: 8, y: 3)
            }
        }
        .buttonStyle(.plain)
        .help(scheme == .dark ? "Switch to light mode" : "Switch to dark mode")
    }

    @ViewBuilder private func picture(at now: Date) -> some View {
        let f = Self.frames
        if f.count >= 99 {
            let i = frameIndex(now)
            Image(nsImage: f[i]).resizable().scaledToFill().scaleEffect(1.03)
        } else {
            Image(systemName: scheme == .dark ? "moon.stars.fill" : "sun.max.fill").font(.system(size: 44)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func frameIndex(_ now: Date) -> Int {
        if let m = move {
            let k = Int(now.timeIntervalSince(m.start) * 25)
            if k < 10 { return (m.toDark ? 42 : 88) + k }
            return m.toDark ? 52 : 0
        }
        let t = Int(now.timeIntervalSinceReferenceDate * 12.5)
        return scheme == .dark ? 52 + t % 36 : t % 42
    }

    private func flip() {
        guard move == nil else { return }
        let toDark = scheme != .dark
        // (the transition pictures are the 10–11 frames where the sky changes colour)
        move = (toDark, Date())
        // the app changes mode while the sun / moon is sliding across
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { store.settings.appearance = toDark ? .dark : .light }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { move = nil }
    }
}
