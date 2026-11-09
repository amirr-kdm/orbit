import SwiftUI

struct SettingsView: View {
    @AppStorage("leitner.showInMenuBar") private var showWordsInMenuBar = true
    @Environment(AppStore.self) private var store
    @State private var deletingCategory: Category?
    @State private var deletingSlot: TimeSlot?
    @AppStorage("settings.tab") private var tab = SettingsTab.look
    @Namespace private var tabNS

    enum SettingsTab: String, CaseIterable, Identifiable {
        case look = "Look", schedule = "Schedule", categories = "Categories", timer = "Timer", words = "Words", data = "Data"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .look: "paintpalette.fill"
            case .schedule: "tablecells"
            case .categories: "tag.fill"
            case .timer: "timer"
            case .words: "archivebox.fill"
            case .data: "externaldrive.fill"
            }
        }
    }

    /// The bar that picks which group of settings is on screen
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { t in
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { tab = t } } label: {
                    Label(t.rawValue, systemImage: t.icon).font(.callout.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(tab == t ? Color.white : Color.secondary)
                        .background { if tab == t { Capsule().fill(store.settings.template.style.accent.gradient).matchedGeometryEffect(id: "settingsTab", in: tabNS) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(Capsule().fill(Color.primary.opacity(0.07)))
        .frame(maxWidth: .infinity)
        .padding(.top, 14).padding(.bottom, 4)
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            tabBar
        Form {
            if tab == .look {
                Section("Appearance") {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.settings.appearance == .system ? "Following your Mac" : store.settings.appearance == .dark ? "Dark mode" : "Light mode").font(.headline)
                            Text("Press the switch to change between light and dark.").font(.caption).foregroundStyle(.secondary)
                            Toggle("Match macOS automatically", isOn: Binding(
                                get: { store.settings.appearance == .system },
                                set: { on in store.settings.appearance = on ? .system : (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light) }
                            ))
                            .toggleStyle(.switch).controlSize(.small).fixedSize()
                        }
                        Spacer()
                        DayNightToggle()
                    }
                    .padding(.vertical, 6)
                }
            }

            if tab == .look {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                        ForEach(ScheduleTemplate.allCases) { t in
                            TemplateCard(template: t, font: store.settings.font,
                                         isSelected: store.settings.template == t) {
                                withAnimation(.spring(duration: 0.3)) { store.settings.template = t }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Template")
                } footer: {
                    Text("Changes the look of the weekly schedule and the app's accent colour.")
                }
            }

            if tab == .look {
                Section {
                    Picker("Font", selection: $store.settings.font) {
                        Section("Whole app") {
                            ForEach(FontChoice.allCases.filter(\.isSystemDesign)) { f in
                                Text(f.title).font(f.font(size: 13)).tag(f)
                            }
                        }
                        Section("Weekly schedule") {
                            ForEach(FontChoice.allCases.filter { !$0.isSystemDesign }) { f in
                                Text(f.title).font(f.font(size: 13)).tag(f)
                            }
                        }
                    }
                    Stepper(value: $store.settings.scheduleFontSize, in: 10...28) {
                        LabeledContent("Cell text size", value: "\(Int(store.settings.scheduleFontSize)) pt")
                    }
                    HStack(spacing: 10) {
                        ForEach(["Math 2", "Physics class\nRoom 204", "English (TOEFL)"], id: \.self) { sample in
                            ScheduleCellView(entry: ScheduleEntry(weekday: 0, slotID: UUID(), text: sample, kind: .todo),
                                             colorHex: nil, template: store.settings.template,
                                             font: store.settings.font, fontSize: store.settings.scheduleFontSize,
                                             minHeight: 70)
                        }
                    }
                    .frame(height: 76)
                    .drawingGroup()
                    .allowsHitTesting(false)
                } header: {
                    Text("Font")
                } footer: {
                    Text("SF fonts change the whole app. Other fonts style the weekly schedule (cells, days and header).")
                }
            }

            if tab == .look {
                Section("Calendar") {
                    Picker("Primary calendar", selection: $store.settings.primaryCalendar) {
                        ForEach(CalendarKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("The other calendar is always shown alongside.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if tab == .schedule {
                Section {
                    ForEach($store.settings.timeSlots) { $slot in
                        HStack {
                            DatePicker("From", selection: minuteBinding($slot.startMinute), displayedComponents: .hourAndMinute)
                            DatePicker("To", selection: minuteBinding($slot.endMinute), displayedComponents: .hourAndMinute)
                            Spacer()
                            Button(role: .destructive) {
                                deletingSlot = slot
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    HStack {
                        Text("Weekly schedule time slots")
                        Spacer()
                        Button("Reset to Default") {
                            store.schedule.removeAll()
                            store.settings.timeSlots = TimeSlot.defaults
                        }
                        .buttonStyle(.borderless)
                        .help("Restores the default slots and clears the schedule")
                        Button {
                            let last = store.settings.timeSlots.map(\.endMinute).max() ?? 8 * 60
                            let start = min(last + 30, 23 * 60)
                            store.settings.timeSlots.append(TimeSlot(startMinute: start, endMinute: min(start + 90, 24 * 60 - 1)))
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if tab == .timer {
                Section("Timer & goal") {
                    Stepper(value: $store.settings.pomodoroMinutes, in: 1...180) {
                        LabeledContent("Pomodoro focus", value: "\(store.settings.pomodoroMinutes) min")
                    }
                    Stepper(value: $store.settings.breakMinutes, in: 1...60) {
                        LabeledContent("Break", value: "\(store.settings.breakMinutes) min")
                    }
                    Stepper(value: $store.settings.dailyGoalMinutes, in: 15...960, step: 15) {
                        LabeledContent("Daily study goal",
                                       value: Fmt.duration(TimeInterval(store.settings.dailyGoalMinutes * 60)))
                    }
                }
            }

            if tab == .words {
                Section("Leitner words") {
                    LeitnerVoicePicker()
                    Text("The voice that reads your words aloud (pronunciation button and spelling practice). Voices marked Enhanced or Premium sound best: download more in System Settings → Accessibility → Spoken Content → System voice → Manage Voices.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(isOn: $showWordsInMenuBar) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show today's word count in the menu bar")
                            Text("A small 📖 number at the top of your screen with the words you reviewed today. Turn it off if you don't want it there.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if tab == .timer {
                Section("Timer sound") {
                    Picker("Alarm sound", selection: $store.settings.alarmSound) {
                        ForEach(TimerEngine.alarmSounds, id: \.self) { Text($0).tag($0) }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: store.settings.alarmVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 22)
                        Slider(value: $store.settings.alarmVolume, in: 0...1)
                        Text("\(Int((store.settings.alarmVolume * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                        Button("Test") { TimerEngine.playAlarm(sound: store.settings.alarmSound, volume: store.settings.alarmVolume) }
                    }
                    Text("Played when a Pomodoro focus or break ends. You also get a macOS notification, so you notice it when Orbit is in the background.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if tab == .timer {
                Section("Still-studying check") { AwakeCheckSettings() }
                Section("Pause in chosen apps") { PauseAppsSettings() }
            }

            if tab == .categories {
                Section {
                    Toggle(isOn: $store.settings.categoryColors) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("To-dos use their category's colour")
                            Text("On: a to-do with a category shows the category's colour in the schedule, Today and Tasks. Off: each cell keeps its own colour.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(store.orderedCategories) { cat in
                        HStack {
                            if cat.parentID != nil {
                                Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary).padding(.leading, 14)
                            }
                            ColorPicker("", selection: Binding(
                                get: { store.category(cat.id)?.color ?? cat.color },
                                set: { c in if let i = store.categories.firstIndex(where: { $0.id == cat.id }) { store.categories[i].colorHex = c.hexString } }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            TextField(cat.parentID == nil ? "Category" : "Subcategory", text: Binding(
                                get: { store.category(cat.id)?.name ?? "" },
                                set: { v in if let i = store.categories.firstIndex(where: { $0.id == cat.id }) { store.categories[i].name = v } }
                            ))
                            .textFieldStyle(.plain)
                            if cat.parentID == nil {
                                Button { store.addSubcategory(to: cat.id) } label: { Label("Sub", systemImage: "plus") }
                                    .buttonStyle(.borderless).font(.caption)
                                    .help("Add a subcategory, e.g. IELTS › Speaking")
                            }
                            Button(role: .destructive) {
                                deletingCategory = cat
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    HStack {
                        Text("Task categories & subcategories")
                        Spacer()
                        Button {
                            store.addCategory()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if tab == .data {
                Section("Data") {
                    LabeledContent("Saved at", value: store.fileURL.path)
                        .textSelection(.enabled)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
            }

        }
        .formStyle(.grouped)
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete category “\(deletingCategory?.name ?? "")”?",
                            isPresented: Binding(get: { deletingCategory != nil }, set: { if !$0 { deletingCategory = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = deletingCategory?.id { store.deleteCategory(id) }
                deletingCategory = nil
            }
        } message: {
            Text(deletingCategory?.parentID != nil
                 ? "Its tasks and sessions move to the parent category."
                 : "Its tasks and sessions are kept, just without a category. Its subcategories become categories of their own.")
        }
        .confirmationDialog("Delete the \(deletingSlot?.title ?? "") slot?",
                            isPresented: Binding(get: { deletingSlot != nil }, set: { if !$0 { deletingSlot = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = deletingSlot?.id { store.deleteSlot(id) }
                deletingSlot = nil
            }
        } message: {
            Text("Everything written in this column of the weekly schedule is removed too.")
        }
    }

    /// Minutes-since-midnight ⇄ Date for the time pickers
    private func minuteBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Cal.gregorian.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes.wrappedValue * 60)) },
            set: { minutes.wrappedValue = Cal.minuteOfDay($0) }
        )
    }
}

/// A clickable preview of a design template
struct TemplateCard: View {
    let template: ScheduleTemplate
    let font: FontChoice
    let isSelected: Bool
    let onSelect: () -> Void

    private static let samples: [[(String, String?)?]] = [
        [("Math", "#4DABF7"), nil, ("Gym", "#FF6B6B"), ("Read", "#FFD43B")],
        [nil, ("Physics", "#FFA94D"), nil, ("TOEFL", "#7C6CF2")],
        [("Signals", "#69DB7C"), nil, ("Work", nil), nil],
    ]

    var body: some View {
        let style = template.style
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    AmbientBackground(style: style)
                    Grid(horizontalSpacing: max(2, style.spacing / 2), verticalSpacing: max(2, style.spacing / 2)) {
                        ForEach(0..<3, id: \.self) { row in
                            GridRow {
                                ForEach(0..<4, id: \.self) { col in
                                    let sample = Self.samples[row][col]
                                    ScheduleCellView(
                                        entry: sample.map { ScheduleEntry(weekday: row, slotID: UUID(), text: $0.0, kind: .fixed) },
                                        colorHex: nil, template: template, font: font, fontSize: 9,   // the theme's own cell colour, so each card shows its look
                                        isTodayRow: row == 1, minHeight: 22, showBadge: false)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 104)
                .drawingGroup()   // painted once as a picture: the glowing sample cells are costly to redraw while scrolling
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Circle().fill(style.accent).frame(width: 8, height: 8)
                        Text(template.title).font(.headline)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(style.accent)
                        }
                    }
                    Text(template.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? style.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
