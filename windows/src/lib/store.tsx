import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import {
  AppData, Category, defaultData, defaultSlots, EntryKind, PlacedPlanet, Recurrence, recurrencePriority,
  ScheduleEntry, SolarSystem, StudySession, SunType, SYSTEM_NAMES, TaskItem, TimeSlot, uid,
} from "./model";
import { addDays, dayKey, minuteOfDay, sameDay, startOfDay, weekDays, weekStart, weekdayIndex, weeksBetween } from "./dates";
import { PLANETS, unlockLevel } from "./planets";

const KEY = "orbit-data-v1";

function load(): AppData {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return { ...defaultData(), ...JSON.parse(raw) };
  } catch { /* fall through */ }
  return defaultData();
}

// ---------- Pure helpers (work on a data snapshot) ----------

export type TodoRef = { kind: "schedule" | "task"; id: string };
export const refKey = (r: TodoRef) => `${r.kind}:${r.id}`;

export interface TodoItem { ref: TodoRef; title: string; detail: string; color: string; isDone: boolean; sortMinute: number }
export interface ScheduleRow { entry: ScheduleEntry; slot: TimeSlot; date: Date; isDone: boolean }

const doneKey = (id: string, day: Date) => `${id}|${dayKey(day)}`;

export function parity(d: AppData, date: Date): "even" | "odd" {
  return ((weeksBetween(new Date(d.settings.evenWeekAnchor), date) % 2) + 2) % 2 === 0 ? "even" : "odd";
}

export function applies(d: AppData, e: ScheduleEntry, date: Date): boolean {
  switch (e.recurrence) {
    case "weekly": return true;
    case "even": return parity(d, date) === "even";
    case "odd": return parity(d, date) === "odd";
    case "once": return e.weekStart ? weeksBetween(new Date(e.weekStart), date) === 0 : true;
  }
}

export function entryAt(d: AppData, weekday: number, slotID: string, date: Date): ScheduleEntry | undefined {
  return d.schedule
    .filter((e) => e.weekday === weekday && e.slotID === slotID && applies(d, e, date))
    .sort((a, b) => recurrencePriority(b.recurrence) - recurrencePriority(a.recurrence))[0];
}

const isShown = (d: AppData, e: ScheduleEntry, date: Date) => entryAt(d, e.weekday, e.slotID, date)?.id === e.id;
export const titleOf = (e: ScheduleEntry) => e.text.split("\n")[0].trim();
export const categoryOf = (d: AppData, id?: string) => d.categories.find((c) => c.id === id);
export const slotOf = (d: AppData, id: string) => d.settings.timeSlots.find((s) => s.id === id);
export const slotTitle = (s: TimeSlot) => {
  const f = (m: number) => (m % 60 === 0 ? `${m / 60}` : `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`);
  return `${f(s.startMinute)}-${f(s.endMinute)}`;
};

export function isDone(d: AppData, ref: TodoRef, day: Date): boolean {
  if (ref.kind === "schedule") return d.scheduleDone.includes(doneKey(ref.id, day));
  return d.tasks.find((t) => t.id === ref.id)?.isDone ?? false;
}

export function scheduleRows(d: AppData, day: Date, kinds: EntryKind[] = ["fixed", "todo"]): ScheduleRow[] {
  const wd = weekdayIndex(day);
  const start = startOfDay(day);
  return d.schedule
    .filter((e) => e.weekday === wd && kinds.includes(e.kind) && isShown(d, e, day) && !d.scheduleMoved.includes(doneKey(e.id, day)))
    .flatMap((e) => {
      const slot = slotOf(d, e.slotID);
      return slot ? [{ entry: e, slot, date: start, isDone: isDone(d, { kind: "schedule", id: e.id }, start) }] : [];
    })
    .sort((a, b) => a.slot.startMinute - b.slot.startMinute);
}

