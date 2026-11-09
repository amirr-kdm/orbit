import SwiftUI

/// Counting down to the days that matter. The pinned one also shows in the notch (Days tab).
/// Pictures to pick from for an event
struct EmojiChoice: View {
    @Binding var emoji: String
    @State private var open = false
    static let all = ["🎯", "📝", "📚", "🎓", "✈️", "🏆", "🎉", "🎂", "💼", "🧪", "💻", "🎤", "🏁", "🚀", "⭐️", "❤️", "🔥", "📅", "🌙", "🏖️", "🧠", "🩺", "⚽️", "🎮", "🎬", "🎵", "🏠", "💍", "🤖", "🌍"]

    var body: some View {
        Button { open.toggle() } label: {
            Text(emoji).font(.system(size: 22)).frame(width: 44, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
        }
        .buttonStyle(.plain).help("Change the picture")
        .popover(isPresented: $open) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 6), spacing: 6) {
                ForEach(Self.all, id: \.self) { e in
                    Button { emoji = e; open = false } label: {
                        Text(e).font(.system(size: 22)).frame(width: 38, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(e == emoji ? Color.accentColor.opacity(0.25) : .clear))
                    }.buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }
}

/// A few colours to pick from
struct ColorChoice: View {
    @Binding var hex: String
    @State private var open = false
    /// "#RRGGBB" from a colour
    static func hexString(_ c: Color) -> String {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .systemIndigo
        return String(format: "#%02X%02X%02X", Int((n.redComponent * 255).rounded()), Int((n.greenComponent * 255).rounded()), Int((n.blueComponent * 255).rounded()))
    }
    static let all = ["#6366F1", "#EC4899", "#F97316", "#22C55E", "#06B6D4", "#EAB308", "#EF4444", "#A855F7", "#14B8A6", "#64748B"]

    var body: some View {
        Button { open.toggle() } label: {
            Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain).help("Change the colour")
        .popover(isPresented: $open) {
            VStack(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Self.all, id: \.self) { c in
                        Button { hex = c; open = false } label: {
                            Circle().fill(Color(hex: c)).frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.white, lineWidth: c == hex ? 3 : 0))
                        }.buttonStyle(.plain)
                    }
                }
                Divider()
                // any colour you like
                ColorPicker("Custom colour", selection: Binding(get: { Color(hex: hex) }, set: { hex = Self.hexString($0) }), supportsOpacity: false)
                    .font(.callout)
            }
            .padding(14)
        }
    }
}

/// The next / pinned event at the top of the sidebar (turn it off on the Countdown page)
struct SidebarCountdown: View {
    @AppStorage("countdown.sidebar") private var show = true
    @Environment(Router.self) private var router
    @State private var store = CountdownStore.shared

    var body: some View {
        if show, let e = store.shown {
            // minutes are enough here: it redraws once a minute, not every second
            TimelineView(.periodic(from: .now, by: 60)) { t in
                let p = CountdownStore.parts(to: e.date, now: t.date)
                Button { router.selection = .countdown } label: {
                    HStack(spacing: 10) {
                        Text(e.emoji).font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(p.past ? countdownHeadline(e, now: t.date) : String(format: "%dd %02dh %02dm", p.days, p.h, p.m))
                                .font(.system(.caption2, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LinearGradient(colors: [e.color.opacity(0.45), e.color.opacity(0.15)], startPoint: .leading, endPoint: .trailing)))
                    .padding(.horizontal, 10).padding(.top, 4)
                }
                .buttonStyle(.plain)
                .help("Open Countdown")
            }
        }
    }
}

struct CountdownPage: View {
    @AppStorage("countdown.sidebar") private var showInSidebar = true
    @State private var store = CountdownStore.shared
    @State private var title = ""
    @State private var emoji = "🎯"
    @State private var colorHex = "#6366F1"
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                form
                sidebarToggle
                if store.events.isEmpty {
                    Text("No events yet. Add an exam, a trip, a deadline…").foregroundStyle(.secondary).padding(.top, 30)
                }
                VStack(spacing: 12) {
                    ForEach(store.sorted) { e in card(e) }
                }
            }
            .padding(24)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle("Countdown")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New event", systemImage: "hourglass").font(.headline)
            HStack(spacing: 10) {
                EmojiChoice(emoji: $emoji)
                ColorChoice(hex: $colorHex)
                TextField("What are you counting down to?", text: $title).onSubmit(add).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Day and time")
                PersianDatePicker(date: $date)
                Spacer()
                Button("Add", action: add).buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background.secondary))
    }

    private var sidebarToggle: some View {
        Toggle("Show the countdown at the top of the sidebar", isOn: $showInSidebar).toggleStyle(.switch)
    }

    private func card(_ e: CountdownEvent) -> some View {
        let pinned = store.shown?.id == e.id
        return HStack(spacing: 16) {
            EmojiChoice(emoji: Binding(get: { e.emoji }, set: { v in store.setEmoji(e.id, v) }))
            ColorChoice(hex: Binding(get: { e.colorHex }, set: { v in store.setColor(e.id, v) }))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.headline).lineLimit(2)
                Text(PersianDatePicker.text(e.date)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // only this little clock redraws each second, not the whole card or page
            TimelineView(.periodic(from: .now, by: 1)) { t in
                let past = e.date <= t.date
                VStack(alignment: .trailing, spacing: 2) {
                    Text(countdownHeadline(e, now: t.date)).font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(past ? Color.secondary : e.color)
                    if !past { Text(countdownClock(e, now: t.date)).font(.system(.callout, design: .rounded)).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            Button { store.pinned = pinned && store.pinned != nil ? nil : e.id } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").foregroundStyle(pinned ? Color.orange : .secondary)
            }.buttonStyle(.plain).help("Show this one in the notch")
            Button(role: .destructive) { withAnimation { store.remove(e.id) } } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [e.color.opacity(0.40), e.color.opacity(0.10)], startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(e.color.opacity(0.55), lineWidth: 1))
        )
        .opacity(e.date <= Date() ? 0.6 : 1)
    }

    private func add() {
        store.add(title: title, date: date, emoji: emoji, colorHex: colorHex)
        title = ""
    }
}
