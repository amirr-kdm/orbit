import SwiftUI

/// What a to-do / timer session points at
enum TodoRef: Hashable {
    case schedule(UUID)
    case task(UUID)
}

/// A row of a day's to-do list: either a "To-do" cell from the weekly schedule or a one-off task
struct TodoItem: Identifiable, Hashable {
    let ref: TodoRef
    let title: String
    let detail: String
    let color: Color
    let isDone: Bool
    let sortMinute: Int
    /// Given up: won't be done
    var isSkipped = false

    var id: TodoRef { ref }
}

/// A weekly schedule to-do shown on the Tasks page
struct ScheduleTodoRow: Identifiable, Hashable {
    let entry: ScheduleEntry
    let slot: TimeSlot
    /// This week's occurrence
    let date: Date
    let isDone: Bool
    var isSkipped = false

    var id: UUID { entry.id }
}

/// Single source of truth. Every change is written to
/// ~/Library/Application Support/Orbit/data.json
@MainActor @Observable
final class AppStore {
    var tasks: [TaskItem] = [] { didSet { save() } }
    var categories: [Category] = [] { didSet { save() } }
    var sessions: [StudySession] = [] { didSet { save() } }
    var settings = AppSettings() { didSet { save() } }
    var schedule: [ScheduleEntry] = [] { didSet { save() } }
    /// Completed schedule to-dos, keyed "entryID|yyyy-MM-dd" (the schedule repeats weekly)
    var scheduleDone: Set<String> = [] { didSet { save() } }
    /// Single occurrences moved off their day, keyed "entryID|yyyy-MM-dd" (they became tasks)
    var scheduleMoved: Set<String> = [] { didSet { save() } }
    /// Schedule to-dos given up on a day, keyed "entryID|yyyy-MM-dd"
    var scheduleSkipped: Set<String> = [] { didSet { save() } }
    /// Planets placed in my galaxy, in the order they were added
    var galaxy: [PlacedPlanet] = [] { didSet { save() } }
    /// Planet used as my profile picture
    var avatarPlanet: String? { didSet { save() } }
    var solarSystems: [SolarSystem] = [] { didSet { save() } }
    var planners: [Planner] = [] { didSet { save() } }
    /// Store planets bought with rockets
    var purchases: [Purchase] = [] { didSet { save() } }
    /// Refund tickets used (everyone gets 3)
    var refundsUsed = 0 { didSet { save() } }
    /// Extra rockets given outside of studying (e.g. a gift)
    var rocketGrant = 0 { didSet { save() } }
    /// Weeks you studied the most in a group, keyed "groupID|yyyy-MM-dd" (week start); 100 rockets each
    var groupWins: [String] = [] { didSet { save() } }
    /// Rocket gifts from the owner already added to rocketGrant (gift ids)
    var claimedGifts: [String] = [] { didSet { save() } }

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private var isLoading = false

    private struct Snapshot: Codable {
        var tasks: [TaskItem] = []
        var categories: [Category] = []
        var sessions: [StudySession] = []
        var settings = AppSettings()
        var schedule: [ScheduleEntry] = []
        var scheduleDone: Set<String> = []
        var scheduleMoved: Set<String> = []
        var scheduleSkipped: Set<String> = []
        var purchases: [Purchase] = []
        var refundsUsed = 0
        var rocketGrant = 0
        var groupWins: [String] = []
        var claimedGifts: [String] = []
        var galaxy: [PlacedPlanet] = []
        var avatarPlanet: String?
        var solarSystems: [SolarSystem] = []
        var planners: [Planner] = []

