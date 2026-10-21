import SwiftUI

enum TaskFilter: String, CaseIterable, Identifiable {
    case today, upcoming, inbox, all, done, skipped

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .inbox: "No Date"
        case .all: "All Open"
        case .done: "Done"
        case .skipped: "Skipped"
        }
    }
}

enum TasksMode: String, CaseIterable, Identifiable {
    case day, week, list, graph
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .list: "List"
        case .graph: "Graph"
        }
    }
    var icon: String {
        switch self {
        case .day: "sun.max"
        case .week: "calendar.day.timeline.left"
        case .list: "list.bullet"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    // CS_TASKS_MODE=graph opens a given view (handy for testing)
    /// Remembered, so coming back to Tasks opens the same view
    @AppStorage("tasksMode") private var mode: TasksMode = ProcessInfo.processInfo.environment["CS_TASKS_MODE"].flatMap(TasksMode.init(rawValue:)) ?? .week
    @State private var anchor = Date()
    @State private var filter: TaskFilter = .all
    @State private var categoryFilter: UUID?
    @State private var search = ""
    @State private var editing: TaskItem?

    private var kind: CalendarKind { store.settings.primaryCalendar }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            switch mode {
            case .day: dayView
            case .week: weekView
            case .list: listView
            case .graph: CategoryGraphView(categoryFilter: categoryFilter, search: search)
            }
        }
        .padding(20)
        .navigationTitle("Tasks")
        .searchable(text: $search, prompt: "Search tasks")
        .toolbar {
            Button {
                editing = TaskItem(title: "", categoryID: categoryFilter,
                                   dueDate: mode == .list ? nil : Cal.persian.startOfDay(for: anchor))
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .keyboardShortcut("n")
        }
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .onAppear {
            if let m = ProcessInfo.processInfo.environment["CS_TASKS_MODE"].flatMap(TasksMode.init(rawValue:)) { mode = m }
            consumeFocusDate()
        }
        .onChange(of: router.tasksFocusDate) { _, _ in consumeFocusDate() }
    }

    /// Another screen (e.g. Calendar) asked to open a specific day
    private func consumeFocusDate() {
        guard let date = router.tasksFocusDate else { return }
        anchor = date
        mode = .day
        router.tasksFocusDate = nil
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(TasksMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            if mode == .graph {
                Text("Tasks and to-dos grouped by category").font(.headline)
            } else if mode != .list {
                HStack(spacing: 2) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 20) }
                        .help(mode == .day ? "Previous day" : "Previous week")
                    Button("Today") { withAnimation { anchor = Date() } }
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 20) }
                        .help(mode == .day ? "Next day" : "Next week")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(.quaternary.opacity(0.6)))

                VStack(alignment: .leading, spacing: 0) {
                    Text(periodTitle(kind)).font(.headline)
                    Text(periodTitle(kind.other)).font(.caption).foregroundStyle(.secondary)
                }
                ParityBadge(parity: store.parity(ofWeek: anchor))
            } else {
                Picker("", selection: $filter) {
                    ForEach(TaskFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
            }

            Spacer()

            Picker("Category", selection: $categoryFilter) {
                Text("All categories").tag(UUID?.none)
                ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
            }
            .frame(width: 210)
        }
    }

    private func periodTitle(_ k: CalendarKind) -> String {
        if mode == .day { return Fmt.fullDate(anchor, k) }
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: anchor)!
        let last = week.end.addingTimeInterval(-1)
        return "\(Fmt.date(week.start, "MMM d", k)) – \(Fmt.date(last, "MMM d, y", k))"
    }

    private func shift(_ delta: Int) {
        let days = mode == .day ? delta : delta * 7
        withAnimation(.easeInOut(duration: 0.2)) {
            anchor = Cal.persian.date(byAdding: .day, value: days, to: anchor) ?? anchor
        }
    }

    // MARK: Filtering helpers

    private func matches(_ task: TaskItem) -> Bool {
        if let categoryFilter, task.categoryID != categoryFilter { return false }
        if !search.isEmpty {
            return task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search)
        }
        return true
    }

    private func matches(_ row: ScheduleTodoRow) -> Bool {
        if let categoryFilter, row.entry.categoryID != categoryFilter { return false }
        if !search.isEmpty {
            return row.entry.text.localizedCaseInsensitiveContains(search)
                || (store.category(row.entry.categoryID)?.name.localizedCaseInsensitiveContains(search) ?? false)
        }
        return true
    }

    private func scheduleTodos(on day: Date) -> [ScheduleTodoRow] {
        store.scheduleRows(on: day, kinds: [.todo]).filter(matches)
    }

    private func tasks(on day: Date) -> [TaskItem] {
        store.tasks(on: day).filter(matches)
    }

    private var inbox: [TaskItem] {
        store.tasks.filter { $0.dueDate == nil && !$0.isDone && !$0.isSkipped && matches($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func addTask(_ title: String, on day: Date?) {
        store.upsertTask(TaskItem(title: title, categoryID: categoryFilter,
                                  dueDate: day.map { Cal.persian.startOfDay(for: $0) }))
    }

    // MARK: Day

    private var dayView: some View {
        let rows = scheduleTodos(on: anchor)
        let items = tasks(on: anchor)
        let all = rows.count + items.count
        let done = rows.filter(\.isDone).count + items.filter(\.isDone).count
        let skipped = rows.filter(\.isSkipped).count + items.filter(\.isSkipped).count
        let fixed = store.scheduleRows(on: anchor, kinds: [.fixed])

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        ProgressRing(progress: all > 0 ? Double(done) / Double(all) : 0, lineWidth: 6)
                        Text("\(done)/\(all)").font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Cal.persian.isDateInToday(anchor) ? "Today" : Fmt.date(anchor, "EEEE", .gregorian))
                            .font(.title2.weight(.bold))
                        Text(all == 0 ? "Nothing planned" : "\(all - done - skipped) left · \(done) done" + (skipped > 0 ? " · \(skipped) skipped" : ""))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !fixed.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "pin.fill").rotationEffect(.degrees(45))
                            Text(fixed.map { "\($0.entry.title) \($0.slot.title)" }.joined(separator: "  ·  "))
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Fixed classes on this day")
                    }
                }

                QuickAddField(placeholder: "Add a task for this day and press Enter…") { addTask($0, on: anchor) }

                Card(title: "From your weekly schedule", systemImage: "tablecells") {
                    if rows.isEmpty {
                        Text("No schedule to-dos on this day.").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(rows) { row in
                        ScheduleTaskRow(row: row)
                        if row.id != rows.last?.id { Divider() }
                    }
                }

                Card(title: "Tasks", systemImage: "tray.full") {
                    if items.isEmpty {
                        Text("No one-off tasks on this day.").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(items) { task in
                        TaskRow(task: task) { editing = task }
                        if task.id != items.last?.id { Divider() }
                    }
                }

                if !inbox.isEmpty {
                    Card(title: "No date", systemImage: "tray") {
                        ForEach(inbox) { task in
                            HStack {
                                TaskRow(task: task) { editing = task }
                                Button("Move Here") { withAnimation { store.moveTask(task.id, to: anchor) } }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Week

    private var weekView: some View {
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: anchor)!
        let days = Cal.persian.days(in: week)

        return VStack(spacing: 12) {
            ScrollView {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(days, id: \.self) { day in
                        DayColumn(day: day,
                                  rows: scheduleTodos(on: day),
                                  tasks: tasks(on: day),
                                  onAdd: { addTask($0, on: day) },
                                  onEdit: { editing = $0 },
                                  onOpenDay: { anchor = day; mode = .day })
                    }
                }
                .padding(.bottom, 4)
            }

            if !inbox.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No date — drag a task onto a day", systemImage: "tray")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        ForEach(inbox) { task in
                            BoardTaskCard(task: task) { editing = task }
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))
                .dropDestination(for: String.self) { items, _ in
                    DragPayload.drop(items, on: nil, store: store)
                }
            }
        }
    }

    // MARK: List

    private var filtered: [TaskItem] {
        let cal = Cal.persian
        let todayStart = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart)!

        let list = store.tasks.filter { t in
            guard matches(t) else { return false }
            switch filter {
            case .today: return t.dueDate.map { $0 >= todayStart && $0 < tomorrow } ?? false
            case .upcoming: return !t.isDone && !t.isSkipped && (t.dueDate.map { $0 >= tomorrow } ?? false)
            case .inbox: return !t.isDone && !t.isSkipped && t.dueDate == nil
            case .all: return !t.isDone && !t.isSkipped
            case .done: return t.isDone
            case .skipped: return t.isSkipped
            }
        }
        if filter == .done {
            return list.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
        return list.sorted { a, b in
            let da = a.dueDate ?? .distantFuture, db = b.dueDate ?? .distantFuture
            if !cal.isDate(da, inSameDayAs: db) { return da < db }
            return AppStore.dayOrder(a, b)
        }
    }

    /// This week's To-do cells from the weekly schedule, filtered like the tasks
    private var scheduleRows: [ScheduleTodoRow] {
        let todayStart = Cal.persian.startOfDay(for: Date())
        return store.scheduleTodoRows().filter { r in
            guard matches(r) else { return false }
            switch filter {
            case .today: return Cal.persian.isDate(r.date, inSameDayAs: todayStart)
            case .upcoming: return !r.isDone && !r.isSkipped && r.date > todayStart
            case .inbox: return false
            case .all: return !r.isDone && !r.isSkipped
            case .done: return r.isDone
            case .skipped: return r.isSkipped
            }
        }
    }

    private var listView: some View {
        let items = filtered
        let rows = scheduleRows
        return VStack(spacing: 12) {
            if filter != .done {
                QuickAddField { title in
                    addTask(title, on: filter == .today ? Date() : nil)
                }
            }
            if items.isEmpty && rows.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "checklist",
                                       description: Text("Add a task with the field above or the + button, or mark cells as To-do in the weekly schedule."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { ScheduleTaskRow(row: $0) }
                        } header: {
                            Label("Weekly schedule · this week", systemImage: "tablecells")
                        }
                    }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { task in
                                TaskRow(task: task, showDate: true) { editing = task }
                            }
                        } header: {
                            Label("Tasks", systemImage: "tray.full")
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

/// "EVEN WEEK" / "ODD WEEK" capsule
struct ParityBadge: View {
    let parity: WeekParity
    @Environment(AppStore.self) private var store

    var body: some View {
        let color = parity == .even ? store.settings.template.style.accent : Color.orange
        Text(parity == .even ? "EVEN WEEK" : "ODD WEEK")
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.gradient))
    }
}

