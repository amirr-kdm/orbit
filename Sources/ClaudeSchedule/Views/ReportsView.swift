import Charts
import SwiftUI

enum ReportPeriod: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }
    var title: String { self == .week ? "Weekly" : "Monthly" }
    var name: String { self == .week ? "week" : "month" }
    var component: Calendar.Component { self == .week ? .weekOfYear : .month }
}

struct ReportsView: View {
    @Environment(AppStore.self) private var store
    @State private var period: ReportPeriod = .week
    @State private var anchor = Date()

    private var kind: CalendarKind { store.settings.primaryCalendar }
    private var cal: Calendar { kind.calendar }

    private var interval: DateInterval {
        cal.dateInterval(of: period.component, for: anchor) ?? DateInterval(start: anchor, duration: 7 * 86400)
    }

    private var previousInterval: DateInterval {
        let prev = cal.date(byAdding: period.component, value: -1, to: interval.start) ?? interval.start
        return cal.dateInterval(of: period.component, for: prev) ?? interval
    }

    // MARK: Data

    private struct DayPoint: Identifiable {
        let id = UUID()
        let day: Date
        let subject: String
        let minutes: Double
    }

    private struct SubjectTotal: Identifiable {
        var id: String { name }
        let name: String
        let color: Color
        let seconds: TimeInterval
    }

    private struct ItemTotal: Identifiable {
        var id: String { title }
        let title: String
        let color: Color
        let seconds: TimeInterval
    }

    private var accent: Color { store.settings.template.style.accent }

    /// The daily chart's colour group for a session (see `body`)
    private func group(_ s: StudySession) -> (name: String, color: Color) {
        if store.settings.categoryColors, let c = store.category(s.categoryID) { return (store.categoryLabel(c.id) ?? c.name, c.color) }
        return store.subject(of: s)
    }

