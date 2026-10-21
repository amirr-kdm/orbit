import SwiftUI

/// Planners: draft weeks with brainstorm notes. A planner can be copied into the weekly schedule.
struct PlannerView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: UUID?
    @State private var deleting: Planner?
    @State private var renamingFolder: UUID?
    @State private var dropTarget: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            if let id = selection, store.planner(id) != nil {
                PlannerDetail(plannerID: id).id(id)
            } else {
                empty
            }
        }
        .navigationTitle("Notes & Brainstorm")
        .onAppear { if selection == nil { selection = store.planners.first?.id } }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let p = deleting {
                    store.deletePlanner(p.id)
                    if selection == p.id { selection = store.planners.first?.id }
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its plan and notes are deleted. Anything already added to the weekly schedule stays there.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Notes & Brainstorm", systemImage: "brain.head.profile").font(.headline)
                Spacer()
                Button { renamingFolder = store.addPlannerFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.borderless)
                    .help("New folder")
                Button { selection = store.addPlanner() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New planner")
            }
            .padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.plannerFolders) { folder in
                        folderRow(folder)
                        if folder.expanded {
                            let inside = store.planners.filter { $0.folderID == folder.id }
                            ForEach(inside) { plannerRow($0).padding(.leading, 18) }
                            if inside.isEmpty {
                                Text("Drag planners here").font(.caption).foregroundStyle(.tertiary)
                                    .padding(.leading, 30).padding(.vertical, 4)
                            }
                        }
                    }
                    ForEach(store.planners.filter { p in !store.plannerFolders.contains { $0.id == p.folderID } }) { plannerRow($0) }
                    // Drop here to take a planner out of its folder
                    Color.clear.frame(height: 60).contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in
                            for s in items { if let id = UUID(uuidString: s) { store.movePlanner(id, to: nil) } }
                            return true
                        }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 220)
    }

    private func folderRow(_ folder: PlannerFolder) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(folder.expanded ? 90 : 0))
            Image(systemName: folder.expanded ? "folder.fill" : "folder").foregroundStyle(.tint)
            if renamingFolder == folder.id {
                TextField("Folder name", text: Binding(get: { folder.name }, set: { store.renamePlannerFolder(folder.id, to: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { renamingFolder = nil }
            } else {
                Text(folder.name).fontWeight(.medium).lineLimit(1)
            }
            Spacer()
            Text("\(store.planners.filter { $0.folderID == folder.id }.count)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(dropTarget == folder.id ? Color.accentColor.opacity(0.25) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { store.togglePlannerFolder(folder.id) } }
        .dropDestination(for: String.self) { items, _ in
            for s in items { if let id = UUID(uuidString: s) { store.movePlanner(id, to: folder.id) } }
            if !folder.expanded { store.togglePlannerFolder(folder.id) }
            return true
        } isTargeted: { dropTarget = $0 ? folder.id : (dropTarget == folder.id ? nil : dropTarget) }
        .contextMenu {
            Button("New Planner Here") {
                let id = store.addPlanner(); store.movePlanner(id, to: folder.id); selection = id
            }
            Button("Rename…") { renamingFolder = folder.id }
            Divider()
            Button("Delete Folder", role: .destructive) { store.deletePlannerFolder(folder.id) }
        }
    }

    private func plannerRow(_ p: Planner) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.name).lineLimit(1)
            Text("\(p.entries.count) to-dos · \(p.notes.count) notes")
                .font(.caption).foregroundStyle(selection == p.id ? .white.opacity(0.8) : .secondary)
        }
        .foregroundStyle(selection == p.id ? .white : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(selection == p.id ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = p.id }
        .draggable(p.id.uuidString) {
            Label(p.name, systemImage: "doc.text").padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        // Drop onto another planner to put it just above (and in the same folder)
        .dropDestination(for: String.self) { items, _ in
            for s in items { if let id = UUID(uuidString: s) { store.movePlanner(id, to: p.folderID, before: p.id) } }
            return true
        }
        .contextMenu {
            Button("Duplicate") { selection = store.duplicatePlanner(p.id) }
            if !store.plannerFolders.isEmpty {
                Menu("Move to Folder") {
                    Button("No Folder") { store.movePlanner(p.id, to: nil) }
                    Divider()
                    ForEach(store.plannerFolders) { f in Button(f.name) { store.movePlanner(p.id, to: f.id) } }
                }
            }
            Divider()
            Button("Delete…", role: .destructive) { deleting = p }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Plan a week, brainstorm, then add it to your schedule").font(.title3.weight(.semibold))
            Text("Each planner has its own weekly plan and notes. Class times from your weekly schedule are locked.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("New Planner") { selection = store.addPlanner() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - One planner

private struct PlannerDetail: View {
    @Environment(AppStore.self) private var store
    let plannerID: UUID

    struct CellKey: Hashable {
        let weekday: Int
        let slotID: UUID
    }

    @State private var editing: CellKey?
    @State private var selected: CellKey?
    @State private var draft = ""
    @State private var editColor: String?
    @State private var paletteColor: String?
    @State private var newCategory: UUID?
    /// 0 = plan for this week, 1 = next week (decides which classes are locked)
    @State private var weekOffset = 1
    @State private var applying = false

    private var planner: Planner { store.planner(plannerID) ?? Planner(name: "") }
    private var template: ScheduleTemplate { store.settings.template }
    private var targetDate: Date { Cal.persian.date(byAdding: .day, value: 7 * weekOffset, to: Date()) ?? Date() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !planner.planHidden {
                    grid
                    toolbar
                }
                NotesPanel(plannerID: plannerID)
            }
            .padding(22)
        }
        .sheet(isPresented: $applying) {
            ApplyPlannerSheet(planner: planner, weekOffset: weekOffset)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            TextField("Planner name", text: Binding(
                get: { planner.name },
                set: { n in store.updatePlanner(plannerID) { $0.name = n } }
            ))
            .textFieldStyle(.plain)
            .font(.title.weight(.bold))

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { store.updatePlanner(plannerID) { $0.planHidden.toggle() } }
            } label: {
                Label(planner.planHidden ? "Show Table" : "Hide Table",
                      systemImage: planner.planHidden ? "tablecells" : "tablecells.badge.ellipsis")
            }
            .help(planner.planHidden ? "Show the weekly plan table" : "Hide the weekly plan table so the notes move up")

            Spacer()

            Picker("", selection: $weekOffset) {
                Text("This week").tag(0)
                Text("Next week").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("Which week's classes are locked in the plan")
            ParityBadge(parity: store.parity(ofWeek: targetDate))

            Button {
                commitEditing()
                applying = true
            } label: {
                Label("Add to Weekly Schedule…", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderedProminent)
            .disabled(planner.entries.isEmpty)
        }
    }

    private var grid: some View {
        let slots = store.settings.timeSlots.sorted { $0.startMinute < $1.startMinute }
        let week = Cal.persian.dateInterval(of: .weekOfYear, for: targetDate)!
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 96, height: 1)
                ForEach(slots) { slot in
                    Text(slot.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<7, id: \.self) { day in
                let date = Cal.persian.date(byAdding: .day, value: day, to: week.start) ?? week.start
                GridRow {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Cal.weekdayNames[day]).font(.system(size: 13, weight: .semibold))
                        Text(Fmt.date(date, "MMM d", store.settings.primaryCalendar)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(day == 6 ? Color.red.opacity(0.85) : Color.primary)
                    .frame(width: 96, alignment: .trailing)

                    ForEach(slots) { slot in
                        cell(day: day, slot: slot)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }

    @ViewBuilder
    private func cell(day: Int, slot: TimeSlot) -> some View {
        let key = CellKey(weekday: day, slotID: slot.id)
        let entry = planner.entries.first { $0.weekday == day && $0.slotID == slot.id }
        if let fixed = store.fixedEntry(weekday: day, slotID: slot.id, inWeekOf: targetDate) {
            LockedCell(fixed: fixed, hidden: entry)
        } else {
            ScheduleCellView(
                entry: entry,
                colorHex: editing == key ? editColor : store.colorHex(of: entry),
                category: store.category(entry?.categoryID),
                template: template,
                font: store.settings.font,
                fontSize: min(store.settings.scheduleFontSize, 15),
                isEditing: editing == key,
                isSelected: selected == key,
                draft: $draft,
                onCommit: { commit(key) },
                onCancel: { if editing == key { editing = nil } },
                minHeight: 50,
                showBadge: false
            )
            .onTapGesture { beginEditing(key) }
            .contextMenu {
                Button("Edit") { beginEditing(key) }
                if let entry {
                    Picker("Category", selection: Binding(
                        get: { entry.categoryID },
                        set: { id in store.updatePlannerEntry(plannerID, entry.id) { $0.categoryID = id } }
                    )) {
                        Text("No category").tag(UUID?.none)
                        ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Divider()
                    Button("Clear Cell", role: .destructive) {
                        store.updatePlanner(plannerID) { $0.entries.removeAll { $0.id == entry.id } }
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            CellPaletteBar(selection: editing != nil ? editColor : (selectedEntry?.colorHex ?? paletteColor), onPick: applyColor)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20)
            Menu {
                Picker("Category", selection: categoryBinding) {
                    Text("No category").tag(UUID?.none)
                    ForEach(store.categories) { c in Text(c.name).tag(Optional(c.id)) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(store.category(categoryBinding.wrappedValue)?.name ?? "Category", systemImage: "tag")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Label("Class times from your weekly schedule are locked", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(.regularMaterial))
    }

    // MARK: Editing

    private var selectedEntry: ScheduleEntry? {
        selected.flatMap { k in planner.entries.first { $0.weekday == k.weekday && $0.slotID == k.slotID } }
    }

    private var categoryBinding: Binding<UUID?> {
        Binding(
            get: { selectedEntry?.categoryID ?? newCategory },
            set: { id in
                newCategory = id
                if let e = selectedEntry { store.updatePlannerEntry(plannerID, e.id) { $0.categoryID = id } }
            }
        )
    }

    private func beginEditing(_ key: CellKey) {
        if editing == key { return }
        commitEditing()
        let entry = planner.entries.first { $0.weekday == key.weekday && $0.slotID == key.slotID }
        draft = entry?.text ?? ""
        editColor = entry == nil ? paletteColor : entry?.colorHex
        selected = key
        editing = key
    }

    private func commitEditing() {
        if let editing { commit(editing) }
    }

    private func commit(_ key: CellKey) {
        guard editing == key else { return }
        store.setPlannerCell(plannerID, weekday: key.weekday, slotID: key.slotID, text: draft,
                             colorHex: editColor, categoryID: newCategory)
        editing = nil
    }

    private func applyColor(_ hex: String?) {
        paletteColor = hex
        if editing != nil {
            editColor = hex
        } else if let e = selectedEntry {
            store.updatePlannerEntry(plannerID, e.id) { $0.colorHex = hex }
        }
    }
}

/// A class time: nothing can be planned here
private struct LockedCell: View {
    let fixed: ScheduleEntry
    /// A planner to-do that sits under a class (it will be skipped)
    let hidden: ScheduleEntry?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 9
                }
                ctx.stroke(p, with: .color(.primary.opacity(0.06)), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(spacing: 2) {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(fixed.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(4)
            if hidden != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .help(hidden.map { "Class time. Your planned “\($0.title)” here will be skipped." }
              ?? "Class time from your weekly schedule. Nothing can be planned here.")
    }
}

// MARK: - Apply to schedule

private struct ApplyPlannerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planner: Planner
    @State var weekOffset: Int
    @State private var recurrence: Recurrence = .once
    @State private var result: PlannerApplyResult?

    private var date: Date { Cal.persian.date(byAdding: .day, value: 7 * weekOffset, to: Date()) ?? Date() }

    var body: some View {
        let conflicts = store.plannerConflicts(planner, weekOf: date)
        let locked = planner.entries.filter { store.fixedEntry(weekday: $0.weekday, slotID: $0.slotID, inWeekOf: date) != nil }

        VStack(alignment: .leading, spacing: 16) {
            if let result {
                done(result)
            } else {
                Text("Add “\(planner.name)” to the weekly schedule").font(.title2.weight(.bold))

                Form {
                    Picker("Week", selection: $weekOffset) {
                        Text("This week · \(store.parity(ofWeek: Date()).title)").tag(0)
                        Text("Next week · \(store.parity(ofWeek: Cal.persian.date(byAdding: .day, value: 7, to: Date()) ?? Date()).title)").tag(1)
                    }
                    Picker("Repeat", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                }
                .formStyle(.grouped)
                .frame(height: 120)

                Label("\(planner.entries.count) planned to-do\(planner.entries.count == 1 ? "" : "s")", systemImage: "checklist")
                if !locked.isEmpty {
                    Label("\(locked.count) sit on class times and will be skipped", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }

                if conflicts.isEmpty {
                    Label("No clashes with your existing to-dos", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                        Button("Add to Schedule") { apply(.replaceOld) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    conflictList(conflicts)
                    Text("What should happen to these?").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        choice("Replace the old to-dos", "The old to-dos are removed and the planner's to-dos take their place.",
                               "arrow.triangle.2.circlepath", prominent: true) { apply(.replaceOld) }
                        choice("Keep the old to-dos", "Skip the planner's clashing to-dos and add everything else.",
                               "hand.raised") { apply(.keepOld) }
                        choice("Cancel", "Don't change the weekly schedule.", "xmark") { dismiss() }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: result == nil ? (conflicts.isEmpty ? 380 : 620) : 300)
    }

    private func conflictList(_ conflicts: [PlannerConflict]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(conflicts.count) clash\(conflicts.count == 1 ? "" : "es") with to-dos already in the schedule",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(conflicts) { c in
                        HStack {
                            Text("\(Cal.weekdayShort[c.new.weekday]) \(store.slot(c.new.slotID)?.title ?? "")")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            Text(c.old.title).strikethrough().foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            Text(c.new.title).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(maxHeight: 150)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        }
    }

    private func choice(_ title: String, _ detail: String, _ icon: String, prominent: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(prominent ? Color.white : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).opacity(0.8)
                }
                Spacer()
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func done(_ r: PlannerApplyResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Added to your weekly schedule", systemImage: "checkmark.circle.fill")
                .font(.title2.weight(.bold)).foregroundStyle(.green)
            Text("\(r.added) new to-do\(r.added == 1 ? "" : "s") added")
            if r.replaced > 0 { Text("\(r.replaced) old to-do\(r.replaced == 1 ? "" : "s") replaced") }
            if r.keptOld > 0 { Text("\(r.keptOld) clashing to-do\(r.keptOld == 1 ? "" : "s") skipped (old ones kept)") }
            if r.skippedFixed > 0 { Text("\(r.skippedFixed) skipped because of class times") }
            Text("Repeat: \(recurrence.title)").foregroundStyle(.secondary)
            Spacer()
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }
    }

    private func apply(_ choice: PlannerConflictChoice) {
        withAnimation { result = store.applyPlanner(planner, weekOf: date, recurrence: recurrence, choice: choice) }
    }
}

// MARK: - Notes

private struct NotesPanel: View {
    @Environment(AppStore.self) private var store
    let plannerID: UUID
    @State private var noteID: UUID?
    @State private var controller = RichTextController()

    private var notes: [PlannerNote] { store.planner(plannerID)?.notes ?? [] }
    private var current: PlannerNote? { notes.first { $0.id == noteID } ?? notes.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Notes & brainstorm", systemImage: "brain.head.profile").font(.title3.weight(.semibold))
                Spacer()
            }
            tabs
            if let note = current {
                VStack(spacing: 0) {
                    HStack {
                        TextField("Title", text: Binding(
                            get: { note.title },
                            set: { t in store.updatePlanner(plannerID) { p in
                                if let i = p.notes.firstIndex(where: { $0.id == note.id }) { p.notes[i].title = t }
                            } }
                        ))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        Spacer()
                        Text("Edited \(note.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    formatBar.padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                    RichTextEditor(noteID: note.id, rtf: note.rtfForEditor, controller: controller) { id, data in
                        store.updatePlanner(plannerID) { p in
                            if let i = p.notes.firstIndex(where: { $0.id == id }) {
                                p.notes[i].rtf = data
                                p.notes[i].html = nil   // saved here: the RTF is now the newest copy
                                p.notes[i].updatedAt = Date()
                            }
                        }
                    }
                    .frame(minHeight: 420)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            } else {
                Button("New Note") { addNote() }
            }
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(notes) { n in
                    let on = n.id == current?.id
                    Button { noteID = n.id } label: {
                        Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "doc.richtext")
                            .lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(on ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.5))))
                            .foregroundStyle(on ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Duplicate") {
                            store.updatePlanner(plannerID) { p in
                                var c = n; c.id = UUID(); c.title += " copy"; p.notes.append(c)
                            }
                        }
                        Button("Delete Note", role: .destructive) {
                            store.updatePlanner(plannerID) { $0.notes.removeAll { $0.id == n.id } }
                            if noteID == n.id { noteID = nil }
                        }
                    }
                }
                Button { addNote() } label: {
                    Label("New note", systemImage: "plus")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var formatBar: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Title") { controller.setHeading(1) }
                Button("Heading") { controller.setHeading(2) }
                Button("Body") { controller.setHeading(0) }
            } label: { Image(systemName: "textformat.size") }
            .menuStyle(.borderlessButton).fixedSize().help("Text style")
            group {
                tool("bold", "Bold") { controller.toggleTrait(.boldFontMask) }
                tool("italic", "Italic") { controller.toggleTrait(.italicFontMask) }
                tool("underline", "Underline") { controller.toggle(.underlineStyle) }
                tool("strikethrough", "Strikethrough") { controller.toggle(.strikethroughStyle) }
            }
            group {
                tool("list.bullet", "Bulleted list") { controller.toggleList(.bullet) }
                tool("list.number", "Numbered list") { controller.toggleList(.number) }
                tool("checklist", "Checklist (click a box to tick it)") { controller.toggleList(.check) }
            }
            group {
                tool("text.alignleft", "Align left") { controller.setAlignment(.left) }
                tool("text.aligncenter", "Centre") { controller.setAlignment(.center) }
                tool("text.alignright", "Align right") { controller.setAlignment(.right) }
                tool("text.justify", "Justify") { controller.setAlignment(.justified) }
            }
            group {
                textTool("LTR", "Left to right (English)") { controller.setDirection(rightToLeft: false) }
                textTool("RTL", "Right to left (Persian / فارسی)") { controller.setDirection(rightToLeft: true) }
            }
            group {
                NoteColorButton(highlight: false, current: controller.textColor) { controller.setColor($0) }
                NoteColorButton(highlight: true, current: controller.highlight) { controller.setColor($0, background: true) }
            }
            group {
                Menu {
                    ForEach([(2, 2), (3, 3), (4, 3), (5, 4)], id: \.0) { r, c in
                        Button("\(c) × \(r)") { controller.insertTable(rows: r, columns: c) }
                    }
                    Divider()
                    Button("Table Options… (rows, columns, merge)") { controller.tableOptions() }
                } label: { Image(systemName: "tablecells") }
                .menuStyle(.borderlessButton).fixedSize().help("Insert a table")
                tool("minus", "Divider line") { controller.insertDivider() }
            }
            Spacer()
        }
        .imageScale(.medium)
    }

    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 0) { c() }
            .padding(.horizontal, 4)
            .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 16) }
    }

    private func tool(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 26, height: 22) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private func textTool(_ label: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).font(.system(size: 10, weight: .bold)).frame(width: 30, height: 22) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private func addNote() {
        let n = PlannerNote(title: "Note \(notes.count + 1)")
        store.updatePlanner(plannerID) { $0.notes.append(n) }
        noteID = n.id
    }
}

/// Text colour / highlight picker for notes: real swatches, the current colour, and custom colours
private struct NoteColorButton: View {
    @Environment(AppStore.self) private var store
    let highlight: Bool
    /// Colour at the cursor (nil = default text colour / no highlight)
    let current: NSColor?
    let apply: (NSColor?) -> Void

    @State private var open = false
    @State private var custom = Color(hex: "#22C55E")

    /// Highlights are drawn see-through so the text stays readable
    private func color(_ hex: String) -> NSColor {
        let c = NSColor(Color(hex: hex))
        return highlight ? c.withAlphaComponent(0.35) : c
    }
    private var currentHex: String? { current.map { Color(nsColor: $0.withAlphaComponent(1)).hexString } }

    var body: some View {
        Button { open.toggle() } label: {
            VStack(spacing: 2) {
                Image(systemName: highlight ? "highlighter" : "paintbrush.pointed")
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(current.map { Color(nsColor: $0.withAlphaComponent(1)) } ?? (highlight ? Color.clear : Color.primary))
                    .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(Color.primary.opacity(current == nil && highlight ? 0.4 : 0), lineWidth: 0.5))
                    .frame(width: 16, height: 3.5)
            }
            .frame(width: 30, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(highlight ? "Highlight" : "Text colour")
        .popover(isPresented: $open, arrowEdge: .bottom) { picker }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(highlight ? "Highlight" : "Text colour").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                swatch(nil)
                ForEach(store.settings.cellPalette.filter { highlight || $0 != "#FFFFFF" }, id: \.self) { swatch($0) }
            }
            Divider()
            HStack {
                ColorPicker("Custom colour", selection: $custom, supportsOpacity: false)
                Spacer()
                Button("Use") {
                    let hex = custom.hexString
                    if !store.settings.cellPalette.contains(hex) { store.settings.cellPalette.append(hex) }
                    apply(color(hex))
                    open = false
                }
                .buttonStyle(.borderedProminent)
            }
            Text("Custom colours are saved with your other colours.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 250)
    }

    private func swatch(_ hex: String?) -> some View {
        let isOn = currentHex == hex
        return Button {
            apply(hex.map(color))
            open = false
        } label: {
            ZStack {
                if let hex {
                    Circle().fill(Color(hex: hex).gradient)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                } else {
                    // Default text colour / no highlight
                    Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                    Image(systemName: highlight ? "nosign" : "textformat")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(hex.map { Color.isLight(hex: $0) ? Color.black : Color.white } ?? Color.accentColor)
                }
            }
            .frame(width: 24, height: 24)
            .padding(2)
            .overlay(Circle().strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(hex ?? (highlight ? "No highlight" : "Default colour"))
    }
}
