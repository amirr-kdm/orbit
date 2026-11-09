import { useEffect, useRef } from "react";
import { dateText } from "../pages/Countdown";
import { shown as shownCountdown, when } from "./countdown";
import { dayKey, startOfDay } from "./dates";
import { dueCount } from "./leitner";
import { AppData } from "./model";
import { parity, scheduleRows, todosOn, useStore, entryColor, titleOf, slotTitle } from "./store";
import { useTimer } from "./timer";
import { monthDay, WEEKDAYS_SHORT, weekdayIndex } from "./dates";

/** What the island window shows, as one JSON string (it changes rarely, so it is written only when it does) */
export function islandSnapshot(d: AppData, now: Date, _tick: number): string {
  const c = shownCountdown(d, now), kind = d.settings.primaryCalendar;
  const todos = todosOn(d, now).filter((x) => !x.isDone && !x.isSkipped).map((x) => ({ kind: x.ref.kind, id: x.ref.id, title: x.title, color: x.color }));
  // the next weekly-schedule item that starts within the lead time (10 min)
  const lead = (d.settings.islandLead ?? 10) * 60_000, mins = now.getHours() * 60 + now.getMinutes();
  const next = d.settings.islandNextUp === false ? undefined : scheduleRows(d, now).filter((r) => !r.isDone && !r.isSkipped && r.slot.startMinute > mins && (r.slot.startMinute - mins) * 60_000 <= lead)
    .sort((a, b) => a.slot.startMinute - b.slot.startMinute)[0];
  const par = parity(d, now);
  return JSON.stringify({
    planet: d.settings.islandPlanet || d.avatarPlanet || "terra",
    cfg: { motion: d.settings.islandMotion !== false, due: d.settings.islandDue !== false, music: d.settings.islandMusic !== false, clickOnly: !!d.settings.islandClickOnly,
      speed: d.settings.islandSpeed ?? 1, openDelay: d.settings.islandOpenDelay ?? 0.12, closeDelay: d.settings.islandCloseDelay ?? 0.35, planetSize: d.settings.islandPlanetSize ?? 30, musicHold: d.settings.islandMusicHold ?? 30 },
    todos, due: dueCount(d.leitner, now),
    countdown: c ? { title: c.title, emoji: c.emoji, color: c.colorHex, when: when(c).getTime(), text: dateText(when(c), kind) } : undefined,
    nextUp: next ? { key: `${next.entry.id}|${dayKey(startOfDay(now))}`, title: titleOf(next.entry), color: entryColor(d, next.entry) ?? "#6366F1", timeText: slotTitle(next.slot),
      startsAt: startOfDay(now).getTime() + next.slot.startMinute * 60_000, canStart: next.entry.kind === "todo", id: next.entry.id } : undefined,
    dateTag: { a: monthDay(now, kind, true), b: `${WEEKDAYS_SHORT[weekdayIndex(now)]} · ${par === "even" ? "Even wk" : "Odd wk"}`, even: par === "even" },
    pomodoro: d.settings.pomodoroMinutes, accent: d.settings.accent,
  });
}

export interface IslandCmd { n: string; cmd: "toggle" | "stop" | "discard" | "start" | "mode" | "toggleDone" | "addTask" | "settings" | "countdown" | "leitner"; kind?: "schedule" | "task"; id?: string; title?: string; mode?: "stopwatch" | "pomodoro" }

/** Runs what the island's buttons ask for (it is a separate window: it can only leave notes in storage) */
export function useIslandCommands(go: (t: any) => void) {
  const { actions } = useStore();
  const timer = useTimer();
  const last = useRef("");
  const ref = useRef({ actions, timer, go }); ref.current = { actions, timer, go };
  useEffect(() => {
    const on = (e: StorageEvent) => {
      if (e.key !== "orbit-island-cmd" || !e.newValue) return;
      let c: IslandCmd; try { c = JSON.parse(e.newValue); } catch { return; }
      if (c.n === last.current) return; last.current = c.n;
      const { actions: a, timer: t, go: g } = ref.current;
      if (c.cmd === "toggle") (t.running ? t.pause() : t.start());
      else if (c.cmd === "stop") t.stop(true);
      else if (c.cmd === "discard") t.stop(false);
      else if (c.cmd === "mode" && c.mode && !t.active) t.setMode(c.mode);
      else if (c.cmd === "start") { if (c.kind && c.id && !t.active) t.setTarget({ kind: c.kind, id: c.id }); else if (!c.id && !t.active) t.setTarget(null); setTimeout(() => ref.current.timer.start(), 0); }
      else if (c.cmd === "toggleDone" && c.kind && c.id) a.toggleDone({ kind: c.kind, id: c.id }, new Date());
      else if (c.cmd === "addTask" && c.title) a.addTask(c.title, new Date());
      else if (c.cmd === "settings") g("settings");
      else if (c.cmd === "countdown") g("countdown");
      else if (c.cmd === "leitner") g("leitner");
    };
    window.addEventListener("storage", on); return () => window.removeEventListener("storage", on);
  }, []);
}
