import SwiftUI

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        )
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String?
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        )
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = .accentColor

    var body: some View {
        // Inset by half the line width so the stroke stays inside the frame and is never clipped
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
        .padding(1)
    }
}

struct CategoryChip: View {
    let category: Category?

    var body: some View {
        if let category {
            HStack(spacing: 4) {
                Circle().fill(category.color).frame(width: 7, height: 7)
                Text(category.name)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(category.color.opacity(0.15)))
        }
    }
}

/// Type-and-Enter field for adding a task
struct QuickAddField: View {
    var placeholder = "Add a task and press Enter…"
    var onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit {
                    let t = text.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    onAdd(t)
                    text = ""
                }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
    }
}

struct TaskRow: View {
    let task: TaskItem
    var showDate = false
    var onEdit: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(TimerEngine.self) private var timer
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { store.tapStatus(.task(task.id), on: task.dueDate ?? Date()) }
            } label: {
                StatusIcon(done: task.isDone, skipped: task.isSkipped).font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isDone || task.isSkipped)
                    .foregroundStyle(task.isDone || task.isSkipped ? .secondary : .primary)
                HStack(spacing: 8) {
                    CategoryChip(category: store.category(task.categoryID))
                    if let d = task.dueDate {
                        if showDate {
                            Label(Fmt.date(d, "MMM d", store.settings.primaryCalendar), systemImage: "calendar")
                        }
                        if task.hasTime {
                            Label(Fmt.time(d), systemImage: "clock")
                        }
                    }
                    Label(Fmt.duration(TimeInterval(task.estimatedMinutes * 60)), systemImage: "hourglass")
                    if !task.notes.isEmpty {
                        Image(systemName: "note.text")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if task.priority == .high && !task.isDone {
                Image(systemName: "flag.fill").foregroundStyle(.red).help("High priority")
            }
            if task.isSkipped {
                Text("Skipped").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            } else if !task.isDone {
                Button {
                    timer.select(.task(task.id))
                    router.selection = .timer
                } label: {
                    Image(systemName: "play.circle").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Study this in the timer")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit", action: onEdit)
            StatusMenuItems(ref: .task(task.id), day: task.dueDate ?? Date())
            Divider()
            Button("Delete", role: .destructive) { store.deleteTask(task.id) }
        }
    }
}

struct SessionRow: View {
    let session: StudySession
    var showDate = false
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(store.subject(of: session).color)
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.itemTitle(of: session)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Fmt.shortDuration(session.duration))
                .font(.body.monospacedDigit().weight(.medium))
        }
        .contextMenu {
            Button("Delete Session", role: .destructive) { store.deleteSession(session.id) }
        }
    }

    private var subtitle: String {
        var s = "\(Fmt.time(session.start)) – \(Fmt.time(session.end))"
        if showDate { s = Fmt.date(session.start, "EEE, MMM d", store.settings.primaryCalendar) + " · " + s }
        if !session.note.isEmpty { s += " · " + session.note }
        return s
    }
}

/// The round status icon of a to-do: ○ to do, ✓ done, ✕ skipped (won't be done)
struct StatusIcon: View {
    let done: Bool
    var skipped = false

    var body: some View {
        Image(systemName: skipped ? "xmark.circle.fill" : (done ? "checkmark.circle.fill" : "circle"))
            .foregroundStyle(skipped ? Color.orange : (done ? Color.green : Color.secondary))
            .help(skipped ? "Skipped, won't be done. Click to bring it back." : (done ? "Done" : "Mark as done"))
    }
}

/// Right-click items for a to-do's status: done, skipped (won't do), or back to to-do
struct StatusMenuItems: View {
    let ref: TodoRef
    let day: Date
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.isSkipped(ref, on: day) {
            Button("Bring Back to To-Do") { withAnimation { store.setSkipped(ref, on: day, false) } }
        } else {
            Button(store.isDone(ref, on: day) ? "Mark as Not Done" : "Mark as Done") { withAnimation { store.toggleDone(ref, on: day) } }
            Button("Skip (Won't Do)") { withAnimation { store.setSkipped(ref, on: day, true) } }
        }
    }
}