export function tasksOn(d: AppData, day: Date): TaskItem[] {
  return d.tasks
    .filter((t) => t.dueDate && sameDay(new Date(t.dueDate), day))
    .sort((a, b) => Number(a.isDone) - Number(b.isDone) || (a.dueDate ?? "").localeCompare(b.dueDate ?? ""));
}

export function todosOn(d: AppData, day: Date): TodoItem[] {
  const sched = scheduleRows(d, day, ["todo"]).map((r) => {
    const cat = categoryOf(d, r.entry.categoryID);
    return {
      ref: { kind: "schedule" as const, id: r.entry.id }, title: titleOf(r.entry),
      detail: slotTitle(r.slot) + (cat ? ` · ${cat.name}` : ""), color: r.entry.colorHex ?? cat?.colorHex ?? "#5B7CFA",
      isDone: r.isDone, sortMinute: r.slot.startMinute,
    };
  });
  const tasks = tasksOn(d, day).map((t) => {
    const cat = categoryOf(d, t.categoryID);
    return {
      ref: { kind: "task" as const, id: t.id }, title: t.title, detail: cat?.name ?? "Task",
      color: cat?.colorHex ?? "#8E8E93", isDone: t.isDone,
      sortMinute: t.hasTime && t.dueDate ? minuteOfDay(new Date(t.dueDate)) : 9999,
    };
  });
  return [...sched, ...tasks];
}

export function sessionsIn(d: AppData, from: Date, to: Date): StudySession[] {
  return d.sessions.filter((s) => { const t = new Date(s.start).getTime(); return t >= from.getTime() && t < to.getTime(); });
}
export const studyTime = (d: AppData, from: Date, to: Date) => sessionsIn(d, from, to).reduce((a, s) => a + s.duration, 0);
export const studyOn = (d: AppData, day: Date) => studyTime(d, startOfDay(day), addDays(startOfDay(day), 1));

export function subjectOf(d: AppData, s: StudySession): { name: string; color: string } {
  if (s.subject) return { name: s.subject, color: s.colorHex || "#8E8E93" };
  const c = categoryOf(d, s.categoryID);
  return c ? { name: c.name, color: c.colorHex } : { name: "Unsorted", color: "#8E8E93" };
}

export function currentSlot(d: AppData, at = new Date()): TimeSlot | undefined {
  const m = minuteOfDay(at);
  return d.settings.timeSlots.find((s) => m >= s.startMinute && m < s.endMinute);
}

// ---------- Galaxy progress (same rules as the Mac app) ----------

export const MAX_LEVEL = 50;
export interface Progress { level: number; totalHours: number; weekHours: number; credits: number }

export function progress(d: AppData, now = new Date()): Progress {
  const total = d.sessions.reduce((a, s) => a + s.duration, 0) / 3600;
  const cw = weekStart(now);
  const weekHours = studyTime(d, cw, new Date(now.getTime() + 1000)) / 3600;
  let level = 1;
  const first = d.sessions.map((s) => new Date(s.start).getTime()).sort((a, b) => a - b)[0];
  if (first !== undefined) {
    let w = weekStart(new Date(first));
    while (w < cw && level < MAX_LEVEL) {
      const next = addDays(w, 7);
      const h = studyTime(d, w, next) / 3600;
      if (h >= 20) level += 2; else if (h >= 10) level += 1;
      w = next;
    }
  }
  level = Math.min(level, MAX_LEVEL);
  return { level, totalHours: total, weekHours, credits: Math.max(0, level - d.galaxy.length) };
}

// ---------- React store ----------

interface Store {
  data: AppData;
  update: (fn: (d: AppData) => void) => void;
  actions: ReturnType<typeof makeActions>;
}

const Ctx = createContext<Store | null>(null);

