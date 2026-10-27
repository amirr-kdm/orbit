import SwiftUI

/// Daily to-do list: today's "To-do" cells from the weekly schedule + one-off tasks.
/// Pick one and press Study to take it to the timer.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    @State private var editing: TaskItem?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(today: context.date)
        }
        .navigationTitle("Today")
        .sheet(item: $editing) { TaskEditor(task: $0) }
    }

    private func content(today: Date) -> some View {
        let scheduleTodos = store.scheduleTodos(on: today)
        let taskTodos = store.todos(on: today).filter { if case .task = $0.ref { true } else { false } }
        let all = scheduleTodos + taskTodos
        let overdue = store.overdueTasks(before: today)
        let studied = store.studyTime(on: today) + (timer.phase == .focus ? timer.elapsed : 0)
        let goal = TimeInterval(store.settings.dailyGoalMinutes * 60)
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: today)!

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To-do · \(Fmt.date(today, "EEEE", .gregorian))").font(.largeTitle.weight(.bold))
                    Text(Fmt.dualDate(today) + ", " + Fmt.date(today, "y", .gregorian))
                        .font(.title3).foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    HStack(spacing: 14) {
                        ZStack {
                            ProgressRing(progress: goal > 0 ? studied / goal : 0, lineWidth: 7)
                            Text("\(Int(goal > 0 ? min(999, studied / goal * 100) : 0))%")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Studied today").font(.caption).foregroundStyle(.secondary)
                            Text(Fmt.duration(studied)).font(.title3.weight(.semibold))
                            Text("Goal: \(Fmt.duration(goal))").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1))

                    StatTile(title: "To-dos done",
                             value: "\(all.filter(\.isDone).count) of \(all.filter { !$0.isSkipped }.count)",
                             subtitle: all.isEmpty ? "Nothing planned yet"
                                : (all.contains(where: \.isSkipped) ? "\(all.filter(\.isSkipped).count) skipped" : nil),
                             systemImage: "checkmark.circle", tint: .green)
                    StatTile(title: "This week", value: Fmt.duration(store.studyTime(in: week)),
                             subtitle: "Total time logged", systemImage: "calendar", tint: .purple)
                }

                if let slot = store.currentSlot(at: today),
                   let e = store.entry(weekday: Cal.weekdayIndex(today), slotID: slot.id, inWeekOf: today) {
                    nowBanner(entry: e, slot: slot)
                }

                Card(title: "From your weekly schedule", systemImage: "tablecells") {
                    if scheduleTodos.isEmpty {
                        HStack {
                            Text("No To-do cells for \(Fmt.date(today, "EEEE", .gregorian)). Mark cells as “To-do” in the weekly schedule and they appear here.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Schedule") { router.selection = .schedule }
                        }
                    }
                    ForEach(scheduleTodos) { item in
                        TodoRow(item: item, day: today)
                        if item.id != scheduleTodos.last?.id { Divider() }
                    }
                }

                Card(title: "Other tasks today", systemImage: "list.bullet") {
                    QuickAddField { title in
                        store.upsertTask(TaskItem(title: title, dueDate: Cal.persian.startOfDay(for: today)))
                    }
                    ForEach(taskTodos) { item in
                        TodoRow(item: item, day: today) {
                            if case .task(let id) = item.ref { editing = store.task(id) }
                        }
                        if item.id != taskTodos.last?.id { Divider() }
                    }
                }

                Card(title: "No specific time", systemImage: "tray") {
                    AnytimeBox(today: today)
                }

                if !overdue.isEmpty {
                    Card(title: "Overdue", systemImage: "exclamationmark.triangle") {
                        ForEach(overdue) { task in
                            HStack {
                                TaskRow(task: task, showDate: true) { editing = task }
                                Button("Move to Today") {
                                    var t = task
                                    t.dueDate = moveToToday(task.dueDate, today: today)
                                    store.upsertTask(t)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }

                let sessions = store.sessions(in: Cal.persian.dayInterval(today))
                Card(title: "Today's sessions", systemImage: "timer") {
                    if sessions.isEmpty {
                        Text("No sessions yet. Pick a to-do above and press Study.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sessions) { SessionRow(session: $0) }
                }
            }
            .padding(24)
        }
    }

    private func nowBanner(entry: ScheduleEntry, slot: TimeSlot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Now · \(slot.title)").font(.caption).foregroundStyle(.secondary)
                Text(entry.title).font(.headline)
            }
            Spacer()
            if entry.kind == .todo {
                Button {
                    timer.select(.schedule(entry.id))
                    router.selection = .timer
                } label: {
                    Label("Study Now", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(timer.isActive)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.4)))
    }

    /// Keep the task's time of day, move it to today
    private func moveToToday(_ date: Date?, today: Date) -> Date {
        let cal = Cal.persian
        let start = cal.startOfDay(for: today)
        guard let date else { return start }
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return cal.date(byAdding: comps, to: start) ?? start
    }
}

/// One row of the to-do list with a checkbox and a "Study" button
struct TodoRow: View {
    let item: TodoItem
    let day: Date
    var onEdit: (() -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router

    var body: some View {
        let studied = store.studyTime(for: item.ref, on: day)
        let isCurrent = timer.target == item.ref

        HStack(spacing: 10) {
            Button {
                withAnimation { store.tapStatus(item.ref, on: day) }
            } label: {
                StatusIcon(done: item.isDone, skipped: item.isSkipped).font(.title3)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isDone || item.isSkipped)
                    .foregroundStyle(item.isDone || item.isSkipped ? .secondary : .primary)
                HStack(spacing: 8) {
                    Label(item.detail, systemImage: {
                        if case .schedule = item.ref { return "clock" } else { return "tag" }
                    }())
                    if studied > 0 {
                        Label(Fmt.duration(studied) + " studied", systemImage: "timer")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if item.isSkipped {
                Text("Skipped").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            } else if !item.isDone {
                Button {
                    timer.select(item.ref)
                    router.selection = .timer
                } label: {
                    Label(isCurrent && timer.isActive ? "In Progress" : "Study",
                          systemImage: isCurrent && timer.isActive ? "timer" : "play.fill")
                }
                .buttonStyle(.bordered)
                .tint(isCurrent ? .green : .accentColor)
                .disabled(timer.isActive && !isCurrent)
                .help(timer.isActive && !isCurrent ? "Finish the running timer first" : "Open in the timer")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit?() }
        .contextMenu {
            if let onEdit { Button("Edit", action: onEdit) }
            StatusMenuItems(ref: item.ref, day: day)
        }
    }
}