    var body: some View {
        let sessions = store.sessions(in: interval)
        let total = sessions.reduce(0) { $0 + $1.duration }
        let prevTotal = store.studyTime(in: previousInterval)
        let days = cal.days(in: interval)
        let pastDays = days.filter { $0 <= Date() }
        let elapsedDays = max(1, pastDays.count)
        let perDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.start) }
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        let activeDays = perDay.values.filter { $0 > 0 }.count
        let best = perDay.max { $0.value < $1.value }
        let completedTasks = store.tasks.filter { t in t.completedAt.map { interval.contains($0) } ?? false }
        let scheduleDone = scheduleTodoStats(days: days)
        let goal = TimeInterval(store.settings.dailyGoalMinutes * 60)

        // The daily chart's colours: with "to-dos use their category's colour" on, several subjects share a
        // colour, so the chart groups by category (one colour = one legend entry); otherwise by subject
        let points: [DayPoint] = sessions.map {
            DayPoint(day: cal.startOfDay(for: $0.start), subject: group($0).name, minutes: $0.duration / 60)
        }
        let groupTotals: [SubjectTotal] = Dictionary(grouping: sessions) { group($0).name }
            .map { name, list in SubjectTotal(name: name, color: group(list[0]).color, seconds: list.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.seconds > $1.seconds }
        let subjectTotals: [SubjectTotal] = Dictionary(grouping: sessions) { store.subject(of: $0).name }
            .map { name, list in
                SubjectTotal(name: name, color: store.subject(of: list[0]).color,
                             seconds: list.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.seconds > $1.seconds }
        let itemTotals: [ItemTotal] = Dictionary(grouping: sessions) { store.itemTitle(of: $0) }
            .map { title, list in
                ItemTotal(title: title, color: store.subject(of: list[0]).color,
                          seconds: list.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.seconds > $1.seconds }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(total: total, prevTotal: prevTotal, days: days, perDay: perDay, goal: goal)

                HStack(spacing: 14) {
                    InsightTile(title: "Daily average", value: Fmt.duration(total / Double(elapsedDays)),
                                caption: goal > 0 ? "per day so far · daily goal \(Fmt.shortDuration(goal))" : "per day so far", icon: "chart.line.uptrend.xyaxis", tint: .purple) {
                        MeterBar(value: goal > 0 ? total / Double(elapsedDays) / goal : 0, tint: .purple)
                    }
                    InsightTile(title: "Active days", value: "\(activeDays) / \(days.count)",
                                caption: activeDays == pastDays.count && activeDays > 0 ? "every day so far 🔥" : "days with study",
                                icon: "flame.fill", tint: .orange) {
                        DayDots(days: days, active: Set(perDay.filter { $0.value > 0 }.keys), tint: .orange)
                    }
                    InsightTile(title: "Best day", value: best.map { Fmt.duration($0.value) } ?? "—",
                                caption: best.map { Fmt.date($0.key, "EEEE, MMM d", kind) + (goal > 0 && $0.value >= goal ? " · goal reached ✓" : "") } ?? "no study yet",
                                icon: "trophy.fill", tint: .yellow) {
                        MeterBar(value: best.map { goal > 0 ? $0.value / goal : 0 } ?? 0, tint: .yellow)
                    }
                    InsightTile(title: "Schedule to-dos", value: scheduleDone.total > 0 ? "\(scheduleDone.done) / \(scheduleDone.total)" : "—",
                                caption: "ticked off so far" + (completedTasks.isEmpty ? "" : " · +\(completedTasks.count) task\(completedTasks.count == 1 ? "" : "s") done"),
                                icon: "checkmark.seal.fill", tint: .green) {
                        MeterBar(value: scheduleDone.total > 0 ? Double(scheduleDone.done) / Double(scheduleDone.total) : 0, tint: .green)
                    }
                }

                Highlights(sessions: sessions, days: days, perDay: perDay,
                           subjects: subjectTotals.map { ($0.name, $0.color, $0.seconds) }, kind: kind, store: store)

                ReportCard(title: "Daily study time", icon: "chart.bar.fill", tint: accent) {
                    if points.isEmpty {
                        emptyState
                    } else {
                        let zeroSubject = groupTotals.first?.name ?? ""
                        let allPoints = points + days.map { DayPoint(day: $0, subject: zeroSubject, minutes: 0) }
                        let todayLabel = dayLabel(cal.startOfDay(for: Date()))
                        Chart {
                            ForEach(allPoints) { p in
                                BarMark(x: .value("Day", dayLabel(p.day)), y: .value("Minutes", p.minutes), width: .ratio(0.62))
                                    .foregroundStyle(by: .value("Subject", p.subject))
                                    .cornerRadius(5)
                            }
                            if goal > 0 {
                                RuleMark(y: .value("Goal", goal / 60))
                                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                                    .foregroundStyle(.secondary)
                                    .annotation(position: .top, alignment: .trailing) {
                                        Text("goal \(Fmt.shortDuration(goal))").font(.caption2).foregroundStyle(.secondary)
                                    }
                            }
                            if days.contains(where: { cal.isDateInToday($0) }) {
                                RuleMark(x: .value("Day", todayLabel))
                                    .foregroundStyle(accent.opacity(0.08))
                                    .lineStyle(StrokeStyle(lineWidth: period == .week ? 70 : 14))
                                    .annotation(position: .top, alignment: .center, spacing: 0) {
                                        Text("TODAY").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(accent)
                                    }
                            }
                            ForEach(days.filter { (perDay[$0] ?? 0) > 0 }, id: \.self) { d in
                                PointMark(x: .value("Day", dayLabel(d)), y: .value("Minutes", (perDay[d] ?? 0) / 60))
                                    .symbolSize(0)
                                    .annotation(position: .top, spacing: 4) {
                                        if period == .week {
                                            Text(Fmt.shortDuration(perDay[d] ?? 0)).font(.caption2.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                            }
                        }
                        .chartForegroundStyleScale(domain: groupTotals.map(\.name), range: groupTotals.map(\.color))
                        .chartXScale(domain: days.map(dayLabel))
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                                AxisValueLabel {
                                    if let m = value.as(Double.self) { Text(Fmt.shortDuration(m * 60)) }
                                }
                            }
                        }
                        .chartLegend(position: .bottom, spacing: 12)
                        .frame(height: 270)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    ReportCard(title: "Study rhythm", icon: "square.grid.3x3.fill", tint: accent) {
                        RhythmGrid(days: days, perDay: perDay, goal: goal, tint: accent, kind: kind, cal: cal)
                    }
                    ReportCard(title: "When you study · minutes per hour of the day", icon: "clock.fill", tint: .teal) {
                        HourChart(sessions: sessions, cal: cal, tint: .teal)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    ReportCard(title: "Time by subject", icon: "chart.pie.fill", tint: .pink) {
                        if subjectTotals.isEmpty {
                            emptyState
                        } else {
                            HStack(spacing: 22) {
                                ZStack {
                                    Chart(subjectTotals) { c in
                                        SectorMark(angle: .value("Time", c.seconds), innerRadius: .ratio(0.64), angularInset: 2)
                                            .foregroundStyle(c.color)
                                            .cornerRadius(5)
                                    }
                                    VStack(spacing: 0) {
                                        Text(Fmt.shortDuration(total)).font(.title3.weight(.bold).monospacedDigit())
                                        Text("\(subjectTotals.count) subjects").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 170, height: 170)

                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(subjectTotals.prefix(7)) { c in
                                        RankRow(color: c.color, title: c.name, seconds: c.seconds,
                                                share: c.seconds / max(total, 1), showPercent: true)
                                    }
                                }
                            }
                        }
                    }

                    ReportCard(title: "Most time spent on", icon: "list.number", tint: .indigo) {
                        if itemTotals.isEmpty {
                            Text("No sessions in this period.").foregroundStyle(.secondary).font(.callout)
                        }
                        let top = itemTotals.first?.seconds ?? 1
                        ForEach(Array(itemTotals.prefix(7).enumerated()), id: \.element.id) { i, t in
                            HStack(spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.heavy).monospacedDigit())
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(i < 3 ? [Color.yellow, .gray, .orange][i].opacity(0.25) : Color.primary.opacity(0.06)))
                                RankRow(color: t.color, title: t.title, seconds: t.seconds, share: t.seconds / max(top, 1), showPercent: false)
                            }
                        }
                    }
                }

                let undone = unfinished(days: days)
                ReportCard(title: "Left undone this \(period.name)", icon: "exclamationmark.circle.fill", tint: .orange) {
                    if undone.isEmpty {
                        Text(days.first.map { $0 > Date() } ?? false ? "This \(period.name) hasn't started yet."
                             : "Everything planned so far was done 🎉")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        let skipped = undone.filter(\.skipped).count
                        Text("\(undone.count - skipped) not ticked off" + (skipped > 0 ? ", \(skipped) skipped (won't do)" : "") + " on days that have already started.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(undone) { u in
                            HStack {
                                Image(systemName: u.skipped ? "xmark.circle.fill" : "circle")
                                    .foregroundStyle(u.skipped ? Color.orange : u.color)
                                Text(u.title).lineLimit(1)
                                Text(u.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                if u.skipped { Text("Skipped").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                                Text(Fmt.date(u.day, "EEE, MMM d", kind)).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !completedTasks.isEmpty {
                    ReportCard(title: "Tasks completed this \(period.name)", icon: "checkmark.circle.fill", tint: .green) {
                        ForEach(completedTasks.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) { t in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(t.title)
                                CategoryChip(category: store.category(t.categoryID)).font(.caption)
                                Spacer()
                                if let d = t.completedAt {
                                    Text(Fmt.date(d, "EEE, MMM d", kind)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Reports")
    }

    /// The big header: period, total, change vs last period, a small trend line and the period's goal ring
    private func hero(total: TimeInterval, prevTotal: TimeInterval, days: [Date], perDay: [Date: TimeInterval], goal: TimeInterval) -> some View {
        let target = goal * Double(days.count)
        let change: Double? = prevTotal > 0 ? (total - prevTotal) / prevTotal : nil
        return HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("", selection: $period) {
                        ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                    HStack(spacing: 0) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 26, height: 22) }
                            .help("Previous \(period.name)")
                        Button("Now") { anchor = Date() }
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 26, height: 22) }
                            .help("Next \(period.name)")
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.15)))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(periodTitle(kind)).font(.title2.weight(.bold))
                    Text(periodTitle(kind.other)).font(.callout).opacity(0.75)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Fmt.duration(total))
                        .font(.system(size: 46, weight: .heavy, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("studied").font(.title3).opacity(0.75)
                }
                Group {
                    if let change {
                        let pct = Int((change * 100).rounded())
                        Label(pct == 0 ? "Same as last \(period.name)" : "\(abs(pct))% \(pct > 0 ? "more" : "less") than last \(period.name)",
                              systemImage: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                    } else {
                        Label(total > 0 ? "Nothing logged last \(period.name)" : "Nothing logged yet", systemImage: "sparkles")
                    }
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.18)))
            }
            Spacer(minLength: 10)
            // trend of daily totals
            Chart(days, id: \.self) { d in
                AreaMark(x: .value("Day", d), y: .value("Time", (perDay[d] ?? 0) / 3600))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.linearGradient(colors: [.white.opacity(0.45), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", d), y: .value("Time", (perDay[d] ?? 0) / 3600))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(width: 260, height: 110)
            // the period's goal
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 12)
                Circle().trim(from: 0, to: target > 0 ? min(1, total / target) : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(target > 0 ? "\(Int((total / target * 100).rounded()))%" : "—").font(.title2.weight(.heavy).monospacedDigit())
                    Text("of \(Fmt.shortDuration(target)) goal").font(.caption2).opacity(0.8)
                }
            }
            .frame(width: 112, height: 112)
            .animation(.spring(duration: 0.6), value: total)
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [accent, Color(hex: "#6D28D9"), Color(hex: "#1E1B4B")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.white.opacity(0.08)).frame(width: 220).offset(x: 60, y: -90)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: accent.opacity(0.35), radius: 18, y: 8)
        )
    }

    private struct Undone: Identifiable {
        let id: String
        let title: String
        let detail: String
        let color: Color
        let day: Date
        let skipped: Bool
    }

    /// Schedule to-dos and dated tasks in the period, on days up to today, that were never ticked off
    private func unfinished(days: [Date]) -> [Undone] {
        var out: [Undone] = []
        for day in days where day <= Date() {
            for t in store.todos(on: day) where !t.isDone {
                out.append(Undone(id: "\(t.id)|\(Cal.dayKey(day))", title: t.title, detail: t.detail,
                                  color: t.color, day: day, skipped: t.isSkipped))
            }
        }
        return out
    }

    /// How many schedule to-dos were ticked off in the period (only counting days up to today)
    private func scheduleTodoStats(days: [Date]) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for day in days where day <= Date() {
            let items = store.scheduleTodos(on: day)
            total += items.count
            done += items.filter(\.isDone).count
        }
        return (done, total)
    }

    private var emptyState: some View {
        Text("No sessions in this period.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func periodTitle(_ k: CalendarKind) -> String {
        let last = interval.end.addingTimeInterval(-1)
        if period == .month && k == kind {
            return Fmt.date(interval.start, "MMMM y", k)
        }
        return "\(Fmt.date(interval.start, "MMM d", k)) – \(Fmt.date(last, "MMM d, y", k))"
    }

    private func dayLabel(_ d: Date) -> String {
        period == .week ? Fmt.date(d, "EEE d", kind) : Fmt.date(d, "d", kind)
    }

    private func shift(_ delta: Int) {
        if let d = cal.date(byAdding: period.component, value: delta, to: anchor) { anchor = d }
    }

    private func comparison(_ now: TimeInterval, _ before: TimeInterval) -> String {
        guard before > 0 else { return now > 0 ? "Nothing logged last \(period.name)" : "—" }
        let pct = Int(((now - before) / before * 100).rounded())
        if pct == 0 { return "Same as last \(period.name)" }
        return "\(pct > 0 ? "↑" : "↓") \(abs(pct))% vs last \(period.name)"
    }
}


// MARK: - Report pieces

/// A section card with a coloured icon badge
private struct ReportCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.16)))
                Text(title).font(.headline)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// A stat with an icon, a value and a small visual underneath