// MARK: - Week board

/// One day of the week board: its schedule to-dos and tasks, plus an add field. Tasks can be dropped here.
struct DayColumn: View {
    let day: Date
    let rows: [ScheduleTodoRow]
    let tasks: [TaskItem]
    var onAdd: (String) -> Void
    var onEdit: (TaskItem) -> Void
    var onOpenDay: () -> Void

    @Environment(AppStore.self) private var store
    @State private var newTitle = ""
    @State private var isTargeted = false

    var body: some View {
        let isToday = Cal.persian.isDateInToday(day)
        let total = rows.count + tasks.count
        let done = rows.filter(\.isDone).count + tasks.filter(\.isDone).count
        let accent = store.settings.template.style.accent
        let kind = store.settings.primaryCalendar

        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpenDay) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(Cal.weekdayShort[Cal.weekdayIndex(day)].uppercased())
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                            .foregroundStyle(isToday ? Color.white : (Cal.isFriday(day) ? Color.red : Color.secondary))
                        Spacer()
                        if total > 0 {
                            Text("\(done)/\(total)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(isToday ? Color.white.opacity(0.85) : Color.secondary)
                        }
                    }
                    Text(Fmt.date(day, "MMM d", kind))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                    Text(Fmt.date(day, "MMM d", kind.other))
                        .font(.caption2)
                        .foregroundStyle(isToday ? Color.white.opacity(0.8) : Color.secondary)
                    if total > 0 {
                        GeometryReader { geo in
                            Capsule().fill((isToday ? Color.white : accent).opacity(0.2))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(isToday ? Color.white : accent)
                                        .frame(width: geo.size.width * Double(done) / Double(total))
                                }
                        }
                        .frame(height: 3)
                        .padding(.top, 3)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isToday ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.05))))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open this day")

            ForEach(rows) { BoardScheduleCard(row: $0) }
            ForEach(tasks) { task in
                BoardTaskCard(task: task) { onEdit(task) }
            }

            HStack(spacing: 4) {
                Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                TextField("Add", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit {
                        let t = newTitle.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        onAdd(t)
                        newTitle = ""
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted ? accent : Color.primary.opacity(0.06), lineWidth: isTargeted ? 2 : 1)
        )
        .dropDestination(for: String.self) { items, _ in
            DragPayload.drop(items, on: day, store: store)
        } isTargeted: { isTargeted = $0 }
    }
}

