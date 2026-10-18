// Dates: weeks start on Saturday; Persian (Jalali) and Gregorian formatting via Intl.

export type CalendarKind = "persian" | "gregorian";

export const WEEKDAYS = ["Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];
export const WEEKDAYS_SHORT = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"];

export const DAY = 86_400_000;

export function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

/** 0 = Saturday … 6 = Friday */
export function weekdayIndex(d: Date): number {
  return (d.getDay() + 1) % 7;
}

export function weekStart(d: Date): Date {
  return addDays(startOfDay(d), -weekdayIndex(d));
}

export function weekDays(d: Date): Date[] {
  const s = weekStart(d);
  return Array.from({ length: 7 }, (_, i) => addDays(s, i));
}

export function sameDay(a: Date, b: Date): boolean {
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}

export function isToday(d: Date): boolean {
  return sameDay(d, new Date());
}

/** Whole weeks between two dates (by week start) */
export function weeksBetween(a: Date, b: Date): number {
  return Math.round((weekStart(b).getTime() - weekStart(a).getTime()) / (7 * DAY));
}

/** Stable key for a calendar day, e.g. "2026-10-18" (same format as the Mac app) */
export function dayKey(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function minuteOfDay(d: Date): number {
  return d.getHours() * 60 + d.getMinutes();
}

const fmtCache = new Map<string, Intl.DateTimeFormat>();
function fmt(kind: CalendarKind, opts: Intl.DateTimeFormatOptions): Intl.DateTimeFormat {
  const key = kind + JSON.stringify(opts);
  let f = fmtCache.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat(kind === "persian" ? "en-US-u-ca-persian-nu-latn" : "en-US", opts);
    fmtCache.set(key, f);
  }
  return f;
}

function part(d: Date, kind: CalendarKind, type: Intl.DateTimeFormatPartTypes, opts: Intl.DateTimeFormatOptions) {
  return fmt(kind, opts).formatToParts(d).find((p) => p.type === type)?.value ?? "";
}

export function monthName(d: Date, kind: CalendarKind, short = false): string {
  return part(d, kind, "month", { month: short ? "short" : "long" });
}
export function dayNum(d: Date, kind: CalendarKind): number {
  return Number(part(d, kind, "day", { day: "numeric" }));
}
export function yearNum(d: Date, kind: CalendarKind): number {
  return Number(part(d, kind, "year", { year: "numeric" }));
}
export function monthNum(d: Date, kind: CalendarKind): number {
  return Number(part(d, kind, "month", { month: "numeric" }));
}

/** "Mehr 26" */
export function monthDay(d: Date, kind: CalendarKind, short = false): string {
  return `${monthName(d, kind, short)} ${dayNum(d, kind)}`;
}
/** "Mehr 26 — October 18" */
export function dualDate(d: Date): string {
  return `${monthDay(d, "persian")} — ${monthDay(d, "gregorian")}`;
}
/** "Sunday, Mehr 26, 1405" */
export function fullDate(d: Date, kind: CalendarKind): string {
  return `${WEEKDAYS[weekdayIndex(d)]}, ${monthDay(d, kind)}, ${yearNum(d, kind)}`;
}

/** First day of the month containing d, in the given calendar */
export function monthStart(d: Date, kind: CalendarKind): Date {
  if (kind === "gregorian") return new Date(d.getFullYear(), d.getMonth(), 1);
  return addDays(startOfDay(d), -(dayNum(d, kind) - 1));
}
export function monthDays(d: Date, kind: CalendarKind): Date[] {
  const s = monthStart(d, kind);
  const days: Date[] = [];
  let x = s;
  const m = monthNum(s, kind);
  while (monthNum(x, kind) === m) {
    days.push(x);
    x = addDays(x, 1);
  }
  return days;
}
export function shiftMonth(d: Date, kind: CalendarKind, delta: number): Date {
  const s = monthStart(d, kind);
  if (delta > 0) return addDays(s, monthDays(s, kind).length + 1);
  return monthStart(addDays(s, -2), kind);
}

export function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  const p = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${p(m)}:${p(sec)}` : `${p(m)}:${p(sec)}`;
}

/** "2h 15m" */
export function duration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const h = Math.floor(mins / 60), m = mins % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

/** "2:15" */
export function shortDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  return `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, "0")}`;
}

export function time(d: Date): string {
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/** Minutes since midnight → "8", "9:30" */
export function slotTime(m: number): string {
  const h = Math.floor(m / 60), mm = m % 60;
  return mm === 0 ? `${h}` : `${h}:${String(mm).padStart(2, "0")}`;
}
