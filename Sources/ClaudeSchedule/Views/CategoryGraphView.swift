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
    @State private var panStart: CGSize?
    @State private var monitor: Any?

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
                             items: graph.edges.filter { $0.a == node.id }.compactMap { e in graph.nodes.first { $0.id == e.b } },
                             showDone: showDone,
                             select: { selected = $0 },
                             close: { selected = nil })
                    .frame(width: 300)
            }
        }
        .onAppear {
            sim.sync(graph)
            installMonitor()
        }
        .onDisappear(perform: removeMonitor)
        .onChange(of: graph) { _, g in sim.sync(g) }
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
            }
            return id
        }
        func include(_ cat: UUID?, _ title: String) -> Bool {
            if let categoryFilter, cat != categoryFilter { return false }
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
                                       color: e.colorHex ?? store.category(e.categoryID)?.colorHex ?? "#5B7CFA",
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
                let hex = e.colorHex ?? store.category(e.categoryID)?.colorHex ?? "#5B7CFA"
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
            .onChange(of: size) { _, s in sim.viewSize = s }
        }
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragNode == nil && panStart == nil {
                    if let i = sim.hit(v.startLocation, size: size) { dragNode = i } else { panStart = sim.pan }
                }
                if let i = dragNode, sim.nodes.indices.contains(i) {
                    let w = sim.toWorld(v.location, size)
                    sim.nodes[i].x = w.x
                    sim.nodes[i].y = w.y
                    sim.nodes[i].pinned = true
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

        // Dot grid that moves with the view
        let spacing = 28 * scale
        if spacing > 9 {
            var dots = Path()
            let ox = (size.width / 2 + sim.pan.width).truncatingRemainder(dividingBy: spacing)
            let oy = (size.height / 2 + sim.pan.height).truncatingRemainder(dividingBy: spacing)
            var x = ox
            while x < size.width {
                var y = oy
                while y < size.height {
                    dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                    y += spacing
                }
                x += spacing
            }
            ctx.fill(dots, with: .color(.primary.opacity(dark ? 0.07 : 0.09)))
        }

        let focus = sim.hovered ?? selected
        var near: Set<String> = []
        if let focus {
            near.insert(focus)
            for (a, b) in sim.links where sim.nodes[a].id == focus || sim.nodes[b].id == focus {
                near.insert(sim.nodes[a].id); near.insert(sim.nodes[b].id)
            }
        }

        // Links
        for (a, b) in sim.links {
            let A = sim.nodes[a], B = sim.nodes[b]
            var path = Path()
            path.move(to: sim.toScreen(A.point, size))
            path.addLine(to: sim.toScreen(B.point, size))
            let lit = focus != nil && near.contains(A.id) && near.contains(B.id)
            let opacity = lit ? 0.75 : (focus == nil ? 0.28 : 0.07)
            ctx.stroke(path, with: .color(Color(hex: A.color).opacity(opacity)),
                       lineWidth: (lit ? 1.8 : 1.1) * min(1.4, max(0.7, scale)))
        }

        // Nodes
        for n in sim.nodes {
            let p = sim.toScreen(n.point, size)
            let r = n.radius * scale
            let dim = focus != nil && !near.contains(n.id)
            let color = Color(hex: n.color)
            let alpha = dim ? 0.18 : 1.0
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)

            if n.isHub {
                let glow = rect.insetBy(dx: -r * 1.2, dy: -r * 1.2)
                ctx.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [color.opacity(dim ? 0.05 : 0.35), color.opacity(0)]),
                    center: p, startRadius: r * 0.6, endRadius: glow.width / 2))
            }
            let shape = n.isSchedule
                ? Path(roundedRect: rect.insetBy(dx: r * 0.08, dy: r * 0.08), cornerRadius: r * 0.45)
                : Path(ellipseIn: rect)
            if n.isDone {
                ctx.fill(shape, with: .color(bg))
                ctx.stroke(shape, with: .color(color.opacity(0.7 * alpha)), lineWidth: max(1.2, r * 0.28))
            } else {
                ctx.fill(shape, with: .linearGradient(
                    Gradient(colors: [color.opacity(alpha), color.opacity(alpha * 0.78)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                ctx.stroke(shape, with: .color(bg.opacity(alpha)), lineWidth: max(1, r * 0.18))
            }
            if n.id == selected || n.id == sim.hovered {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3.5, dy: -3.5)),
                           with: .color(n.id == selected ? Color.primary.opacity(0.85) : color.opacity(0.6)), lineWidth: 1.6)
            }

            let showLabel = n.isHub || scale >= 1.15 || n.id == focus || (focus != nil && near.contains(n.id))
            if showLabel {
                let title = n.title.count > 26 ? String(n.title.prefix(25)) + "…" : n.title
                let label = Text(title)
                    .font(n.isHub ? .system(size: 12.5, weight: .semibold) : .system(size: 10.5))
                    .foregroundStyle(n.isHub ? Color.primary.opacity(dim ? 0.3 : 0.9) : Color.secondary.opacity(dim ? 0.3 : 1))
                ctx.draw(label, at: CGPoint(x: p.x, y: p.y + r + (n.isHub ? 6 : 4)), anchor: .top)
            }
        }
    }

    // MARK: Overlays

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Circle().frame(width: 12, height: 12); Text("Category") }
            HStack(spacing: 6) { Circle().frame(width: 7, height: 7).padding(.horizontal, 2.5); Text("Task") }
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2.5).frame(width: 8, height: 8).padding(.horizontal, 2); Text("Weekly to-do") }
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
            Button { sim.shake() } label: { Image(systemName: "wand.and.rays") }.help("Re-arrange")
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

        status(done ? "Done this week" : (day < Cal.persian.startOfDay(for: Date()) ? "Not done (day has passed)" : "To do"),
               done ? .green : (day < Cal.persian.startOfDay(for: Date()) ? .orange : .accentColor))

        section("When") {
            row("calendar", when, Fmt.date(day, "EEEE, MMMM d", kind))
            row("calendar.badge.clock", kind.other == .persian ? "Persian" : "Gregorian", Fmt.date(day, "MMMM d, y", kind.other))
            if let slot { row("clock", "Time", "\(slot.title) · \(slot.endMinute - slot.startMinute) min") }
            row(e.recurrence.icon, "Repeats", e.recurrence == .once
                ? "Only the week of \(e.weekStart.map { Fmt.date($0, "MMM d", kind) } ?? "")" : e.recurrence.title)
            row("tag", "Category", store.category(e.categoryID)?.name ?? "None")
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
        status(t.isDone ? "Done\(t.completedAt.map { " · " + Fmt.date($0, "MMM d", kind) } ?? "")" : (overdue ? "Overdue" : "To do"),
               t.isDone ? .green : (overdue ? .orange : .accentColor))

        section("When") {
            if let d = t.dueDate {
                row("calendar", "Date", Fmt.date(d, "EEEE, MMMM d", kind))
                row("calendar.badge.clock", kind.other == .persian ? "Persian" : "Gregorian", Fmt.date(d, "MMMM d, y", kind.other))
                if t.hasTime { row("clock", "Time", "\(Fmt.time(d)) · \(t.estimatedMinutes) min") }
            } else {
                row("tray", "Date", "No date")
            }
            row("tag", "Category", store.category(t.categoryID)?.name ?? "None")
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
        let sessions = store.sessions.filter { $0.categoryID == catID }
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

        var point: CGPoint { CGPoint(x: x, y: y) }
        var radius: CGFloat {
            isHub ? min(26, 12 + 2.2 * sqrt(CGFloat(degree))) : (isSchedule ? 6.5 : 6)
        }
    }

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
            let d = hypot(nodes[i].x - w.x, nodes[i].y - w.y) - nodes[i].radius
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
                node.x = p.x; node.y = p.y; node.vx = p.vx; node.vy = p.vy
            } else {
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

    func shake() {
        for i in nodes.indices {
            nodes[i].x = .random(in: -300...300)
            nodes[i].y = .random(in: -220...220)
        }
        reheat(1)
    }

    func tick() {
        if pinnedCount > 0 { alphaTarget = 0.3 } else { alphaTarget = 0 }
        alpha += (alphaTarget - alpha) * 0.0228
        guard alpha > 0.003, !nodes.isEmpty else {
            if !settled { DispatchQueue.main.async { self.settled = true } }
            return
        }
        let n = nodes.count

        // Links: pull each item towards its category, at a distance that grows with the category's size
        for (a, b) in links {
            let ra = nodes[a].radius, rb = nodes[b].radius
            let target = 34 + ra + rb + 3 * sqrt(CGFloat(nodes[a].degree))
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
            let k: CGFloat = nodes[i].isHub ? 0.05 : 0.02
            nodes[i].vx -= nodes[i].x * k * alpha
            nodes[i].vy -= nodes[i].y * k * alpha
        }

        // Collision: nodes never overlap
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = nodes[j].x - nodes[i].x, dy = nodes[j].y - nodes[i].y
                let minD = nodes[i].radius + nodes[j].radius + 5
                let d2 = dx * dx + dy * dy
                guard d2 < minD * minD else { continue }
                let d = max(0.01, sqrt(d2))
                let push = (minD - d) / d * 0.5
                nodes[i].x -= dx * push; nodes[i].y -= dy * push
                nodes[j].x += dx * push; nodes[j].y += dy * push
            }
        }

        // Move with friction
        for i in 0..<n {
            if nodes[i].pinned { nodes[i].vx = 0; nodes[i].vy = 0; continue }
            nodes[i].vx *= 0.6
            nodes[i].vy *= 0.6
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy
        }
    }

    private var pinnedCount: Int { nodes.reduce(0) { $0 + ($1.pinned ? 1 : 0) } }
}
