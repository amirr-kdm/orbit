import { ensureNotifyPermission, inTauri } from "./notify";
import { playAlarm } from "./sound";
import React, { createContext, useContext, useEffect, useRef, useState } from "react";
import { uid } from "./model";
import { categoryLabel, categoryOf, TodoRef, titleOf, useStore } from "./store";
import { useFriends } from "./friends";

type Mode = "stopwatch" | "pomodoro";
type Phase = "focus" | "rest";

interface Timer {
  mode: Mode; setMode: (m: Mode) => void;
  target: TodoRef | null; setTarget: (r: TodoRef | null) => void;
  categoryID?: string; setCategoryID: (id?: string) => void;
  note: string; setNote: (n: string) => void;
  phase: Phase; running: boolean; active: boolean;
  elapsed: number; display: number; phaseLength: number | null; completed: number;
  start: () => void; pause: () => void; stop: (save?: boolean) => void; skipBreak: () => void;
  targetTitle: string | null;
}
const Ctx = createContext<Timer | null>(null);

// ---- Pomodoro alerts ---------------------------------------------------------------------------------------------------
// In the Windows app (Tauri) notifications go through the system's toast, and a timer in Rust keeps the alarm on time even when
// the window is minimised (a web page's own timers are slowed right down then). In a plain browser the web Notification API is used.

const phaseText = (focusEnded: boolean, what: string | undefined, breakMinutes: number) => ({
  title: focusEnded ? "Focus session finished 🍅" : "Break is over ⏰",
  body: focusEnded ? `${what ? `${what}: ` : ""}nice work! Take a ${breakMinutes}-minute break.` : "Time to get back to studying.",
});

/** Ask the system to notify at the end of the phase (cancelled when the timer is paused or stopped) */
async function scheduleAlarm(seconds: number, focusEnded: boolean, what: string | undefined, breakMinutes: number) {
  if (!inTauri()) return;
  try {
    if (!(await ensureNotifyPermission())) return;
    const { invoke } = await import("@tauri-apps/api/core");
    await invoke("schedule_alarm", { seconds: Math.max(1, Math.round(seconds)), ...phaseText(focusEnded, what, breakMinutes) });
  } catch { /* not available */ }
}
async function cancelAlarm() {
  if (!inTauri()) return;
  try { const { invoke } = await import("@tauri-apps/api/core"); await invoke("cancel_alarm"); } catch { /* not available */ }
}

/** The phase ended while the page was running: a notification too if the window isn't in front (the Rust alarm may be the one that fired) */
function notifyPhaseEnd(focusEnded: boolean, what: string | undefined, breakMinutes: number) {
  if (inTauri()) return;   // the Rust alarm already showed it
  try {
    if (!("Notification" in window) || Notification.permission !== "granted") return;
    const t = phaseText(focusEnded, what, breakMinutes);
    const n = new Notification(t.title, { body: t.body, tag: "orbit-pomodoro", requireInteraction: true, silent: true });
    n.onclick = () => { window.focus(); n.close(); };
  } catch { /* not supported */ }
}

