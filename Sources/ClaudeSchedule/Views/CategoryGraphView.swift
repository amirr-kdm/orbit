import AppKit
import SwiftUI

/// Obsidian-style graph: every category is a hub, and its tasks and schedule to-dos orbit around it.
/// Trackpad: two-finger scroll pans, pinch zooms around the pointer. Drag nodes to move them.
struct CategoryGraphView: View {
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var scheme
    var categoryFilter: UUID?
    var search: String

    /// Shared so the layout, zoom and position survive switching pages
    @State private var sim = GraphSim.shared
    @AppStorage("graphShowDone") private var showDone = false
    @AppStorage("graphPeriod") private var period: GraphPeriod = .week
    @State private var anchor = Date()
    @State private var selected: String?
    @State private var dragNode: Int?
    @State private var grabOffset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var monitor: Any?
    @AppStorage("graphHubSize") private var hubSize = 1.0
    @AppStorage("graphLeafSize") private var leafSize = 1.0
    @AppStorage("graphLinkLength") private var linkLength = 1.0
    @State private var showLook = false

    var body: some View {
        let graph = buildGraph()
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .topLeading) {
                canvas
                legend.padding(12)
                periodBar.padding(12).frame(maxWidth: .infinity, alignment: .top)
                zoomControls.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                Text("Pinch to zoom · two-finger scroll to move · drag nodes")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                if graph.nodes.isEmpty {
                    Text("Nothing to show. Add tasks or To-do cells with a category.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .underPageBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            if let id = selected, let node = graph.nodes.first(where: { $0.id == id }) {
                GraphDetails(node: node,
                             items: items(of: node.id, in: graph),
                             showDone: showDone,
                             select: { selected = $0 },
                             close: { selected = nil })
                    .frame(width: 300)
            }
        }
        .onAppear {
            sim.setLook(hub: hubSize, leaf: leafSize, link: linkLength)
            sim.sync(graph)
            installMonitor()
        }
        .onDisappear(perform: removeMonitor)
        .onChange(of: graph) { _, g in sim.sync(g) }
        .onChange(of: hubSize) { _, _ in sim.setLook(hub: hubSize, leaf: leafSize, link: linkLength) }
        .onChange(of: leafSize) { _, _ in sim.setLook(hub: hubSize, leaf: leafSize, link: linkLength) }
        .onChange(of: linkLength) { _, _ in sim.setLook(hub: hubSize, leaf: leafSize, link: linkLength) }
    }

    /// What a hub holds: its own items plus its subcategories' items (the subcategory hubs themselves aren't listed)
    private func items(of id: String, in graph: GraphData) -> [GraphData.Node] {
        graph.edges.filter { $0.a == id }.flatMap { e -> [GraphData.Node] in
            guard let n = graph.nodes.first(where: { $0.id == e.b }) else { return [] }
            return n.isHub ? items(of: n.id, in: graph) : [n]
        }
    }

    // MARK: Data

    private func buildGraph() -> GraphData {
        var nodes: [GraphData.Node] = []
        var edges: [GraphData.Edge] = []
        var hubs: [String: GraphData.Node] = [:]
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()

        func hub(for categoryID: UUID?) -> String {
            let id = "cat:" + (categoryID?.uuidString ?? "none")
            if hubs[id] == nil {
                let c = store.category(categoryID)
                hubs[id] = .init(id: id, title: c?.name ?? "No category", color: c?.colorHex ?? "#8E8E93",
                                 isHub: true, isSchedule: false, isDone: false, detail: "", ref: nil, date: nil)
                // a subcategory hangs off its parent category's hub
                if let parent = c?.parentID, store.category(parent) != nil {
                    edges.append(.init(a: hub(for: parent), b: id))
                }
            }
            return id
        }
        func include(_ cat: UUID?, _ title: String) -> Bool {
            if let categoryFilter, !store.isInside(cat, categoryFilter) { return false }
            return q.isEmpty || title.lowercased().contains(q)
        }

        let kind = store.settings.primaryCalendar
        let range = periodInterval
        let multiDay = period == .week || period == .month

        // Tasks: all of them, or the ones dated inside the period
        for t in store.tasks where (showDone || !t.isDone) && include(t.categoryID, t.title) {
            if let range {
                guard let d = t.dueDate, range.contains(d) else { continue }
            }
            let h = hub(for: t.categoryID)
            let detail = t.dueDate.map { Fmt.date($0, "EEE, MMM d", kind) } ?? "No date"
            nodes.append(.init(id: "task:\(t.id)", title: t.title, color: store.category(t.categoryID)?.colorHex ?? "#8E8E93",
                               isHub: false, isSchedule: false, isDone: t.isDone, detail: "Task · \(detail)", ref: .task(t.id),
                               date: t.dueDate))
            edges.append(.init(a: h, b: "task:\(t.id)"))
        }

        // Weekly to-dos: every weekly cell once (All), or one node per day it actually happens in the period
        if let range {
            for day in Cal.persian.days(in: range) {
                for r in store.scheduleRows(on: day, kinds: [.todo]) where include(r.entry.categoryID, r.entry.title) {
                    if r.isDone && !showDone { continue }
                    let e = r.entry
                    let id = "entry:\(e.id)|\(Cal.dayKey(day))"
                    let h = hub(for: e.categoryID)
                    nodes.append(.init(id: id, title: multiDay ? "\(e.title) · \(Fmt.date(day, period == .week ? "EEE" : "MMM d", kind))" : e.title,
                                       color: store.colorHex(of: e) ?? store.category(e.categoryID)?.colorHex ?? "#5B7CFA",
                                       isHub: false, isSchedule: true, isDone: r.isDone,
                                       detail: "\(Fmt.date(day, "EEE, MMM d", kind)) · \(r.slot.title)", ref: .schedule(e.id), date: day))
                    edges.append(.init(a: h, b: id))
                }
            }
        } else {
            for e in store.schedule where e.kind == .todo && include(e.categoryID, e.title) {
                let done = store.isDone(.schedule(e.id), on: store.occurrence(of: e))
                if done && !showDone { continue }
                let h = hub(for: e.categoryID)
                let slot = store.slot(e.slotID)?.title ?? ""
                let hex = store.colorHex(of: e) ?? store.category(e.categoryID)?.colorHex ?? "#5B7CFA"
                nodes.append(.init(id: "entry:\(e.id)", title: e.title, color: hex, isHub: false, isSchedule: true,
                                   isDone: done, detail: "Weekly schedule · \(Cal.weekdayNames[e.weekday]) \(slot)",
                                   ref: .schedule(e.id), date: nil))
                edges.append(.init(a: h, b: "entry:\(e.id)"))
            }
        }
        return GraphData(nodes: hubs.values.sorted { $0.title < $1.title } + nodes, edges: edges)
    }

