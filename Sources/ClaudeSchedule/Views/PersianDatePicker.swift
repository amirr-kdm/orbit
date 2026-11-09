import SwiftUI

/// A Persian (Shamsi) date and time picker: month names in Persian, weeks start on Saturday, right to left.
struct PersianDatePicker: View {
    @Binding var date: Date
    @State private var open = false
    @State private var year = 1405
    @State private var month = 1

    private static let cal: Calendar = { var c = Calendar(identifier: .persian); c.locale = Locale(identifier: "fa_IR"); return c }()
    static let months = ["Farvardin", "Ordibehesht", "Khordad", "Tir", "Mordad", "Shahrivar", "Mehr", "Aban", "Azar", "Dey", "Bahman", "Esfand"]
    private static let weekdays = ["Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    private var cal: Calendar { Self.cal }

    /// 1405/08/24 · 01:34
    static func text(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d)
        let wd = weekdays[((c.weekday ?? 7) % 7)]
        // numbers first, in left-to-right marks so the Persian weekday cannot reorder them
        return String(format: "\u{200E}%04d/%02d/%02d\u{200E}  ·  %@  ·  \u{200E}%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, wd, c.hour ?? 0, c.minute ?? 0)
    }

    var body: some View {
        Button { sync(); open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(Self.text(date)).monospacedDigit().environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { picker }
    }

    private func sync() {
        let c = cal.dateComponents([.year, .month], from: date)
        year = c.year ?? 1405; month = c.month ?? 1
    }

    private var daysInMonth: Int {
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
        return cal.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    /// empty cells before the 1st (the week starts on Saturday)
    private var lead: Int {
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return cal.component(.weekday, from: first) % 7
    }

    private func move(_ by: Int) {
        var m = month + by, y = year
        if m > 12 { m = 1; y += 1 } else if m < 1 { m = 12; y -= 1 }
        month = m; year = y
    }

    private var picker: some View {
        let cur = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let today = cal.dateComponents([.year, .month, .day], from: Date())
        return VStack(spacing: 12) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                Spacer()
                Text("\(Self.months[month - 1]) \(year)").font(.headline)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
            }
            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(1...daysInMonth, id: \.self) { d in
                    let selected = cur.year == year && cur.month == month && cur.day == d
                    let isToday = today.year == year && today.month == month && today.day == d
                    Button { pick(d) } label: {
                        Text("\(d)").font(.callout.weight(selected ? .bold : .regular)).monospacedDigit()
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(Circle().fill(selected ? Color.accentColor : .clear).frame(width: 30))
                            .overlay(Circle().strokeBorder(isToday && !selected ? Color.accentColor : .clear, lineWidth: 1.5).frame(width: 30))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { cur.hour ?? 0 }, set: { setTime(hour: $0, minute: nil) })) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }.labelsHidden().frame(width: 70)
                Text(":")
                Picker("", selection: Binding(get: { cur.minute ?? 0 }, set: { setTime(hour: nil, minute: $0) })) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }.labelsHidden().frame(width: 70)
                Spacer()
                Button("Today") { date = Date(); sync() }.controlSize(.small)
            }
        }
        .padding(16).frame(width: 300)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    private func pick(_ day: Int) {
        let t = cal.dateComponents([.hour, .minute], from: date)
        if let d = cal.date(from: DateComponents(year: year, month: month, day: day, hour: t.hour, minute: t.minute)) { date = d }
    }

    private func setTime(hour: Int?, minute: Int?) {
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if let hour { c.hour = hour }
        if let minute { c.minute = minute }
        if let d = cal.date(from: c) { date = d }
    }
}
