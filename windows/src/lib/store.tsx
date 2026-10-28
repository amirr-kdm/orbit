import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import {
  AppData, Category, defaultData, PALETTE, Planner, PlannerNote, defaultSlots, EntryKind, PlacedPlanet, Recurrence, recurrencePriority,
  ScheduleEntry, SolarSystem, StudySession, SunType, SYSTEM_NAMES, TaskItem, TimeSlot, uid,
} from "./model";
import { addDays, dayKey, minuteOfDay, sameDay, startOfDay, weekDays, weekStart, weekdayIndex, weeksBetween } from "./dates";
import { PLANETS, unlockLevel } from "./planets";
import { STORE } from "./storePlanets";
import { walletBuy, walletClaim, walletRefresh, walletRefund } from "./wallet";

const KEY = "orbit-data-v1";

function load(): AppData {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) {
      const def = defaultData(), saved = JSON.parse(raw);
      // Fields added in later versions get their defaults
      const merged: AppData = { ...def, ...saved, settings: { ...def.settings, ...saved.settings } };
      merged.schedule = normalized(merged.schedule);
      return merged;
    }
  } catch { /* fall through */ }
  return defaultData();
}

// ---------- Pure helpers (work on a data snapshot) ----------

export type TodoRef = { kind: "schedule" | "task"; id: string };
export const refKey = (r: TodoRef) => `${r.kind}:${r.id}`;

export interface TodoItem { ref: TodoRef; title: string; detail: string; color: string; isDone: boolean; sortMinute: number; isSkipped?: boolean }
export interface ScheduleRow { entry: ScheduleEntry; slot: TimeSlot; date: Date; isDone: boolean; isSkipped?: boolean }

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
/** "IELTS › Speaking" for a subcategory, just the name otherwise */
export const categoryLabel = (d: AppData, id?: string) => {
  const c = categoryOf(d, id); if (!c) return undefined;
  const p = categoryOf(d, c.parentID); return p ? `${p.name} › ${c.name}` : c.name;
};
/** Categories in display order: each one followed by its subcategories */
export const orderedCategories = (d: AppData) =>
  d.categories.filter((c) => !c.parentID || !categoryOf(d, c.parentID)).flatMap((c) => [c, ...d.categories.filter((s) => s.parentID === c.id)]);
/** Is `id` this category or one of its subcategories? */
export const isInside = (d: AppData, id: string | undefined, filter: string) => id === filter || (!!id && categoryOf(d, id)?.parentID === filter);
/** The colour a schedule cell shows: its category's colour for to-dos when that setting is on, else its own */
export const entryColor = (d: AppData, e: ScheduleEntry) =>
  d.settings.categoryColors && e.kind === "todo" && categoryOf(d, e.categoryID) ? categoryOf(d, e.categoryID)!.colorHex : e.colorHex;
export const slotOf = (d: AppData, id: string) => d.settings.timeSlots.find((s) => s.id === id);
export const slotTitle = (s: TimeSlot) => {
  const f = (m: number) => (m % 60 === 0 ? `${m / 60}` : `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`);
  return `${f(s.startMinute)}-${f(s.endMinute)}`;
};

export function isSkipped(d: AppData, ref: TodoRef, day: Date): boolean {
  if (ref.kind === "schedule") return d.scheduleSkipped.includes(doneKey(ref.id, day));
  return d.tasks.find((t) => t.id === ref.id)?.isSkipped ?? false;
}

/** An "every week" cell sharing its slot with an even-only (odd-only) cell can only show in the other weeks,
 *  so it becomes odd-only (even-only). Nothing visible changes, but it no longer silently disappears. */
