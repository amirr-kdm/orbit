import SwiftUI

/// Month view of everything: weekly-schedule classes and to-dos (respecting even/odd weeks),
/// one-off tasks and study time, with a detail panel for the selected day.
struct CalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var anchor = Date()
    @State private var selectedDay = Cal.persian.startOfDay(for: Date())
    @State private var editing: TaskItem?

    private var kind: CalendarKind { store.settings.primaryCalendar }
    private var cal: Calendar { kind.calendar }
    private var accent: Color { store.settings.template.style.accent }

    /// Month grid cells; nil for the blank cells before day 1
    private var cells: [Date?] {
        guard let month = cal.dateInterval(of: .month, for: anchor) else { return [] }
        let days = cal.days(in: month)
        let offset = (cal.component(.weekday, from: month.start) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + days.map { Optional($0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            monthPanel
            Divider()
            dayPanel.frame(width: 360)
        }
        .navigationTitle("Calendar")
        .sheet(item: $editing) { TaskEditor(task: $0) }
    }

    // MARK: Month

    private var monthPanel: some View {
        @Bindable var store = store
        return VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.date(anchor, "MMMM y", kind)).font(.title.weight(.bold))
                    Text(secondaryMonthTitle).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $store.settings.primaryCalendar) {
                    ForEach(CalendarKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                ControlGroup {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Previous month")
                    Button("Today") {
                        anchor = Date()
                        selectedDay = cal.startOfDay(for: Date())
                    }
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .help("Next month")
                }
                .frame(width: 180)
            }

            HStack(spacing: 14) {
                legend(color: accent, icon: "circle", text: "To-do")
                legend(color: .secondary, icon: "pin.fill", text: "Class (fixed)")
                legend(color: accent, icon: "timer", text: "Studied")
                Spacer()
                Text("Click a day for details · double-click to open it in Tasks")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Cal.weekdayNames, id: \.self) { name in
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(name == "Friday" ? Color.red : Color.secondary)
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(day: day,
                                    kind: kind,
                                    isToday: cal.isDateInToday(day),
                                    isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                                    todos: store.scheduleRows(on: day, kinds: [.todo]),
                                    fixed: store.scheduleRows(on: day, kinds: [.fixed]),
                                    tasks: store.tasks(on: day),
                                    study: store.studyTime(on: day))
                                .onTapGesture(count: 2) {
                                    router.tasksFocusDate = day
                                    router.selection = .tasks
                                }
                                .onTapGesture { selectedDay = day }
                        } else {
                            Color.clear.frame(height: 108)
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func legend(color: Color, icon: String, text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var secondaryMonthTitle: String {
        guard let month = cal.dateInterval(of: .month, for: anchor) else { return "" }
        let other = kind.other
        let last = month.end.addingTimeInterval(-1)
        let first = Fmt.date(month.start, "MMMM", other)
        let lastTitle = Fmt.date(last, "MMMM y", other)
        return first == Fmt.date(last, "MMMM", other) ? lastTitle : "\(first) – \(lastTitle)"
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: anchor) { anchor = d }
    }

    // MARK: Day panel

    private var dayPanel: some View {
        let fixed = store.scheduleRows(on: selectedDay, kinds: [.fixed])
        let todos = store.scheduleRows(on: selectedDay, kinds: [.todo])
        let tasks = store.tasks(on: selectedDay)
        let sessions = store.sessions(in: cal.dayInterval(selectedDay))
        let total = sessions.reduce(0) { $0 + $1.duration }

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.fullDate(selectedDay, kind)).font(.title2.weight(.semibold))
                        Spacer()
                    }
                    Text(Fmt.fullDate(selectedDay, kind.other)).foregroundStyle(.secondary)
                    HStack {
                        ParityBadge(parity: store.parity(ofWeek: selectedDay))
                        Spacer()
                        Button {
                            router.tasksFocusDate = selectedDay
                            router.selection = .tasks
                        } label: {
                            Label("Open in Tasks", systemImage: "arrow.up.right")
                        }
                        .controlSize(.small)
                    }
                }

                QuickAddField(placeholder: "Add a task for this day…") { title in
                    store.upsertTask(TaskItem(title: title, dueDate: selectedDay))
                }

                if !fixed.isEmpty {
                    section("Classes", icon: "pin.fill") {
                        ForEach(fixed) { row in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(row.entry.color ?? store.category(row.entry.categoryID)?.color ?? .gray)
                                    .frame(width: 4, height: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.entry.title)
                                    Text(row.slot.title + (store.category(row.entry.categoryID).map { " · \($0.name)" } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let badge = row.entry.recurrence.badge {
                                    Text(badge).font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                section("To-do", icon: "checklist", trailing: todos.isEmpty && tasks.isEmpty ? nil
                        : "\(todos.filter(\.isDone).count + tasks.filter(\.isDone).count)/\(todos.count + tasks.count)") {
                    if todos.isEmpty && tasks.isEmpty {
                        Text("Nothing to do on this day.").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(todos) { BoardScheduleCard(row: $0) }
                    ForEach(tasks) { task in
                        BoardTaskCard(task: task) { editing = task }
                    }
                }

                section("Study sessions", icon: "timer", trailing: total > 0 ? Fmt.duration(total) : nil) {
                    if sessions.isEmpty {
                        Text("No sessions.").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(sessions) { SessionRow(session: $0) }
                }
            }
            .padding(20)
        }
    }

    private func section<Content: View>(_ title: String, icon: String, trailing: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                if let trailing { Text(trailing).foregroundStyle(.secondary).font(.callout) }
            }
            content()
        }
    }
}

struct DayCell: View {
    let day: Date
    let kind: CalendarKind
    let isToday: Bool
    let isSelected: Bool
    let todos: [ScheduleTodoRow]
    let fixed: [ScheduleTodoRow]
    let tasks: [TaskItem]
    let study: TimeInterval

    @Environment(AppStore.self) private var store

    private struct Line: Identifiable {
        let id: String
        let title: String
        let color: Color
        let isDone: Bool
    }

    var body: some View {
        let otherDay = kind.other.calendar.component(.day, from: day)
        let accent = store.settings.template.style.accent
        let lines: [Line] =
            todos.map { Line(id: $0.id.uuidString, title: $0.entry.title,
                             color: $0.entry.color ?? store.category($0.entry.categoryID)?.color ?? accent,
                             isDone: $0.isDone) }
            + tasks.map { Line(id: $0.id.uuidString, title: $0.title,
                               color: store.category($0.categoryID)?.color ?? .gray, isDone: $0.isDone) }
        let done = lines.filter(\.isDone).count

        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.date(day, "d", kind))
                    .font(.title3.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Color.white : (Cal.isFriday(day) ? Color.red : Color.primary))
                    .padding(.horizontal, isToday ? 6 : 0)
                    .background { if isToday { Capsule().fill(accent.gradient) } }
                Spacer()
                Text(otherDay == 1 ? Fmt.date(day, "MMM d", kind.other) : Fmt.date(day, "d", kind.other))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(lines.prefix(2)) { line in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(line.color).frame(width: 3, height: 10)
                    Text(line.title).strikethrough(line.isDone).lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(line.isDone ? .secondary : .primary)
            }
            if lines.count > 2 {
                Text("+\(lines.count - 2) more").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if !fixed.isEmpty {
                    Label("\(fixed.count)", systemImage: "pin.fill")
                        .help(fixed.map(\.entry.title).joined(separator: ", "))
                }
                if !lines.isEmpty {
                    Label("\(done)/\(lines.count)", systemImage: done == lines.count ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done == lines.count ? Color.green : Color.secondary)
                }
                Spacer(minLength: 0)
                if study > 0 {
                    Label(Fmt.shortDuration(study), systemImage: "timer")
                        .foregroundStyle(accent)
                }
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 108, maxHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? accent.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? accent : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}

/// Icon + text with a tight gap
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title.fixedSize()
        }
    }
}