private struct InsightTile<Visual: View>: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let tint: Color
    @ViewBuilder var visual: Visual

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(.caption2.weight(.heavy)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon).foregroundStyle(tint)
            }
            Text(value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            visual
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.14), Color(nsColor: .controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.18)))
    }
}

private struct MeterBar: View {
    let value: Double
    let tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint.gradient).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 7)
        .animation(.spring(duration: 0.6), value: value)
    }
}

/// One dot per day of the period: lit when you studied
private struct DayDots: View {
    let days: [Date]
    let active: Set<Date>
    let tint: Color
    var body: some View {
        HStack(spacing: days.count > 10 ? 2 : 5) {
            ForEach(days, id: \.self) { d in
                let on = active.contains(d), future = d > Date()
                RoundedRectangle(cornerRadius: 2)
                    .fill(on ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(future ? 0.04 : 0.1)))
                    .frame(height: 7)
            }
        }
    }
}

/// A row with a dot, a name, a bar and the time
private struct RankRow: View {
    let color: Color
    let title: String
    let seconds: TimeInterval
    let share: Double
    let showPercent: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).lineLimit(1)
                Spacer()
                Text(Fmt.shortDuration(seconds)).font(.callout.weight(.semibold).monospacedDigit())
                if showPercent {
                    Text("\(Int((share * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }
            }
            MeterBar(value: share, tint: color).frame(height: 5)
        }
    }
}

