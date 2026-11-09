import { AppData, Countdown } from "./model";

/** Old entries stored just a day ("2026-11-20"): treat that as the start of the day in local time */
export const when = (c: Countdown) => (c.date.length === 10 ? new Date(c.date + "T00:00:00") : new Date(c.date));
export const sorted = (list: Countdown[] | undefined) => [...(list ?? [])].sort((a, b) => when(a).getTime() - when(b).getTime());

/** 12 days 04:33:10 */
export function parts(c: Countdown, now = new Date()) {
  const ms = when(c).getTime() - now.getTime(), past = ms <= 0, secs = Math.floor(Math.abs(ms) / 1000);
  return { past, days: Math.floor(secs / 86400), h: Math.floor((secs % 86400) / 3600), m: Math.floor((secs % 3600) / 60), s: secs % 60 };
}
const p2 = (n: number) => String(n).padStart(2, "0");
export function headline(c: Countdown, now = new Date()) {
  const p = parts(c, now);
  if (p.past) return p.days === 0 ? "Happening now" : `${p.days} day${p.days === 1 ? "" : "s"} ago`;
  return p.days === 0 ? "Today" : `${p.days} day${p.days === 1 ? "" : "s"}`;
}
export const clockText = (c: Countdown, now = new Date()) => { const p = parts(c, now); return `${p2(p.h)}:${p2(p.m)}:${p2(p.s)}`; };
export const shortText = (c: Countdown, now = new Date()) => { const p = parts(c, now); return p.past ? headline(c, now) : `${p.days}d ${p2(p.h)}h ${p2(p.m)}m`; };

/** What the sidebar and island show: the pinned one, else the next one coming */
export function shown(d: Pick<AppData, "countdowns" | "countdownPinned">, now = new Date()): Countdown | undefined {
  const list = sorted(d.countdowns), pin = list.find((c) => c.id === d.countdownPinned);
  return pin ?? list.find((c) => when(c) >= now) ?? list[0];
}
export const daysLeft = (c: Countdown, now = new Date()) => { const p = parts(c, now); return p.past ? -p.days : p.days; };
export const nearest = (list: Countdown[] | undefined, now = new Date()) => sorted(list).find((c) => when(c) >= now);
