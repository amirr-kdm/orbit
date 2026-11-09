import { useSyncExternalStore } from "react";
import { AppData, EntryKind, Recurrence, ScheduleEntry, TaskItem, Priority, uid } from "./model";
import { entryAt, normalized } from "./store";
import { startOfDay, weekStart } from "./dates";

/** Copy a to-do, then paste it into a schedule cell or onto a day of the Tasks board (same as the Mac app) */
export interface TodoClip { text: string; notes: string; colorHex?: string; categoryID?: string; minutes?: number; kind: EntryKind; recurrence: Recurrence; priority: Priority }
let clip: TodoClip | null = null;
const subs = new Set<() => void>();
const set = (c: TodoClip) => { clip = c; subs.forEach((f) => f()); };
export const useHasClip = () => useSyncExternalStore((f) => { subs.add(f); return () => { subs.delete(f); }; }, () => clip !== null);

export const copyEntry = (e: ScheduleEntry) => set({ text: e.text, notes: e.notes ?? "", colorHex: e.colorHex, categoryID: e.categoryID, minutes: e.minutes, kind: e.kind, recurrence: e.recurrence, priority: 1 });
export const copyTask = (t: TaskItem) => set({ text: t.title, notes: t.notes, categoryID: t.categoryID, minutes: t.estimatedMinutes, kind: "todo", recurrence: "weekly", priority: t.priority });

/** Into a schedule cell: whatever the cell shows that week is replaced */
export function pasteIntoCell(d: AppData, weekday: number, slotID: string, weekOf: Date) {
  if (!clip) return;
  const old = entryAt(d, weekday, slotID, weekOf);
  if (old) d.schedule = d.schedule.filter((e) => e.id !== old.id);
  d.schedule.push({ id: uid(), weekday, slotID, text: clip.text, colorHex: clip.colorHex, kind: clip.kind, categoryID: clip.categoryID, recurrence: clip.recurrence,
    weekStart: clip.recurrence === "once" ? weekStart(weekOf).toISOString() : undefined, notes: clip.notes || undefined, minutes: clip.minutes });
  d.schedule = normalized(d.schedule);
}
/** Onto a day of the Tasks board: it becomes a task on that day */
export function pasteAsTask(d: AppData, day: Date) {
  if (!clip) return;
  const [title, ...rest] = clip.text.split("\n");
  d.tasks.push({ id: uid(), title: title.trim(), notes: [clip.notes, rest.join("\n")].filter(Boolean).join("\n"), categoryID: clip.categoryID, priority: clip.priority, dueDate: startOfDay(day).toISOString(),
    hasTime: false, estimatedMinutes: clip.minutes ?? 30, isDone: false, createdAt: new Date().toISOString() });
}
