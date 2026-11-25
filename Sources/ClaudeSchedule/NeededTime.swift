import SwiftUI

/// The time a to-do needs (set when it is created or edited) and how much of it is already studied
extension AppStore {
    func neededMinutes(for ref: TodoRef) -> Int? {
        switch ref {
        case .schedule(let id): return entry(id)?.minutes
        case .task(let id): return task(id)?.needMinutes
        }
    }

    /// Seconds studied on it: a task counts all its sessions, a weekly to-do only the sessions of that day
    func studiedSeconds(for ref: TodoRef, on day: Date) -> TimeInterval {
        switch ref {
        case .task(let id):
            return sessions.filter { $0.taskID == id }.reduce(0) { $0 + $1.duration }
        case .schedule(let id):
            return sessions.filter { $0.scheduleEntryID == id && Cal.persian.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.duration }
        }
    }

    /// How long a Pomodoro focus should be for it: the time it needs, or what is left of it after earlier sessions (at most 3 hours)
    func focusMinutes(for ref: TodoRef, on day: Date = Date()) -> Int? {
        guard let need = neededMinutes(for: ref) else { return nil }
        let done = Int(studiedSeconds(for: ref, on: day) / 60)
        return min(180, max(1, done > 0 && done < need ? need - done : need))
    }
}

/// A thin bar with "studied / needed" minutes
struct NeedProgress: View {
    let studied: TimeInterval
    let needed: Int

    var body: some View {
        let total = Double(max(1, needed) * 60), frac = min(1, studied / total)
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if frac > 0 { Capsule().fill(frac >= 1 ? Color.green : Color.accentColor).frame(width: max(5, g.size.width * frac)) }
                }
            }
            .frame(height: 5)
            Text("\(Int(studied / 60))/\(needed)m").font(.system(size: 9, weight: .semibold)).monospacedDigit()
                .foregroundStyle(frac >= 1 ? Color.green : Color.secondary).fixedSize()
        }
    }
}
