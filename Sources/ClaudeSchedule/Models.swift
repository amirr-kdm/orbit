import SwiftUI

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low = 0, medium = 1, high = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// A category / subject for one-off tasks (e.g. Math, Work, Gym)
struct Category: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String

    var color: Color { Color(hex: colorHex) }
}

/// A one-off task (not part of the weekly schedule)
struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes = ""
    var categoryID: UUID?
    var priority: Priority = .medium
    /// Planned day (and time when hasTime); nil = no date
    var dueDate: Date?
    var hasTime = false
    var estimatedMinutes = 30
    var isDone = false
    /// Given up: won't be done (counts as neither done nor left)
    var isSkipped = false
    var createdAt = Date()
    var completedAt: Date?
    /// Made for a Fight Club monster: only study in this task's subject shoots at it
    var bossID: UUID?
}

// MARK: - Weekly schedule

/// A column of the weekly schedule, e.g. 8:00–9:30
struct TimeSlot: Identifiable, Codable, Hashable {
    var id = UUID()
    var startMinute: Int
    var endMinute: Int

    var title: String { "\(Fmt.slotTime(startMinute))-\(Fmt.slotTime(endMinute))" }
    var duration: TimeInterval { TimeInterval((endMinute - startMinute) * 60) }

    static let defaults: [TimeSlot] = stride(from: 6 * 60, through: 22 * 60, by: 120).map {
        TimeSlot(startMinute: $0, endMinute: $0 + 90)
    }
}

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    /// Fixed commitment (class, work shift…) – only shown in the schedule
    case fixed
    /// Something to study/do – also appears in that day's to-do list
    case todo

    var id: String { rawValue }
    var title: String { self == .fixed ? "Fixed" : "To-do" }
}

/// Which weeks a schedule cell appears in
enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case weekly, even, odd, once

    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: "Every week"
        case .even: "Even weeks"
        case .odd: "Odd weeks"
        case .once: "This week only"
        }
    }
    var icon: String {
        switch self {
        case .weekly: "repeat"
        case .even: "2.circle"
        case .odd: "1.circle"
        case .once: "1.square"
        }
    }
    /// Small badge shown on the cell (none for every week)
    var badge: String? {
        switch self {
        case .weekly: nil
        case .even: "EVEN"
        case .odd: "ODD"
        case .once: "ONCE"
        }
    }
    /// When several entries share a cell, the most specific one wins
    var priority: Int {
        switch self {
        case .weekly: 0
        case .even, .odd: 1
        case .once: 2
        }
    }
}

enum WeekParity: String {
    case even, odd
    var title: String { self == .even ? "Even week" : "Odd week" }
}

/// One filled cell of the weekly schedule
struct ScheduleEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 0 = Saturday … 6 = Friday
    var weekday: Int
    var slotID: UUID
    var text: String
    var colorHex: String?
    var kind: EntryKind = .fixed
    var categoryID: UUID?
    var recurrence: Recurrence = .weekly
    /// Start of the week for `.once` entries
    var weekStart: Date?
    /// Free notes about this item (shown and edited in the Tasks graph)
    var notes = ""

    /// First line of the cell, used as the to-do title
    var title: String {
        text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? text
    }
    var color: Color? { colorHex.map(Color.init(hex:)) }
}

/// A recorded study/work session
struct StudySession: Identifiable, Codable, Hashable {
    var id = UUID()
    var categoryID: UUID?
    var taskID: UUID?
    var scheduleEntryID: UUID?
    /// Snapshot of what was studied, so reports survive later edits
    var subject = ""
    var colorHex = ""
    var start: Date
    var duration: TimeInterval
    var note = ""

    var end: Date { start.addingTimeInterval(duration) }
}

struct AppSettings: Codable, Equatable {
    var primaryCalendar: CalendarKind = .persian
    var pomodoroMinutes = 25
    var breakMinutes = 5
    var dailyGoalMinutes = 240
    var timeSlots: [TimeSlot] = TimeSlot.defaults
    /// Text size inside weekly schedule cells
    var scheduleFontSize: Double = 14
    var appearance: Appearance = .system
    var font: FontChoice = .system
    var template: ScheduleTemplate = .aurora
    /// Start of a week that counts as "even"; every other week from it is odd
    var evenWeekAnchor: Date = AppSettings.defaultEvenAnchor
    /// Colours offered for schedule and planner cells (add your own, delete any)
    var cellPalette: [String] = AppSettings.defaultPalette

