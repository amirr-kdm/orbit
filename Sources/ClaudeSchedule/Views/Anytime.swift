import SwiftUI

/// Tasks with no day and no time ("whenever"): a small pool you can add to from anywhere
extension AppStore {
    var anytimeTasks: [TaskItem] {
        tasks.filter { $0.dueDate == nil && !$0.isDone && !$0.isSkipped }.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func addAnytime(_ title: String) -> TaskItem {
        let t = TaskItem(title: title, dueDate: nil)
        upsertTask(t)
        return t
    }
}

/// The "No specific time" box: quick add + the open tasks without a day. Used on Today and beside the weekly schedule.
struct AnytimeBox: View {
    var compact = false
    var today: Date = Date()
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    @State private var editing: TaskItem?

    var body: some View {
        let items = store.anytimeTasks
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                HStack(spacing: 10) {
                    Label("No specific time", systemImage: "tray").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    QuickAddField(placeholder: "Add a task for whenever…") { store.addAnytime($0) }
                        .frame(maxWidth: 280)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(items) { chip($0) } }
                    }
                }
            } else {
                QuickAddField(placeholder: "Add a task with no specific time…") { store.addAnytime($0) }
                if items.isEmpty {
                    Text("Nothing waiting. Things you add here have no day or time; move them to today when you're ready.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(items) { t in
                    HStack {
                        TaskRow(task: t) { editing = t }
                        Button("Do today") {
                            var n = t
                            n.dueDate = Cal.persian.startOfDay(for: today)
                            store.upsertTask(n)
                        }.controlSize(.small)
                    }
                    if t.id != items.last?.id { Divider() }
                }
            }
        }
        .sheet(item: $editing) { TaskEditor(task: $0) }
    }

    private func chip(_ t: TaskItem) -> some View {
        HStack(spacing: 4) {
            Button { withAnimation { store.tapStatus(.task(t.id), on: Date()) } } label: { Image(systemName: "circle") }
                .buttonStyle(.plain)
            Text(t.title).lineLimit(1).font(.caption)
            Button { timer.select(.task(t.id)); router.selection = .timer } label: { Image(systemName: "play.circle") }
                .buttonStyle(.plain).help("Study this")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(.regularMaterial))
        .onTapGesture(count: 2) { editing = t }
    }
}

/// ⌘N: type a task and choose when (or "whenever"); optionally start studying it
struct QuickTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router
    @State private var title = ""
    @State private var when = 0   // 0 whenever, 1 today
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New task").font(.title3.weight(.bold))
            TextField("What do you need to do?", text: $title)
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit { add(start: false) }
            Picker("", selection: $when) {
                Text("No specific time").tag(0)
                Text("Today").tag(1)
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add & start") { add(start: true) }.disabled(timer.isActive)
                Button("Add") { add(start: false) }.keyboardShortcut(.defaultAction)
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20).frame(width: 380)
        .onAppear { focused = true }
    }

    private func add(start: Bool) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var item = TaskItem(title: t, dueDate: when == 1 ? Cal.persian.startOfDay(for: Date()) : nil)
        item.createdAt = Date()
        store.upsertTask(item)
        if start { timer.select(.task(item.id)); router.selection = .timer }
        dismiss()
    }
}