export function normalized(schedule: ScheduleEntry[]): ScheduleEntry[] {
  const groups = new Map<string, ScheduleEntry[]>();
  for (const e of schedule) { const k = `${e.weekday}|${e.slotID}`; groups.set(k, [...(groups.get(k) ?? []), e]); }
  const fix = new Map<string, Recurrence>();
  for (const list of groups.values()) {
    if (list.length < 2) continue;
    const parities = new Set(list.map((e) => e.recurrence).filter((r) => r === "even" || r === "odd"));
    if (parities.size !== 1) continue;
    const taken = [...parities][0];
    for (const e of list) if (e.recurrence === "weekly") fix.set(e.id, taken === "even" ? "odd" : "even");
  }
  return fix.size ? schedule.map((e) => (fix.has(e.id) ? { ...e, recurrence: fix.get(e.id)! } : e)) : schedule;
}

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
      return slot ? [{ entry: e, slot, date: start, isDone: isDone(d, { kind: "schedule", id: e.id }, start),
        isSkipped: isSkipped(d, { kind: "schedule", id: e.id }, start) }] : [];
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
      detail: slotTitle(r.slot) + (cat ? ` · ${categoryLabel(d, cat.id)}` : ""), color: entryColor(d, r.entry) ?? cat?.colorHex ?? "#5B7CFA",
      isDone: r.isDone, sortMinute: r.slot.startMinute, isSkipped: r.isSkipped,
    };
  });
  const tasks = tasksOn(d, day).map((t) => {
    const cat = categoryOf(d, t.categoryID);
    return {
      ref: { kind: "task" as const, id: t.id }, title: t.title, detail: categoryLabel(d, t.categoryID) ?? "Task",
      color: cat?.colorHex ?? "#8E8E93", isDone: t.isDone, isSkipped: t.isSkipped,
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
/** Study that earns rewards (levels, rockets, streak, leaderboards, challenges, Fight Club): timed sessions only */
export const rewardTime = (d: AppData, from: Date, to: Date) => sessionsIn(d, from, to).filter((s) => !s.isManual).reduce((a, s) => a + s.duration, 0);
export const rewardOn = (d: AppData, day: Date) => rewardTime(d, startOfDay(day), addDays(startOfDay(day), 1));
const entryOf = (d: AppData, id?: string) => d.schedule.find((e) => e.id === id);
/** Hex of the colour a session shows (follows the category-colour setting) */
export function subjectHex(d: AppData, s: StudySession): string {
  const c = categoryOf(d, s.categoryID);
  if (d.settings.categoryColors && c && entryOf(d, s.scheduleEntryID)?.kind !== "fixed") return c.colorHex;
  return s.colorHex || "#8E8E93";
}

export function subjectOf(d: AppData, s: StudySession): { name: string; color: string } {
  const c = categoryOf(d, s.categoryID);
  if (d.settings.categoryColors && c && entryOf(d, s.scheduleEntryID)?.kind !== "fixed") return { name: s.subject || c.name, color: c.colorHex };
  if (s.subject) return { name: s.subject, color: s.colorHex || "#8E8E93" };
  return c ? { name: c.name, color: c.colorHex } : { name: "Unsorted", color: "#8E8E93" };
}

export function currentSlot(d: AppData, at = new Date()): TimeSlot | undefined {
  const m = minuteOfDay(at);
  return d.settings.timeSlots.find((s) => m >= s.startMinute && m < s.endMinute);
}

// ---------- Planner ----------

/** The class (fixed cell) occupying a slot in the given week; planner cells there are locked */
export function fixedAt(d: AppData, weekday: number, slotID: string, date: Date): ScheduleEntry | undefined {
  const e = entryAt(d, weekday, slotID, date);
  return e?.kind === "fixed" ? e : undefined;
}

export interface PlannerConflict { new: ScheduleEntry; old: ScheduleEntry }
export type ConflictChoice = "replaceOld" | "keepOld";
export interface ApplyResult { added: number; replaced: number; keptOld: number; skippedFixed: number }

/** Planner to-dos that would land on a cell already showing a schedule to-do that week */
export function plannerConflicts(d: AppData, p: Planner, date: Date): PlannerConflict[] {
  return p.entries.flatMap((n) => {
    if (fixedAt(d, n.weekday, n.slotID, date)) return [];
    const old = entryAt(d, n.weekday, n.slotID, date);
    return old && old.kind === "todo" ? [{ new: n, old }] : [];
  }).sort((a, b) => a.new.weekday - b.new.weekday || (slotOf(d, a.new.slotID)?.startMinute ?? 0) - (slotOf(d, b.new.slotID)?.startMinute ?? 0));
}

/** Same rules as the Mac app: class cells are always skipped; clashes follow `choice`.
 *  A one-week plan overrides an old repeating to-do for that week instead of deleting it. */
export function applyPlannerTo(d: AppData, p: Planner, date: Date, recurrence: Recurrence, choice: ConflictChoice): ApplyResult {
  const r: ApplyResult = { added: 0, replaced: 0, keptOld: 0, skippedFixed: 0 };
  const week = weekStart(date).toISOString();
  for (const n of p.entries) {
    if (!n.text || !slotOf(d, n.slotID)) continue;
    const old = entryAt(d, n.weekday, n.slotID, date);
    if (old) {
      if (old.kind === "fixed") { r.skippedFixed++; continue; }
      if (choice === "keepOld") { r.keptOld++; continue; }
      if (recurrence !== "once" || old.recurrence === "once") d.schedule = d.schedule.filter((e) => e.id !== old.id);
      r.replaced++;
    } else r.added++;
    d.schedule.push({ id: uid(), weekday: n.weekday, slotID: n.slotID, text: n.text, colorHex: n.colorHex, kind: "todo",
      categoryID: n.categoryID, recurrence, weekStart: recurrence === "once" ? week : undefined });
  }
  return r;
}

// ---------- Galaxy progress (same rules as the Mac app) ----------

export const MAX_LEVEL = 60;
export const HOURS_PER_LEVEL = 3;
export interface Progress { level: number; totalHours: number; weekHours: number; credits: number }

export function progress(d: AppData, now = new Date()): Progress {
  const total = d.sessions.filter((s) => !s.isManual).reduce((a, s) => a + s.duration, 0) / 3600;
  const cw = weekStart(now);
  const weekHours = rewardTime(d, cw, new Date(now.getTime() + 1000)) / 3600;
  // One level for every 3 hours studied in total, straight away
  const level = Math.min(MAX_LEVEL, 1 + Math.floor(total / HOURS_PER_LEVEL));
  return { level, totalHours: total, weekHours, credits: Math.max(0, level - d.galaxy.length) };
}

// ---------- Rockets (store currency) ----------

export const STARTING_ROCKETS = 200, ROCKETS_PER_HOUR = 25, GROUP_WIN_ROCKETS = 100, REFUND_TICKETS = 3;
export const BONUS_TIERS: [string, number][] = [["10h", 100], ["15h", 140], ["20h", 200], ["25h", 240], ["30h", 300], ["30h+", 400]];
export const weeklyBonus = (h: number) => (h > 30 ? 400 : h >= 30 ? 300 : h >= 25 ? 240 : h >= 20 ? 200 : h >= 15 ? 140 : h >= 10 ? 100 : 0);

/** Finished weeks (Sat → Fri) since you started, with their bonus */
export function weekBonuses(d: AppData, now = new Date()): { start: Date; hours: number; rockets: number }[] {
  const first = d.sessions.map((s) => new Date(s.start).getTime()).sort((a, b) => a - b)[0];
  if (first === undefined) return [];
  const cur = weekStart(now), out = [];
  for (let w = weekStart(new Date(first)); w < cur; w = addDays(w, 7)) {
    const hours = rewardTime(d, w, addDays(w, 7)) / 3600;
    out.push({ start: w, hours, rockets: weeklyBonus(hours) });
  }
  return out;
}

/** Until this day rockets came for every hour studied; since then they come from the Level Pass (25 a level) */
export const LEVEL_PASS_START = new Date(2026, 9, 21);
/** Rockets a level gives: 25 up to level 9, 75 from level 10, then 50 more with every further ten levels (20 → 125 …); the server uses the same table */
export const rocketsForLevel = (level: number) => (level < 10 ? 25 : 75 + 50 * (Math.floor(level / 10) - 1));
/** Levels 10, 20 … 60 also give a special planet */
export const levelPlanet = (level: number) => (level > 0 && level % 10 === 0 ? `lv_t${level / 10}` : null);
export const canClaim = (d: AppData, level: number) => level >= 1 && level <= progress(d).level && !(d.claimedLevels ?? []).includes(level);
export const totalHours = (d: AppData) => d.sessions.filter((s) => !s.isManual).reduce((a, s) => a + s.duration, 0) / 3600;

export interface Wallet { study: number; levels: number; bonuses: number; groups: number; spent: number; balance: number }
/** The server wallet (lib/wallet.tsx) once it's known for this account — then it is the balance */
export const serverWallet: { balance: number | null; refundsLeft: number | null } = { balance: null, refundsLeft: null };
export const refundsLeft = (d: AppData) => serverWallet.refundsLeft ?? Math.max(0, REFUND_TICKETS - d.refundsUsed);
export function wallet(d: AppData): Wallet {
  const study = Math.floor(d.sessions.filter((s) => new Date(s.start) < LEVEL_PASS_START).reduce((a, s) => a + s.duration, 0) / 3600 * ROCKETS_PER_HOUR);
  const levels = (d.claimedLevels ?? []).reduce((a, l) => a + rocketsForLevel(l), 0);
  const bonuses = weekBonuses(d).reduce((a, b) => a + b.rockets, 0);
  const groups = d.groupWins.length * GROUP_WIN_ROCKETS;
  const spent = d.purchases.reduce((a, p) => a + p.price, 0);
  if (serverWallet.balance !== null) return { study, levels, bonuses, groups, spent, balance: serverWallet.balance };
  return { study, levels, bonuses, groups, spent, balance: STARTING_ROCKETS + d.rocketGrant + study + levels + bonuses + groups - spent };
}
export const ownedCount = (d: AppData, id: string) => d.purchases.filter((p) => p.planetID === id).length;
export const placedCount = (d: AppData, id: string) => d.galaxy.filter((g) => g.planetID === id).length;
export const unplacedCount = (d: AppData, id: string) => Math.max(0, ownedCount(d, id) - placedCount(d, id));
const roomIn = (d: AppData, sid?: string) => {
  const count = (id: string) => d.galaxy.filter((g) => g.systemID === id).length;
  const t = d.solarSystems.find((s) => s.id === sid) ?? (sid ? undefined : d.solarSystems.find((s) => count(s.id) < 8));
  return t && count(t.id) < 8 ? t : undefined;
};

// ---------- React store ----------

interface Store {
  data: AppData;
  /** Replace everything (restoring a cloud backup) */
  replaceAll: (d: AppData) => void;
  update: (fn: (d: AppData) => void) => void;
  actions: ReturnType<typeof withWallet>;
  /** Set after a study session is saved: the Level Pass opens and the ship flies from → to (hours) */
  passMoment: { from: number; to: number; id: number } | null;
  setPassMoment: (m: { from: number; to: number; id: number } | null) => void;
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
    setSkipped: (ref: TodoRef, day: Date, skipped: boolean) => update((d) => {
      if (ref.kind === "schedule") {
        const k = doneKey(ref.id, day);
        d.scheduleSkipped = d.scheduleSkipped.filter((x) => x !== k);
        if (skipped) { d.scheduleSkipped.push(k); d.scheduleDone = d.scheduleDone.filter((x) => x !== k); }
      } else {
        const t = d.tasks.find((x) => x.id === ref.id);
        if (t) { t.isSkipped = skipped; if (skipped) { t.isDone = false; t.completedAt = undefined; } }
      }
    }),
    /** The round status button: a skipped item goes back to "to do", otherwise done is toggled */
    tapStatus: (ref: TodoRef, day: Date) => update((d) => {
      if (isSkipped(d, ref, day)) {
        if (ref.kind === "schedule") d.scheduleSkipped = d.scheduleSkipped.filter((x) => x !== doneKey(ref.id, day));
        else { const t = d.tasks.find((x) => x.id === ref.id); if (t) t.isSkipped = false; }
        return;
      }
      if (ref.kind === "schedule") {
        const k = doneKey(ref.id, day);
        d.scheduleDone = d.scheduleDone.includes(k) ? d.scheduleDone.filter((x) => x !== k) : [...d.scheduleDone, k];
      } else {
        const t = d.tasks.find((x) => x.id === ref.id);
        if (t) { t.isDone = !t.isDone; t.completedAt = t.isDone ? new Date().toISOString() : undefined; }
      }
    }),
    toggleDone: (ref: TodoRef, day: Date) => update((d) => {
      if (ref.kind === "schedule") d.scheduleSkipped = d.scheduleSkipped.filter((x) => x !== doneKey(ref.id, day));
      else { const t = d.tasks.find((x) => x.id === ref.id); if (t) t.isSkipped = false; }
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
        d.schedule = normalized(d.schedule);
      }
    }),
    updateEntry: (id: string, fn: (e: ScheduleEntry) => void) => update((d) => { const e = d.schedule.find((x) => x.id === id); if (e) fn(e); }),
    deleteEntry: (id: string) => update((d) => { d.schedule = d.schedule.filter((e) => e.id !== id); }),
    setRecurrence: (id: string, r: Recurrence, weekOf: Date) => update((d) => {
      const e = d.schedule.find((x) => x.id === id);
      if (e) { e.recurrence = r; e.weekStart = r === "once" ? weekStart(weekOf).toISOString() : undefined; }
      d.schedule = normalized(d.schedule);
    }),
    swapParity: () => update((d) => { d.settings.evenWeekAnchor = addDays(new Date(d.settings.evenWeekAnchor), 7).toISOString(); }),

    // sessions
    addSession: (s: StudySession) => update((d) => { d.sessions.push(s); d.sessions.sort((a, b) => a.start.localeCompare(b.start)); }),
    deleteSession: (id: string) => update((d) => { d.sessions = d.sessions.filter((s) => s.id !== id); }),

    // categories & settings
    addSubcategory: (parent: string) => update((d) => {
      const p = d.categories.find((c) => c.id === parent);
      if (p) d.categories.push({ id: uid(), name: "New subcategory", colorHex: p.colorHex, parentID: parent });
    }),
    addCategory: () => update((d) => {
      const pal = ["#4F7CF7", "#F28C38", "#2BB673", "#E5484D", "#9B6BDF", "#14B8C4", "#D9A21B", "#E255A1"];
      d.categories.push({ id: uid(), name: "New category", colorHex: pal[d.categories.length % pal.length] });
    }),
    updateCategory: (c: Category) => update((d) => { const i = d.categories.findIndex((x) => x.id === c.id); if (i >= 0) d.categories[i] = c; }),
    /** Deleting a subcategory moves its items up to the parent; deleting a category keeps its subcategories as categories */
    deleteCategory: (id: string) => update((d) => {
      const parent = d.categories.find((c) => c.id === id)?.parentID;
      d.categories = d.categories.filter((c) => c.id !== id);
      d.categories.forEach((c) => { if (c.parentID === id) c.parentID = undefined; });
      d.tasks.forEach((t) => { if (t.categoryID === id) t.categoryID = parent; });
      d.schedule.forEach((e) => { if (e.categoryID === id) e.categoryID = parent; });
      d.sessions.forEach((s) => { if (s.categoryID === id) s.categoryID = parent; });
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

    // cell colours
    addColor: (hex: string) => update((d) => { if (!d.settings.cellPalette.includes(hex)) d.settings.cellPalette.push(hex); }),
    removeColor: (hex: string) => update((d) => { d.settings.cellPalette = d.settings.cellPalette.filter((c) => c !== hex); }),
    resetColors: () => update((d) => { d.settings.cellPalette = [...PALETTE]; }),

    // planners
    addPlanner: (): string => {
      const id = uid();
      update((d) => { d.planners.push({ id, name: `Planner ${d.planners.length + 1}`, createdAt: new Date().toISOString(), entries: [],
        notes: [{ id: uid(), title: "Brainstorm", html: "", updatedAt: new Date().toISOString() }] }); });
      return id;
    },
    updatePlanner: (id: string, fn: (p: Planner) => void) => update((d) => { const p = d.planners.find((x) => x.id === id); if (p) fn(p); }),
    deletePlanner: (id: string) => update((d) => { d.planners = d.planners.filter((p) => p.id !== id); }),
    duplicatePlanner: (id: string): string => {
      const nid = uid();
      update((d) => {
        const p = d.planners.find((x) => x.id === id);
        if (!p) return;
        d.planners.push({ ...structuredClone(p), id: nid, name: `${p.name} copy`, createdAt: new Date().toISOString(),
          entries: p.entries.map((e) => ({ ...e, id: uid() })), notes: p.notes.map((n): PlannerNote => ({ ...n, id: uid() })) });
      });
      return nid;
    },
    setPlannerCell: (plannerID: string, weekday: number, slotID: string, text: string, colorHex?: string, categoryID?: string) => update((d) => {
      const p = d.planners.find((x) => x.id === plannerID);
      if (!p) return;
      const trimmed = text.trim();
      const e = p.entries.find((x) => x.weekday === weekday && x.slotID === slotID);
      if (e) {
        if (!trimmed) p.entries = p.entries.filter((x) => x !== e);
        else { e.text = trimmed; e.colorHex = colorHex; }
      } else if (trimmed) {
        p.entries.push({ id: uid(), weekday, slotID, text: trimmed, colorHex, kind: "todo", categoryID, recurrence: "weekly" });
      }
    }),
    applyPlanner: (plannerID: string, date: Date, recurrence: Recurrence, choice: ConflictChoice) => update((d) => {
      const p = d.planners.find((x) => x.id === plannerID);
      if (p) applyPlannerTo(d, p, date, recurrence, choice);
      d.schedule = normalized(d.schedule);
    }),

    // store
    buyPlanet: (id: string) => update((d) => {
      const p = STORE.find((x) => x.id === id);
      if (p?.price && wallet(d).balance >= p.price) d.purchases.push({ id: uid(), planetID: id, price: p.price, date: new Date().toISOString() });
    }),
    refund: (id: string) => update((d) => {
      if (d.refundsUsed >= REFUND_TICKETS || !STORE.find((x) => x.id === id)?.price) return;
      const i = d.purchases.map((p) => p.planetID).lastIndexOf(id);
      if (i < 0) return;
      d.purchases.splice(i, 1); d.refundsUsed += 1;
      if (placedCount(d, id) > ownedCount(d, id)) { const j = d.galaxy.map((g) => g.planetID).lastIndexOf(id); if (j >= 0) d.galaxy.splice(j, 1); }
      if (d.avatarPlanet === id && ownedCount(d, id) === 0) d.avatarPlanet = undefined;
    }),
    /** Take a level's rewards: its rockets, plus a planet on every 10th level */
    claimLevel: (level: number) => update((d) => {
      if (!canClaim(d, level)) return;
      (d.claimedLevels ??= []).push(level);
      const p = levelPlanet(level); if (p) d.purchases.push({ id: uid(), planetID: p, price: 0, date: new Date().toISOString() });
    }),
    moveSystem: (id: string, x: number, y: number) => update((d) => { const s = d.solarSystems.find((v) => v.id === id); if (s) { s.x = x; s.y = y; } }),
    placeOwned: (id: string, systemID?: string) => update((d) => {
      const t = roomIn(d, systemID);
      if (unplacedCount(d, id) > 0 && progress(d).credits > 0 && t) d.galaxy.push({ id: uid(), planetID: id, addedAt: new Date().toISOString(), systemID: t.id });
    }),
    movePlaced: (placedID: string, systemID: string) => update((d) => {
      const g = d.galaxy.find((x) => x.id === placedID);
      if (g && roomIn(d, systemID)) g.systemID = systemID;
    }),
    recordGroupWins: (keys: string[]) => update((d) => { for (const k of keys) if (!d.groupWins.includes(k)) d.groupWins.push(k); }),
    setAvatar: (id: string) => update((d) => { d.avatarPlanet = id; }),

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
    /** Removes a system (the last one can't be removed); its planets move to systems with room */
    deleteSystem: (id: string) => update((d) => {
      if (d.solarSystems.length < 2) return;
      d.solarSystems = d.solarSystems.filter((s) => s.id !== id);
      for (const g of d.galaxy) if (g.systemID === id) {
        const room = d.solarSystems.find((s) => d.galaxy.filter((x) => x.systemID === s.id).length < 8);
        if (room) g.systemID = room.id;
        else { const nid = uid(); d.solarSystems.push({ id: nid, name: SYSTEM_NAMES[d.solarSystems.length % SYSTEM_NAMES.length], sun: "yellow" }); g.systemID = nid; }
      }
    }),
    updateSystem: (id: string, fn: (s: SolarSystem) => void) => update((d) => { const s = d.solarSystems.find((x) => x.id === id); if (s) fn(s); }),
  };
}

/** Rockets go through the server wallet once it exists (lib/wallet.ts); a saved session opens the Level Pass */
function withWallet(a: ReturnType<typeof makeActions>, get: () => AppData, update: Store["update"],
                    setPassMoment: (m: { from: number; to: number; id: number } | null) => void) {
  return { ...a,
    buyPlanet: (id: string) => walletBuy(id, get, update, () => a.buyPlanet(id)),
    refund: (id: string) => walletRefund(id, get, update, () => a.refund(id)),
    claimLevel: (lv: number) => walletClaim(lv, get, update, () => a.claimLevel(lv)),
    walletRefresh: () => walletRefresh(get, update),
    addSession: (s: StudySession) => {
      const before = totalHours(get());
      a.addSession(s);
      if (s.duration >= 60 && !s.isManual) setPassMoment({ from: before, to: before + s.duration / 3600, id: Date.now() });
    },
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

  const [passMoment, setPassMoment] = useState<Store["passMoment"]>(null);
  const dataRef = useRef(data); dataRef.current = data;
  const actions = useMemo(() => {
    return withWallet(makeActions(update), () => dataRef.current, update, setPassMoment);
  }, [update]);
  const replaceAll = useCallback((d: AppData) => {
    const def = defaultData();
    setData({ ...def, ...d, settings: { ...def.settings, ...d.settings }, schedule: normalized(d.schedule ?? []) });
  }, []);
  const value = useMemo(() => ({ data, update, actions, replaceAll, passMoment, setPassMoment }), [data, update, actions, replaceAll, passMoment]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useStore(): Store {
  const s = useContext(Ctx);
  if (!s) throw new Error("StoreProvider missing");
  return s;
}

export { weekDays };
