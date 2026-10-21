import { addDays, monthNum, startOfDay, yearNum } from "./dates";

/** Days in a row with study. Missed days are covered by streak freezes: 3 a month (Persian months, like the Mac app),
 *  used automatically (one day or several in a row), so one bad day doesn't break the streak. */
export const FREEZES_PER_MONTH = 3;
export interface StreakInfo { days: number; frozen: Date[]; freezesLeft: number }

export function computeStreak(studied: (d: Date) => boolean, today = new Date()): StreakInfo {
  const key = (d: Date) => yearNum(d, "persian") * 100 + monthNum(d, "persian");
  let day = startOfDay(today);
  // Today isn't over yet: an empty today doesn't break (or freeze) anything
  if (!studied(day)) day = addDays(day, -1);
  let days = 0;
  let frozen: Date[] = [], pending: Date[] = [];
  const used = new Map<number, number>();
  for (let n = 0; n < 3650; n++) {
    if (studied(day)) { days++; frozen = frozen.concat(pending); pending = []; }
    else {
      const k = key(day);
      if ((used.get(k) ?? 0) >= FREEZES_PER_MONTH) break;
      used.set(k, (used.get(k) ?? 0) + 1); pending.push(day);
    }
    day = addDays(day, -1);
  }
  const spent = frozen.filter((d) => key(d) === key(today)).length;
  return { days, frozen, freezesLeft: Math.max(0, FREEZES_PER_MONTH - spent) };
}
