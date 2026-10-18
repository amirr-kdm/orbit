import Foundation

/// Which calendar is primary: Persian (Jalali) or Gregorian
enum CalendarKind: String, Codable, CaseIterable, Identifiable {
    case persian, gregorian

    var id: String { rawValue }
    var title: String { self == .persian ? "Persian" : "Gregorian" }
    var other: CalendarKind { self == .persian ? .gregorian : .persian }
    var calendar: Calendar { self == .persian ? Cal.persian : Cal.gregorian }
}

enum Cal {
    static let locale = Locale(identifier: "en_US")
    static let persian = make(.persian)
    static let gregorian = make(.gregorian)

    /// Week starts on Saturday
    static let weekdayNames = ["Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    static let weekdayShort = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]

    private static func make(_ id: Calendar.Identifier) -> Calendar {
        var c = Calendar(identifier: id)
        c.locale = locale
        c.firstWeekday = 7 // Saturday
        c.minimumDaysInFirstWeek = 1
        c.timeZone = .current
        return c
    }

    static func isFriday(_ date: Date) -> Bool {
        persian.component(.weekday, from: date) == 6
    }

    /// 0 = Saturday … 6 = Friday
    static func weekdayIndex(_ date: Date) -> Int {
        (persian.component(.weekday, from: date) - persian.firstWeekday + 7) % 7
    }

    /// Minutes since midnight
    static func minuteOfDay(_ date: Date) -> Int {
        let c = persian.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Saturday that starts the week containing `date`
    static func weekStart(_ date: Date) -> Date {
        persian.dateInterval(of: .weekOfYear, for: date)?.start ?? persian.startOfDay(for: date)
    }

    /// Whole weeks from `from` to `to` (negative when going back)
    static func weeksBetween(_ from: Date, _ to: Date) -> Int {
        let days = persian.dateComponents([.day], from: weekStart(from), to: weekStart(to)).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    /// Stable key for a calendar day, e.g. "2026-10-18"
    static func dayKey(_ date: Date) -> String {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension Calendar {
    /// Start of every day in an interval
    func days(in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var d = startOfDay(for: interval.start)
        while d < interval.end {
            result.append(d)
            guard let next = date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return result
    }

    func dayInterval(_ date: Date) -> DateInterval {
        dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86400)
    }
}

enum Fmt {
    private static var cache: [String: DateFormatter] = [:]

    static func date(_ date: Date, _ format: String, _ kind: CalendarKind) -> String {
        let key = "\(kind.rawValue)|\(format)"
        if let f = cache[key] { return f.string(from: date) }
        let f = DateFormatter()
        f.calendar = kind.calendar
        f.locale = Cal.locale
        f.dateFormat = format
        cache[key] = f
        return f.string(from: date)
    }

    static func time(_ date: Date) -> String { Self.date(date, "HH:mm", .gregorian) }

    /// "Sunday, Mehr 26, 1405"
    static func fullDate(_ date: Date, _ kind: CalendarKind) -> String {
        Self.date(date, "EEEE, MMMM d, y", kind)
    }

    /// "Mehr 26 — October 18"
    static func dualDate(_ date: Date) -> String {
        "\(Self.date(date, "MMMM d", .persian)) — \(Self.date(date, "MMMM d", .gregorian))"
    }

    static func num(_ n: Int) -> String { "\(n)" }

    /// "01:23:45" / "23:45"
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// "2h 15m"
    static func duration(_ t: TimeInterval) -> String {
        let mins = Int(t / 60)
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "2:15"
    static func shortDuration(_ t: TimeInterval) -> String {
        let mins = Int(t / 60)
        return String(format: "%d:%02d", mins / 60, mins % 60)
    }

    /// Minutes since midnight → "8", "9:30"
    static func slotTime(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)" : String(format: "%d:%02d", h, m)
    }
}