/// Compact card for a schedule to-do on the week board
struct BoardScheduleCard: View {
    let row: ScheduleTodoRow
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        let e = row.entry
        let category = store.category(e.categoryID)
        let color = store.color(of: e) ?? category?.color ?? .accentColor

        BoardCard(color: color, isDone: row.isDone, isSkipped: row.isSkipped, hovering: hovering,
                  toggle: { store.tapStatus(.schedule(e.id), on: row.date) },
                  play: row.isDone || row.isSkipped || timer.isActive ? nil : {
                      timer.select(.schedule(e.id))
                      router.selection = .timer
                  }) {
            Text(e.title).strikethrough(row.isDone || row.isSkipped)
        } meta: {
            Text(row.slot.title).monospacedDigit()
            if let badge = e.recurrence.badge { Text(badge).fontWeight(.heavy) }
            else if let category { Text(category.name) }
        }
        .onHover { hovering = $0 }
        .draggable(DragPayload.occurrence(e.id, row.date)) {
            Label(e.title, systemImage: "arrow.right")
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        }
        .help("Drag to another day to move just this day's session")
        .contextMenu {
            StatusMenuItems(ref: .schedule(e.id), day: row.date)
            MoveToMenu(from: row.date) { day in withAnimation { store.moveOccurrence(e.id, from: row.date, to: day) } }
            Button("Study Now") { timer.select(.schedule(e.id)); router.selection = .timer }
                .disabled(timer.isActive)
            Button("Show in Weekly Schedule") { router.selection = .schedule }
        }
    }
}

