import SwiftUI

/// The black shape that hangs from the top of the screen around the notch
struct NotchbitView: View {
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @State private var model = NotchbitModel.shared
    @State private var music = NowPlaying.shared
    @State private var leitner = LeitnerStore.shared
    @AppStorage("notchbit.planet") private var planetChoice = ""
    @AppStorage("notchbit.leitner") private var showLeitner = false
    @AppStorage("notchbit.planetSize") private var planetSize = 30.0
    @AppStorage("notchbit.speed") private var speed = 1.0
    @AppStorage("notchbit.logo") private var logoID = "headphones"
    @AppStorage("notchbit.logoScales") private var logoScales = "{}"
    @AppStorage("notchbit.planetMotion") private var planetMotion = true

    @State private var bounce = false
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity = 0.0
    @State private var newTask = ""
    @State private var picking = false
    /// The planet turning, drawn once as a few pictures and played back by Core Animation
    @State private var planetFrames: [NSImage] = []
    /// Which planet / size the frames above belong to: the player is rebuilt only when they are really new
    @State private var framesKey = ""
    @State private var loopSeconds = 12.0
    @FocusState private var typing: Bool

    private var planet: PlanetDef? {
        PlanetCatalog.planet(planetChoice.isEmpty ? store.avatarPlanet : planetChoice)
            ?? PlanetCatalog.planet("terra") ?? PlanetCatalog.all.first
    }
    private var accent: Color { planet.map { Color(hex: $0.colors[min(1, $0.colors.count - 1)]) } ?? .indigo }

