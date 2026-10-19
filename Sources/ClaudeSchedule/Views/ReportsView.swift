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

    var body: some View {
        let sessions = store.sessions(in: interval)
        let total = sessions.reduce(0) { $0 + $1.duration }
        let prevTotal = store.studyTime(in: previousInterval)
        let days = cal.days(in: interval)
        let elapsedDays = max(1, days.filter { $0 <= Date() }.count)
        let perDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.start) }
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        let activeDays = perDay.values.filter { $0 > 0 }.count
        let best = perDay.max { $0.value < $1.value }
        let completedTasks = store.tasks.filter { t in t.completedAt.map { interval.contains($0) } ?? false }
        let scheduleDone = scheduleTodoStats(days: days)

        let points: [DayPoint] = sessions.map {
            DayPoint(day: cal.startOfDay(for: $0.start), subject: store.subject(of: $0).name, minutes: $0.duration / 60)
        }
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
                header

                HStack(spacing: 14) {
                    StatTile(title: "Total studied", value: Fmt.duration(total),
                             subtitle: comparison(total, prevTotal), systemImage: "clock", tint: .blue)
                    StatTile(title: "Daily average", value: Fmt.duration(total / Double(elapsedDays)),
                             subtitle: "\(activeDays) active of \(days.count) days",
                             systemImage: "chart.line.uptrend.xyaxis", tint: .purple)
                    StatTile(title: "Best day",
                             value: best.map { Fmt.duration($0.value) } ?? "—",
                             subtitle: best.map { Fmt.date($0.key, "EEEE, MMM d", kind) },
                             systemImage: "trophy", tint: .orange)
                    StatTile(title: "To-dos completed",
                             value: "\(scheduleDone.done + completedTasks.count)",
                             subtitle: scheduleDone.total > 0
                                ? "Schedule: \(scheduleDone.done) of \(scheduleDone.total)" : nil,
                             systemImage: "checkmark.seal", tint: .green)
                }

                Card(title: "Daily study time", systemImage: "chart.bar") {
                    if points.isEmpty {
                        emptyState
                    } else {
                        let zeroSubject = subjectTotals.first?.name ?? ""
                        let allPoints = points + days.map { DayPoint(day: $0, subject: zeroSubject, minutes: 0) }
                        Chart(allPoints) { p in
                            BarMark(x: .value("Day", dayLabel(p.day)),
                                    y: .value("Minutes", p.minutes))
                                .foregroundStyle(by: .value("Subject", p.subject))
                                .cornerRadius(3)
                        }
                        .chartForegroundStyleScale(domain: subjectTotals.map(\.name), range: subjectTotals.map(\.color))
                        .chartXScale(domain: days.map(dayLabel))
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let m = value.as(Double.self) { Text(Fmt.shortDuration(m * 60)) }
                                }
                            }
                        }
                        .chartLegend(position: .bottom)
                        .frame(height: 260)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    Card(title: "Time by subject", systemImage: "chart.pie") {
                        if subjectTotals.isEmpty {
                            emptyState
                        } else {
                            HStack(spacing: 20) {
                                Chart(subjectTotals) { c in
                                    SectorMark(angle: .value("Time", c.seconds),
                                               innerRadius: .ratio(0.58), angularInset: 1.5)
                                        .foregroundStyle(c.color)
                                        .cornerRadius(4)
                                }
                                .frame(width: 170, height: 170)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(subjectTotals) { c in
                                        HStack {
                                            Circle().fill(c.color).frame(width: 9, height: 9)
                                            Text(c.name).lineLimit(1)
                                            Spacer()
                                            Text(Fmt.shortDuration(c.seconds)).monospacedDigit()
                                            Text("(\(Int((c.seconds / max(total, 1) * 100).rounded()))%)")
                                                .foregroundStyle(.secondary).font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Card(title: "Most time spent on", systemImage: "list.number") {
                        if itemTotals.isEmpty {
                            Text("No sessions in this period.").foregroundStyle(.secondary).font(.callout)
                        }
                        ForEach(itemTotals.prefix(8)) { t in
                            HStack {
                                Circle().fill(t.color).frame(width: 8, height: 8)
                                Text(t.title).lineLimit(1)
                                Spacer()
                                Text(Fmt.shortDuration(t.seconds)).monospacedDigit()
                            }
                        }
                    }
                }

                let undone = unfinished(days: days)
                Card(title: "Left undone this \(period.name)", systemImage: "exclamationmark.circle") {
                    if undone.isEmpty {
                        Text(days.first.map { $0 > Date() } ?? false ? "This \(period.name) hasn't started yet."
                             : "Everything planned so far was done 🎉")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        Text("\(undone.count) to-do\(undone.count == 1 ? "" : "s") planned for days that have already started weren't ticked off.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(undone) { u in
                            HStack {
                                Image(systemName: "circle").foregroundStyle(u.color)
                                Text(u.title).lineLimit(1)
                                Text(u.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(Fmt.date(u.day, "EEE, MMM d", kind)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !completedTasks.isEmpty {
                    Card(title: "Tasks completed this \(period.name)", systemImage: "checkmark.circle") {
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

    private struct Undone: Identifiable {
        let id: String
        let title: String
        let detail: String
        let color: Color
        let day: Date
    }

    /// Schedule to-dos and dated tasks in the period, on days up to today, that were never ticked off
    private func unfinished(days: [Date]) -> [Undone] {
        var out: [Undone] = []
        for day in days where day <= Date() {
            for t in store.todos(on: day) where !t.isDone {
                out.append(Undone(id: "\(t.id)|\(Cal.dayKey(day))", title: t.title, detail: t.detail,
                                  color: t.color, day: day))
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(periodTitle(kind)).font(.title.weight(.bold))
                Text(periodTitle(kind.other)).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            ControlGroup {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous \(period.name)")
                Button("Now") { anchor = Date() }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next \(period.name)")
            }
            .frame(width: 160)
        }
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