/// Compact, draggable card for a one-off task on the week board
struct BoardTaskCard: View {
    let task: TaskItem
    var onEdit: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        let category = store.category(task.categoryID)

        BoardCard(color: category?.color ?? .gray, isDone: task.isDone, isSkipped: task.isSkipped, hovering: hovering,
                  toggle: { store.tapStatus(.task(task.id), on: task.dueDate ?? Date()) },
                  edit: onEdit,
                  play: task.isDone || task.isSkipped || timer.isActive ? nil : {
                      timer.select(.task(task.id))
                      router.selection = .timer
                  }) {
            Text(task.title).strikethrough(task.isDone || task.isSkipped)
        } meta: {
            if task.hasTime, let d = task.dueDate { Label(Fmt.time(d), systemImage: "clock") }
            if let category { Text(category.name) }
            if task.priority == .high { Image(systemName: "flag.fill").foregroundStyle(.red) }
        }
        .onHover { hovering = $0 }
        .draggable(DragPayload.task(task.id)) {
            Text(task.title)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        }
        .contextMenu {
            Button("Edit", action: onEdit)
            StatusMenuItems(ref: .task(task.id), day: task.dueDate ?? Date())
            MoveToMenu(from: task.dueDate ?? Date()) { day in withAnimation { store.moveTask(task.id, to: day) } }
            Divider()
            Button("Delete", role: .destructive) { store.deleteTask(task.id) }
        }
    }
}

