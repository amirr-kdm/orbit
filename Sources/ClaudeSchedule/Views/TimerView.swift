import SwiftUI

struct TimerView: View {
    @Environment(TimerEngine.self) private var timer
    @Environment(AppStore.self) private var store
    @State private var showManual = false
    @State private var confirmDiscard = false

    var body: some View {
        HStack(spacing: 0) {
            timerPanel.frame(maxWidth: .infinity)
            Divider()
            sessionsPanel.frame(width: 320)
        }
        .navigationTitle("Timer")
        .sheet(isPresented: $showManual) { ManualSessionSheet() }
    }

    // MARK: Timer

    private var targetItem: TodoItem? {
        guard let ref = timer.target else { return nil }
        return store.todos(on: Date()).first { $0.ref == ref } ?? store.todoItem(for: ref)
    }

    private var ringColor: Color {
        if timer.phase == .rest { return .green }
        if let targetItem { return targetItem.color == .gray ? .accentColor : targetItem.color }
        return store.category(timer.categoryID)?.color ?? .accentColor
    }

    private var progress: Double {
        if let length = timer.phaseLength { return length > 0 ? timer.elapsed / length : 0 }
        // In stopwatch mode the ring shows progress towards the daily goal
        let goal = TimeInterval(store.settings.dailyGoalMinutes * 60)
        return goal > 0 ? (store.studyTime(on: Date()) + timer.elapsed) / goal : 0
    }

    private var timerPanel: some View {
        @Bindable var timer = timer
        var todos = store.todos(on: Date())
        if let ref = timer.target, !todos.contains(where: { $0.ref == ref }), let item = store.todoItem(for: ref) {
            todos.insert(item, at: 0)
        }

        return VStack(spacing: 22) {
            // What am I studying?
            VStack(spacing: 6) {
                Text(timer.phase == .rest ? "Break" : (timer.targetTitle ?? "Free study"))
                    .font(.title.weight(.semibold))
                    .lineLimit(1)
                if let targetItem {
                    Text(targetItem.detail).foregroundStyle(.secondary)
                }
            }

            Picker("", selection: $timer.mode) {
                ForEach(TimerEngine.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .disabled(timer.isActive)

            ZStack {
                ProgressRing(progress: progress, lineWidth: 16, tint: ringColor)
                VStack(spacing: 6) {
                    Text(phaseLabel).font(.headline).foregroundStyle(.secondary)
                    Text(Fmt.clock(timer.displayTime))
                        .font(.system(size: 60, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if timer.mode == .stopwatch {
                        Text("Ring: daily goal progress").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 270, height: 270)

            Form {
                Picker("Studying", selection: Binding(get: { timer.target }, set: { timer.select($0) })) {
                    Text("Free study").tag(TodoRef?.none)
                    ForEach(todos) { item in
                        Text(item.isDone ? "✓ \(item.title) (\(item.detail))" : "\(item.title) (\(item.detail))")
                            .tag(Optional(item.ref))
                    }
                }
                .disabled(timer.isActive)
                if timer.target == nil {
                    Picker("Category", selection: $timer.categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.orderedCategories) { Text(store.categoryLabel($0.id) ?? $0.name).tag(Optional($0.id)) }
                    }
                }
                TextField("Session note (e.g. chapter 3)", text: $timer.note)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 440, maxHeight: 170)
            .scrollDisabled(true)

            HStack(spacing: 14) {
                Button {
                    timer.toggle()
                } label: {
                    Label(timer.isRunning ? "Pause" : (timer.isActive ? "Resume" : "Start"),
                          systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)

                if timer.isActive {
                    if timer.phase == .rest {
                        Button("Skip Break") { timer.skipBreak() }
                            .controlSize(.large)
                    } else {
                        Button {
                            timer.stop()
                        } label: {
                            Label("Finish & Save", systemImage: "stop.fill")
                        }
                        .controlSize(.large)

                        Button(role: .destructive) {
                            confirmDiscard = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.large)
                        .help("Discard without saving")
                    }
                }
            }
            .confirmationDialog("Discard this session?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { timer.stop(save: false) }
            }

            if timer.mode == .pomodoro {
                Text("Pomodoro: \(store.settings.pomodoroMinutes) min focus, \(store.settings.breakMinutes) min break · completed this run: \(timer.completedPomodoros)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
    }

    private var phaseLabel: String {
        if timer.phase == .rest { return "Break ☕️" }
        if !timer.isActive { return "Ready" }
        return timer.isRunning ? "Focusing" : "Paused"
    }

    // MARK: Sessions

    private var sessionsPanel: some View {
        let sessions = store.sessions(in: Cal.persian.dayInterval(Date())).reversed()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Today's sessions").font(.headline)
                    Text(Fmt.duration(store.studyTime(on: Date()))).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showManual = true
                } label: {
                    Label("Log Manually", systemImage: "plus")
                }
                .help("Log a session you forgot to time")
            }
            if sessions.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary)
            }
            List {
                ForEach(Array(sessions)) { SessionRow(session: $0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(20)
    }
}

/// Log a session by hand
struct ManualSessionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: TodoRef?
    @State private var categoryID: UUID?
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var minutes = 60
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Studied", selection: $target) {
                    Text("Free study").tag(TodoRef?.none)
                    ForEach(store.todos(on: start)) { Text("\($0.title) (\($0.detail))").tag(Optional($0.ref)) }
                }
                if target == nil {
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.orderedCategories) { Text(store.categoryLabel($0.id) ?? $0.name).tag(Optional($0.id)) }
                    }
                }
                DatePicker("Started", selection: $start)
                Stepper(value: $minutes, in: 1...720, step: 5) {
                    LabeledContent("Duration", value: Fmt.duration(TimeInterval(minutes * 60)))
                }
                TextField("Note", text: $note)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Log") {
                    store.addSession(store.makeSession(ref: target, categoryID: categoryID, start: start,
                                                       duration: TimeInterval(minutes * 60), note: note))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460)
        .environment(\.calendar, store.settings.primaryCalendar.calendar)
    }
}