/// Days of the period as tiles, deeper colour for more study (relative to the daily goal)
private struct RhythmGrid: View {
    let days: [Date]
    let perDay: [Date: TimeInterval]
    let goal: TimeInterval
    let tint: Color
    let kind: CalendarKind
    let cal: Calendar

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: cols, spacing: 6) {
                // pad the first week so days line up under their weekday
                let lead = days.first.map { (cal.component(.weekday, from: $0) - cal.firstWeekday + 7) % 7 } ?? 0
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: days.count <= 7 ? 64 : 34) }
                ForEach(days, id: \.self) { d in
                    let t = perDay[d] ?? 0
                    let level = goal > 0 ? min(1, t / goal) : (t > 0 ? 1 : 0)
                    let future = d > Date()
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(t > 0 ? AnyShapeStyle(tint.opacity(0.2 + 0.8 * level)) : AnyShapeStyle(Color.primary.opacity(future ? 0.03 : 0.07)))
                        .overlay(
                            VStack(spacing: 2) {
                                Text(Fmt.date(d, days.count <= 7 ? "EEE d" : "d", kind)).font(.caption2.weight(.semibold))
                                if days.count <= 7 {
                                    Text(t > 0 ? Fmt.shortDuration(t) : "—").font(.caption.weight(.bold).monospacedDigit())
                                }
                            }
                            .foregroundStyle(t > 0 && level > 0.5 ? .white : .secondary)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(cal.isDateInToday(d) ? tint : .clear, lineWidth: 2))
                        .frame(height: days.count <= 7 ? 64 : 34)
                        .help("\(Fmt.date(d, "EEEE, MMM d", kind)) · \(t > 0 ? Fmt.duration(t) : "no study")")
                }
            }
            HStack(spacing: 4) {
                Text("No study").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 3).fill(v == 0 ? Color.primary.opacity(0.07) : tint.opacity(0.2 + 0.8 * v)).frame(width: 14, height: 10)
                }
                Text("Daily goal reached").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Minutes studied in each hour of the day across the period
