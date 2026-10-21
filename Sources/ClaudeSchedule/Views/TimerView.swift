import SwiftUI

struct TimerView: View {
    @Environment(TimerEngine.self) private var timer
    @Environment(AppStore.self) private var store
    @State private var showManual = false
    @State private var confirmDiscard = false

    var body: some View {
        HStack(spacing: 0) {
            timerPanel.frame(maxWidth: .infinity)
            sessionsPanel
                .frame(width: 320)
                .background(.ultraThinMaterial)
        }
        .background { TimerBackdrop(rest: timer.phase == .rest, lift: liftProgress) }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Timer")
        .sheet(isPresented: $showManual) { ManualSessionSheet() }
    }

    // MARK: Timer

    private var targetItem: TodoItem? {
        guard let ref = timer.target else { return nil }
        return store.todos(on: Date()).first { $0.ref == ref } ?? store.todoItem(for: ref)
    }

    private var ringColor: Color {
        if timer.phase == .rest { return Color(hex: "#7EE081") }
        if let targetItem, targetItem.color != .gray { return targetItem.color }
        return store.category(timer.categoryID)?.color ?? Color(hex: "#E8384F")
    }

    private var progress: Double {
        if let length = timer.phaseLength { return length > 0 ? timer.elapsed / length : 0 }
        // In stopwatch mode the ring shows progress towards the daily goal
        let goal = TimeInterval(store.settings.dailyGoalMinutes * 60)
        return goal > 0 ? (store.studyTime(on: Date()) + timer.elapsed) / goal : 0
    }

    /// How far the launch has climbed: today's study towards the daily goal
    private var liftProgress: Double {
        let goal = TimeInterval(store.settings.dailyGoalMinutes * 60)
        return goal > 0 ? min(1, (store.studyTime(on: Date()) + (timer.phase == .focus ? timer.elapsed : 0)) / goal) : 0
    }

