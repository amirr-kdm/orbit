import SwiftUI
import Charts

/// The IELTS "Exam report": progress charts with hover details, a skills radar and the gap to the target.
struct IELTSReport: View {
    @Environment(AppStore.self) private var store
    /// The overall target (worked out from the four skill targets)
    let tests: [IELTSTest]   // oldest first (already filtered by category)
    let target: Double
    let tL: Double, tR: Double, tW: Double, tS: Double
    private func skillTarget(_ s: IELTSSkill) -> Double {
        switch s { case .listening: tL; case .reading: tR; case .writing: tW; case .speaking: tS }
    }
    // one hover state per chart, so only the chart under the mouse shows its card
    @State private var hoverOverall: UUID?
    @State private var hoverSkills: UUID?
    @State private var hidden: Set<IELTSSkill> = []

    private let red = Color(hex: "#E8384F"), green = Color(hex: "#34C77B")
    private var cal: CalendarKind { store.settings.primaryCalendar }
    /// Average band of a skill over the tests shown (the chosen category)
    private func average(_ s: IELTSSkill) -> Double? {
        let v = tests.compactMap { $0.band(s) }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    private func test(_ id: UUID?) -> IELTSTest? { tests.first { $0.id == id } }

    private var domain: ClosedRange<Double> {
        let all = tests.flatMap { t in IELTSSkill.allCases.compactMap { t.band($0) } + [t.overall].compactMap { $0 } } + [target] + IELTSSkill.allCases.map { skillTarget($0) }
        let lo = max(0, floor((all.min() ?? 4) - 0.5)), hi = min(9, ceil((all.max() ?? 8) + 0.5))
        return lo...max(hi, lo + 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("Overall band", "Each test's overall, with your target", "chart.line.uptrend.xyaxis", red) { overallChart.frame(height: 250) }
            card("Each skill", "Hover the chart for the details of a test", "waveform.path.ecg", .accentColor, trailing: AnyView(skillChips)) { skillsChart.frame(height: 280) }
            HStack(alignment: .top, spacing: 18) {
                card("Skills shape", "Your average, your latest test and the target", "hexagon", Color(hex: "#8E6BD8")) { radar }
                card("Gap to target", "Average of each skill against its own target", "target", green) { gaps }
            }
            changes
        }
    }

    // MARK: card

    private func card<C: View>(_ title: String, _ sub: String, _ icon: String, _ tint: Color, trailing: AnyView? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                trailing
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [tint.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center)))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.22)))
    }

    // MARK: charts

    /// The card shows only while the mouse is on (close to) a point of the chart. `ys` gives the heights of a test's points.
    private func hoverLayer(_ proxy: ChartProxy, _ hover: Binding<UUID?>, _ ys: @escaping (IELTSTest) -> [Double]) -> some View {
        GeometryReader { g in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        guard let frame = proxy.plotFrame else { return }
                        let origin = g[frame].origin
                        let found = tests.first { t in
                            guard let x = proxy.position(forX: t.date), abs(x + origin.x - p.x) < 18 else { return false }
                            return ys(t).contains { y in proxy.position(forY: y).map { abs($0 + origin.y - p.y) < 18 } ?? false }
                        }
                        hover.wrappedValue = found?.id
                    case .ended: hover.wrappedValue = nil
                    }
                }
        }
    }

    private func tooltip(_ t: IELTSTest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.name.isEmpty ? "Test" : t.name).font(.caption.weight(.bold))
            Text(Fmt.date(t.date, "MMM d", cal)).font(.caption2).foregroundStyle(.secondary)
            ForEach(IELTSSkill.allCases) { s in
                HStack(spacing: 5) {
                    Circle().fill(s.color).frame(width: 6, height: 6)
                    Text(s.title).font(.caption2)
                    Spacer(minLength: 10)
                    Text(IELTSTest.format(t.band(s))).font(.caption2.weight(.semibold).monospacedDigit())
                }
            }
            Divider()
            HStack { Text("Overall").font(.caption.weight(.bold)); Spacer(minLength: 10); Text(IELTSTest.format(t.overall)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(red) }
        }
        .padding(9).frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    @AxisContentBuilder private func xAxis() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 6)) { v in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(Color.primary.opacity(0.10))
            AxisValueLabel { if let d = v.as(Date.self) { Text(Fmt.date(d, "MMM d", cal)).font(.caption2) } }
        }
    }
    @AxisContentBuilder private func yAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: .stride(by: 0.5)) { v in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(Color.primary.opacity(0.10))
            AxisValueLabel { if let b = v.as(Double.self) { Text(IELTSTest.format(b)).font(.caption2.monospacedDigit()) } }
        }
    }

    private var overallChart: some View {
        let pts = tests.filter { $0.overall != nil }
        return Chart {
            ForEach(pts) { t in
                AreaMark(x: .value("Date", t.date), yStart: .value("Base", domain.lowerBound), yEnd: .value("Band", t.overall!))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [red.opacity(0.40), red.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", t.date), y: .value("Band", t.overall!))
                    .interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "#FF7A59"), red], startPoint: .leading, endPoint: .trailing))
                PointMark(x: .value("Date", t.date), y: .value("Band", t.overall!))
                    .symbol { Circle().fill(red).frame(width: t.id == hoverOverall ? 14 : 10).overlay(Circle().strokeBorder(.white, lineWidth: 2)).shadow(color: red.opacity(0.6), radius: 6) }
            }
            RuleMark(y: .value("Target", target)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(green)
                .annotation(position: .top, alignment: .leading, spacing: 3) {
                    Text("🎯 Target \(IELTSTest.format(target))").font(.caption2.weight(.bold)).foregroundStyle(green).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(green.opacity(0.15)))
                }
            if let h = test(hoverOverall) {
                RuleMark(x: .value("Date", h.date)).foregroundStyle(Color.primary.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { tooltip(h) }
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(range: .plotDimension(padding: 16))
        .chartXAxis { xAxis() }
        .chartYAxis { yAxis() }
        .chartOverlay { hoverLayer($0, $hoverOverall) { [$0.overall].compactMap { $0 } } }
    }

    private var skillChips: some View {
        HStack(spacing: 6) {
            ForEach(IELTSSkill.allCases) { s in
                Button {
                    if hidden.contains(s) { hidden.remove(s) } else { hidden.insert(s) }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.title).font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(s.color.opacity(hidden.contains(s) ? 0.05 : 0.22)))
                    .overlay(Capsule().strokeBorder(s.color.opacity(hidden.contains(s) ? 0.15 : 0.6)))
                    .opacity(hidden.contains(s) ? 0.5 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var skillsChart: some View {
        Chart {
            ForEach(IELTSSkill.allCases.filter { !hidden.contains($0) }) { s in
                ForEach(tests.filter { $0.band(s) != nil }) { t in
                    LineMark(x: .value("Date", t.date), y: .value("Band", t.band(s)!), series: .value("Skill", s.title))
                        .interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(s.color)
                    PointMark(x: .value("Date", t.date), y: .value("Band", t.band(s)!))
                        .symbol { Circle().fill(s.color).frame(width: t.id == hoverSkills ? 11 : 7).overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)) }
                }
            }
            ForEach(IELTSSkill.allCases.filter { !hidden.contains($0) }) { s in
                RuleMark(y: .value("Target", skillTarget(s))).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5])).foregroundStyle(s.color.opacity(0.55))
            }
            if let h = test(hoverSkills) {
                RuleMark(x: .value("Date", h.date)).foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { tooltip(h) }
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(range: .plotDimension(padding: 16))
        .chartXAxis { xAxis() }
        .chartYAxis { yAxis() }
        .chartOverlay { hoverLayer($0, $hoverSkills) { t in IELTSSkill.allCases.filter { !hidden.contains($0) }.compactMap { t.band($0) } } }
    }

    // MARK: radar

    private var radar: some View {
        let avg = IELTSSkill.allCases.map { average($0) ?? 0 }
        let latest = tests.last
        let last = IELTSSkill.allCases.map { latest?.band($0) ?? 0 }
        return VStack(spacing: 10) {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2), R = min(size.width, size.height) / 2 - 30
                func pt(_ i: Int, _ v: Double) -> CGPoint {
                    let a = -Double.pi / 2 + Double(i) * .pi / 2
                    return CGPoint(x: c.x + cos(a) * R * max(0, v - 3) / 6, y: c.y + sin(a) * R * max(0, v - 3) / 6)
                }
                func poly(_ vals: [Double]) -> Path { var p = Path(); for i in 0..<4 { i == 0 ? p.move(to: pt(i, vals[i])) : p.addLine(to: pt(i, vals[i])) }; p.closeSubpath(); return p }
                for r in [4.0, 5.0, 6.0, 7.0, 8.0, 9.0] {
                    ctx.stroke(poly([r, r, r, r]), with: .color(.primary.opacity(r == 9 ? 0.22 : 0.10)), lineWidth: 1)
                    ctx.draw(Text(String(format: "%.0f", r)).font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: c.x + 8, y: c.y - R * (r - 3) / 6 + 2))
                }
                for i in 0..<4 { var l = Path(); l.move(to: c); l.addLine(to: pt(i, 9)); ctx.stroke(l, with: .color(.primary.opacity(0.10)), lineWidth: 1) }
                ctx.stroke(poly(IELTSSkill.allCases.map { skillTarget($0) }), with: .color(green), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                ctx.fill(poly(avg), with: .color(Color.accentColor.opacity(0.25)))
                ctx.stroke(poly(avg), with: .color(Color.accentColor), lineWidth: 2)
                if latest != nil {
                    ctx.stroke(poly(last), with: .color(red), lineWidth: 2.2)
                    for i in 0..<4 { let q = pt(i, last[i]); ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(red)) }
                }
                for (i, s) in IELTSSkill.allCases.enumerated() {
                    ctx.draw(Text(s.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(s.color), at: pt(i, 9.9))
                }
            }
            .frame(height: 290)
            HStack(spacing: 14) {
                legend(Color.accentColor, "Average"); legend(red, "Latest test"); legend(green, "Target")
            }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Capsule().fill(c).frame(width: 14, height: 4); Text(t).font(.caption).foregroundStyle(.secondary) }
    }

    // MARK: gap to target

    private var gaps: some View {
        VStack(spacing: 16) {
            ForEach(IELTSSkill.allCases) { s in
                let v = average(s)
                let target = skillTarget(s)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(s.title, systemImage: s.icon).font(.callout.weight(.semibold)).foregroundStyle(s.color)
                        Spacer()
                        if let v {
                            Text(v >= target ? "✓ reached" : "\(String(format: "%.2f", target - v)) to go").font(.caption.weight(.semibold))
                                .foregroundStyle(v >= target ? green : .secondary)
                        } else { Text("no score yet").font(.caption).foregroundStyle(.secondary) }
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10))
                            if let v { Capsule().fill(LinearGradient(colors: [s.color.opacity(0.6), s.color], startPoint: .leading, endPoint: .trailing)).frame(width: max(8, g.size.width * v / 9)) }
                            Rectangle().fill(green).frame(width: 2, height: 16).offset(x: g.size.width * target / 9 - 1)
                        }
                    }
                    .frame(height: 10)
                }
            }
            Text("The green mark is the target of each skill.").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: change since first test

    private var changes: some View {
        HStack(spacing: 12) {
            ForEach(IELTSSkill.allCases) { s in
                let v = tests.compactMap { $0.band(s) }
                let d = v.count >= 2 ? v.last! - v.first! : nil
                VStack(alignment: .leading, spacing: 3) {
                    Label(s.title, systemImage: s.icon).font(.caption.weight(.semibold)).foregroundStyle(s.color)
                    Text(d.map { ($0 > 0 ? "▲ +" : ($0 < 0 ? "▼ " : "")) + String(format: "%.1f", $0) } ?? "—").font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(d.map { $0 > 0 ? green : ($0 < 0 ? Color.red : .secondary) } ?? .secondary)
                    Text("since your first test").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(s.color.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(s.color.opacity(0.25)))
            }
        }
    }
}