        init(tasks: [TaskItem], categories: [Category], sessions: [StudySession], settings: AppSettings,
             schedule: [ScheduleEntry], scheduleDone: Set<String>, scheduleMoved: Set<String>,
             galaxy: [PlacedPlanet], avatarPlanet: String?, solarSystems: [SolarSystem], planners: [Planner],
             scheduleSkipped: Set<String>, purchases: [Purchase], refundsUsed: Int, rocketGrant: Int, groupWins: [String], claimedGifts: [String]) {
            self.groupWins = groupWins
            self.claimedGifts = claimedGifts
            self.refundsUsed = refundsUsed
            self.rocketGrant = rocketGrant
            self.scheduleSkipped = scheduleSkipped
            self.purchases = purchases
            self.solarSystems = solarSystems
            self.planners = planners
            self.scheduleMoved = scheduleMoved
            self.galaxy = galaxy
            self.avatarPlanet = avatarPlanet
            self.tasks = tasks
            self.categories = categories
            self.sessions = sessions
            self.settings = settings
            self.schedule = schedule
            self.scheduleDone = scheduleDone
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
            categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
            sessions = try c.decodeIfPresent([StudySession].self, forKey: .sessions) ?? []
            settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
            schedule = try c.decodeIfPresent([ScheduleEntry].self, forKey: .schedule) ?? []
            scheduleDone = try c.decodeIfPresent(Set<String>.self, forKey: .scheduleDone) ?? []
            scheduleMoved = try c.decodeIfPresent(Set<String>.self, forKey: .scheduleMoved) ?? []
            scheduleSkipped = try c.decodeIfPresent(Set<String>.self, forKey: .scheduleSkipped) ?? []
            purchases = try c.decodeIfPresent([Purchase].self, forKey: .purchases) ?? []
            refundsUsed = try c.decodeIfPresent(Int.self, forKey: .refundsUsed) ?? 0
            rocketGrant = try c.decodeIfPresent(Int.self, forKey: .rocketGrant) ?? 0
            groupWins = try c.decodeIfPresent([String].self, forKey: .groupWins) ?? []
            claimedGifts = try c.decodeIfPresent([String].self, forKey: .claimedGifts) ?? []
            galaxy = try c.decodeIfPresent([PlacedPlanet].self, forKey: .galaxy) ?? []
            avatarPlanet = try c.decodeIfPresent(String.self, forKey: .avatarPlanet)
            solarSystems = try c.decodeIfPresent([SolarSystem].self, forKey: .solarSystems) ?? []
            planners = try c.decodeIfPresent([Planner].self, forKey: .planners) ?? []
        }
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // CS_DATA_DIR lets you test with a separate data folder
        let dir = ProcessInfo.processInfo.environment["CS_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? support.appendingPathComponent("Orbit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")

        // One-time migration from the app's previous names (newest first); not for test folders
        for old in ProcessInfo.processInfo.environment["CS_DATA_DIR"] == nil ? ["Claude Schedule", "Nazm"] : [] {
            let legacy = support.appendingPathComponent("\(old)/data.json")
            if !FileManager.default.fileExists(atPath: fileURL.path), FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.copyItem(at: legacy, to: fileURL)
            }
        }

        load()
        normalizeSchedule()
        if categories.isEmpty { seedCategories() }
        // Developer tool: CS_SET_ROCKETS=1000 sets the rocket balance once
        if let target = ProcessInfo.processInfo.environment["CS_SET_ROCKETS"].flatMap(Int.init) { setRocketBalance(target) }
        ensureHomeSystem()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            try apply(data)
        } catch {
            // Never throw a broken file away – keep a copy next to it
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("data-broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("ClaudeSchedule: failed to load data: \(error)")
        }
    }