function makeActions(update: Store["update"]) {
  return {
    // tasks
    upsertTask: (t: TaskItem) => update((d) => {
      const i = d.tasks.findIndex((x) => x.id === t.id);
      if (i >= 0) d.tasks[i] = t; else d.tasks.push(t);
    }),
    addTask: (title: string, day?: Date, categoryID?: string) => update((d) => {
      d.tasks.push({ id: uid(), title, notes: "", categoryID, priority: 1, dueDate: day ? startOfDay(day).toISOString() : undefined,
        hasTime: false, estimatedMinutes: 30, isDone: false, createdAt: new Date().toISOString() });
    }),
    deleteTask: (id: string) => update((d) => { d.tasks = d.tasks.filter((t) => t.id !== id); }),
    moveTask: (id: string, day?: Date) => update((d) => {
      const t = d.tasks.find((x) => x.id === id);
      if (!t) return;
      if (!day) { t.dueDate = undefined; t.hasTime = false; return; }
      const base = startOfDay(day);
      if (t.hasTime && t.dueDate) { const old = new Date(t.dueDate); base.setHours(old.getHours(), old.getMinutes()); }
      t.dueDate = base.toISOString();
    }),
    toggleDone: (ref: TodoRef, day: Date) => update((d) => {
      if (ref.kind === "schedule") {
        const k = doneKey(ref.id, day);
        d.scheduleDone = d.scheduleDone.includes(k) ? d.scheduleDone.filter((x) => x !== k) : [...d.scheduleDone, k];
      } else {
        const t = d.tasks.find((x) => x.id === ref.id);
        if (t) { t.isDone = !t.isDone; t.completedAt = t.isDone ? new Date().toISOString() : undefined; }
      }
    }),
    /** Move one occurrence of a schedule to-do to another day (becomes a task) */
    moveOccurrence: (entryID: string, from: Date, to?: Date) => update((d) => {
      const e = d.schedule.find((x) => x.id === entryID);
      if (!e || (to && sameDay(from, to))) return;
      const k = doneKey(entryID, from);
      const wasDone = d.scheduleDone.includes(k);
      d.scheduleMoved.push(k);
      d.scheduleDone = d.scheduleDone.filter((x) => x !== k);
      const slot = slotOf(d, e.slotID);
      let due: string | undefined;
      if (to && slot) { const b = startOfDay(to); b.setMinutes(slot.startMinute); due = b.toISOString(); }
      d.tasks.push({ id: uid(), title: titleOf(e), notes: "", categoryID: e.categoryID, priority: 1, dueDate: due,
        hasTime: !!due, estimatedMinutes: slot ? slot.endMinute - slot.startMinute : 30, isDone: wasDone,
        createdAt: new Date().toISOString(), completedAt: wasDone ? new Date().toISOString() : undefined });
    }),

    // schedule
    setCell: (weekday: number, slotID: string, weekOf: Date, text: string, colorHex: string | undefined,
              kind: EntryKind, categoryID: string | undefined, recurrence: Recurrence) => update((d) => {
      const trimmed = text.trim();
      const existing = entryAt(d, weekday, slotID, weekOf);
      if (existing) {
        if (!trimmed) d.schedule = d.schedule.filter((e) => e.id !== existing.id);
        else { existing.text = trimmed; existing.colorHex = colorHex; }
      } else if (trimmed) {
        d.schedule.push({ id: uid(), weekday, slotID, text: trimmed, colorHex, kind, categoryID, recurrence,
          weekStart: recurrence === "once" ? weekStart(weekOf).toISOString() : undefined });
      }
    }),
    updateEntry: (id: string, fn: (e: ScheduleEntry) => void) => update((d) => { const e = d.schedule.find((x) => x.id === id); if (e) fn(e); }),
    deleteEntry: (id: string) => update((d) => { d.schedule = d.schedule.filter((e) => e.id !== id); }),
    setRecurrence: (id: string, r: Recurrence, weekOf: Date) => update((d) => {
      const e = d.schedule.find((x) => x.id === id);
      if (e) { e.recurrence = r; e.weekStart = r === "once" ? weekStart(weekOf).toISOString() : undefined; }
    }),
    swapParity: () => update((d) => { d.settings.evenWeekAnchor = addDays(new Date(d.settings.evenWeekAnchor), 7).toISOString(); }),

    // sessions
    addSession: (s: StudySession) => update((d) => { d.sessions.push(s); d.sessions.sort((a, b) => a.start.localeCompare(b.start)); }),
    deleteSession: (id: string) => update((d) => { d.sessions = d.sessions.filter((s) => s.id !== id); }),

    // categories & settings
    addCategory: () => update((d) => {
      const pal = ["#4F7CF7", "#F28C38", "#2BB673", "#E5484D", "#9B6BDF", "#14B8C4", "#D9A21B", "#E255A1"];
      d.categories.push({ id: uid(), name: "New category", colorHex: pal[d.categories.length % pal.length] });
    }),
    updateCategory: (c: Category) => update((d) => { const i = d.categories.findIndex((x) => x.id === c.id); if (i >= 0) d.categories[i] = c; }),
    deleteCategory: (id: string) => update((d) => {
      d.categories = d.categories.filter((c) => c.id !== id);
      d.tasks.forEach((t) => { if (t.categoryID === id) t.categoryID = undefined; });
      d.schedule.forEach((e) => { if (e.categoryID === id) e.categoryID = undefined; });
    }),
    resetSlots: () => update((d) => { d.schedule = []; d.settings.timeSlots = defaultSlots(); }),
    addSlot: () => update((d) => {
      const last = Math.max(480, ...d.settings.timeSlots.map((s) => s.endMinute));
      const start = Math.min(last + 30, 23 * 60);
      d.settings.timeSlots.push({ id: uid(), startMinute: start, endMinute: Math.min(start + 90, 1439) });
    }),
    deleteSlot: (id: string) => update((d) => {
      d.settings.timeSlots = d.settings.timeSlots.filter((s) => s.id !== id);
      d.schedule = d.schedule.filter((e) => e.slotID !== id);
    }),

    // galaxy
    addPlanet: (planetID: string, systemID?: string) => update((d) => {
      const p = progress(d);
      const def = PLANETS.find((x) => x.id === planetID);
      if (p.credits <= 0 || !def || unlockLevel(def.group) > p.level) return;
      const count = (sid: string) => d.galaxy.filter((g) => g.systemID === sid).length;
      const target = d.solarSystems.find((s) => s.id === systemID) ?? d.solarSystems.find((s) => count(s.id) < 8);
      if (!target || count(target.id) >= 8) return;
      d.galaxy.push({ id: uid(), planetID, addedAt: new Date().toISOString(), systemID: target.id } as PlacedPlanet);
    }),
    removePlanet: (id: string) => update((d) => { d.galaxy = d.galaxy.filter((g) => g.id !== id); }),
    createSystem: (sun: SunType): string => {
      const id = uid();
      update((d) => { d.solarSystems.push({ id, name: SYSTEM_NAMES[d.solarSystems.length % SYSTEM_NAMES.length], sun }); });
      return id;
    },
    updateSystem: (id: string, fn: (s: SolarSystem) => void) => update((d) => { const s = d.solarSystems.find((x) => x.id === id); if (s) fn(s); }),
  };
}

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const [data, setData] = useState<AppData>(load);
  const first = useRef(true);

  const update = useCallback((fn: (d: AppData) => void) => {
    setData((prev) => {
      const next: AppData = structuredClone(prev);
      fn(next);
      return next;
    });
  }, []);

  useEffect(() => {
    if (first.current) { first.current = false; return; }
    try { localStorage.setItem(KEY, JSON.stringify(data)); } catch { /* storage full or blocked */ }
  }, [data]);

  const actions = useMemo(() => makeActions(update), [update]);
  const value = useMemo(() => ({ data, update, actions }), [data, update, actions]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useStore(): Store {
  const s = useContext(Ctx);
  if (!s) throw new Error("StoreProvider missing");
  return s;
}

export { weekDays };
