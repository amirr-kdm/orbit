import Foundation

/// How to handle planner to-dos that land on a cell that already has a to-do in the weekly schedule
enum PlannerConflictChoice {
    /// Remove the old to-dos and put the planner's in their place
    case replaceOld
    /// Keep the old to-dos; drop only the conflicting planner to-dos and add the rest
    case keepOld
}

/// A planner to-do that would land on a cell already used by a schedule to-do
struct PlannerConflict: Identifiable {
    let new: ScheduleEntry
    let old: ScheduleEntry
    var id: UUID { new.id }
}

struct PlannerApplyResult {
    var added = 0
    var replaced = 0
    var keptOld = 0
    var skippedFixed = 0
}

extension AppStore {
    func planner(_ id: UUID?) -> Planner? {
        guard let id else { return nil }
        return planners.first { $0.id == id }
    }

    @discardableResult
    func addPlanner(named name: String? = nil) -> UUID {
        let p = Planner(name: name ?? "Planner \(planners.count + 1)")
        planners.append(p)
        return p.id
    }

    func updatePlanner(_ id: UUID, _ change: (inout Planner) -> Void) {
        guard let i = planners.firstIndex(where: { $0.id == id }) else { return }
        change(&planners[i])
    }

    func deletePlanner(_ id: UUID) {
        planners.removeAll { $0.id == id }
    }

    @discardableResult
    func duplicatePlanner(_ id: UUID) -> UUID? {
        guard var copy = planner(id) else { return nil }
        copy.id = UUID()
        copy.name += " copy"
        copy.createdAt = Date()
        copy.entries = copy.entries.map { var e = $0; e.id = UUID(); return e }
        copy.notes = copy.notes.map { var n = $0; n.id = UUID(); return n }
        planners.append(copy)
        return copy.id
    }

    /// The class (fixed cell) that occupies this slot in the given week. Planner cells there are locked.
    func fixedEntry(weekday: Int, slotID: UUID, inWeekOf date: Date) -> ScheduleEntry? {
        guard let e = entry(weekday: weekday, slotID: slotID, inWeekOf: date), e.kind == .fixed else { return nil }
        return e
    }

    /// Creates, updates or clears a planner cell
    func setPlannerCell(_ plannerID: UUID, weekday: Int, slotID: UUID, text: String, colorHex: String?, categoryID: UUID?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updatePlanner(plannerID) { p in
            if let i = p.entries.firstIndex(where: { $0.weekday == weekday && $0.slotID == slotID }) {
                if trimmed.isEmpty {
                    p.entries.remove(at: i)
                } else {
                    p.entries[i].text = trimmed
                    p.entries[i].colorHex = colorHex
                }
            } else if !trimmed.isEmpty {
                p.entries.append(ScheduleEntry(weekday: weekday, slotID: slotID, text: trimmed, colorHex: colorHex,
                                               kind: .todo, categoryID: categoryID))
            }
        }
    }

    func updatePlannerEntry(_ plannerID: UUID, _ entryID: UUID, _ change: (inout ScheduleEntry) -> Void) {
        updatePlanner(plannerID) { p in
            if let i = p.entries.firstIndex(where: { $0.id == entryID }) { change(&p.entries[i]) }
        }
    }

    /// Planner to-dos that would overwrite a schedule to-do shown in that week
    func plannerConflicts(_ planner: Planner, weekOf date: Date) -> [PlannerConflict] {
        planner.entries.compactMap { n in
            guard fixedEntry(weekday: n.weekday, slotID: n.slotID, inWeekOf: date) == nil,
                  let old = entry(weekday: n.weekday, slotID: n.slotID, inWeekOf: date), old.kind == .todo
            else { return nil }
            return PlannerConflict(new: n, old: old)
        }
        .sorted { ($0.new.weekday, slot($0.new.slotID)?.startMinute ?? 0) < ($1.new.weekday, slot($1.new.slotID)?.startMinute ?? 0) }
    }

    /// Copies the planner's to-dos into the weekly schedule.
    /// Cells taken by a class are always skipped; conflicts with existing to-dos follow `choice`.
    @discardableResult
    func applyPlanner(_ planner: Planner, weekOf date: Date, recurrence: Recurrence,
                      choice: PlannerConflictChoice) -> PlannerApplyResult {
        var result = PlannerApplyResult()
        var newSchedule = schedule
        let week = Cal.weekStart(date)

        func shown(_ weekday: Int, _ slotID: UUID) -> ScheduleEntry? {
            newSchedule
                .filter { $0.weekday == weekday && $0.slotID == slotID && applies($0, toWeekOf: date) }
                .max { $0.recurrence.priority < $1.recurrence.priority }
        }

        for n in planner.entries where !n.text.isEmpty && slot(n.slotID) != nil {
            if let old = shown(n.weekday, n.slotID) {
                if old.kind == .fixed { result.skippedFixed += 1; continue }
                if choice == .keepOld { result.keptOld += 1; continue }
                // A one-week plan simply overrides the old to-do for that week (it wins by priority),
                // unless the old one is itself a one-week entry. Repeating plans replace it outright.
                if recurrence != .once || old.recurrence == .once {
                    newSchedule.removeAll { $0.id == old.id }
                }
                result.replaced += 1
            } else {
                result.added += 1
            }
            newSchedule.append(ScheduleEntry(weekday: n.weekday, slotID: n.slotID, text: n.text, colorHex: n.colorHex,
                                             kind: .todo, categoryID: n.categoryID, recurrence: recurrence,
                                             weekStart: recurrence == .once ? week : nil))
        }
        schedule = newSchedule
        return result
    }
}