    static let defaultPalette: [String] = ["#FFFFFF", "#FF6B6B", "#FFA94D", "#FFD43B", "#69DB7C",
                                           "#4DABF7", "#7C6CF2", "#F783AC", "#94A3B8"]

    /// The week of Mehr 25 – Aban 1, 1405 (Oct 17–23, 2026) is an even week
    static let defaultEvenAnchor: Date = {
        let d = Cal.gregorian.date(from: DateComponents(year: 2026, month: 10, day: 18)) ?? Date()
        return Cal.weekStart(d)
    }()
}

// MARK: - Planner

/// A rich-text note inside a planner (stored as RTF so tables and formatting survive)
struct PlannerNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "Note"
    var rtf = Data()
    var updatedAt = Date()
    /// Set when the note was last edited in the Windows app (it stores HTML); shown and saved back as RTF here
    var html: String?

    /// The note as RTF: a Windows edit (HTML) wins over the old RTF
    @MainActor var rtfForEditor: Data {
        // (older Windows builds saved the word "undefined" when opening a Mac note: ignore it)
        guard let html, html != "undefined", let data = html.data(using: .utf8),
              let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                       .characterEncoding: String.Encoding.utf8.rawValue],
                                                 documentAttributes: nil)
        else { return rtf }
        return text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) ?? rtf
    }
}

/// A draft week you can plan freely, take notes in, and later copy into the weekly schedule
struct Planner: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// To-do cells of the planned week (same weekday / time-slot layout as the weekly schedule)
    var entries: [ScheduleEntry] = []
    var notes: [PlannerNote] = [PlannerNote(title: "Brainstorm")]
    /// The folder it's filed in (nil = not in a folder)
    var folderID: UUID?
    /// The weekly plan table is folded away (only the notes show)
    var planHidden = false

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Planner"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        entries = try c.decodeIfPresent([ScheduleEntry].self, forKey: .entries) ?? []
        notes = try c.decodeIfPresent([PlannerNote].self, forKey: .notes) ?? []
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        planHidden = try c.decodeIfPresent(Bool.self, forKey: .planHidden) ?? false
    }
}

/// A folder in the Planner sidebar
struct PlannerFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var expanded = true
}

// MARK: - Decoding tolerant of missing keys
// So that adding fields in later versions never wipes existing data.

extension TaskItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        hasTime = try c.decodeIfPresent(Bool.self, forKey: .hasTime) ?? false
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 30
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        isSkipped = try c.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

extension StudySession {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        scheduleEntryID = try c.decodeIfPresent(UUID.self, forKey: .scheduleEntryID)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
        start = try c.decode(Date.self, forKey: .start)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        primaryCalendar = try c.decodeIfPresent(CalendarKind.self, forKey: .primaryCalendar) ?? d.primaryCalendar
        pomodoroMinutes = try c.decodeIfPresent(Int.self, forKey: .pomodoroMinutes) ?? d.pomodoroMinutes
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? d.breakMinutes
        dailyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? d.dailyGoalMinutes
        timeSlots = try c.decodeIfPresent([TimeSlot].self, forKey: .timeSlots) ?? d.timeSlots
        scheduleFontSize = try c.decodeIfPresent(Double.self, forKey: .scheduleFontSize) ?? d.scheduleFontSize
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        font = (try? c.decodeIfPresent(FontChoice.self, forKey: .font)) ?? d.font
        template = (try? c.decodeIfPresent(ScheduleTemplate.self, forKey: .template)) ?? d.template
        evenWeekAnchor = try c.decodeIfPresent(Date.self, forKey: .evenWeekAnchor) ?? d.evenWeekAnchor
        cellPalette = try c.decodeIfPresent([String].self, forKey: .cellPalette) ?? d.cellPalette
    }
}

extension ScheduleEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        weekday = try c.decode(Int.self, forKey: .weekday)
        slotID = try c.decode(UUID.self, forKey: .slotID)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        kind = try c.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .fixed
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        recurrence = (try? c.decodeIfPresent(Recurrence.self, forKey: .recurrence)) ?? .weekly
        weekStart = try c.decodeIfPresent(Date.self, forKey: .weekStart)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

// MARK: - Color <-> Hex

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    /// True for light colours (yellow, white…) that need dark text on top
    static func isLight(hex: String) -> Bool {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.62
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#888888" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
