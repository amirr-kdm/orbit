import AppKit
import SwiftUI

/// The fixed weekly timetable: days × time slots.
/// Cells marked "To-do" also show up in that day's to-do list.
struct WeeklyScheduleView: View {
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router

    struct CellKey: Hashable {
        let weekday: Int
        let slotID: UUID
    }

    @State private var editing: CellKey?
    @State private var selected: CellKey?
    @State private var hovered: CellKey?
    @State private var draft = ""
    @State private var editColor: String?
    /// Colour and type used for newly typed cells
    @State private var paletteColor: String?
    @State private var newKind: EntryKind = .todo
    @State private var newCategory: UUID?
    @State private var newRecurrence: Recurrence = .weekly
    /// 0 = this week, 1 = next week, -1 = last week…
    @State private var weekOffset = 0

    /// Any date inside the week being viewed
    private var viewDate: Date {
        Cal.persian.date(byAdding: .day, value: 7 * weekOffset, to: Date()) ?? Date()
    }

    private var template: ScheduleTemplate { store.settings.template }
    private var style: TemplateStyle { template.style }
    private var font: FontChoice { store.settings.font }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .navigationTitle("Weekly Schedule")
    }

    private func content(now: Date) -> some View {
        let slots = store.settings.timeSlots.sorted { $0.startMinute < $1.startMinute }
        let today = Cal.weekdayIndex(now)
        let currentSlot = store.currentSlot(at: now)
        let viewDate = self.viewDate

        return ZStack {
            AmbientBackground(style: style)
                .onTapGesture { commitEditing() }

            VStack(spacing: 14) {
                header(now: now, today: today, currentSlot: currentSlot, slots: slots)
                weekBar(viewDate: viewDate)
                board(now: now, viewDate: viewDate, today: weekOffset == 0 ? today : -1,
                      currentSlot: weekOffset == 0 ? currentSlot : nil, slots: slots)
                toolbar
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
        }
        // Never ask for more room than the window has (that pushed the sidebar's account chip around)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
    }

    // MARK: Header

    private func header(now: Date, today: Int, currentSlot: TimeSlot?, slots: [TimeSlot]) -> some View {
        return HStack(alignment: .center, spacing: 16) {
            // Always today's date; the week bar below shows the week being viewed
            PageHeader(page: .schedule, title: Fmt.dualDate(now),
                       subtitle: "Today · \(Fmt.date(now, "EEEE", .gregorian)) · \(store.parity(ofWeek: now).title)")
            ViewThatFits(in: .horizontal) { weekStats; Color.clear.frame(width: 0, height: 0) }
            nowCard(now: now, today: today, currentSlot: currentSlot, slots: slots)
        }
    }

    // MARK: Week bar

    private func weekBar(viewDate: Date) -> some View {
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: viewDate)!
        let last = week.end.addingTimeInterval(-1)
        let kind = store.settings.primaryCalendar
        let parity = store.parity(ofWeek: viewDate)

        return HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button { changeWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 26, height: 22) }
                    .help("Previous week")
                Button { changeWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 26, height: 22) }
                    .help("Next week")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))
            .padding(3)
            .background(Capsule().fill(.regularMaterial))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(Fmt.date(week.start, "MMMM d", kind)) – \(Fmt.date(last, "MMMM d, y", kind))")
                    .font(font.font(size: 17, weight: .semibold))
                Text("\(Fmt.date(week.start, "MMM d", kind.other)) – \(Fmt.date(last, "MMM d, y", kind.other))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(parity == .even ? "EVEN WEEK" : "ODD WEEK")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill((parity == .even ? style.accent : Color.orange).gradient))
                .shadow(color: (parity == .even ? style.accent : Color.orange).opacity(0.35), radius: 6, y: 2)
                .help("Right-click to swap even and odd weeks")
                .contextMenu {
                    Button("Swap Even and Odd Weeks") {
                        store.setParity(parity == .even ? .odd : .even, forWeekOf: viewDate)
                    }
                }

            if weekOffset != 0 {
                Text(weekOffset > 0 ? "\(weekOffset) week\(weekOffset == 1 ? "" : "s") ahead"
                                    : "\(-weekOffset) week\(weekOffset == -1 ? "" : "s") ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Back to This Week") { changeWeek(-weekOffset) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        }
    }

    private func changeWeek(_ delta: Int) {
        commitEditing()
        selected = nil
        withAnimation(.easeInOut(duration: 0.2)) { weekOffset += delta }
    }

    private var weekStats: some View {
        let week = store.entries(inWeekOf: viewDate)
        let todos = week.filter { $0.kind == .todo }.count
        let fixed = week.filter { $0.kind == .fixed }.count
        let planned = week.reduce(0.0) { $0 + (store.slot($1.slotID)?.duration ?? 0) }

        return HStack(spacing: 18) {
            miniStat("\(todos)", "To-dos", "checklist")
            miniStat("\(fixed)", "Fixed", "pin")
            miniStat(Fmt.duration(planned), "Planned", "clock")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func miniStat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Label(label, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func nowCard(now: Date, today: Int, currentSlot: TimeSlot?, slots: [TimeSlot]) -> some View {
        let minute = Cal.minuteOfDay(now)
        let entry = currentSlot.flatMap { store.entry(weekday: today, slotID: $0.id, inWeekOf: now) }
        let next = slots.first { $0.startMinute > minute && store.entry(weekday: today, slotID: $0.id, inWeekOf: now) != nil }
        let active = currentSlot != nil

        return VStack(alignment: .leading, spacing: 6) {
            if let slot = currentSlot {
                let progress = Double(minute - slot.startMinute) / Double(max(1, slot.endMinute - slot.startMinute))
                HStack {
                    Text("NOW · \(slot.title)").font(.system(size: 11, weight: .bold)).tracking(1.2)
                    Spacer()
                    Text("\(slot.endMinute - minute)m left").font(.caption.monospacedDigit())
                }
                .opacity(0.85)
                Text(entry?.title ?? "Free slot")
                    .font(font.font(size: 17, weight: .semibold))
                    .lineLimit(1)
                ProgressView(value: min(1, max(0, progress)))
                    .tint(.white)
                if let entry, entry.kind == .todo {
                    Button {
                        timer.select(.schedule(entry.id))
                        router.selection = .timer
                    } label: {
                        Label("Study now", systemImage: "play.fill").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(timer.isActive)
                }
            } else {
                Text("OUTSIDE SCHEDULE HOURS").font(.system(size: 11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                if let next, let e = store.entry(weekday: today, slotID: next.id, inWeekOf: now) {
                    Text("Next: \(e.title)").font(font.font(size: 16, weight: .semibold)).lineLimit(1)
                    Text("Starts at \(Fmt.slotTime(next.startMinute))").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Nothing else today").font(font.font(size: 16, weight: .semibold))
                    Text("Enjoy the free time ✨").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(active ? Color.white : Color.primary)
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            if active {
                shape.fill(LinearGradient(colors: [style.accent, style.accent.opacity(0.7)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: style.accent.opacity(0.45), radius: 12, y: 5)
            } else {
                shape.fill(.regularMaterial)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
            }
        }
    }

    // MARK: Board

    private func board(now: Date, viewDate: Date, today: Int, currentSlot: TimeSlot?, slots: [TimeSlot]) -> some View {
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: viewDate)!
        let minute = Cal.minuteOfDay(now)

        return Grid(horizontalSpacing: style.spacing, verticalSpacing: style.spacing) {
            GridRow {
                Color.clear.frame(width: 118, height: 1)
                ForEach(slots) { slot in
                    slotHeader(slot, isCurrent: currentSlot?.id == slot.id)
                }
            }
            ForEach(0..<7, id: \.self) { day in
                let date = Cal.persian.date(byAdding: .day, value: day, to: week.start) ?? now
                GridRow {
                    dayLabel(day: day, date: date, isToday: day == today)
                    ForEach(slots) { slot in
                        let key = CellKey(weekday: day, slotID: slot.id)
                        let entry = store.entry(weekday: day, slotID: slot.id, inWeekOf: viewDate)
                        let isNow = day == today && currentSlot?.id == slot.id
                        ScheduleCellView(
                            entry: entry,
                            colorHex: editing == key ? editColor : store.colorHex(of: entry),
                            category: store.category(entry?.categoryID),
                            recurrence: entry?.recurrence,
                            template: template,
                            font: font,
                            fontSize: store.settings.scheduleFontSize,
                            isEditing: editing == key,
                            isSelected: selected == key,
                            isHovered: hovered == key,
                            isNow: isNow,
                            isTodayRow: day == today,
                            isDone: entry.map { $0.kind == .todo && store.isDone(.schedule($0.id), on: date) } ?? false,
                            isSkipped: entry.map { $0.kind == .todo && store.isSkipped(.schedule($0.id), on: date) } ?? false,
                            slotProgress: isNow ? Double(minute - slot.startMinute) / Double(max(1, slot.endMinute - slot.startMinute)) : nil,
                            draft: $draft,
                            onCommit: { commit(key) },
                            onCancel: { cancel(key) },
                            onToggleDone: entry.map { e in { store.tapStatus(.schedule(e.id), on: date) } }
                        )
                        .overlay {
                            // Empty this week, but used in other weeks (e.g. an every-other-week class)
                            if entry == nil && editing != key, let other = otherWeeks(day: day, slotID: slot.id) {
                                Text(other)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .padding(4)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onTapGesture { beginEditing(key) }
                        .onHover { inside in
                            if inside { hovered = key } else if hovered == key { hovered = nil }
                        }
                        .contextMenu { contextMenu(key: key, entry: entry) }
                    }
                }
            }
        }
        .padding(style.fill == .grid ? 14 : 16)
        .background {
            if style.fill != .grid {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// "Odd weeks: Robotics" for a slot that is empty this week but used in other weeks
    private func otherWeeks(day: Int, slotID: UUID) -> String? {
        let others = store.schedule.filter { $0.weekday == day && $0.slotID == slotID && ($0.recurrence == .even || $0.recurrence == .odd) }
        guard !others.isEmpty else { return nil }
        return others.map { "\($0.recurrence.title): \($0.title)" }.joined(separator: "\n")
    }

    private func slotHeader(_ slot: TimeSlot, isCurrent: Bool) -> some View {
        Text(slot.title)
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(isCurrent ? Color.white : Color.secondary)
            .padding(.horizontal, style.pillHeaders ? 10 : 0)
            .padding(.vertical, style.pillHeaders ? 5 : 0)
            .background {
                if style.pillHeaders || isCurrent {
                    Capsule().fill(isCurrent ? AnyShapeStyle(style.accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
    }

    private func dayLabel(day: Int, date: Date, isToday: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Cal.weekdayNames[day])
                .font(font.font(size: 14, weight: .semibold))
            Text(Fmt.date(date, "MMM d", store.settings.primaryCalendar))
                .font(.caption2)
                .opacity(0.7)
        }
        .foregroundStyle(isToday ? Color.white : (day == 6 ? Color.red.opacity(0.85) : Color.primary))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.accent.gradient)
                    .shadow(color: style.accent.opacity(0.4), radius: 6, y: 2)
            }
        }
        .frame(width: 118, alignment: .trailing)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        @Bindable var store = store
        // Scrolls sideways when the window is narrow, so it never squeezes the sidebar
        return ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) {
            HStack(spacing: 12) {
                CellPaletteBar(selection: editing != nil ? editColor : (selectedEntry?.colorHex ?? paletteColor),
                               onPick: applyColor)

                divider

                Picker("Type", selection: kindBinding) {
                    Label("Fixed", systemImage: "pin").tag(EntryKind.fixed)
                    Label("To-do", systemImage: "checklist").tag(EntryKind.todo)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help("To-do cells also appear in that day's to-do list")

                Menu {
                    Picker("Category", selection: categoryBinding) {
                        Text("No category").tag(UUID?.none)
                        ForEach(store.orderedCategories) { c in
                            Label { Text(store.categoryLabel(c.id) ?? c.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(c.color) }
                                .tag(Optional(c.id))
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Manage Categories…") { router.selection = .settings }
                } label: {
                    Label(store.categoryLabel(categoryBinding.wrappedValue) ?? "Category", systemImage: "tag")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Category of the selected cell (and of new cells)")

                Menu {
                    Picker("Repeat", selection: recurrenceBinding) {
                        ForEach(Recurrence.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(recurrenceBinding.wrappedValue.title, systemImage: recurrenceBinding.wrappedValue.icon)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Which weeks the selected cell (and new cells) appear in")

                divider

                HStack(spacing: 6) {
                    Button { store.settings.scheduleFontSize = max(10, store.settings.scheduleFontSize - 1) } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(.borderless)
                    .help("Smaller text")
                    Slider(value: Binding(get: { store.settings.scheduleFontSize },
                                          set: { store.settings.scheduleFontSize = $0.rounded() }),
                           in: 10...28)
                        .frame(width: 90)
                        .controlSize(.small)
                    Button { store.settings.scheduleFontSize = min(28, store.settings.scheduleFontSize + 1) } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .buttonStyle(.borderless)
                    .help("Larger text")
                    Text("\(Int(store.settings.scheduleFontSize))pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }

                divider

                Menu {
                    Picker("Template", selection: $store.settings.template) {
                        ForEach(ScheduleTemplate.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(template.title, systemImage: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Design template")

                Menu {
                    Picker("Appearance", selection: $store.settings.appearance) {
                        ForEach(Appearance.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: store.settings.appearance.icon)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Light / Dark mode")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)

            Text("Click a cell to type · ⏎ saves · ⇧⏎ new line · esc cancels")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
                .help("Right-click a cell to change its type or colour, clear it, or study it now")
        }
        .padding(.vertical, 12).padding(.horizontal, 4)
        }
        .padding(.vertical, -12)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20)
    }

    // MARK: Context menu

    @ViewBuilder
    private func contextMenu(key: CellKey, entry: ScheduleEntry?) -> some View {
        Button("Edit") { beginEditing(key) }
        if let entry {
            Picker("Type", selection: Binding(
                get: { entry.kind },
                set: { k in store.updateEntry(entry.id) { $0.kind = k } }
            )) {
                ForEach(EntryKind.allCases) { Text($0.title).tag($0) }
            }
            Picker("Repeat", selection: Binding(
                get: { entry.recurrence },
                set: { r in store.setRecurrence(r, for: entry.id, viewingWeekOf: viewDate) }
            )) {
                ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
            }
            Picker("Category", selection: Binding(
                get: { entry.categoryID },
                set: { id in store.updateEntry(entry.id) { $0.categoryID = id } }
            )) {
                Text("No category").tag(UUID?.none)
                ForEach(store.orderedCategories) { Text(store.categoryLabel($0.id) ?? $0.name).tag(Optional($0.id)) }
            }
            Menu("Colour") {
                Button("Template colour") { store.updateEntry(entry.id) { $0.colorHex = nil } }
                ForEach(store.settings.cellPalette, id: \.self) { hex in
                    Button(hex) { store.updateEntry(entry.id) { $0.colorHex = hex } }
                }
            }
            if entry.kind == .todo {
                Divider()
                StatusMenuItems(ref: .schedule(entry.id), day: store.occurrence(of: entry, inWeekOf: viewDate))
                Button("Study This Now") {
                    timer.select(.schedule(entry.id))
                    router.selection = .timer
                }
            }
            Divider()
            Button("Clear Cell", role: .destructive) {
                store.deleteEntry(entry.id)
                if selected == key { selected = nil }
            }
        }
    }

    // MARK: Editing

    private var selectedEntry: ScheduleEntry? {
        selected.flatMap { store.entry(weekday: $0.weekday, slotID: $0.slotID, inWeekOf: viewDate) }
    }

    private var kindBinding: Binding<EntryKind> {
        Binding(
            get: { selectedEntry?.kind ?? newKind },
            set: { k in
                newKind = k
                if let e = selectedEntry { store.updateEntry(e.id) { $0.kind = k } }
            }
        )
    }

    private var recurrenceBinding: Binding<Recurrence> {
        Binding(
            get: { selectedEntry?.recurrence ?? newRecurrence },
            set: { r in
                newRecurrence = r
                if let e = selectedEntry { store.setRecurrence(r, for: e.id, viewingWeekOf: viewDate) }
            }
        )
    }

    private var categoryBinding: Binding<UUID?> {
        Binding(
            get: { selectedEntry?.categoryID ?? newCategory },
            set: { id in
                newCategory = id
                if let e = selectedEntry { store.updateEntry(e.id) { $0.categoryID = id } }
            }
        )
    }

    private func beginEditing(_ key: CellKey) {
        if editing == key { return }
        commitEditing()
        let entry = store.entry(weekday: key.weekday, slotID: key.slotID, inWeekOf: viewDate)
        draft = entry?.text ?? ""
        editColor = entry == nil ? paletteColor : entry?.colorHex
        selected = key
        editing = key
    }

    private func commitEditing() {
        if let editing { commit(editing) }
    }

    private func commit(_ key: CellKey) {
        // Ignore late callbacks from an editor that is already gone
        guard editing == key else { return }
        store.setCell(weekday: key.weekday, slotID: key.slotID, weekOf: viewDate, text: draft,
                      colorHex: editColor, kind: newKind, categoryID: newCategory, recurrence: newRecurrence)
        editing = nil
    }

    private func cancel(_ key: CellKey) {
        guard editing == key else { return }
        editing = nil
    }

    private func applyColor(_ hex: String?) {
        paletteColor = hex
        if editing != nil {
            editColor = hex
        } else if let e = selectedEntry {
            store.updateEntry(e.id) { $0.colorHex = hex }
        }
    }
}

// MARK: - Cell

/// One cell of the schedule, drawn in the style of the chosen template
struct ScheduleCellView: View {
    let entry: ScheduleEntry?
    let colorHex: String?
    var category: Category?
    var recurrence: Recurrence?
    let template: ScheduleTemplate
    let font: FontChoice
    let fontSize: Double
    var isEditing = false
    var isSelected = false
    var isHovered = false
    var isNow = false
    var isTodayRow = false
    var isDone = false
    var isSkipped = false
    var slotProgress: Double?
    var draft: Binding<String> = .constant("")
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onToggleDone: (() -> Void)?
    var minHeight: CGFloat = 54
    var showBadge = true

    private var style: TemplateStyle { template.style }
    private var hasContent: Bool { entry != nil || isEditing }
    private var hex: String { colorHex ?? template.defaultCellColor }
    private var color: Color { Color(hex: hex) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: style.corner, style: .continuous) }

    private var textColor: Color {
        guard hasContent else { return .primary }
        switch style.fill {
        case .gradient: return Color.isLight(hex: hex) ? Color.black.opacity(0.8) : .white
        case .neon: return color
        default: return .primary
        }
    }

    private var nsTextColor: NSColor {
        switch style.fill {
        case .gradient: return Color.isLight(hex: hex) ? NSColor.black.withAlphaComponent(0.85) : .white
        case .neon: return NSColor(color)
        default: return .labelColor
        }
    }

    var body: some View {
        ZStack {
            background

            if isEditing {
                CellTextEditor(text: draft,
                               font: font.nsFont(size: fontSize, weight: .semibold),
                               textColor: nsTextColor,
                               onCommit: onCommit,
                               onCancel: onCancel)
                    .padding(4)
            } else if let entry {
                VStack(spacing: 3) {
                    Text(entry.text)
                        .font(font.font(size: fontSize, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .strikethrough(isDone || isSkipped)
                        .minimumScaleFactor(0.5)
                        .lineLimit(5)
                    if let category {
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill").font(.system(size: max(7, fontSize * 0.5)))
                            Text(category.name).lineLimit(1)
                        }
                        .font(.system(size: max(9, fontSize * 0.68), weight: .medium))
                        .opacity(0.75)
                    }
                }
                .foregroundStyle(textColor)
                .opacity(isDone || isSkipped ? 0.6 : 1)
                .padding(.top, showBadge && recurrence?.badge != nil ? 10 : 0)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if showBadge { badge(entry) }
            } else if isHovered {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style.accent.opacity(0.8))
            }

            if let slotProgress {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Capsule().fill(textColor.opacity(0.18))
                            .overlay(alignment: .leading) {
                                Capsule().fill(hasContent ? textColor.opacity(0.85) : style.accent)
                                    .frame(width: geo.size.width * min(1, max(0, slotProgress)))
                            }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
        .overlay {
            if style.fill == .grid {
                Rectangle().stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
            }
        }
        .overlay {
            if isNow {
                shape.strokeBorder(style.accent, lineWidth: 2.5)
                    .shadow(color: style.accent, radius: 8)
                    .phaseAnimator([0.45, 1.0]) { view, phase in view.opacity(phase) } animation: { _ in
                        .easeInOut(duration: 1.3)
                    }
            } else if isEditing || isSelected {
                shape.strokeBorder(style.accent, lineWidth: 2)
            }
        }
        .shadow(color: style.shadow && hasContent ? color.opacity(0.3) : .clear, radius: 6, y: 3)
        .scaleEffect(isHovered && hasContent && !isEditing && style.fill != .grid ? 1.03 : 1)
        .animation(.spring(duration: 0.25), value: isHovered)
        .contentShape(shape)
    }

    @ViewBuilder
    private var background: some View {
        if !hasContent {
            if style.fill == .grid {
                Rectangle().fill(isTodayRow ? style.accent.opacity(0.07) : Color(nsColor: .controlBackgroundColor))
            } else {
                shape.fill(isTodayRow ? style.accent.opacity(0.08) : Color.primary.opacity(0.035))
                    .overlay(shape.strokeBorder(isHovered ? style.accent.opacity(0.6) : Color.primary.opacity(0.08),
                                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
        } else {
            switch style.fill {
            case .gradient:
                shape.fill(LinearGradient(colors: [color, color.opacity(0.72)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            case .tint:
                shape.fill(color.opacity(0.22))
                    .overlay(shape.strokeBorder(color.opacity(0.4), lineWidth: 1))
            case .neon:
                shape.fill(color.opacity(0.08))
                    .overlay(shape.strokeBorder(color, lineWidth: 1.5))
                    .shadow(color: color.opacity(0.7), radius: 6)
            case .card:
                shape.fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 5) }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
            case .glass:
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(color.opacity(0.28)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            case .grid:
                Rectangle().fill(color.opacity(0.3))
            }
        }
    }

    /// Pin for fixed cells, a tickable circle for to-dos
    @ViewBuilder
    private func badge(_ entry: ScheduleEntry) -> some View {
        let icon = entry.kind == .fixed ? "pin.fill" : (isSkipped ? "xmark.circle.fill" : (isDone ? "checkmark.circle.fill" : "circle"))
        let image = Image(systemName: icon)
            .font(.system(size: entry.kind == .fixed ? 8 : 11, weight: .semibold))
            .foregroundStyle(isSkipped ? Color.orange : (isDone ? Color.green : textColor.opacity(0.65)))
            .rotationEffect(.degrees(entry.kind == .fixed ? 45 : 0))
        VStack {
            HStack {
                if let badge = recurrence?.badge {
                    Text(badge)
                        .font(.system(size: 7.5, weight: .heavy))
                        .tracking(0.6)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(textColor.opacity(0.18)))
                        .foregroundStyle(textColor.opacity(0.85))
                        .help(recurrence?.title ?? "")
                }
                Spacer()
                if entry.kind == .todo, let onToggleDone {
                    Button(action: onToggleDone) { image }
                        .buttonStyle(.plain)
                        .help(isDone ? "Mark as not done" : "Mark as done for this day")
                } else {
                    image.help(entry.kind == .fixed ? "Fixed" : "To-do")
                }
            }
            Spacer()
        }
        .padding(6)
    }
}

// MARK: - Editor

/// Multi-line cell editor, text centred both ways.
/// Enter saves, Shift+Enter inserts a new line, Esc cancels.
struct CellTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CenteredTextView {
        let tv = CenteredTextView(frame: .zero)
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
        tv.font = font
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        tv.string = text
        tv.alignment = .center
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            tv.recenter()
        }
        return tv
    }

    func updateNSView(_ tv: CenteredTextView, context: Context) {
        context.coordinator.parent = self
        if tv.string != text { tv.string = text }
        if tv.font != font { tv.font = font }
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        tv.alignment = .center
        tv.recenter()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CellTextEditor
        private var finished = false

        init(_ parent: CellTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    finish(commit: true)
                }
                return true
            case #selector(NSResponder.insertLineBreak(_:)):
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish(commit: false)
                return true
            default:
                return false
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            finish(commit: true)
        }

        private func finish(commit: Bool) {
            guard !finished else { return }
            finished = true
            commit ? parent.onCommit() : parent.onCancel()
        }
    }
}

/// NSTextView that keeps its text vertically centred in its frame
final class CenteredTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recenter()
    }

    override func didChangeText() {
        super.didChangeText()
        recenter()
    }

    func recenter() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let top = max(2, (bounds.height - used) / 2)
        if abs(textContainerInset.height - top) > 0.5 {
            textContainerInset = NSSize(width: 4, height: top)
        }
    }
}
