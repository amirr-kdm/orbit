import SwiftUI

/// A date you are counting down to (an exam, a trip…). Kept on this Mac in the app's settings.
struct CountdownEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var emoji = "🎯"
    /// The colour of its card, sidebar chip and notch tab
    var colorHex = "#6366F1"

    init(title: String, date: Date, emoji: String = "🎯", colorHex: String = "#6366F1") {
        self.title = title; self.date = date; self.emoji = emoji; self.colorHex = colorHex
    }

    // events saved before colours existed have no colour: they get the default one
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🎯"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#6366F1"
    }
    var color: Color { Color(hex: colorHex) }
}

@MainActor @Observable
final class CountdownStore {
    static let shared = CountdownStore()
    private let key = "countdown.events", pinKey = "countdown.pinned"

    var events: [CountdownEvent] = [] { didSet { save() } }
    /// The one the notch shows (nil = the next one coming)
    var pinned: UUID? { didSet { UserDefaults.standard.set(pinned?.uuidString, forKey: pinKey) } }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let e = try? JSONDecoder().decode([CountdownEvent].self, from: d) { events = e }
        pinned = UserDefaults.standard.string(forKey: pinKey).flatMap(UUID.init(uuidString:))
    }

    private func save() {
        if let d = try? JSONEncoder().encode(events) { UserDefaults.standard.set(d, forKey: key) }
        NotificationCenter.default.post(name: .orbitDataSaved, object: nil)
    }

    func add(title: String, date: Date, emoji: String, colorHex: String = "#6366F1") {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        events.append(CountdownEvent(title: t, date: date, emoji: emoji.isEmpty ? "🎯" : emoji, colorHex: colorHex))
    }

    func setEmoji(_ id: UUID, _ emoji: String) {
        if let i = events.firstIndex(where: { $0.id == id }) { events[i].emoji = emoji }
    }

    func setColor(_ id: UUID, _ hex: String) {
        if let i = events.firstIndex(where: { $0.id == id }) { events[i].colorHex = hex }
    }

    func remove(_ id: UUID) {
        events.removeAll { $0.id == id }
        if pinned == id { pinned = nil }
    }

    /// Soonest first, events already past at the end
    var sorted: [CountdownEvent] {
        let now = Date()
        return events.sorted { a, b in
            let pa = a.date < now, pb = b.date < now
            return pa != pb ? !pa : a.date < b.date
        }
    }

    /// What the notch shows: the pinned one, else the next one coming
    var shown: CountdownEvent? {
        if let p = pinned, let e = events.first(where: { $0.id == p }) { return e }
        return sorted.first { $0.date >= Date() } ?? sorted.first
    }

    /// 12 days 04:33:10
    nonisolated static func parts(to date: Date, now: Date = Date()) -> (days: Int, h: Int, m: Int, s: Int, past: Bool) {
        let past = date <= now
        let secs = Int(abs(date.timeIntervalSince(now)))
        return (secs / 86400, secs % 86400 / 3600, secs % 3600 / 60, secs % 60, past)
    }
}

/// "12 days" / "Today" / "3 days ago"
func countdownHeadline(_ e: CountdownEvent, now: Date = Date()) -> String {
    let p = CountdownStore.parts(to: e.date, now: now)
    if p.past { return p.days == 0 ? "Happening now" : "\(p.days) day\(p.days == 1 ? "" : "s") ago" }
    return p.days == 0 ? "Today" : "\(p.days) day\(p.days == 1 ? "" : "s")"
}

func countdownClock(_ e: CountdownEvent, now: Date = Date()) -> String {
    let p = CountdownStore.parts(to: e.date, now: now)
    return String(format: "%02d:%02d:%02d", p.h, p.m, p.s)
}
