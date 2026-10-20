import SwiftUI

/// Days in a row with study. Missed days are covered by streak freezes: 3 a month,
/// used automatically (one day or several in a row), so one bad day doesn't break the streak.
struct StreakInfo: Equatable {
    /// Days studied in the current streak (frozen days keep it alive but don't add to it)
    let days: Int
    /// Missed days covered by a freeze
    let frozen: [Date]
    /// Freezes still unused this month
    let freezesLeft: Int

    static let freezesPerMonth = 3

    /// `studied(day)` says whether any study happened that day
    static func compute(today: Date = Date(), studied: (Date) -> Bool) -> StreakInfo {
        let cal = Cal.persian
        func monthKey(_ d: Date) -> Int { let c = cal.dateComponents([.year, .month], from: d); return (c.year ?? 0) * 100 + (c.month ?? 0) }
        var day = cal.startOfDay(for: today)
        // Today isn't over yet: an empty today doesn't break (or freeze) anything
        if !studied(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var days = 0
        var frozen: [Date] = []
        var pending: [Date] = []          // frozen days not yet backed by an earlier study day
        var used: [Int: Int] = [:]
        for _ in 0..<3650 {
            if studied(day) {
                days += 1
                frozen += pending
                pending = []
            } else {
                let k = monthKey(day)
                guard (used[k] ?? 0) < freezesPerMonth else { break }
                used[k, default: 0] += 1
                pending.append(day)
            }
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        // Freezes spent past the start of the streak don't count
        var spent: [Int: Int] = [:]
        for d in frozen { spent[monthKey(d), default: 0] += 1 }
        let left = max(0, freezesPerMonth - (spent[monthKey(today)] ?? 0))
        return StreakInfo(days: days, frozen: frozen, freezesLeft: left)
    }
}

extension AppStore {
    var streakInfo: StreakInfo { StreakInfo.compute { studyTime(on: $0) > 0 } }
}

/// The streak lightning bolt (Resources/streak.png)
struct StreakIcon: View {
    var size: CGFloat = 16
    static let image: NSImage? = Bundle.main.url(forResource: "streak", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let img = Self.image {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Text("⚡️").font(.system(size: size * 0.8))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Bolt + number, e.g. on leaderboards
struct StreakBadge: View {
    let days: Int
    var size: CGFloat = 15
    var body: some View {
        HStack(spacing: 2) {
            StreakIcon(size: size)
            Text("\(days)").font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}