export function TimerProvider({ children }: { children: React.ReactNode }) {
  const { data, actions } = useStore();
  const friends = useFriends();
  const [mode, setMode] = useState<Mode>("stopwatch");
  const [target, setTargetState] = useState<TodoRef | null>(null);
  const [categoryID, setCategoryID] = useState<string>();
  const [note, setNote] = useState("");
  const [phase, setPhase] = useState<Phase>("focus");
  const [accumulated, setAccumulated] = useState(0);
  const [runStart, setRunStart] = useState<number | null>(null);
  const [sessionStart, setSessionStart] = useState<number | null>(null);
  const [now, setNow] = useState(Date.now());
  const [completed, setCompleted] = useState(0);
  const dataRef = useRef(data); dataRef.current = data;

  const running = runStart !== null;
  const active = sessionStart !== null;
  const elapsed = accumulated + (runStart ? (now - runStart) / 1000 : 0);
  const phaseLength = mode === "pomodoro" ? (phase === "focus" ? data.settings.pomodoroMinutes : data.settings.breakMinutes) * 60 : null;
  const display = phaseLength ? Math.max(0, phaseLength - elapsed) : elapsed;

  const targetTitle = (() => {
    if (!target) return null;
    if (target.kind === "schedule") { const e = data.schedule.find((x) => x.id === target.id); return e ? titleOf(e) : null; }
    return data.tasks.find((t) => t.id === target.id)?.title ?? null;
  })();

  const saveSession = (seconds: number) => {
    if (seconds < 30 || sessionStart === null) return;
    const d = dataRef.current;
    let subject = "", colorHex = "", cat = categoryID, scheduleEntryID, taskID;
    if (target?.kind === "schedule") {
      const e = d.schedule.find((x) => x.id === target.id);
      scheduleEntryID = target.id; cat = e?.categoryID ?? cat; subject = e ? titleOf(e) : ""; colorHex = e?.colorHex ?? "#4F7CF7";
    } else if (target?.kind === "task") {
      const t = d.tasks.find((x) => x.id === target.id);
      taskID = target.id; cat = t?.categoryID ?? cat;
      const c = categoryOf(d, cat); subject = categoryLabel(d, cat) ?? t?.title ?? ""; colorHex = c?.colorHex ?? "#8E8E93";
    } else {
      const c = categoryOf(d, cat); subject = categoryLabel(d, cat) ?? "Free study"; colorHex = c?.colorHex ?? "#8E8E93";
    }
    actions.addSession({ id: uid(), categoryID: cat, taskID, scheduleEntryID, subject, colorHex,
      start: new Date(sessionStart).toISOString(), duration: Math.round(seconds), note });
    setNote("");
  };

  const reset = () => { setAccumulated(0); setRunStart(null); setSessionStart(null); };
  const start = () => { if (running) return; if (!active) setSessionStart(Date.now()); setRunStart(Date.now()); setNow(Date.now()); if (mode === "pomodoro") void ensureNotifyPermission(); };
  const pause = () => { if (!running) return; setAccumulated(elapsed); setRunStart(null); };
  const stop = (save = true) => { if (save && phase === "focus") saveSession(elapsed); reset(); setPhase("focus"); };

  useEffect(() => {
    if (!running) return;
    const t = setInterval(() => setNow(Date.now()), 1000); // whole app re-renders on each tick
    return () => clearInterval(t);
  }, [running]);

  // Tell the system when this phase ends (and take it back when the timer pauses, stops or changes phase)
  useEffect(() => {
    if (!running || !phaseLength) { void cancelAlarm(); return; }
    void scheduleAlarm(phaseLength - elapsed, phase === "focus", targetTitle ?? undefined, data.settings.breakMinutes);
    return () => { void cancelAlarm(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, phase, phaseLength, runStart]);

  // A hidden or minimised window slows its timers right down: wake up exactly when the phase ends, and when the window comes back
  useEffect(() => {
    if (!running) return;
    const wake = () => setNow(Date.now());
    const t = phaseLength ? window.setTimeout(wake, Math.max(0, (phaseLength - elapsed) * 1000) + 50) : undefined;
    document.addEventListener("visibilitychange", wake); window.addEventListener("focus", wake);
    return () => { if (t) window.clearTimeout(t); document.removeEventListener("visibilitychange", wake); window.removeEventListener("focus", wake); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, phase, phaseLength, runStart]);

  // Pomodoro phase end
  useEffect(() => {
    if (!phaseLength || !running || elapsed < phaseLength) return;
    playAlarm(data.settings.alarmTone, data.settings.alarmVolume);
    notifyPhaseEnd(phase === "focus", targetTitle ?? undefined, data.settings.breakMinutes);
    if (phase === "focus") {
      saveSession(phaseLength); setCompleted((c) => c + 1); reset(); setPhase("rest");
      setTimeout(() => { setSessionStart(Date.now()); setRunStart(Date.now()); }, 0);
    } else { reset(); setPhase("focus"); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [elapsed]);

  // Tell friends what I'm studying
  useEffect(() => {
    const title = running && phase === "focus" ? targetTitle ?? categoryOf(data, categoryID)?.name ?? "Studying" : null;
    friends.setLive(title, sessionStart ? new Date(sessionStart) : null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, phase, targetTitle]);

  const value: Timer = {
    mode, setMode, target, setTarget: (r) => { if (!active) setTargetState(r); }, categoryID, setCategoryID, note, setNote,
    phase, running, active, elapsed, display, phaseLength, completed, start, pause, stop,
    skipBreak: () => { reset(); setPhase("focus"); }, targetTitle,
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useTimer(): Timer {
  const t = useContext(Ctx);
  if (!t) throw new Error("TimerProvider missing");
  return t;
}