/// Shared look of the week-board cards
struct BoardCard<Title: View, Meta: View>: View {
    let color: Color
    let isDone: Bool
    var isSkipped = false
    let hovering: Bool
    var toggle: () -> Void
    var edit: (() -> Void)? = nil
    var play: (() -> Void)?
    @ViewBuilder var title: Title
    @ViewBuilder var meta: Meta

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button(action: { withAnimation { toggle() } }) {
                StatusIcon(done: isDone, skipped: isSkipped)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                    .foregroundStyle(isDone || isSkipped ? .secondary : .primary)
                HStack(spacing: 6) { meta }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering, let edit {
                Button(action: edit) { Image(systemName: "pencil.circle") .font(.title3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Edit")
            }
            if hovering, let play {
                Button(action: play) { Image(systemName: "play.circle.fill").font(.title3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Study in the timer")
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 5 : 2, y: 1)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                .fill(color)
                .frame(width: 4)
        }
        .opacity(isDone || isSkipped ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}

struct TaskEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var task: TaskItem
    @State private var hasDate: Bool
    private let isNew: Bool

    init(task: TaskItem) {
        _task = State(initialValue: task)
        _hasDate = State(initialValue: task.dueDate != nil)
        isNew = task.title.isEmpty
    }

    private var kind: CalendarKind { store.settings.primaryCalendar }

    private var dateBinding: Binding<Date> {
        Binding(get: { task.dueDate ?? Cal.persian.startOfDay(for: Date()) },
                set: { task.dueDate = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $task.title)
                Picker("Category", selection: $task.categoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Priority", selection: $task.priority) {
                    ForEach(Priority.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Section {
                    Toggle("Has date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                        LabeledContent("\(kind.other.title) date",
                                       value: Fmt.fullDate(dateBinding.wrappedValue, kind.other))
                        Toggle("Specific time", isOn: $task.hasTime)
                        if task.hasTime {
                            DatePicker("Time", selection: dateBinding, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Stepper(value: $task.estimatedMinutes, in: 5...720, step: 5) {
                    LabeledContent("Estimate", value: Fmt.duration(TimeInterval(task.estimatedMinutes * 60)))
                }
                TextField("Notes", text: $task.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        store.deleteTask(task.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480)
        .environment(\.calendar, kind.calendar)
        .onChange(of: hasDate) { _, on in
            if on, task.dueDate == nil { task.dueDate = Cal.persian.startOfDay(for: Date()) }
        }
    }

    private func save() {
        task.title = task.title.trimmingCharacters(in: .whitespaces)
        if !hasDate {
            task.dueDate = nil
            task.hasTime = false
        } else if !task.hasTime, let d = task.dueDate {
            task.dueDate = Cal.persian.startOfDay(for: d)
        }
        store.upsertTask(task)
        dismiss()
    }
}

/// A To-do cell from the weekly schedule, shown as a recurring task
struct ScheduleTaskRow: View {
    let row: ScheduleTodoRow

    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router

    var body: some View {
        let entry = row.entry
        let category = store.category(entry.categoryID)
        let isToday = Cal.persian.isDateInToday(row.date)

        HStack(spacing: 10) {
            Button {
                withAnimation { store.tapStatus(.schedule(entry.id), on: row.date) }
            } label: {
                StatusIcon(done: row.isDone, skipped: row.isSkipped).font(.title3)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 2)
                .fill(store.color(of: entry) ?? category?.color ?? .accentColor)
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text.replacingOccurrences(of: "\n", with: " · "))
                    .strikethrough(row.isDone || row.isSkipped)
                    .foregroundStyle(row.isDone || row.isSkipped ? .secondary : .primary)
                HStack(spacing: 8) {
                    CategoryChip(category: category)
                    Label(isToday ? "Today" : (entry.recurrence == .weekly ? "Every \(Cal.weekdayNames[entry.weekday])"
                                                                         : "\(Cal.weekdayNames[entry.weekday]) · \(entry.recurrence.title)"),
                          systemImage: entry.recurrence.icon)
                    Label(row.slot.title, systemImage: "clock")
                    Label(Fmt.date(row.date, "MMM d", store.settings.primaryCalendar), systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Picker("Category", selection: Binding(
                    get: { entry.categoryID },
                    set: { id in store.updateEntry(entry.id) { $0.categoryID = id } }
                )) {
                    Text("No category").tag(UUID?.none)
                    ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: category == nil ? "tag" : "tag.fill")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Set category")

            if row.isSkipped {
                Text("Skipped").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            } else if !row.isDone {
                Button {
                    timer.select(.schedule(entry.id))
                    router.selection = .timer
                } label: {
                    Image(systemName: "play.circle").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(timer.isActive)
                .help("Study this in the timer")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            StatusMenuItems(ref: .schedule(entry.id), day: row.date)
            Button("Show in Weekly Schedule") { router.selection = .schedule }
        }
    }
}

/// What gets dragged on the week board: a task, or one day's occurrence of a schedule to-do
enum DragPayload {
    static func task(_ id: UUID) -> String { "task:\(id.uuidString)" }
    static func occurrence(_ id: UUID, _ day: Date) -> String {
        "occ:\(id.uuidString)|\(Int(Cal.persian.startOfDay(for: day).timeIntervalSince1970))"
    }

    /// Handles a drop onto a day (nil = "No date")
    @MainActor
    static func drop(_ items: [String], on day: Date?, store: AppStore) -> Bool {
        var handled = false
        for item in items {
            if item.hasPrefix("occ:") {
                let parts = item.dropFirst(4).split(separator: "|")
                guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
                      let secs = TimeInterval(String(parts[1])) else { continue }
                withAnimation { store.moveOccurrence(id, from: Date(timeIntervalSince1970: secs), to: day) }
                handled = true
            } else {
                let raw = item.hasPrefix("task:") ? String(item.dropFirst(5)) : item
                guard let id = UUID(uuidString: raw) else { continue }
                withAnimation { store.moveTask(id, to: day) }
                handled = true
            }
        }
        return handled
    }
}

/// "Move to ▸" submenu: any day of the same week, the same day next week, or no date
struct MoveToMenu: View {
    let from: Date
    var onMove: (Date?) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: from)!
        let days = Cal.persian.days(in: week)
        let kind = store.settings.primaryCalendar
        Menu("Move to") {
            ForEach(days, id: \.self) { day in
                Button("\(Cal.weekdayNames[Cal.weekdayIndex(day)]) · \(Fmt.date(day, "MMM d", kind))") { onMove(day) }
                    .disabled(Cal.persian.isDate(day, inSameDayAs: from))
            }
            Divider()
            if let next = Cal.persian.date(byAdding: .day, value: 7, to: from) {
                Button("Same Day Next Week · \(Fmt.date(next, "MMM d", kind))") { onMove(next) }
            }
            Button("No Date") { onMove(nil) }
        }
    }
}