    // MARK: Period

    /// nil = everything (no date filter)
    private var periodInterval: DateInterval? {
        switch period {
        case .all: nil
        case .day: Cal.persian.dayInterval(anchor)
        case .week: Cal.persian.dateInterval(of: .weekOfYear, for: anchor)
        case .month: store.settings.primaryCalendar.calendar.dateInterval(of: .month, for: anchor)
        }
    }

    private var periodTitle: String {
        let k = store.settings.primaryCalendar
        guard let r = periodInterval else { return "Everything" }
        switch period {
        case .day: return Fmt.date(anchor, "EEEE, MMM d", k)
        case .month: return Fmt.date(r.start, "MMMM y", k)
        default: return "\(Fmt.date(r.start, "MMM d", k)) – \(Fmt.date(r.end.addingTimeInterval(-1), "MMM d", k))"
        }
    }

    private func shift(_ delta: Int) {
        let comp: Calendar.Component = period == .day ? .day : (period == .week ? .weekOfYear : .month)
        anchor = store.settings.primaryCalendar.calendar.date(byAdding: comp, value: delta, to: anchor) ?? anchor
    }

    private var periodBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $period) {
                ForEach(GraphPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            if period != .all {
                HStack(spacing: 2) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 18) }
                    Button("Today") { anchor = Date() }
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 18) }
                }
                .buttonStyle(.borderless)
            }
            Text(periodTitle).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.regularMaterial))
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: sim.settled && dragNode == nil)) { _ in
                Canvas { ctx, _ in
                    sim.tick()
                    draw(ctx, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(size: size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    sim.pointer = p
                    let h = sim.hit(p, size: size).map { sim.nodes[$0].id }
                    if h != sim.hovered { sim.hovered = h }
                case .ended:
                    sim.pointer = nil
                    sim.hovered = nil
                }
            }
            .onAppear { sim.viewSize = size }
            .onChange(of: size) { old, s in
                // the details panel opening or closing changes the width: keep the graph where it was on screen
                sim.pan = CGSize(width: sim.pan.width + (old.width - s.width) / 2, height: sim.pan.height + (old.height - s.height) / 2)
                sim.viewSize = s
            }
        }
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                // a click is not a drag: nothing moves until the pointer has really moved
                guard hypot(v.translation.width, v.translation.height) > 4 || dragNode != nil || panStart != nil else { return }
                if dragNode == nil && panStart == nil {
                    if let i = sim.hit(v.startLocation, size: size) {
                        dragNode = i
                        // keep the spot you grabbed under the pointer (no jump to the node's centre)
                        let w = sim.toWorld(v.startLocation, size)
                        grabOffset = CGSize(width: sim.nodes[i].x - w.x, height: sim.nodes[i].y - w.y)
                    } else { panStart = sim.pan }
                }
                if let i = dragNode, sim.nodes.indices.contains(i) {
                    let w = sim.toWorld(v.location, size)
                    sim.place(i, at: CGPoint(x: w.x + grabOffset.width, y: w.y + grabOffset.height))
                    sim.reheat(0.3)
                } else if let s = panStart {
                    sim.pan = CGSize(width: s.width + v.translation.width, height: s.height + v.translation.height)
                }
            }
            .onEnded { v in
                if hypot(v.translation.width, v.translation.height) <= 4 {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selected = sim.hit(v.location, size: size).map { sim.nodes[$0].id }
                    }
                }
                if let i = dragNode, sim.nodes.indices.contains(i) { sim.nodes[i].pinned = false }
                dragNode = nil
                panStart = nil
            }
    }

    // MARK: Trackpad

    /// Two-finger scroll pans, pinch (or a mouse wheel) zooms around the pointer — only while over the graph
    private func installMonitor() {
        guard monitor == nil else { return }
        let sim = sim
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            MainActor.assumeIsolated {
                guard let p = sim.pointer else { return event }
                switch event.type {
                case .magnify:
                    sim.zoom(by: 1 + event.magnification, at: p)
                case .scrollWheel:
                    if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
                        sim.pan.width += event.scrollingDeltaX
                        sim.pan.height += event.scrollingDeltaY
                    } else {
                        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 120 : event.scrollingDeltaY / 12
                        sim.zoom(by: exp(dy), at: p)
                    }
                default:
                    return event
                }
                return nil
            }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let dark = scheme == .dark
        let bg = Color(nsColor: .underPageBackgroundColor)
        let scale = sim.scale
        let now = Date()

        // Soft dot grid that moves with the view
        let spacing = 30 * scale
        if spacing > 10 {
            var dots = Path()
            let ox = (size.width / 2 + sim.pan.width).truncatingRemainder(dividingBy: spacing)
            let oy = (size.height / 2 + sim.pan.height).truncatingRemainder(dividingBy: spacing)
            var x = ox
            while x < size.width {
                var y = oy
                while y < size.height {
                    dots.addEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                    y += spacing
                }
                x += spacing
            }
            ctx.fill(dots, with: .color(.primary.opacity(dark ? 0.06 : 0.08)))
        }

        // Hover / selection highlight eases in and out
        let focus = sim.hovered ?? selected
        if focus != nil { sim.lastFocus = focus }
        sim.focusLevel += ((focus == nil ? 0 : 1) - sim.focusLevel) * 0.18
        if focus == nil && sim.focusLevel < 0.01 { sim.lastFocus = nil }
        let f = sim.focusLevel
        let shown = focus ?? sim.lastFocus
        var near: Set<String> = []
        if let shown {
            near.insert(shown)
            for (a, b) in sim.links where sim.nodes[a].id == shown || sim.nodes[b].id == shown {
                near.insert(sim.nodes[a].id); near.insert(sim.nodes[b].id)
            }
        }
        func dimFactor(_ id: String) -> Double { near.contains(id) ? 1 : 1 - 0.8 * f }

        // Links: gently curved, fading from the category colour to the item's colour
        for (a, b) in sim.links {
            let A = sim.nodes[a], B = sim.nodes[b]
            let grow = min(sim.appear(A, at: now), sim.appear(B, at: now))
            guard grow > 0.02 else { continue }
            let p1 = sim.toScreen(A.point, size), p2 = sim.toScreen(B.point, size)
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let ctrl = CGPoint(x: mid.x - dy * 0.08, y: mid.y + dx * 0.08)
            let k = min(1, grow)
            let end = CGPoint(x: p1.x + dx * k, y: p1.y + dy * k)
            var path = Path()
            path.move(to: p1)
            path.addQuadCurve(to: end, control: ctrl)
            let lit = shown != nil && near.contains(A.id) && near.contains(B.id)
            let base = lit ? 0.32 + 0.45 * f : 0.3 * (1 - 0.75 * f)
            ctx.stroke(path, with: .linearGradient(
                Gradient(colors: [Color(hex: A.color).opacity(base), Color(hex: B.color).opacity(base * 0.8)]),
                startPoint: p1, endPoint: p2),
                style: StrokeStyle(lineWidth: (lit ? 1 + 0.8 * f : 1) * min(1.5, max(0.7, scale)), lineCap: .round))
        }

        // Nodes: round, softly lit, with a faint halo
        for n in sim.nodes {
            let grow = sim.appear(n, at: now)
            guard grow > 0.01 else { continue }
            let p = sim.toScreen(n.point, size)
            let r = sim.radius(n) * scale * grow
            let o = dimFactor(n.id)
            let color = Color(hex: n.color)
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let isHover = n.id == sim.hovered

            // Halo
            let haloR = r * (n.isHub ? 2.4 : 1.9) * (isHover ? 1.25 : 1)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - haloR, y: p.y - haloR, width: haloR * 2, height: haloR * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity((n.isHub ? 0.32 : 0.18) * o), color.opacity(0)]),
                                           center: p, startRadius: r * 0.5, endRadius: haloR))

            if n.isDone {
                // Done: a quiet ring with a check
                ctx.fill(Path(ellipseIn: rect), with: .color(bg.opacity(o)))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.12, dy: r * 0.12)),
                           with: .color(color.opacity(0.75 * o)), lineWidth: max(1.2, r * 0.24))
                if r > 5 {
                    ctx.draw(Text(Image(systemName: "checkmark")).font(.system(size: r * 0.85, weight: .bold))
                        .foregroundStyle(color.opacity(o)), at: p)
                }
            } else {
                // Lit from the top-left like a small sphere
                var lit = ctx
                lit.opacity = o
                lit.fill(Path(ellipseIn: rect), with: .color(color))
                lit.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0), Color.black.opacity(0.18)]),
                    center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.6))
                if n.isSchedule {
                    // Weekly to-dos carry a small inner ring
                    lit.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.42, dy: r * 0.42)),
                               with: .color(.white.opacity(0.8)), lineWidth: max(0.8, r * 0.16))
                }
            }
            ctx.stroke(Path(ellipseIn: rect), with: .color(bg.opacity(0.7 * o)), lineWidth: max(0.8, r * 0.12))
            if n.id == selected {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.primary.opacity(0.8)), lineWidth: 1.6)
            }

            let showLabel = n.isHub || scale >= 1.15 || n.id == shown || (shown != nil && near.contains(n.id) && f > 0.3)
            if showLabel && grow > 0.6 {
                let title = n.title.count > 26 ? String(n.title.prefix(25)) + "…" : n.title
                let label = Text(title)
                    .font(n.isHub ? .system(size: 12.5, weight: .semibold, design: .rounded) : .system(size: 10.5, design: .rounded))
                    .foregroundStyle(n.isHub ? Color.primary.opacity(0.9 * o) : Color.secondary.opacity(o))
                ctx.draw(label, at: CGPoint(x: p.x, y: p.y + r + (n.isHub ? 7 : 5)), anchor: .top)
            }
        }
    }

    // MARK: Overlays

    private var lookPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Graph look").font(.headline)
            lookSlider("Category size", "circle.circle", $hubSize, 0.5...2.2)
            lookSlider("To-do size", "circle.fill", $leafSize, 0.5...2.8)
            lookSlider("Link length", "line.diagonal", $linkLength, 0.4...3)
            HStack {
                Button("Reset") { hubSize = 1; leafSize = 1; linkLength = 1 }
                Spacer()
                Button("Re-arrange ✨") { sim.shake() }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 270)
    }

    private func lookSlider(_ title: String, _ icon: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: icon).font(.callout)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Circle().frame(width: 12, height: 12); Text("Category") }
            HStack(spacing: 6) { Circle().frame(width: 7, height: 7).padding(.horizontal, 2.5); Text("Task") }
            HStack(spacing: 6) {
                Circle().frame(width: 8, height: 8).overlay(Circle().inset(by: 2.3).stroke(Color.white, lineWidth: 1.2)).padding(.horizontal, 2)
                Text("Weekly to-do")
            }
            HStack(spacing: 6) { Circle().strokeBorder(lineWidth: 1.5).frame(width: 8, height: 8).padding(.horizontal, 2); Text("Done") }
            Toggle("Show done", isOn: $showDone).toggleStyle(.checkbox).padding(.top, 2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { sim.zoom(by: 1 / 1.25, at: nil) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
            Button { withAnimation(.easeInOut) { sim.fit() } } label: { Image(systemName: "scope") }.help("Fit everything")
            Button { sim.zoom(by: 1.25, at: nil) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
            Button { sim.shake() } label: { Image(systemName: "wand.and.rays") }.help("Re-arrange with an animation")
            Button { showLook.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .help("Node size and link length")
                .popover(isPresented: $showLook, arrowEdge: .top) { lookPanel }
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(Capsule().fill(.regularMaterial))
    }
}

/// Everything about the clicked item: dates in both calendars, time, repeat rule, study time, and notes
private struct GraphDetails: View {
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    let node: GraphData.Node
    /// Items of a category hub
    let items: [GraphData.Node]
    let showDone: Bool
    let select: (String) -> Void
    let close: () -> Void

    private var kind: CalendarKind { store.settings.primaryCalendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(node.isHub ? "Category" : (node.isSchedule ? "Weekly to-do" : "Task"),
                          systemImage: node.isHub ? "tag" : (node.isSchedule ? "tablecells" : "checklist"))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help("Close")
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Color(hex: node.color)).frame(width: 12, height: 12)
                    Text(node.title).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                }

                switch node.ref {
                case .task(let id): if let t = store.task(id) { taskInfo(t) }
                case .schedule(let id): if let e = store.entry(id) { entryInfo(e) }
                case nil: hubInfo
                }
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }

    // MARK: Weekly to-do

    @ViewBuilder
    private func entryInfo(_ e: ScheduleEntry) -> some View {
        let (day, when) = node.date.map { ($0, "Date") } ?? nextOccurrence(e)
        let done = store.isDone(.schedule(e.id), on: day)
        let slot = store.slot(e.slotID)

        if store.isSkipped(.schedule(e.id), on: day) {
            status("Skipped (won't do)", .orange)
        } else {
        status(done ? "Done this week" : (day < Cal.persian.startOfDay(for: Date()) ? "Not done (day has passed)" : "To do"),
               done ? .green : (day < Cal.persian.startOfDay(for: Date()) ? .orange : .accentColor))
        }

        section("When") {
            row("calendar", when, Fmt.date(day, "EEEE, MMMM d", kind))
            row("calendar.badge.clock", kind.other == .persian ? "Persian" : "Gregorian", Fmt.date(day, "MMMM d, y", kind.other))
            if let slot { row("clock", "Time", "\(slot.title) · \(slot.endMinute - slot.startMinute) min") }
            row(e.recurrence.icon, "Repeats", e.recurrence == .once
                ? "Only the week of \(e.weekStart.map { Fmt.date($0, "MMM d", kind) } ?? "")" : e.recurrence.title)
            row("tag", "Category", store.categoryLabel(e.categoryID) ?? "None")
        }
        studied(.schedule(e.id))
        if e.text.contains("\n") {
            section("In the cell") { Text(e.text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        notes(Binding(get: { store.entry(e.id)?.notes ?? "" },
                      set: { v in store.updateEntry(e.id) { $0.notes = v } }))
        actions(.schedule(e.id), done: done) {
            Button("Open in Schedule") { router.selection = .schedule }
            Button("Open Day") { router.tasksFocusDate = day }
        }
    }

    /// The next week this entry actually appears in (odd / even / one-week entries may skip this week)
    private func nextOccurrence(_ e: ScheduleEntry) -> (Date, String) {
        let labels = ["This week", "Next week", "In 2 weeks"]
        for k in 0..<3 {
            let ref = Cal.persian.date(byAdding: .day, value: 7 * k, to: Date()) ?? Date()
            if store.applies(e, toWeekOf: ref) { return (store.occurrence(of: e, inWeekOf: ref), labels[k]) }
        }
        let ws = e.weekStart ?? Date()
        return (store.occurrence(of: e, inWeekOf: ws), "Week of")
    }

    // MARK: Task

    @ViewBuilder
    private func taskInfo(_ t: TaskItem) -> some View {
        let overdue = !t.isDone && (t.dueDate.map { $0 < Cal.persian.startOfDay(for: Date()) } ?? false)
        if t.isSkipped {
            status("Skipped (won't do)", .orange)
        } else {
        status(t.isDone ? "Done\(t.completedAt.map { " · " + Fmt.date($0, "MMM d", kind) } ?? "")" : (overdue ? "Overdue" : "To do"),
               t.isDone ? .green : (overdue ? .orange : .accentColor))
        }

        section("When") {
            if let d = t.dueDate {
                row("calendar", "Date", Fmt.date(d, "EEEE, MMMM d", kind))
                row("calendar.badge.clock", kind.other == .persian ? "Persian" : "Gregorian", Fmt.date(d, "MMMM d, y", kind.other))
                if t.hasTime { row("clock", "Time", "\(Fmt.time(d)) · \(t.estimatedMinutes) min") }
            } else {
                row("tray", "Date", "No date")
            }
            row("tag", "Category", store.categoryLabel(t.categoryID) ?? "None")
            row("flag", "Priority", t.priority.title)
            if !t.hasTime { row("hourglass", "Estimate", "\(t.estimatedMinutes) min") }
            row("plus.circle", "Created", Fmt.date(t.createdAt, "MMM d, y", kind))
        }
        studied(.task(t.id))
        notes(Binding(get: { store.task(t.id)?.notes ?? "" },
                      set: { v in if var x = store.task(t.id) { x.notes = v; store.upsertTask(x) } }))
        actions(.task(t.id), done: t.isDone) {
            if let d = t.dueDate { Button("Open Day") { router.tasksFocusDate = d } }
        }
    }

    // MARK: Category

    @ViewBuilder
    private var hubInfo: some View {
        let catID = UUID(uuidString: String(node.id.dropFirst(4)))
        let sessions = store.sessions.filter { s in catID.map { store.isInside(s.categoryID, $0) } ?? (s.categoryID == nil) }
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: Date())
        section("Overview") {
            row("list.bullet", "Items", "\(items.count)")
            row("checkmark.circle", "Done", "\(items.filter(\.isDone).count)")
            row("clock", "Studied", sessions.isEmpty ? "—" : Fmt.duration(sessions.reduce(0) { $0 + $1.duration }))
            if let week {
                let w = sessions.filter { week.contains($0.start) }.reduce(0) { $0 + $1.duration }
                row("calendar", "This week", w > 0 ? Fmt.duration(w) : "—")
            }
        }
        let open = items.filter { !$0.isDone }, done = items.filter(\.isDone)
        section("To do (\(open.count))") {
            if open.isEmpty { Text("Nothing left 🎉").font(.callout).foregroundStyle(.secondary) }
            itemList(open)
        }
        if !done.isEmpty {
            section("Done (\(done.count))") { itemList(done) }
        } else if !showDone {
            Text("Turn on “Show done” to list finished items.").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func itemList(_ list: [GraphData.Node]) -> some View {
        ForEach(list, id: \.id) { i in
                Button { select(i.id) } label: {
                    HStack {
                        Image(systemName: i.isDone ? "checkmark.circle.fill" : (i.isSchedule ? "square" : "circle"))
                            .foregroundStyle(Color(hex: i.color))
                        Text(i.title).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func studied(_ ref: TodoRef) -> some View {
        let list = store.sessions.filter { s in
            switch ref {
            case .schedule(let id): s.scheduleEntryID == id
            case .task(let id): s.taskID == id
            }
        }
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: Date())
        section("Study time") {
            row("clock", "Total", list.isEmpty ? "Not studied yet" : Fmt.duration(list.reduce(0) { $0 + $1.duration }))
            if !list.isEmpty {
                if let week {
                    let w = list.filter { week.contains($0.start) }.reduce(0) { $0 + $1.duration }
                    row("calendar", "This week", w > 0 ? Fmt.duration(w) : "—")
                }
                row("number", "Sessions", "\(list.count)")
                if let last = list.map(\.start).max() { row("clock.arrow.circlepath", "Last studied", Fmt.date(last, "EEE, MMM d", kind)) }
            }
        }
    }

    private func notes(_ text: Binding<String>) -> some View {
        section("Notes") {
            TextEditor(text: text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("Add a note…").font(.callout).foregroundStyle(.tertiary).padding(11).allowsHitTesting(false)
                    }
                }
        }
    }

    private func actions<Extra: View>(_ ref: TodoRef, done: Bool, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(done ? "Mark not done" : "Mark done") {
                    if case .schedule(let id) = ref, let e = store.entry(id) {
                        store.toggleDone(ref, on: node.date ?? nextOccurrence(e).0)
                    } else {
                        store.toggleDone(ref, on: Date())
                    }
                }
                Button("Study") {
                    timer.select(ref)
                    router.selection = .timer
                }
                .buttonStyle(.borderedProminent)
                .disabled(timer.isActive)
            }
            let day: Date = {
                if case .schedule(let id) = ref, let e = store.entry(id) { return node.date ?? nextOccurrence(e).0 }
                if case .task(let id) = ref { return store.task(id)?.dueDate ?? Date() }
                return Date()
            }()
            let skipped = store.isSkipped(ref, on: day)
            Button(skipped ? "Bring back to to-do" : "Skip (won't do)") { store.setSkipped(ref, on: day, !skipped) }
                .buttonStyle(.borderless).foregroundStyle(.orange)
            HStack { extra() }.buttonStyle(.borderless).font(.caption)
        }
    }

    private func status(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            content()
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

// MARK: - Model

/// Which items the graph shows
enum GraphPeriod: String, CaseIterable, Identifiable {
    case all, day, week, month

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

struct GraphData: Equatable {
    struct Node: Equatable {
        let id: String
        let title: String
        let color: String
        let isHub: Bool
        let isSchedule: Bool
        let isDone: Bool
        let detail: String
        let ref: TodoRef?
        /// The day this item happens (nil = undated / every week)
        let date: Date?
    }
    struct Edge: Equatable {
        let a: String
        let b: String
    }
    var nodes: [Node]
    var edges: [Edge]
}

/// A small d3-style force simulation: charge, links, centring and collision, cooling down over a few seconds.
@MainActor @Observable
final class GraphSim {
    static let shared = GraphSim()

    struct Node {
        let id: String
        var title: String
        var color: String
        var isHub: Bool
        var isSchedule: Bool
        var isDone: Bool
        var detail: String
        var ref: TodoRef?
        var degree = 0
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var pinned = false
        /// When the node starts to grow in (for the appear / re-arrange animation)
        var birth = Date()
        /// Where you dropped a category: it stays there instead of drifting to the centre
        var anchor: CGPoint?

        var point: CGPoint { CGPoint(x: x, y: y) }
    }

    /// User settings: category size, to-do size and link length multipliers
    @ObservationIgnored var hubSize: CGFloat = 1
    @ObservationIgnored var leafSize: CGFloat = 1
    @ObservationIgnored var linkLength: CGFloat = 1

    func radius(_ n: Node) -> CGFloat {
        n.isHub ? min(30, 11 + 2.2 * sqrt(CGFloat(n.degree))) * hubSize : 6.2 * leafSize
    }

    /// 0 → 1 with a little overshoot, so nodes pop in softly
    func appear(_ n: Node, at now: Date) -> CGFloat {
        let t = min(1, max(0, now.timeIntervalSince(n.birth) / 0.55))
        guard t < 1 else { return 1 }
        let c1 = 1.70158, c3 = c1 + 1
        return CGFloat(1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2))
    }

    /// Hover highlight fades in and out instead of switching instantly
    @ObservationIgnored var focusLevel: CGFloat = 0
    @ObservationIgnored var lastFocus: String?

    @ObservationIgnored var nodes: [Node] = []
    @ObservationIgnored var links: [(Int, Int)] = []
    @ObservationIgnored private var alpha: CGFloat = 1
    @ObservationIgnored private var alphaTarget: CGFloat = 0
    @ObservationIgnored var pointer: CGPoint?
    @ObservationIgnored var viewSize: CGSize = CGSize(width: 800, height: 600)

    /// Observed so the canvas stops animating once the layout is still
    var settled = false
    var hovered: String?
    var scale: CGFloat = 1
    var pan: CGSize = .zero

    // MARK: Coordinates

    func toScreen(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + pan.width + p.x * scale, y: size.height / 2 + pan.height + p.y * scale)
    }

    func toWorld(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - size.width / 2 - pan.width) / scale, y: (p.y - size.height / 2 - pan.height) / scale)
    }

    func hit(_ p: CGPoint, size: CGSize) -> Int? {
        let w = toWorld(p, size)
        var best: Int?
        var bestD = CGFloat.infinity
        for i in nodes.indices {
            let d = hypot(nodes[i].x - w.x, nodes[i].y - w.y) - radius(nodes[i])
            if d < bestD { bestD = d; best = i }
        }
        return bestD <= 5 / scale ? best : nil
    }

    /// Zoom keeping the point under the pointer (or the centre) still
    func zoom(by factor: CGFloat, at screenPoint: CGPoint?) {
        let p = screenPoint ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let w = toWorld(p, viewSize)
        let newScale = min(5, max(0.2, scale * factor))
        scale = newScale
        pan = CGSize(width: p.x - viewSize.width / 2 - w.x * newScale, height: p.y - viewSize.height / 2 - w.y * newScale)
    }

    /// Zoom and centre so every node is visible
    func fit() {
        guard !nodes.isEmpty else { scale = 1; pan = .zero; return }
        let xs = nodes.map(\.x), ys = nodes.map(\.y)
        let w = (xs.max()! - xs.min()!) + 120, h = (ys.max()! - ys.min()!) + 120
        scale = min(2, max(0.2, min(viewSize.width / max(w, 1), viewSize.height / max(h, 1))))
        let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2
        pan = CGSize(width: -cx * scale, height: -cy * scale)
    }

    // MARK: Simulation

    func sync(_ g: GraphData) {
        let old = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var hubCenters: [String: CGPoint] = [:]
        let hubs = g.nodes.filter(\.isHub)
        for (i, h) in hubs.enumerated() {
            if let p = old[h.id] { hubCenters[h.id] = p.point; continue }
            // Spread new hubs on a circle
            let angle = CGFloat(i) / CGFloat(max(1, hubs.count)) * 2 * .pi
            hubCenters[h.id] = CGPoint(x: cos(angle) * 160, y: sin(angle) * 160)
        }
        let parent = Dictionary(g.edges.map { ($0.b, $0.a) }, uniquingKeysWith: { a, _ in a })
        var added = false
        nodes = g.nodes.enumerated().map { i, n in
            var node = Node(id: n.id, title: n.title, color: n.color, isHub: n.isHub, isSchedule: n.isSchedule,
                            isDone: n.isDone, detail: n.detail, ref: n.ref, x: 0, y: 0)
            if let p = old[n.id] {
                node.x = p.x; node.y = p.y; node.vx = p.vx; node.vy = p.vy; node.birth = p.birth; node.anchor = p.anchor
            } else {
                node.birth = Date().addingTimeInterval(n.isHub ? 0 : 0.15 + min(1, Double(i) * 0.02))
                added = true
                // Start each item close to its category, on a little spiral
                let c = n.isHub ? hubCenters[n.id]! : (parent[n.id].flatMap { hubCenters[$0] } ?? .zero)
                let k = CGFloat(i)
                let a = k * .pi * (3 - sqrt(5))
                let r: CGFloat = n.isHub ? 0 : 30 + 4 * sqrt(k)
                node.x = c.x + cos(a) * r
                node.y = c.y + sin(a) * r
            }
            return node
        }
        let index = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        links = g.edges.compactMap { e in
            guard let a = index[e.a], let b = index[e.b] else { return nil }
            return (a, b)
        }
        for (a, b) in links { nodes[a].degree += 1; nodes[b].degree += 1 }
        reheat(added || old.isEmpty ? 1 : 0.3)
    }

    func reheat(_ to: CGFloat) {
        alpha = max(alpha, to)
        if settled { settled = false }
    }

    /// The ✨ button: everything gathers in the middle, then the categories bloom outward
    /// and their items pop in one after another
    func shake() {
        let now = Date()
        var leaf = 0
        for i in nodes.indices { nodes[i].anchor = nil }
        let hubs = nodes.indices.filter { nodes[$0].isHub }
        for (k, i) in hubs.enumerated() {
            let a = CGFloat(k) / CGFloat(max(1, hubs.count)) * 2 * .pi
            nodes[i].x = cos(a) * 6; nodes[i].y = sin(a) * 6
            nodes[i].vx = cos(a) * 14; nodes[i].vy = sin(a) * 14
            nodes[i].birth = now.addingTimeInterval(Double(k) * 0.08)
        }
        for i in nodes.indices where !nodes[i].isHub {
            let a = CGFloat.random(in: 0...(2 * .pi))
            nodes[i].x = cos(a) * 3; nodes[i].y = sin(a) * 3
            nodes[i].vx = 0; nodes[i].vy = 0
            nodes[i].birth = now.addingTimeInterval(0.25 + min(1.4, Double(leaf) * 0.035))
            leaf += 1
        }
        alpha = 1
        settled = false
    }

    /// How close two nodes may get. Categories keep room for their items so clusters never overlap.
    func minDistance(_ a: Node, _ b: Node) -> CGFloat {
        if a.isHub && b.isHub {
            func reach(_ n: Node) -> CGFloat { radius(n) + (40 + 3 * sqrt(CGFloat(n.degree))) * linkLength + 14 * leafSize }
            return reach(a) + reach(b) + 10
        }
        return radius(a) + radius(b) + 5
    }

    /// Move a dragged node to `p`, sliding around other categories instead of over them
    func place(_ i: Int, at p: CGPoint) {
        var q = p
        if nodes[i].isHub {
            for _ in 0..<4 {
                for j in nodes.indices where j != i && nodes[j].isHub {
                    let dx = q.x - nodes[j].x, dy = q.y - nodes[j].y
                    let d = max(0.01, hypot(dx, dy)), minD = minDistance(nodes[i], nodes[j])
                    if d < minD { q = CGPoint(x: nodes[j].x + dx / d * minD, y: nodes[j].y + dy / d * minD) }
                }
            }
        }
        nodes[i].x = q.x; nodes[i].y = q.y
        nodes[i].pinned = true
        if nodes[i].isHub { nodes[i].anchor = q }
    }

    /// Size / length settings changed: let the layout adjust smoothly
    func setLook(hub: CGFloat, leaf: CGFloat, link: CGFloat) {
        guard hub != hubSize || leaf != leafSize || link != linkLength else { return }
        hubSize = hub; leafSize = leaf; linkLength = link
        reheat(0.5)
    }

    func tick() {
        if pinnedCount > 0 { alphaTarget = 0.3 } else { alphaTarget = 0 }
        alpha += (alphaTarget - alpha) * 0.016
        let now = Date()
        let animating = nodes.contains { now.timeIntervalSince($0.birth) < 0.6 }
            || abs(focusLevel - (lastFocus == nil ? 0 : 1)) > 0.01
        guard alpha > 0.003 || animating, !nodes.isEmpty else {
            if !settled { DispatchQueue.main.async { self.settled = true } }
            return
        }
        guard alpha > 0.003 else { return }
        let n = nodes.count

        // Links: pull each item towards its category, at a distance that grows with the category's size
        for (a, b) in links {
            let ra = radius(nodes[a]), rb = radius(nodes[b])
            let target = (34 + 3 * sqrt(CGFloat(nodes[a].degree))) * linkLength + ra + rb
            var dx = nodes[b].x + nodes[b].vx - nodes[a].x - nodes[a].vx
            var dy = nodes[b].y + nodes[b].vy - nodes[a].y - nodes[a].vy
            if dx == 0 && dy == 0 { dx = .random(in: -0.5...0.5); dy = .random(in: -0.5...0.5) }
            let l = sqrt(dx * dx + dy * dy)
            let strength = 0.7 / CGFloat(max(1, min(nodes[a].degree, nodes[b].degree)))
            let k = (l - target) / l * alpha * strength
            dx *= k; dy *= k
            let bias = CGFloat(nodes[a].degree) / CGFloat(nodes[a].degree + nodes[b].degree)
            nodes[b].vx -= dx * bias; nodes[b].vy -= dy * bias
            nodes[a].vx += dx * (1 - bias); nodes[a].vy += dy * (1 - bias)
        }

        // Charge: everything repels, categories much more so clusters keep apart
        for i in 0..<n {
            for j in (i + 1)..<n {
                var dx = nodes[j].x - nodes[i].x, dy = nodes[j].y - nodes[i].y
                var d2 = dx * dx + dy * dy
                if d2 > 360_000 { continue }
                if d2 < 1 { dx = .random(in: -1...1); dy = .random(in: -1...1); d2 = 1 }
                d2 = max(d2, 100)
                let si: CGFloat = nodes[i].isHub ? -520 : -55
                let sj: CGFloat = nodes[j].isHub ? -520 : -55
                nodes[i].vx += dx * sj * alpha / d2; nodes[i].vy += dy * sj * alpha / d2
                nodes[j].vx -= dx * si * alpha / d2; nodes[j].vy -= dy * si * alpha / d2
            }
        }

        // Gentle pull to the centre
        for i in 0..<n {
            if let a = nodes[i].anchor {
                // A dropped category is held at its spot
                nodes[i].vx += (a.x - nodes[i].x) * 0.12
                nodes[i].vy += (a.y - nodes[i].y) * 0.12
                continue
            }
            let k: CGFloat = nodes[i].isHub ? 0.05 : 0.02
            nodes[i].vx -= nodes[i].x * k * alpha
            nodes[i].vy -= nodes[i].y * k * alpha
        }

        // Collision: nodes never overlap
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = nodes[j].x - nodes[i].x, dy = nodes[j].y - nodes[i].y
                let minD = minDistance(nodes[i], nodes[j])
                let d2 = dx * dx + dy * dy
                guard d2 < minD * minD else { continue }
                let d = max(0.01, sqrt(d2))
                // Dragged nodes hold still; the others make room
                let wi: CGFloat = nodes[i].pinned ? 0 : (nodes[j].pinned ? 1 : 0.5)
                let wj: CGFloat = nodes[j].pinned ? 0 : (nodes[i].pinned ? 1 : 0.5)
                let push = (minD - d) / d
                nodes[i].x -= dx * push * wi; nodes[i].y -= dy * push * wi
                nodes[j].x += dx * push * wj; nodes[j].y += dy * push * wj
                if nodes[i].anchor != nil { nodes[i].anchor = nodes[i].point }
                if nodes[j].anchor != nil { nodes[j].anchor = nodes[j].point }
            }
        }

        // Move with friction
        for i in 0..<n {
            if nodes[i].pinned { nodes[i].vx = 0; nodes[i].vy = 0; continue }
            nodes[i].vx *= 0.58
            nodes[i].vy *= 0.58
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy
        }
    }

    private var pinnedCount: Int { nodes.reduce(0) { $0 + ($1.pinned ? 1 : 0) } }
}