private struct HourChart: View {
    let sessions: [StudySession]
    let cal: Calendar
    let tint: Color

    private struct Slot: Identifiable { let id: Int; let minutes: Double }

    var body: some View {
        var mins = Array(repeating: 0.0, count: 24)
        for s in sessions {
            var t = s.start
            while t < s.end {
                let h = cal.component(.hour, from: t)
                let next = cal.date(bySetting: .minute, value: 0, of: t.addingTimeInterval(3600)).map { min($0, s.end) } ?? s.end
                let chunk = max(60, min(next, s.end).timeIntervalSince(t))
                mins[h] += min(chunk, s.end.timeIntervalSince(t)) / 60
                t = t.addingTimeInterval(chunk)
            }
        }
        let peak = mins.enumerated().max { $0.element < $1.element }
        let slots = mins.enumerated().map { Slot(id: $0.offset, minutes: $0.element) }
        return VStack(alignment: .leading, spacing: 8) {
            if sessions.isEmpty {
                Text("No sessions in this period.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(slots) { s in
                    BarMark(x: .value("Hour", String(format: "%02d", s.id)), y: .value("Minutes", s.minutes), width: .ratio(0.7))
                        .foregroundStyle(s.id == peak?.offset ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.35)))
                        .cornerRadius(3)
                }
                .chartXScale(domain: (0..<24).map { String(format: "%02d", $0) })
                .chartXAxis {
                    AxisMarks(values: ["00", "06", "12", "18"]) { _ in AxisValueLabel() }
                }
                .chartYAxis(.hidden)
                .frame(height: 150)
                if let peak, peak.element > 0 {
                    Label("You focus most around \(String(format: "%02d:00", peak.offset))", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}


/// Small facts about the period, each with its own icon
private struct Highlights: View {
    let sessions: [StudySession]
    let days: [Date]
    let perDay: [Date: TimeInterval]
    /// Subjects, most studied first
    let subjects: [(name: String, color: Color, seconds: TimeInterval)]
    let kind: CalendarKind
    let store: AppStore

    var body: some View {
        let longest = sessions.max { $0.duration < $1.duration }
        let bestRun = longestRun
        let avg = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)
        HStack(spacing: 12) {
            fact("timer", .blue, "Longest session",
                 longest.map { Fmt.duration($0.duration) } ?? "—",
                 longest.map { "\(store.itemTitle(of: $0)) · \(Fmt.date($0.start, "EEE", kind))" } ?? "no sessions yet")
            fact("flame.fill", .orange, "Longest streak", bestRun > 0 ? "\(bestRun) day\(bestRun == 1 ? "" : "s")" : "—",
                 "days in a row with study")
            fact("star.fill", subjects.first?.color ?? .pink, "Top subject", subjects.first?.name ?? "—",
                 subjects.first.map { Fmt.duration($0.seconds) } ?? "nothing studied yet")
            fact("square.stack.3d.up.fill", .indigo, "Sessions", "\(sessions.count)",
                 sessions.isEmpty ? "start the timer to log one" : "about \(Fmt.shortDuration(avg)) each")
        }
    }

    /// Most days in a row with study inside the period (up to today)
    private var longestRun: Int {
        var run = 0, best = 0
        for d in days where d <= Date() {
            if (perDay[d] ?? 0) > 0 { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }

    private func fact(_ icon: String, _ tint: Color, _ title: String, _ value: String, _ caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.gradient))
                .shadow(color: tint.opacity(0.4), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.bold)).lineLimit(1)
                Text(caption).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}
