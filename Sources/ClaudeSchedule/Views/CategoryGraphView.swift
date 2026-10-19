import SwiftUI

/// Obsidian-style graph: every category is a hub, and its tasks and schedule to-dos orbit around it.
struct CategoryGraphView: View {
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    var categoryFilter: UUID?
    var search: String

    @State private var sim = GraphSim()
    @State private var showDone = false
    @State private var selected: String?
    @State private var hovered: String?
    @State private var scale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var dragNode: Int?
    @State private var pinchStart: CGFloat?

    var body: some View {
        let graph = buildGraph()
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .topLeading) {
                canvas
                legend.padding(12)
                zoomControls.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                if graph.nodes.isEmpty {
                    Text("Nothing to show. Add tasks or To-do cells with a category.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            if let id = selected, let node = sim.nodes.first(where: { $0.id == id }) {
                details(node).frame(width: 260)
            }
        }
        .onAppear { sim.sync(graph) }
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
                                 isHub: true, isSchedule: false, isDone: false, detail: "", ref: nil)
            }
            return id
        }
        func include(_ cat: UUID?, _ title: String) -> Bool {
            if let categoryFilter, cat != categoryFilter { return false }
            return q.isEmpty || title.lowercased().contains(q)
        }

        for t in store.tasks where (showDone || !t.isDone) && include(t.categoryID, t.title) {
            let h = hub(for: t.categoryID)
            let detail = t.dueDate.map { Fmt.date($0, "EEE, MMM d", store.settings.primaryCalendar) } ?? "No date"
            nodes.append(.init(id: "task:\(t.id)", title: t.title, color: store.category(t.categoryID)?.colorHex ?? "#8E8E93",
                               isHub: false, isSchedule: false, isDone: t.isDone, detail: "Task · \(detail)", ref: .task(t.id)))
            edges.append(.init(a: h, b: "task:\(t.id)"))
        }
        for e in store.schedule where e.kind == .todo && include(e.categoryID, e.title) {
            let done = store.isDone(.schedule(e.id), on: store.occurrence(of: e))
            if done && !showDone { continue }
            let h = hub(for: e.categoryID)
            let slot = store.slot(e.slotID)?.title ?? ""
            let hex = e.colorHex ?? store.category(e.categoryID)?.colorHex ?? "#5B7CFA"
            nodes.append(.init(id: "entry:\(e.id)", title: e.title, color: hex, isHub: false, isSchedule: true,
                               isDone: done, detail: "Weekly schedule · \(Cal.weekdayNames[e.weekday]) \(slot)",
                               ref: .schedule(e.id)))
            edges.append(.init(a: h, b: "entry:\(e.id)"))
        }
        return GraphData(nodes: hubs.values.sorted { $0.title < $1.title } + nodes, edges: edges)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: sim.settled && dragNode == nil)) { _ in
                Canvas { ctx, _ in
                    sim.step()
                    draw(ctx, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(size: size))
            .simultaneousGesture(MagnifyGesture()
                .onChanged { v in
                    if pinchStart == nil { pinchStart = scale }
                    scale = min(4, max(0.25, (pinchStart ?? 1) * v.magnification))
                }
                .onEnded { _ in pinchStart = nil })
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered = hit(p, size: size).map { sim.nodes[$0].id }
                case .ended: hovered = nil
                }
            }
        }
    }

    private func toScreen(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + pan.width + p.x * scale, y: size.height / 2 + pan.height + p.y * scale)
    }

    private func toWorld(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - size.width / 2 - pan.width) / scale, y: (p.y - size.height / 2 - pan.height) / scale)
    }

    private func hit(_ p: CGPoint, size: CGSize) -> Int? {
        let w = toWorld(p, size)
        return sim.nodes.indices.min { a, b in
            hypot(sim.nodes[a].pos.x - w.x, sim.nodes[a].pos.y - w.y) < hypot(sim.nodes[b].pos.x - w.x, sim.nodes[b].pos.y - w.y)
        }.flatMap { i in
            hypot(sim.nodes[i].pos.x - w.x, sim.nodes[i].pos.y - w.y) <= sim.nodes[i].radius + 6 / scale ? i : nil
        }
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragNode == nil && panStart == nil {
                    if let i = hit(v.startLocation, size: size) { dragNode = i } else { panStart = pan }
                }
                if let i = dragNode, sim.nodes.indices.contains(i) {
                    sim.nodes[i].pos = toWorld(v.location, size)
                    sim.nodes[i].pinned = true
                    sim.wake()
                } else if let s = panStart {
                    pan = CGSize(width: s.width + v.translation.width, height: s.height + v.translation.height)
                }
            }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height) > 4
                if !moved {
                    selected = hit(v.location, size: size).map { sim.nodes[$0].id }
                }
                if let i = dragNode, sim.nodes.indices.contains(i) { sim.nodes[i].pinned = false }
                dragNode = nil
                panStart = nil
            }
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let focus = hovered ?? selected
        let neighbours: Set<String> = focus.map { f in
            Set(sim.links.flatMap { l -> [String] in
                let a = sim.nodes[l.0].id, b = sim.nodes[l.1].id
                return a == f || b == f ? [a, b] : []
            } + [f])
        } ?? []

        for l in sim.links {
            let a = sim.nodes[l.0], b = sim.nodes[l.1]
            var path = Path()
            path.move(to: toScreen(a.pos, size))
            path.addLine(to: toScreen(b.pos, size))
            let lit = focus != nil && neighbours.contains(a.id) && neighbours.contains(b.id)
            ctx.stroke(path, with: .color(lit ? Color(hex: a.color).opacity(0.8) : Color.primary.opacity(focus == nil ? 0.16 : 0.06)),
                       lineWidth: lit ? 1.6 : 1)
        }

        for n in sim.nodes {
            let p = toScreen(n.pos, size)
            let r = n.radius * scale
            let dim = focus != nil && !neighbours.contains(n.id)
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let shape = n.isSchedule ? Path(roundedRect: rect.insetBy(dx: r * 0.1, dy: r * 0.1), cornerRadius: r * 0.35) : Path(ellipseIn: rect)
            let color = Color(hex: n.color)
            if n.isHub {
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r * 0.5, dy: -r * 0.5)), with: .color(color.opacity(dim ? 0.03 : 0.14)))
            }
            ctx.fill(shape, with: .color(color.opacity(dim ? 0.2 : (n.isDone ? 0.35 : 1))))
            if n.id == selected {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.primary), lineWidth: 2)
            }
            if n.isDone {
                ctx.draw(Text(Image(systemName: "checkmark")).font(.system(size: max(7, r), weight: .bold)).foregroundStyle(.white), at: p)
            }

            let showLabel = n.isHub || scale > 1.3 || n.id == focus || (focus != nil && neighbours.contains(n.id))
            if showLabel {
                let label = Text(n.title)
                    .font(n.isHub ? .system(size: 13, weight: .bold) : .system(size: 11))
                    .foregroundStyle(dim ? Color.secondary.opacity(0.4) : (n.isHub ? Color.primary : Color.secondary))
                ctx.draw(label, at: CGPoint(x: p.x, y: p.y + r + 9), anchor: .center)
            }
        }
    }

    // MARK: Overlays

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Circle().frame(width: 12, height: 12); Text("Category") }
            HStack(spacing: 6) { Circle().frame(width: 7, height: 7).padding(.horizontal, 2.5); Text("Task") }
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).frame(width: 7, height: 7).padding(.horizontal, 2.5); Text("Weekly to-do") }
            Toggle("Show done", isOn: $showDone).toggleStyle(.checkbox).padding(.top, 2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { withAnimation { scale = max(0.25, scale / 1.25) } } label: { Image(systemName: "minus.magnifyingglass") }
            Button { withAnimation { scale = 1; pan = .zero } } label: { Image(systemName: "scope") }.help("Re-centre")
            Button { withAnimation { scale = min(4, scale * 1.25) } } label: { Image(systemName: "plus.magnifyingglass") }
            Button { sim.shake() } label: { Image(systemName: "wand.and.rays") }.help("Re-arrange")
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(Capsule().fill(.regularMaterial))
    }

    @ViewBuilder
    private func details(_ n: GraphSim.Node) -> some View {
        Card(title: n.isHub ? "Category" : (n.isSchedule ? "Weekly to-do" : "Task"),
             systemImage: n.isHub ? "tag" : (n.isSchedule ? "tablecells" : "checklist")) {
            HStack {
                Circle().fill(Color(hex: n.color)).frame(width: 12, height: 12)
                Text(n.title).font(.headline)
            }
            if n.isHub {
                let items = sim.links.filter { sim.nodes[$0.0].id == n.id }.map { sim.nodes[$0.1] }
                Text("\(items.count) item\(items.count == 1 ? "" : "s"), \(items.filter(\.isDone).count) done")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(items, id: \.id) { i in
                    Button { selected = i.id } label: {
                        HStack {
                            Image(systemName: i.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(Color(hex: i.color))
                            Text(i.title).lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else if let ref = n.ref {
                Text(n.detail).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(n.isDone ? "Mark not done" : "Mark done") {
                        if case .schedule(let id) = ref, let e = store.entry(id) {
                            store.toggleDone(ref, on: store.occurrence(of: e))
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
            }
            Button("Close") { selected = nil }.buttonStyle(.borderless).font(.caption)
        }
    }
}

// MARK: - Model

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
    }
    struct Edge: Equatable {
        let a: String
        let b: String
    }
    var nodes: [Node]
    var edges: [Edge]
}

/// A tiny force simulation: nodes repel, links pull, everything drifts to the centre.
@MainActor @Observable
final class GraphSim {
    struct Node {
        let id: String
        var title: String
        var color: String
        var isHub: Bool
        var isSchedule: Bool
        var isDone: Bool
        var detail: String
        var ref: TodoRef?
        var pos: CGPoint
        var vel: CGVector = .zero
        var pinned = false
        var radius: CGFloat { isHub ? 16 : 7 }
    }

    @ObservationIgnored var nodes: [Node] = []
    @ObservationIgnored var links: [(Int, Int)] = []
    @ObservationIgnored private var heat: CGFloat = 1
    /// Observed so the canvas stops animating once the layout is still
    var settled = false

    func sync(_ g: GraphData) {
        let old = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        nodes = g.nodes.map { n in
            let prev = old[n.id]
            let start = prev?.pos ?? CGPoint(x: .random(in: -200...200), y: .random(in: -150...150))
            return Node(id: n.id, title: n.title, color: n.color, isHub: n.isHub, isSchedule: n.isSchedule,
                        isDone: n.isDone, detail: n.detail, ref: n.ref, pos: start)
        }
        let index = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        links = g.edges.compactMap { e in
            guard let a = index[e.a], let b = index[e.b] else { return nil }
            return (a, b)
        }
        wake()
    }

    func wake() {
        heat = max(heat, 0.6)
        if settled { settled = false }
    }

    func shake() {
        for i in nodes.indices { nodes[i].pos = CGPoint(x: .random(in: -250...250), y: .random(in: -180...180)) }
        heat = 1
        settled = false
    }

    func step() {
        guard heat > 0.01, !nodes.isEmpty else {
            if !settled { DispatchQueue.main.async { self.settled = true } }
            return
        }
        let n = nodes.count
        var force = [CGVector](repeating: .zero, count: n)

        for i in 0..<n {
            for j in (i + 1)..<n {
                var dx = nodes[i].pos.x - nodes[j].pos.x, dy = nodes[i].pos.y - nodes[j].pos.y
                var d2 = dx * dx + dy * dy
                if d2 < 0.01 { dx = .random(in: -1...1); dy = .random(in: -1...1); d2 = 1 }
                let k: CGFloat = (nodes[i].isHub && nodes[j].isHub) ? 9000 : 1400
                let f = k / d2
                let d = sqrt(d2)
                force[i].dx += dx / d * f; force[i].dy += dy / d * f
                force[j].dx -= dx / d * f; force[j].dy -= dy / d * f
            }
        }
        for (a, b) in links {
            let dx = nodes[b].pos.x - nodes[a].pos.x, dy = nodes[b].pos.y - nodes[a].pos.y
            let d = max(1, sqrt(dx * dx + dy * dy))
            let f = (d - 60) * 0.05
            force[a].dx += dx / d * f; force[a].dy += dy / d * f
            force[b].dx -= dx / d * f; force[b].dy -= dy / d * f
        }
        for i in 0..<n {
            force[i].dx -= nodes[i].pos.x * 0.008
            force[i].dy -= nodes[i].pos.y * 0.008
            if nodes[i].pinned { nodes[i].vel = .zero; continue }
            nodes[i].vel.dx = (nodes[i].vel.dx + force[i].dx * heat) * 0.82
            nodes[i].vel.dy = (nodes[i].vel.dy + force[i].dy * heat) * 0.82
            let speed = hypot(nodes[i].vel.dx, nodes[i].vel.dy)
            if speed > 30 { nodes[i].vel.dx *= 30 / speed; nodes[i].vel.dy *= 30 / speed }
            nodes[i].pos.x += nodes[i].vel.dx
            nodes[i].pos.y += nodes[i].vel.dy
        }
        heat *= 0.992
    }
}