    private var timerPanel: some View {
        @Bindable var timer = timer
        var todos = store.todos(on: Date())
        if let ref = timer.target, !todos.contains(where: { $0.ref == ref }), let item = store.todoItem(for: ref) {
            todos.insert(item, at: 0)
        }

        return VStack(spacing: 18) {
            // What am I studying?
            VStack(spacing: 4) {
                Text(phaseLabel.uppercased())
                    .font(.caption.weight(.heavy)).tracking(3)
                    .foregroundStyle(ringColor)
                Text(timer.phase == .rest ? "Break time" : (timer.targetTitle ?? "Free study"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                if let targetItem, timer.phase == .focus {
                    Text(targetItem.detail).font(.callout).foregroundStyle(.white.opacity(0.7))
                }
            }

            Picker("", selection: $timer.mode) {
                ForEach(TimerEngine.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .disabled(timer.isActive)

            ZStack {
                SolarDial(time: timer.displayTime, spin: timer.elapsed, progress: progress, tint: ringColor,
                          moving: timer.isRunning, rest: timer.phase == .rest)
                    .frame(width: 330, height: 330)
                if timer.phase == .rest, let img = PlanetPainter.bundleImage("timer-break") {
                    Image(nsImage: img).resizable().scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color(hex: "#7EE081").opacity(0.7), lineWidth: 2))
                        .shadow(color: Color(hex: "#7EE081").opacity(0.5), radius: 18)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.5), value: timer.phase == .rest)

            // Digital read-out
            VStack(spacing: 2) {
                Text(Fmt.clock(timer.displayTime))
                    .font(.system(size: 56, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .shadow(color: ringColor.opacity(timer.isRunning ? 0.55 : 0), radius: 16)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
            }

            // What, category, note — on glass
            VStack(spacing: 0) {
                row("book.closed.fill") {
                    Picker("Studying", selection: Binding(get: { timer.target }, set: { timer.select($0) })) {
                        Text("Free study").tag(TodoRef?.none)
                        ForEach(todos) { item in
                            Text(item.isDone ? "✓ \(item.title) (\(item.detail))" : "\(item.title) (\(item.detail))")
                                .tag(Optional(item.ref))
                        }
                    }
                    .disabled(timer.isActive)
                }
                if timer.target == nil {
                    Divider().opacity(0.4)
                    row("tag.fill") {
                        Picker("Category", selection: $timer.categoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.orderedCategories) { Text(store.categoryLabel($0.id) ?? $0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                Divider().opacity(0.4)
                row("square.and.pencil") {
                    TextField("Session note (e.g. chapter 3)", text: $timer.note).textFieldStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))

            // Controls
            HStack(spacing: 12) {
                Button {
                    timer.toggle()
                } label: {
                    Label(timer.isRunning ? "Pause" : (timer.isActive ? "Resume" : "Launch"),
                          systemImage: timer.isRunning ? "pause.fill" : (timer.isActive ? "play.fill" : "paperplane.fill"))
                        .font(.headline)
                        .frame(width: 150, height: 40)
                        .background(Capsule().fill(LinearGradient(colors: [ringColor, ringColor.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                        .foregroundStyle(.white)
                        .shadow(color: ringColor.opacity(0.6), radius: timer.isRunning ? 4 : 14)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)

                if timer.isActive {
                    if timer.phase == .rest {
                        glassButton("Skip Break", "forward.fill") { timer.skipBreak() }
                    } else {
                        glassButton("Finish & Save", "flag.checkered") { timer.stop() }
                        glassButton(nil, "trash") { confirmDiscard = true }
                            .help("Discard without saving")
                    }
                }
            }
            .confirmationDialog("Discard this session?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { timer.stop(save: false) }
            }
        }
        .padding(28)
        .foregroundStyle(.white)
    }

    private func row<Content: View>(_ icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(ringColor).frame(width: 18)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func glassButton(_ title: String?, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let title { Label(title, systemImage: icon) } else { Image(systemName: icon) }
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, title == nil ? 14 : 18).frame(height: 40)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if timer.mode == .pomodoro {
            let left = timer.phase == .rest ? "until focus" : "left in this focus"
            return "\(left) · \(store.settings.pomodoroMinutes)/\(store.settings.breakMinutes) min · 🍅 \(timer.completedPomodoros)"
        }
        let today = store.studyTime(on: Date()) + timer.elapsed
        return "Today \(Fmt.duration(today)) of \(Fmt.duration(TimeInterval(store.settings.dailyGoalMinutes * 60))) goal"
    }

    private var phaseLabel: String {
        if timer.phase == .rest { return "Break · the cow is on a ride" }
        if !timer.isActive { return "Ready for launch" }
        return timer.isRunning ? "In orbit · focusing" : "Paused"
    }

    // MARK: Sessions

    private var sessionsPanel: some View {
        let sessions = store.sessions(in: Cal.persian.dayInterval(Date())).reversed()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Today's flights").font(.headline)
                    Text(Fmt.duration(store.studyTime(on: Date()))).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showManual = true
                } label: {
                    Label("Log Manually", systemImage: "plus")
                }
                .help("Log a session you forgot to time")
            }
            if sessions.isEmpty {
                VStack(spacing: 10) {
                    if let img = PlanetPainter.bundleImage("timer-earth") {
                        Image(nsImage: img).resizable().interpolation(.none).scaledToFit()
                            .frame(width: 170)

                    }
                    Text("No flights yet today").font(.callout.weight(.semibold))
                    Text("Press Launch to start your first one 🚀").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            List {
                ForEach(Array(sessions)) { SessionRow(session: $0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(20)
    }
}

/// The page behind the timer: the launch picture (your own, if present; else a drawn night sky) fitted
/// to the height behind the dial, rising a little as today's study climbs toward the goal;
/// during a break, a calm green night.
private struct TimerBackdrop: View {
    let rest: Bool
    let lift: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#05060C")
                if let img = PlanetPainter.bundleImage("timer-launch") {
                    // a tall picture on black: fit it to the height and let its edges fade into the night
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(height: geo.size.height * 1.12)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                                     .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .offset(x: -160, y: geo.size.height * 0.06 + geo.size.height * 0.08 * (0.5 - lift))
                        .animation(.easeInOut(duration: 1.2), value: lift)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Canvas { ctx, size in StarsBackground.paint(&ctx, size: size) }
                    LinearGradient(colors: [.clear, Color(hex: "#C9C3A8").opacity(0.18)], startPoint: .center, endPoint: .bottom)
                }
                if rest {
                    LinearGradient(colors: [Color(hex: "#0B1B4A").opacity(0.85), Color(hex: "#1F5F3A").opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom)
                        .transition(.opacity)
                }
                // keep the text readable over the picture
                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.2), .black.opacity(0.55)], startPoint: .leading, endPoint: .trailing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.8), value: rest)
        }
        .ignoresSafeArea()
    }
}

/// A solar-system clock: planets on blue orbits around a sun, red hands for the time, a dotted rim with
/// markers, and a glowing arc for progress (daily goal, or the Pomodoro phase). Planets move only while running.
private struct SolarDial: View {
    let time: TimeInterval
    /// Elapsed seconds — drives the planets so they stop when paused
    let spin: TimeInterval
    let progress: Double
    let tint: Color
    let moving: Bool
    let rest: Bool

    private static let planets: [(ring: Int, color: String, size: Double, speed: Double, start: Double, ringed: Bool)] = [
        (0, "#C9763C", 0.022, 0.050, 1.0, false), (1, "#3FB6C8", 0.026, 0.034, 3.7, false),
        (2, "#D9A066", 0.030, 0.026, 5.1, false), (3, "#B5523B", 0.050, 0.019, 2.4, false),
        (4, "#C9A98D", 0.040, 0.014, 0.3, true),  (5, "#6E8BD8", 0.034, 0.011, 4.2, false),
        (6, "#5B4FB0", 0.028, 0.008, 1.9, false)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !moving || AppActivity.paused)) { _ in
            Canvas { ctx, size in paint(&ctx, size: size) }
        }
    }

    private func paint(_ ctx: inout GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2 - 4
        func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        func point(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r) }

        // glassy disc
        ctx.fill(circle(R * 0.93), with: .color(.black.opacity(0.55)))

        // dotted rim with diamonds at the hours
        for i in 0..<120 where i % 10 != 0 {
            let p = point(R * 0.97, Double(i) / 120 * .pi * 2)
            ctx.fill(circle(1).applying(.init(translationX: p.x - c.x, y: p.y - c.y)), with: .color(.white.opacity(0.55)))
        }
        for i in 0..<12 {
            let a = Double(i) / 12 * .pi * 2, p = point(R * 0.97, a), s = i % 3 == 0 ? 5.5 : 3.5
            var d = Path()
            d.move(to: CGPoint(x: p.x, y: p.y - s)); d.addLine(to: CGPoint(x: p.x + s * 0.6, y: p.y))
            d.addLine(to: CGPoint(x: p.x, y: p.y + s)); d.addLine(to: CGPoint(x: p.x - s * 0.6, y: p.y)); d.closeSubpath()
            ctx.fill(d, with: .color(.white.opacity(0.9)))
        }

        // progress arc just inside the rim
        let pr = R * 0.89
        var track = Path(); track.addArc(center: c, radius: pr, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
        ctx.stroke(track, with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: 6))
        let p = max(0, min(1, progress))
        if p > 0 {
            var arc = Path(); arc.addArc(center: c, radius: pr, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * p), clockwise: false)
            var glow = ctx; glow.addFilter(.blur(radius: 6))
            glow.stroke(arc, with: .color(tint.opacity(0.8)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            ctx.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }

        // blue orbits
        let orbitColor = rest ? Color(hex: "#3E8E5E") : Color(hex: "#2F6FD8")
        let radii = (0..<7).map { R * (0.24 + Double($0) * 0.095) }
        for (i, r) in radii.enumerated() {
            ctx.stroke(circle(r), with: .color(orbitColor.opacity(i == 1 ? 0.35 : 0.75)),
                       style: StrokeStyle(lineWidth: 1.4, dash: i == 1 ? [2, 4] : []))
        }
        // a few stars between the orbits
        var rng = SeededRandom(seed: "solar-dial")
        for _ in 0..<40 {
            let a = rng.next() * .pi * 2, r = R * (0.2 + rng.next() * 0.68)
            let q = point(r, a)
            ctx.fill(circle(0.9).applying(.init(translationX: q.x - c.x, y: q.y - c.y)), with: .color(.white.opacity(0.35 + rng.next() * 0.4)))
        }

        // planets
        for pl in Self.planets {
            let a = pl.start + spin * pl.speed
            let q = point(radii[pl.ring], a), s = R * pl.size
            if pl.ringed {
                var ring = Path(ellipseIn: CGRect(x: q.x - s * 1.9, y: q.y - s * 0.55, width: s * 3.8, height: s * 1.1))
                ring = ring.applying(.init(translationX: -q.x, y: -q.y).concatenating(.init(rotationAngle: -0.4)).concatenating(.init(translationX: q.x, y: q.y)))
                ctx.stroke(ring, with: .color(Color(hex: "#E6D3A3")), lineWidth: 1.6)
            }
            ctx.fill(circle(s).applying(.init(translationX: q.x - c.x, y: q.y - c.y)), with: .color(Color(hex: pl.color)))
            ctx.fill(circle(s * 0.45).applying(.init(translationX: q.x - c.x - s * 0.3, y: q.y - c.y - s * 0.3)), with: .color(.white.opacity(0.18)))
        }

        // the sun
        var sunGlow = ctx; sunGlow.addFilter(.blur(radius: 10))
        sunGlow.fill(circle(R * 0.11), with: .color(Color(hex: "#FFC940").opacity(0.7)))
        ctx.fill(circle(R * 0.075), with: .color(Color(hex: "#FFD447")))
        ctx.stroke(circle(R * 0.075), with: .color(Color(hex: "#E8384F")), lineWidth: 2)

        // hands: hours, minutes (thick red) and seconds (thin)
        let t = time
        let hand = Color(hex: "#E8384F")
        func drawHand(_ angle: Double, _ length: Double, _ width: Double, _ back: Double = 0.12) {
            var h = Path()
            h.move(to: point(-R * back, angle)); h.addLine(to: point(R * length, angle))
            ctx.stroke(h, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round))
            ctx.stroke(h, with: .color(hand), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        let toAngle = { (f: Double) in f * .pi * 2 - .pi / 2 }
        drawHand(toAngle((t / 3600).truncatingRemainder(dividingBy: 12) / 12), 0.45, 5)
        drawHand(toAngle((t / 60).truncatingRemainder(dividingBy: 60) / 60), 0.7, 4)
        drawHand(toAngle(t.truncatingRemainder(dividingBy: 60) / 60), 0.82, 1.6, 0.18)
        ctx.fill(circle(R * 0.035), with: .color(Color(hex: "#FFD447")))
    }
}

/// Log a session by hand
struct ManualSessionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: TodoRef?
    @State private var categoryID: UUID?
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var minutes = 60
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Studied", selection: $target) {
                    Text("Free study").tag(TodoRef?.none)
                    ForEach(store.todos(on: start)) { Text("\($0.title) (\($0.detail))").tag(Optional($0.ref)) }
                }
                if target == nil {
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.orderedCategories) { Text(store.categoryLabel($0.id) ?? $0.name).tag(Optional($0.id)) }
                    }
                }
                DatePicker("Started", selection: $start)
                Stepper(value: $minutes, in: 1...720, step: 5) {
                    LabeledContent("Duration", value: Fmt.duration(TimeInterval(minutes * 60)))
                }
                TextField("Note", text: $note)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Log") {
                    store.addSession(store.makeSession(ref: target, categoryID: categoryID, start: start,
                                                       duration: TimeInterval(minutes * 60), note: note))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460)
        .environment(\.calendar, store.settings.primaryCalendar.calendar)
    }
}