    /// Replace everything in memory with a data file's contents
    private func apply(_ data: Data) throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(Snapshot.self, from: data)
            tasks = snap.tasks
            categories = snap.categories
            sessions = snap.sessions
            settings = snap.settings
            schedule = snap.schedule
            scheduleDone = snap.scheduleDone
            scheduleMoved = snap.scheduleMoved
            scheduleSkipped = snap.scheduleSkipped
            purchases = snap.purchases
            refundsUsed = snap.refundsUsed
            rocketGrant = snap.rocketGrant
            groupWins = snap.groupWins
            claimedGifts = snap.claimedGifts
            galaxy = snap.galaxy
            avatarPlanet = snap.avatarPlanet
            solarSystems = snap.solarSystems
            planners = snap.planners
        }
    }

    // MARK: Cloud backup hooks

    /// Called after every successful save (the cloud backup listens to this)
    @ObservationIgnored var onSaved: (() -> Void)?

    /// The folder holding data.json
    var dataFolder: URL { fileURL.deletingLastPathComponent() }

    /// The whole data file, as saved on disk
    func exportData() -> Data? { encodeSnapshot() }

    /// Replace all data with a downloaded copy (the current file is kept next to it first)
    @discardableResult
    func restore(from data: Data, keepingBackupNamed backupName: String? = nil) -> Bool {
        if let backupName, FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.copyItem(at: fileURL, to: dataFolder.appendingPathComponent(backupName))
        }
        guard (try? apply(data)) != nil else { return false }
        if categories.isEmpty { seedCategories() }
        ensureHomeSystem()
        save()
        return true
    }

    private func encodeSnapshot() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let snap = Snapshot(tasks: tasks, categories: categories, sessions: sessions, settings: settings,
                            schedule: schedule, scheduleDone: scheduleDone, scheduleMoved: scheduleMoved,
                            galaxy: galaxy, avatarPlanet: avatarPlanet, solarSystems: solarSystems,
                            planners: planners, scheduleSkipped: scheduleSkipped,
                            purchases: purchases, refundsUsed: refundsUsed,
                            rocketGrant: rocketGrant, groupWins: groupWins, claimedGifts: claimedGifts)
        return try? encoder.encode(snap)
    }

    private func save() {
        guard !isLoading else { return }
        guard let data = encodeSnapshot() else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            onSaved?()
        } catch {
            NSLog("ClaudeSchedule: failed to save data: \(error)")
        }
    }

    private func seedCategories() {
        categories = [
            Category(name: "Study", colorHex: "#4F7CF7"),
            Category(name: "Work", colorHex: "#F28C38"),
            Category(name: "Reading", colorHex: "#2BB673"),
            Category(name: "Exercise", colorHex: "#E5484D"),
            Category(name: "Personal", colorHex: "#9B6BDF"),
        ]
    }

    // MARK: Categories

    func category(_ id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func addCategory() {
        let palette = ["#4F7CF7", "#F28C38", "#2BB673", "#E5484D", "#9B6BDF", "#14B8C4", "#D9A21B", "#E255A1"]
        categories.append(Category(name: "New category", colorHex: palette[categories.count % palette.count]))
    }

    func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for i in tasks.indices where tasks[i].categoryID == id { tasks[i].categoryID = nil }
        for i in schedule.indices where schedule[i].categoryID == id { schedule[i].categoryID = nil }
        for i in sessions.indices where sessions[i].categoryID == id { sessions[i].categoryID = nil }
    }

    // MARK: Tasks

    func task(_ id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    func upsertTask(_ task: TaskItem) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i] = task
        } else {
            tasks.append(task)
        }
    }

    func deleteTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    func toggleTask(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone.toggle()
        tasks[i].isSkipped = false
        tasks[i].completedAt = tasks[i].isDone ? Date() : nil
    }

    func tasks(on day: Date) -> [TaskItem] {
        tasks.filter { t in
            guard let d = t.dueDate else { return false }
            return Cal.persian.isDate(d, inSameDayAs: day)
        }
        .sorted(by: Self.dayOrder)
    }

    /// Unfinished tasks whose day has passed
    func overdueTasks(before day: Date = Date()) -> [TaskItem] {
        let start = Cal.persian.startOfDay(for: day)
        return tasks.filter { !$0.isDone && !$0.isSkipped && ($0.dueDate.map { $0 < start } ?? false) }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    /// Open first, then timed tasks by time, then by priority
    static func dayOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let ca = a.isDone || a.isSkipped, cb = b.isDone || b.isSkipped
        if ca != cb { return !ca }
        if a.hasTime != b.hasTime { return a.hasTime }
        if a.hasTime, let da = a.dueDate, let db = b.dueDate, da != db { return da < db }
        if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
        return a.createdAt < b.createdAt
    }

    // MARK: Weekly schedule

    func slot(_ id: UUID) -> TimeSlot? {
        settings.timeSlots.first { $0.id == id }
    }

    func entry(_ id: UUID?) -> ScheduleEntry? {
        guard let id else { return nil }
        return schedule.first { $0.id == id }
    }

    // MARK: Odd / even weeks

    func parity(ofWeek date: Date) -> WeekParity {
        let n = Cal.weeksBetween(settings.evenWeekAnchor, date)
        return n % 2 == 0 ? .even : .odd
    }

    /// Flips which weeks count as even
    func setParity(_ parity: WeekParity, forWeekOf date: Date) {
        guard self.parity(ofWeek: date) != parity else { return }
        settings.evenWeekAnchor = Cal.persian.date(byAdding: .day, value: 7, to: settings.evenWeekAnchor)
            ?? settings.evenWeekAnchor
    }

    /// Does this cell show up in the week containing `date`?
    func applies(_ e: ScheduleEntry, toWeekOf date: Date) -> Bool {
        switch e.recurrence {
        case .weekly: true
        case .even: parity(ofWeek: date) == .even
        case .odd: parity(ofWeek: date) == .odd
        case .once: e.weekStart.map { Cal.weeksBetween($0, date) == 0 } ?? true
        }
    }

    /// The entry shown in a cell for a given week (the most specific one if several match)
    func entry(weekday: Int, slotID: UUID, inWeekOf date: Date) -> ScheduleEntry? {
        schedule
            .filter { $0.weekday == weekday && $0.slotID == slotID && applies($0, toWeekOf: date) }
            .max { $0.recurrence.priority < $1.recurrence.priority }
    }

    /// True when this entry is the one displayed in its cell that week
    func isShown(_ e: ScheduleEntry, inWeekOf date: Date) -> Bool {
        entry(weekday: e.weekday, slotID: e.slotID, inWeekOf: date)?.id == e.id
    }

    /// Entries visible in a week
    func entries(inWeekOf date: Date) -> [ScheduleEntry] {
        schedule.filter { isShown($0, inWeekOf: date) }
    }

    /// Creates, updates or (when the text is empty) clears the cell shown in that week
    func setCell(weekday: Int, slotID: UUID, weekOf date: Date, text: String, colorHex: String?,
                 kind: EntryKind, categoryID: UUID?, recurrence: Recurrence) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = entry(weekday: weekday, slotID: slotID, inWeekOf: date),
           let i = schedule.firstIndex(where: { $0.id == existing.id }) {
            if trimmed.isEmpty {
                schedule.remove(at: i)
            } else {
                schedule[i].text = trimmed
                schedule[i].colorHex = colorHex
            }
        } else if !trimmed.isEmpty {
            schedule.append(ScheduleEntry(weekday: weekday, slotID: slotID, text: trimmed,
                                          colorHex: colorHex, kind: kind, categoryID: categoryID,
                                          recurrence: recurrence,
                                          weekStart: recurrence == .once ? Cal.weekStart(date) : nil))
            normalizeSchedule()
        }
    }

    /// An "every week" cell that shares its slot with an even-only (or odd-only) cell can only ever show
    /// in the other weeks, so make that explicit: it becomes odd-only (or even-only).
    /// Nothing visible changes, but it no longer silently disappears in the other weeks, it carries an
    /// EVEN / ODD tag, and the shadowed copy never hides in Today, Tasks or the graph.
    func normalizeSchedule() {
        var changed = schedule
        let groups = Dictionary(grouping: changed.indices) { "\(changed[$0].weekday)|\(changed[$0].slotID)" }
        for (_, idx) in groups where idx.count > 1 {
            let parities = Set(idx.map { changed[$0].recurrence }.filter { $0 == .even || $0 == .odd })
            guard parities.count == 1, let taken = parities.first else { continue }
            for i in idx where changed[i].recurrence == .weekly {
                changed[i].recurrence = taken == .even ? .odd : .even
            }
        }
        if changed != schedule { schedule = changed }
    }

    /// Change a cell's repeat rule; "this week only" pins it to the week being viewed
    func setRecurrence(_ r: Recurrence, for id: UUID, viewingWeekOf date: Date) {
        updateEntry(id) { e in
            e.recurrence = r
            e.weekStart = r == .once ? Cal.weekStart(date) : nil
        }
        normalizeSchedule()
    }

    func updateEntry(_ id: UUID, _ change: (inout ScheduleEntry) -> Void) {
        guard let i = schedule.firstIndex(where: { $0.id == id }) else { return }
        change(&schedule[i])
    }

    func deleteEntry(_ id: UUID) {
        schedule.removeAll { $0.id == id }
    }

    func deleteSlot(_ id: UUID) {
        settings.timeSlots.removeAll { $0.id == id }
        schedule.removeAll { $0.slotID == id }
    }

    /// The slot that contains the given moment, if any
    func currentSlot(at date: Date = Date()) -> TimeSlot? {
        let m = Cal.minuteOfDay(date)
        return settings.timeSlots.first { m >= $0.startMinute && m < $0.endMinute }
    }

    /// The date a weekly entry falls on in the week containing `date`
    func occurrence(of entry: ScheduleEntry, inWeekOf date: Date = Date()) -> Date {
        let start = Cal.persian.dateInterval(of: .weekOfYear, for: date)?.start ?? Cal.persian.startOfDay(for: date)
        return Cal.persian.date(byAdding: .day, value: entry.weekday, to: start) ?? start
    }

    /// Schedule to-dos as task rows: one per weekly cell, dated to this week's occurrence
    func scheduleTodoRows(inWeekOf date: Date = Date()) -> [ScheduleTodoRow] {
        let slots = settings.timeSlots
        return schedule
            .filter { $0.kind == .todo && isShown($0, inWeekOf: date) }
            .compactMap { e -> ScheduleTodoRow? in
                guard let slot = slots.first(where: { $0.id == e.slotID }) else { return nil }
                let day = occurrence(of: e, inWeekOf: date)
                if isMoved(e.id, from: day) { return nil }
                return ScheduleTodoRow(entry: e, slot: slot, date: day,
                                       isDone: isDone(.schedule(e.id), on: day),
                                       isSkipped: isSkipped(.schedule(e.id), on: day))
            }
            .sorted { ($0.date, $0.slot.startMinute) < ($1.date, $1.slot.startMinute) }
    }

    /// Every schedule cell shown on a given day (classes and/or to-dos), ordered by time
    func scheduleRows(on day: Date, kinds: Set<EntryKind> = [.fixed, .todo]) -> [ScheduleTodoRow] {
        let weekday = Cal.weekdayIndex(day)
        let start = Cal.persian.startOfDay(for: day)
        return schedule
            .filter { $0.weekday == weekday && kinds.contains($0.kind) && isShown($0, inWeekOf: day)
                      && !isMoved($0.id, from: day) }
            .compactMap { e -> ScheduleTodoRow? in
                guard let slot = slot(e.slotID) else { return nil }
                return ScheduleTodoRow(entry: e, slot: slot, date: start, isDone: isDone(.schedule(e.id), on: start),
                                       isSkipped: isSkipped(.schedule(e.id), on: start))
            }
            .sorted { $0.slot.startMinute < $1.slot.startMinute }
    }

    func isMoved(_ entryID: UUID, from day: Date) -> Bool {
        scheduleMoved.contains(doneKey(entryID, day))
    }

    /// Move one occurrence of a schedule to-do to another day. The weekly cell stays as it is;
    /// that single day's occurrence is hidden and becomes a task on the new day (same time, title, category).
    func moveOccurrence(_ entryID: UUID, from day: Date, to newDay: Date?) {
        guard let e = entry(entryID) else { return }
        if let newDay, Cal.persian.isDate(day, inSameDayAs: newDay) { return }
        let wasDone = isDone(.schedule(entryID), on: day)
        scheduleMoved.insert(doneKey(entryID, day))
        scheduleDone.remove(doneKey(entryID, day))

        let lines = e.text.split(separator: "\n", maxSplits: 1).map(String.init)
        var t = TaskItem(title: e.title, notes: lines.count > 1 ? lines[1] : "", categoryID: e.categoryID)
        if let newDay, let slot = slot(e.slotID) {
            let start = Cal.persian.startOfDay(for: newDay)
            t.dueDate = start.addingTimeInterval(TimeInterval(slot.startMinute * 60))
            t.hasTime = true
            t.estimatedMinutes = slot.endMinute - slot.startMinute
        }
        t.isDone = wasDone
        t.completedAt = wasDone ? Date() : nil
        tasks.append(t)
    }

    /// Put a moved occurrence back on its original day
    func restoreOccurrence(_ entryID: UUID, on day: Date) {
        scheduleMoved.remove(doneKey(entryID, day))
    }

    /// Move a task to another day, keeping its time of day
    func moveTask(_ id: UUID, to day: Date?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard let day else {
            tasks[i].dueDate = nil
            tasks[i].hasTime = false
            return
        }
        let start = Cal.persian.startOfDay(for: day)
        if tasks[i].hasTime, let old = tasks[i].dueDate {
            let comps = Cal.persian.dateComponents([.hour, .minute], from: old)
            tasks[i].dueDate = Cal.persian.date(byAdding: comps, to: start) ?? start
        } else {
            tasks[i].dueDate = start
        }
    }

    /// A to-do row for any reference (used when the timer target is not in today's list)
    func todoItem(for ref: TodoRef) -> TodoItem? {
        switch ref {
        case .schedule(let id):
            guard let e = entry(id), let slot = slot(e.slotID) else { return nil }
            return TodoItem(ref: ref, title: e.title, detail: "\(Cal.weekdayShort[e.weekday]) \(slot.title)",
                            color: e.color ?? category(e.categoryID)?.color ?? .accentColor,
                            isDone: false, sortMinute: slot.startMinute)
        case .task(let id):
            guard let t = task(id) else { return nil }
            return TodoItem(ref: ref, title: t.title, detail: category(t.categoryID)?.name ?? "Task",
                            color: category(t.categoryID)?.color ?? .gray, isDone: t.isDone, sortMinute: 9999)
        }
    }

    // MARK: Daily to-do list

    private func doneKey(_ id: UUID, _ day: Date) -> String { "\(id.uuidString)|\(Cal.dayKey(day))" }

    func isDone(_ ref: TodoRef, on day: Date) -> Bool {
        switch ref {
        case .schedule(let id): scheduleDone.contains(doneKey(id, day))
        case .task(let id): task(id)?.isDone ?? false
        }
    }

    func isSkipped(_ ref: TodoRef, on day: Date) -> Bool {
        switch ref {
        case .schedule(let id): scheduleSkipped.contains(doneKey(id, day))
        case .task(let id): task(id)?.isSkipped ?? false
        }
    }

    /// Mark as given up (won't be done) or bring it back to "to do". Skipping clears "done".
    func setSkipped(_ ref: TodoRef, on day: Date, _ skipped: Bool) {
        switch ref {
        case .schedule(let id):
            let key = doneKey(id, day)
            if skipped { scheduleSkipped.insert(key); scheduleDone.remove(key) } else { scheduleSkipped.remove(key) }
        case .task(let id):
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[i].isSkipped = skipped
            if skipped { tasks[i].isDone = false; tasks[i].completedAt = nil }
        }
    }

    /// The round status button: a skipped item goes back to "to do", otherwise done is toggled
    func tapStatus(_ ref: TodoRef, on day: Date) {
        if isSkipped(ref, on: day) { setSkipped(ref, on: day, false) } else { toggleDone(ref, on: day) }
    }

    func toggleDone(_ ref: TodoRef, on day: Date) {
        if isSkipped(ref, on: day) { setSkipped(ref, on: day, false) }
        switch ref {
        case .schedule(let id):
            let key = doneKey(id, day)
            if scheduleDone.contains(key) { scheduleDone.remove(key) } else { scheduleDone.insert(key) }
        case .task(let id):
            toggleTask(id)
        }
    }

    /// Schedule cells marked "To-do" for that weekday
    func scheduleTodos(on day: Date) -> [TodoItem] {
        let weekday = Cal.weekdayIndex(day)
        let slots = settings.timeSlots
        return schedule
            .filter { $0.weekday == weekday && $0.kind == .todo && isShown($0, inWeekOf: day)
                      && !isMoved($0.id, from: day) }
            .compactMap { e -> TodoItem? in
                guard let slot = slots.first(where: { $0.id == e.slotID }) else { return nil }
                let detail = category(e.categoryID).map { "\(slot.title) · \($0.name)" } ?? slot.title
                return TodoItem(ref: .schedule(e.id), title: e.title, detail: detail,
                                color: e.color ?? .accentColor,
                                isDone: isDone(.schedule(e.id), on: day), sortMinute: slot.startMinute,
                                isSkipped: isSkipped(.schedule(e.id), on: day))
            }
            .sorted { $0.sortMinute < $1.sortMinute }
    }

    /// Everything to do on a day: schedule to-dos first (by time), then one-off tasks
    func todos(on day: Date) -> [TodoItem] {
        let taskItems = tasks(on: day).map { t in
            TodoItem(ref: .task(t.id), title: t.title,
                     detail: category(t.categoryID)?.name ?? "Task",
                     color: category(t.categoryID)?.color ?? .gray,
                     isDone: t.isDone,
                     sortMinute: t.hasTime ? (t.dueDate.map(Cal.minuteOfDay) ?? 9999) : 9999,
                     isSkipped: t.isSkipped)
        }
        return scheduleTodos(on: day) + taskItems
    }

    func title(of ref: TodoRef) -> String? {
        switch ref {
        case .schedule(let id): entry(id)?.title
        case .task(let id): task(id)?.title
        }
    }

    // MARK: Sessions

    /// Builds a session with a snapshot of its subject and colour
    func makeSession(ref: TodoRef?, categoryID: UUID?, start: Date, duration: TimeInterval, note: String) -> StudySession {
        var s = StudySession(categoryID: categoryID, start: start, duration: duration, note: note)
        switch ref {
        case .schedule(let id):
            let e = entry(id)
            s.scheduleEntryID = id
            s.categoryID = e?.categoryID ?? categoryID
            s.subject = e?.title ?? ""
            s.colorHex = e?.colorHex ?? "#4F7CF7"
        case .task(let id):
            let t = task(id)
            s.taskID = id
            s.categoryID = t?.categoryID ?? categoryID
            s.subject = category(s.categoryID)?.name ?? t?.title ?? ""
            s.colorHex = category(s.categoryID)?.colorHex ?? "#8E8E93"
        case nil:
            s.subject = category(categoryID)?.name ?? "Free study"
            s.colorHex = category(categoryID)?.colorHex ?? "#8E8E93"
        }
        return s
    }

    /// Name + colour a session is grouped under in reports
    func subject(of s: StudySession) -> (name: String, color: Color) {
        if !s.subject.isEmpty {
            return (s.subject, s.colorHex.isEmpty ? .gray : Color(hex: s.colorHex))
        }
        if let c = category(s.categoryID) { return (c.name, c.color) }
        return ("Unsorted", .gray)
    }

    /// What was worked on, for "top items" lists
    func itemTitle(of s: StudySession) -> String {
        if let id = s.scheduleEntryID { return entry(id)?.title ?? s.subject }
        if let id = s.taskID { return task(id)?.title ?? s.subject }
        return subject(of: s).name
    }

    func addSession(_ s: StudySession) {
        sessions.append(s)
        sessions.sort { $0.start < $1.start }
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    func sessions(in interval: DateInterval) -> [StudySession] {
        sessions.filter { $0.start >= interval.start && $0.start < interval.end }
    }

    func studyTime(in interval: DateInterval) -> TimeInterval {
        sessions(in: interval).reduce(0) { $0 + $1.duration }
    }

    func studyTime(on day: Date) -> TimeInterval {
        studyTime(in: Cal.persian.dayInterval(day))
    }

    /// Time logged today against one to-do
    func studyTime(for ref: TodoRef, on day: Date) -> TimeInterval {
        sessions(in: Cal.persian.dayInterval(day)).filter { s in
            switch ref {
            case .schedule(let id): s.scheduleEntryID == id
            case .task(let id): s.taskID == id
            }
        }
        .reduce(0) { $0 + $1.duration }
    }
}

/// Which screen is open
@MainActor @Observable
final class Router {
    /// A day another screen asked the Tasks page to open
    var tasksFocusDate: Date?

    // CS_START_TAB opens a given screen (handy for testing)
    var selection: SidebarItem? = ProcessInfo.processInfo.environment["CS_START_TAB"]
        .flatMap(SidebarItem.init(rawValue:)) ?? .today
}