    var body: some View {
        _ = model.settingsRevision   // redraw as soon as a Notchbit setting changes
        let level = model.level
        return chrome(level)
                        .animation(.spring(response: 0.42 / max(0.3, speed), dampingFraction: 0.78), value: level)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.leftWing)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.rightWing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(Reactions(onPhase: pulse, onTyping: { model.editing = $0 }, typing: typing, planetKey: planetKey, makeFrames: makePlanetFrames))
            .onChange(of: picking) { _, _ in model.listOpen = model.tab == .tasks || picking }
            .onChange(of: model.tab) { _, t in model.listOpen = t == .tasks || picking }
            .environment(\.colorScheme, .dark)
    }

    private var planetKey: String { "\(planet?.id ?? "")|\(Int(planetSize))" }

    /// The black shape and what is in it.
    /// The shape grows and shrinks (animated); the content is laid out at its final size and just fades in once the shape has opened a little,
    /// and out before it closes. No clipping or masking is needed, which keeps the animation light.
    private func chrome(_ level: NotchbitModel.Level) -> some View {
        let size = model.size(level)
        // What is showing is laid out at its own size at once; only when closing does the old (bigger) layout stay, so the content can fade out in place.
        // (Laying a small view out in the old big frame put it below the shrinking shape, on the desktop.)
        let layout = model.size(level == .closed ? model.layoutLevel : level)
        let fade: AnyTransition = .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                                              removal: .opacity.animation(.easeIn(duration: 0.08)))
        return ZStack(alignment: .top) {
            shaped(level).frame(width: size.width, height: size.height)
            VStack(spacing: 0) {
                // the row with the planet follows the shape's edges while it grows, so the planet slides out smoothly with it
                topRow(level).frame(width: size.width, height: model.notchH)
                // what is below is laid out at its final size and fades in
                Group {
                    switch level {
                    case .closed:
                        if model.hudDropShown, let h = model.hud { dropHUD(h).transition(.opacity.combined(with: .move(edge: .top))) }
                    case .peek: peek.transition(fade)
                    case .full: full.transition(fade)
                    }
                }
                .frame(width: layout.width, height: max(0, layout.height - model.notchH), alignment: .top)
            }
            .frame(width: max(size.width, layout.width), height: layout.height, alignment: .top)
            .overlay(alignment: .bottom) {
                if level == .peek {
                    Capsule().fill(.white.opacity(0.22)).frame(width: 30, height: 3).padding(.bottom, 5)
                        .allowsHitTesting(false).transition(fade)
                }
            }
        }
        .frame(width: max(size.width, layout.width), height: max(size.height, layout.height), alignment: .top)
    }

    private func notchShape(_ level: NotchbitModel.Level) -> some Shape {
        let r: CGFloat = level == .closed ? (model.hudDropShown ? 24 : 12) : 26
        return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0, style: .continuous)
    }

    // MARK: Look

    /// The black shape with its rounded bottom corners
    private func shaped(_ level: NotchbitModel.Level) -> some View {
        background(level).clipShape(notchShape(level))
    }

    private func background(_ level: NotchbitModel.Level) -> some View {
        ZStack {
            Color.black
            if level != .closed {
                LinearGradient(colors: [accent.opacity(0.30), Color(hex: "#6366F1").opacity(0.12), .clear],
                               startPoint: .bottomLeading, endPoint: .topTrailing)
                RadialGradient(colors: [Color(hex: "#EC4899").opacity(0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 200)
                Stars()
            }
        }
        .overlay(alignment: .bottom) {
            if level != .closed {
                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
            }
        }
    }

    // MARK: Top row (beside the notch)

    private func topRow(_ level: NotchbitModel.Level) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if model.hudInline && level == .closed, let h = model.hud {
                    hudIcon(h).transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if model.badgeShown {
                    Text("\(leitner.totalDue)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Color.orange.gradient))
                        .help("Words to review today")
                        .onTapGesture { openLeitner() }
                }
                if !(model.hudInline && level == .closed) { icon }
            }
            .padding(level == .closed ? .trailing : .leading, level == .closed ? 0 : 12)
            .frame(width: model.leftWing, alignment: level == .closed ? .trailing : .leading)
            Spacer(minLength: model.notchW)
            if level == .closed {
                if model.hudInline, let h = model.hud {
                    hudBar(h).frame(width: model.rightWing, alignment: .trailing)
                } else if model.batteryShown, let h = model.hud {
                    batteryTag(h).frame(width: model.rightWing, alignment: .leading)
                } else if model.lockShown, let l = model.lock {
                    lockTag(l).frame(width: model.rightWing, alignment: .leading)
                } else {
                    rightTag.frame(width: model.rightWing, alignment: .leading)
                }
            } else {
                dateTag.padding(.trailing, 12)
            }
        }
        .frame(height: model.notchH)
    }

    // MARK: Battery and lock (tiny, on the right of the notch)

    private func batteryTag(_ h: NotchbitModel.HUD) -> some View {
        let c = hudColor(h, h.value)
        return HStack(spacing: 4) {
            Image(systemName: hudSymbol(h)).font(.system(size: 12, weight: .semibold)).foregroundStyle(c)
                .contentTransition(.symbolEffect(.replace))
            Text("\(Int((h.value * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.92))
        }
        .padding(.leading, 3)
        .transition(.opacity)
    }

    private func lockTag(_ l: NotchbitModel.LockState) -> some View {
        Image(systemName: l == .locked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(l == .locked ? Color.white.opacity(0.92) : Color(hex: "#34D399"))
            .contentTransition(.symbolEffect(.replace))
            .padding(.leading, 5)
            .transition(.opacity)
    }

    // MARK: Volume / brightness

    private func hudSymbol(_ h: NotchbitModel.HUD) -> String {
        switch h.kind {
        case .volume:
            if h.muted || h.value < 0.01 { return "speaker.slash.fill" }
            return h.value < 0.34 ? "speaker.wave.1.fill" : (h.value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        case .brightness:
            return h.value < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard:
            return "keyboard.fill"
        case .song:
            return "music.note"
        case .battery:
            if h.charging { return "battery.100percent.bolt" }
            return h.value < 0.13 ? "battery.0percent" : (h.value < 0.38 ? "battery.25percent" : (h.value < 0.63 ? "battery.50percent" : (h.value < 0.88 ? "battery.75percent" : "battery.100percent")))
        }
    }

    /// The bar gets more vivid (and warmer) the higher the level
    /// The colour the user picked for this bar, if they picked one
    private func customHUDColor(_ h: NotchbitModel.HUD) -> Color? {
        guard h.kind == .volume || h.kind == .brightness else { return nil }
        let key = h.kind == .volume ? "notchbit.hudVolumeHex" : "notchbit.hudBrightnessHex"
        guard let hex = UserDefaults.standard.string(forKey: key), hex.hasPrefix("#") else { return nil }
        return Color(hex: hex)
    }

    /// Your colour, paler and dimmer at a low level and fully vivid at a high one
    private static func intensity(_ c: Color, _ v: Double) -> Color {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return c }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        n.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        let t = CGFloat(max(0, min(1, v)))
        return Color(hue: Double(h), saturation: Double(sat * (0.30 + 0.70 * t)), brightness: Double(min(1, b * (0.55 + 0.45 * t))))
    }

    private func hudColor(_ h: NotchbitModel.HUD, _ v: Double) -> Color {
        if h.kind == .keyboard { return Color(hex: "#A5B4FC") }
        if h.kind == .song { return Color(hex: "#F9A8D4") }
        if h.kind == .battery { return h.charging ? Color(hex: "#34D399") : (h.value <= 0.2 ? Color(hex: "#F87171") : (h.value <= 0.4 ? Color(hex: "#FBBF24") : Color(hex: "#E5E7EB"))) }
        if let c = customHUDColor(h) { return Self.intensity(c, v) }
        switch h.kind {
        case .volume: return Color(hue: 0.50 * (1 - v), saturation: 0.25 + 0.65 * v, brightness: 0.85 + 0.15 * v)
        case .keyboard, .battery, .song: return Color(hex: "#A5B4FC")
        case .brightness: return Color(hue: 0.13, saturation: 0.15 + 0.75 * v, brightness: 0.75 + 0.25 * v)
        }
    }

    /// Under the notch, inside the notch's own width and as low as possible: a small glowing icon, a thin bar of 16 little blocks that light up and warm with the level, and the number
    private func dropHUD(_ h: NotchbitModel.HUD) -> some View {
        let shown = h.muted && h.kind == .volume ? 0 : h.value
        let c = hudColor(h, shown)
        let blocks = 16
        if h.kind == .keyboard { return AnyView(dropKeyboard(h, c)) }
        if h.kind == .song { return AnyView(dropSong(h, c)) }
        return AnyView(HStack(spacing: 7) {
            ZStack {
                Circle().fill(c.opacity(0.18))
                Circle().strokeBorder(c.opacity(0.5), lineWidth: 0.8)
                Image(systemName: hudSymbol(h)).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(c)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 19, height: 19)

            HStack(spacing: 2) {
                ForEach(0..<blocks, id: \.self) { i in
                    let level = Double(i + 1) / Double(blocks)
                    let lit = shown >= level - 0.5 / Double(blocks)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(lit ? hudColor(h, level) : Color.white.opacity(0.13))
                        .frame(height: lit ? 3.5 : 2.5)
                }
            }
            .frame(height: 4)

            Text("\(Int((shown * 100).rounded()))\(h.kind == .battery ? "%" : "")")
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(c).frame(width: h.kind == .battery ? 32 : 24, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .animation(.easeOut(duration: 0.1), value: shown))
    }

    /// The next song: a small note and its name, plain and low
    private func dropSong(_ h: NotchbitModel.HUD, _ c: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(c.opacity(0.18))
                Circle().strokeBorder(c.opacity(0.5), lineWidth: 0.8)
                Image(systemName: "music.note").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(c)
            }
            .frame(width: 19, height: 19)
            (Text(h.name).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
             + Text(h.code.isEmpty ? "" : "  ·  \(h.code)").font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55)))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .transition(.opacity)
    }

    /// Keyboard language, small and plain: the short code in a soft chip and the layout's name
    private func dropKeyboard(_ h: NotchbitModel.HUD, _ c: Color) -> some View {
        HStack(spacing: 8) {
            Text(h.code)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(c)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(Capsule().fill(c.opacity(0.18)))
                .overlay(Capsule().strokeBorder(c.opacity(0.4), lineWidth: 0.8))
            Text(h.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .transition(.opacity)
    }

    /// Beside the notch, left: the icon in a soft glowing disc of the bar's colour
    private func hudIcon(_ h: NotchbitModel.HUD) -> some View {
        let shown = h.muted && h.kind == .volume ? 0 : h.value
        let c = hudColor(h, shown)
        return ZStack {
            Circle().fill(c.opacity(0.18))
            Circle().strokeBorder(c.opacity(0.45), lineWidth: 1)
            Image(systemName: hudSymbol(h))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c)
                .shadow(color: c.opacity(0.7), radius: 4)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 28, height: 28)
        .animation(.easeOut(duration: 0.15), value: shown)
    }

    /// Beside the notch, right: a glowing bar in the same colour and the number
    private func hudBar(_ h: NotchbitModel.HUD) -> some View {
        let shown = h.muted && h.kind == .volume ? 0 : h.value
        let c = hudColor(h, shown)
        if h.kind == .keyboard {
            return AnyView(HStack(spacing: 6) {
                Text(h.name).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.6)
                Text(h.code).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(c)
            }.padding(.trailing, 12))
        }
        return AnyView(HStack(spacing: 9) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(LinearGradient(colors: [c.opacity(0.55), c], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, 64 * shown))
                    .shadow(color: c.opacity(0.7), radius: 4)
            }
            .frame(width: 60, height: 3)
            Text("\(Int((shown * 100).rounded()))\(h.kind == .battery ? "%" : "")")
                .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white).frame(width: h.kind == .battery ? 34 : 26, alignment: .trailing)
        }
        .padding(.trailing, 12)
        .animation(.easeOut(duration: 0.12), value: shown))
    }

    /// The planet, or the cover of the song that is playing; a thin ring around it follows the timer
    private var icon: some View {
        ZStack {
            Circle().stroke(accent, lineWidth: 2).scaleEffect(ringScale).opacity(ringOpacity)

            if music.showing && model.level == .closed && !model.screenLocked {
                cover(planetSize * 0.74)
                    .frame(width: planetSize + 2, height: planetSize + 2, alignment: .trailing)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            } else if let planet {
                Group {
                if !planetFrames.isEmpty {
                    // drawn once, played by Core Animation: it moves and costs almost nothing (drawing it live many times a second did not)
                    Group {
                        if planetMotion {
                            GifLoop(frames: planetFrames, duration: loopSeconds, bob: true).id(framesKey)
                        } else {
                            Image(nsImage: planetFrames[0]).resizable().interpolation(.high)
                        }
                    }
                    .frame(width: planetSize, height: planetSize)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 8, paused: false)) { t in
                        PlanetView(planet: planet, size: planetSize, phase: t.date.timeIntervalSinceReferenceDate / 12)
                    }
                }
                }
                .transition(.move(edge: .leading).combined(with: .scale(scale: 0.2)).combined(with: .opacity))
            }
        }
        
        .frame(width: planetSize + 2, height: planetSize + 2)
        .scaleEffect(bounce ? 1.3 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: music.showing && model.level == .closed && !model.screenLocked)
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: bounce)
    }

    private func cover(_ side: CGFloat) -> some View {
        Group {
            if let img = music.artwork {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [accent, Color(hex: "#6366F1")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: side * 0.45, weight: .bold)).foregroundStyle(.white))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
    }

    private var progress: Double {
        if let len = timer.phaseLength { return min(1, timer.elapsed / max(1, len)) }
        return (timer.elapsed.truncatingRemainder(dividingBy: 3600)) / 3600
    }

    /// Right of the notch: headphones while music plays, otherwise the timer
    private var rightTag: some View {
        Group {
            if music.isActive {
                Group {
                    if let logo = NotchLogos.logo(logoID) {
                        GifLoop(frames: NotchLogos.frames(of: logo), duration: logo.duration).id(logo.id)
                    } else {
                        Image(systemName: "headphones").resizable().scaledToFit().foregroundStyle(.orange)
                    }
                }
                .frame(width: 25, height: 25)
                .scaleEffect(NotchLogos.scale(logoID, in: logoScales), anchor: .leading)
                .padding(.leading, 0)
                .frame(width: model.rightWing, alignment: .leading)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                timerTag
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: music.isActive)
    }

    @ViewBuilder private var timerTag: some View {
        if timer.isActive {
            HStack(spacing: 5) {
                Image(systemName: timer.isRunning ? "circle.fill" : "pause.fill")
                    .font(.system(size: timer.isRunning ? 5 : 8, weight: .bold))
                    .foregroundStyle(timer.phase == .focus ? Color.orange : Color.green)
                    .opacity(timer.isRunning ? 1 : 0.8)
                Text(Fmt.clock(timer.displayTime))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white.opacity(timer.isRunning ? 1 : 0.6))
                    .minimumScaleFactor(0.75).lineLimit(1)
            }
            .padding(.leading, 1)
            .transition(.opacity)
        }
    }

    /// Today's date and whether this week is even or odd
    private var dateTag: some View {
        let parity = store.parity(ofWeek: Date())
        return VStack(alignment: .trailing, spacing: 1) {
            Text(Fmt.date(Date(), "MMM d", store.settings.primaryCalendar))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
            Text("\(Fmt.date(Date(), "EEE", store.settings.primaryCalendar)) · \(parity.title.replacingOccurrences(of: " week", with: " wk"))")
                .font(.system(size: 9, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(parity == .even ? Color.cyan : Color.pink)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private func makePlanetFrames() {
        guard let planet else { planetFrames = []; framesKey = ""; return }
        // a planet that is itself an animated picture plays its own frames; the others turn their moons
        let own = planet.image.map { PlanetPainter.frames($0).count } ?? 0
        let count = own > 1 ? min(own, 60) : 48
        let frames = (0..<count).compactMap { k -> NSImage? in
            PlanetPainter.frameOverride = own > 1 ? k * own / count : nil
            defer { PlanetPainter.frameOverride = nil }
            let r = ImageRenderer(content: PlanetView(planet: planet, size: planetSize, phase: Double(k) / Double(count)))
            r.scale = 3
            return r.nsImage
        }
        loopSeconds = own > 1 ? Double(own) / 8 : 12
        planetFrames = frames
        framesKey = "\(planet.id)|\(Int(planetSize))"   // set together with the frames, so the old picture is replaced
    }

    private func pulse() {
        bounce = true
        ringScale = 1; ringOpacity = 0.9
        withAnimation(.easeOut(duration: 1.0)) { ringScale = 2.3; ringOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { bounce = false }
    }

    private func openLeitner() {
        NotchbitController.shared.closeNow()
        LeitnerQuickPanel.shared.show()
    }

    // MARK: Small view (hover)

    @ViewBuilder private var peek: some View {
        Group {
            if let n = model.nextUp {
                nextUpCard(n)
            } else if music.showing {
                HStack(spacing: 11) {
                    cover(42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(music.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                        Text(music.artist).font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    musicButtons(compact: true)
                }
            } else if timer.isActive {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Fmt.clock(timer.displayTime))
                            .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(timer.targetTitle ?? (timer.phase == .focus ? "Focus" : "Break"))
                            .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    roundButton(timer.isRunning ? "pause.fill" : "play.fill", primary: true) { timer.toggle() }
                    roundButton("stop.fill") { timer.stop() }
                    if !timer.isRunning { roundButton("trash.fill") { timer.stop(save: false) } }
                }
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ready to focus?").font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(timer.mode == .pomodoro ? "\(store.settings.pomodoroMinutes) min Pomodoro" : "Stopwatch")
                            .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 6)
                    Button { timer.start() } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .background(Capsule().fill(LinearGradient(colors: [accent, Color(hex: "#6366F1")], startPoint: .leading, endPoint: .trailing)))
                            .foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 0).padding(.bottom, 10)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { NotchbitController.shared.set(.full, tab: music.showing ? .music : timer.isActive ? .timer : .tasks) }
    }

    /// "Next up": the weekly-schedule item that is about to start, with a Start button
    private func nextUpCard(_ n: NextUpInfo) -> some View {
        let c = Color(hex: n.colorHex)
        return HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    let m = Int(ceil(n.start.timeIntervalSinceNow / 60))
                    Text(m <= 0 ? "NOW" : "NEXT · IN \(m) MIN")
                        .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(1.4).foregroundStyle(c)
                }
                Text(n.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(n.timeText).font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 6)
            if n.canStart, !timer.isActive {
                Button {
                    if let ref = n.ref { timer.select(ref); timer.start() }
                    NotchbitController.shared.dismissNextUp()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(Capsule().fill(LinearGradient(colors: [c, c.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            roundButton("xmark") { NotchbitController.shared.dismissNextUp() }
        }
    }

    // MARK: Big view

    private var full: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(NotchbitModel.Tab.allCases) { t in
                    Button { typing = false; model.editing = false; picking = false; NotchbitController.shared.setTab(t) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.icon).font(.system(size: 10, weight: .bold))
                            if model.tab == t { Text(t.rawValue).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize() }
                            if t == .music && music.showing { Circle().fill(.green).frame(width: 5, height: 5) }
                        }
                        .padding(.horizontal, model.tab == t ? 10 : 8).padding(.vertical, 4)
                        .background(Capsule().fill(model.tab == t ? Color.white.opacity(0.16) : .clear))
                        .foregroundStyle(model.tab == t ? .white : .white.opacity(0.55))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { NotchbitController.shared.closeNow(); NotchbitController.shared.openSettings?() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 22)
                }.buttonStyle(.plain).help("Notchbit settings")
                Button { NotchbitController.shared.set(.peek) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 22)
                }.buttonStyle(.plain)
            }
            Group {
                switch model.tab {
                case .timer: timerTab
                case .tasks: tasksTab
                case .music: musicTab
                case .countdown: countdownTab
                }
            }
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.top, 3).padding(.bottom, 10)
    }

    private var timerTab: some View {
        Group {
            if picking && !timer.isActive { taskPicker } else { timerFace }
        }
        .onChange(of: timer.isActive) { _, now in if now { picking = false } }
    }

    /// Choose what to study, or write a new task
    private var taskPicker: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Button { withAnimation(.snappy(duration: 0.2)) { picking = false } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.1)))
                }.buttonStyle(.plain)
                Text("What are you studying?").font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    pickerRow(title: "Free study (no task)", color: .gray, selected: timer.target == nil) { timer.select(nil); picking = false }
                    ForEach(todayTodos) { item in
                        pickerRow(title: item.title, color: item.color, selected: timer.target == item.ref) { timer.select(item.ref); picking = false }
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                TextField("New task — Return to pick it", text: $newTask)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .rounded))
                    .focused($typing)
                    .onSubmit {
                        let t = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let task = TaskItem(title: t, dueDate: Date())
                        store.upsertTask(task)
                        timer.select(.task(task.id))
                        newTask = ""; picking = false
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.09)))
        }
    }

    private func pickerRow(title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(accent) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(selected ? 0.12 : 0.05)))
        }.buttonStyle(.plain)
    }

    private var timerFace: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 4)
                Circle().trim(from: 0, to: timer.isActive ? progress : 0)
                    .stroke(LinearGradient(colors: [accent, Color(hex: "#EC4899")], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
                VStack(spacing: 0) {
                    Text(Fmt.clock(timer.isActive ? timer.displayTime : (timer.phaseLength ?? 0)))
                        .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7)
                    Text(timer.mode == .stopwatch ? "Stopwatch" : (timer.phase == .focus ? "Focus" : "Break"))
                        .font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                if timer.isActive {
                    Text(timer.targetTitle ?? "Free study")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
                } else {
                    Button { withAnimation(.snappy(duration: 0.2)) { picking = true } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checklist").font(.system(size: 10, weight: .bold))
                            Text(timer.targetTitle ?? "Free study — pick a task").font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.1)))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    Button { timer.toggle() } label: {
                        Label(timer.isRunning ? "Pause" : (timer.isActive ? "Resume" : "Start"), systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(.white)).foregroundStyle(.black)
                    }.buttonStyle(.plain)
                    if timer.isActive {
                        Button { timer.stop() } label: {
                            Label("Finish", systemImage: "stop.fill")
                                .font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(0.14)))
                        }.buttonStyle(.plain)
                        if !timer.isRunning {
                            Button { timer.stop(save: false) } label: {
                                Label("Discard", systemImage: "trash")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Color.red.opacity(0.28)))
                            }.buttonStyle(.plain).help("Throw this timer away without saving the time")
                        }
                    }
                }
                if !timer.isActive {
                    HStack(spacing: 0) {
                        ForEach(TimerEngine.Mode.allCases) { m in
                            Button { timer.mode = m } label: {
                                Text(m.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(Capsule().fill(timer.mode == m ? Color.white.opacity(0.18) : .clear))
                                    .foregroundStyle(timer.mode == m ? .white : .white.opacity(0.5))
                            }.buttonStyle(.plain)
                        }
                    }
                    .background(Capsule().fill(.white.opacity(0.07)))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var todayTodos: [TodoItem] {
        store.todos(on: Date()).filter { !$0.isDone && !$0.isSkipped }
    }

    private var tasksTab: some View {
        VStack(spacing: 8) {
            let items = todayTodos
            if items.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing left for today ✨").font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            HStack(spacing: 9) {
                                Circle().fill(item.color).frame(width: 7, height: 7)
                                Text(item.title).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
                                Spacer(minLength: 4)
                                if timer.isActive && timer.target == item.ref {
                                    Image(systemName: "waveform").font(.system(size: 11, weight: .bold)).foregroundStyle(accent)
                                } else if !timer.isActive {
                                    Button { timer.select(item.ref); timer.start() } label: {
                                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                                            .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.14)))
                                    }.buttonStyle(.plain).help("Start the timer on this")
                                }
                                Button { store.toggleDone(item.ref, on: Date()) } label: {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                        .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.08)))
                                }.buttonStyle(.plain).help("Mark done")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                TextField("Add a task for today", text: $newTask)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .rounded))
                    .focused($typing)
                    .onSubmit(addTask)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.09)))
        }
    }

    private func addTask() {
        let t = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.upsertTask(TaskItem(title: t, dueDate: Date()))
        newTask = ""
    }

    /// The pinned (or next) event as a countdown
    private var countdownTab: some View {
        Group {
            if let e = CountdownStore.shared.shown {
                TimelineView(.periodic(from: .now, by: 1)) { t in
                    HStack(spacing: 16) {
                        Text(e.emoji).font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.title).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                            Text(PersianDatePicker.text(e.date))
                                .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(countdownHeadline(e, now: t.date)).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(e.color)
                            if e.date > t.date {
                                Text(countdownClock(e, now: t.date)).font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("No event yet").font(.system(size: 12, weight: .semibold, design: .rounded))
                    Button { NotchbitController.shared.closeNow(); NotchbitController.shared.openCountdown?() } label: {
                        Label("Add one", systemImage: "plus").font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(.white.opacity(0.14)))
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private var musicTab: some View {
        Group {
            if music.hasTrack {
                HStack(spacing: 14) {
                    cover(62)
                        .shadow(color: accent.opacity(0.5), radius: 8, y: 2)
                        .onTapGesture { music.openPlayer() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(music.title).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                        Text(music.artist).font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        Text(music.source?.title ?? "").font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 6)
                    musicButtons(compact: false)
                }
            } else {
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                    Text("Nothing playing").font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Play something in Apple Music or Spotify").font(.system(size: 10, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Buttons

    private func musicButtons(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            roundButton("backward.fill") { music.previous() }
            roundButton(music.isPlaying ? "pause.fill" : "play.fill", primary: true) { music.playPause() }
            roundButton("forward.fill") { music.next() }
            if music.source == .music {
                roundButton(music.isFavorite ? "star.fill" : "star", tint: music.isFavorite ? .yellow : nil) { music.toggleFavorite() }
                    .help("Add to your Apple Music favorites")
            }
        }
    }

    private func roundButton(_ symbol: String, primary: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        RoundButton(symbol: symbol, primary: primary, tint: tint, action: action)
    }
}

/// The notch's reactions to timer phases, typing and planet changes (kept apart so the main view stays simple)
private struct Reactions: ViewModifier {
    @Environment(TimerEngine.self) private var timer
    let onPhase: () -> Void
    let onTyping: (Bool) -> Void
    let typing: Bool
    let planetKey: String
    let makeFrames: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: timer.phase) { _, _ in onPhase() }
            .onChange(of: typing) { _, now in onTyping(now) }
            .task(id: planetKey) { makeFrames() }
    }
}

private struct RoundButton: View {
    let symbol: String
    var primary = false
    var tint: Color?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: primary ? 12 : 10, weight: .bold))
                .foregroundStyle(primary ? Color.black : (tint ?? Color.white))
                .frame(width: primary ? 30 : 26, height: primary ? 30 : 26)
                .background(Circle().fill(primary ? Color.white : Color.white.opacity(hover ? 0.22 : 0.12)))
                .scaleEffect(hover ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// A few slowly twinkling stars behind the open notch. Core Animation does the twinkling, so it costs almost no CPU.
private struct Stars: NSViewRepresentable {
    private static let stars: [(x: Double, y: Double, r: Double, speed: Double, phase: Double)] = (0..<26).map { i in
        func h(_ n: Int) -> Double { let v = sin(Double(n) * 12.9898 + 78.233) * 43758.5453; return v - v.rounded(.down) }
        return (h(i * 3 + 1), h(i * 3 + 2), 0.6 + h(i * 3 + 3) * 0.9, 0.6 + h(i + 50) * 1.6, h(i + 90) * 6.28)
    }

    final class StarsView: NSView {
        var layers: [(CALayer, Double, Double)] = []
        override func layout() {
            super.layout()
            for (l, x, y) in layers { l.position = CGPoint(x: x * bounds.width, y: y * bounds.height) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> StarsView {
        let v = StarsView()
        v.wantsLayer = true
        for s in Self.stars {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: s.r, height: s.r)
            l.cornerRadius = s.r / 2
            l.backgroundColor = NSColor.white.cgColor
            l.opacity = 0.25
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.2; a.toValue = 0.8
            a.duration = 1.2 / s.speed + 0.8
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timeOffset = s.phase
            l.add(a, forKey: "twinkle")
            v.layer?.addSublayer(l)
            v.layers.append((l, s.x, 1 - s.y))
        }
        return v
    }

    func updateNSView(_ v: StarsView, context: Context) {}
}

/// Plays a few pictures in a loop on the render server (Core Animation), so it costs almost no CPU.
/// `bob` also lets it float up and down a little.
private struct GifLoop: NSViewRepresentable {
    let frames: [NSImage]
    let duration: Double
    var bob = false

    final class LoopView: NSView {
        let inner = CALayer()
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            inner.frame = bounds
            CATransaction.commit()
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> LoopView {
        let v = LoopView()
        v.wantsLayer = true
        let layer = v.inner
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .linear
        v.layer?.addSublayer(layer)
        let cg = frames.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        if let first = cg.first { layer.contents = first }
        if cg.count > 1 {
            let a = CAKeyframeAnimation(keyPath: "contents")
            a.values = cg
            a.calculationMode = .discrete
            a.duration = duration
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: "gif")
        }
        if bob {
            let b = CABasicAnimation(keyPath: "transform.translation.y")
            b.fromValue = -1.4; b.toValue = 1.4
            b.duration = 2.4
            b.autoreverses = true
            b.repeatCount = .infinity
            b.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            b.isRemovedOnCompletion = false
            layer.add(b, forKey: "bob")
        }
        return v
    }

    func updateNSView(_ v: LoopView, context: Context) {}
}
