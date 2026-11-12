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
  /** "Are you still there?" is showing: seconds left to answer */
  askingLeft: number | null; imHere: () => void;
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

/** The session open when Orbit was closed comes back paused, with its time */
const SAVED = "orbit-timer-session";
const saved = (() => { try { const s = JSON.parse(localStorage.getItem(SAVED) ?? "null"); return s && s.sessionStart ? s : null; } catch { return null; } })();

export function TimerProvider({ children }: { children: React.ReactNode }) {
  const { data, actions } = useStore();
  const friends = useFriends();
  const [mode, setMode] = useState<Mode>(saved?.mode ?? "stopwatch");
  const [target, setTargetState] = useState<TodoRef | null>(saved?.target ?? null);
  const [categoryID, setCategoryID] = useState<string | undefined>(saved?.categoryID);
  const [note, setNote] = useState("");
  const [phase, setPhase] = useState<Phase>(saved?.phase ?? "focus");
  const [accumulated, setAccumulated] = useState<number>(saved?.elapsed ?? 0);
  const [runStart, setRunStart] = useState<number | null>(null);
  const [sessionStart, setSessionStart] = useState<number | null>(saved?.sessionStart ?? null);
  const [now, setNow] = useState(Date.now());
  const [completed, setCompleted] = useState(0);
  const [askingLeft, setAskingLeft] = useState<number | null>(null);
  const autoPaused = useRef(false);
  const dataRef = useRef(data); dataRef.current = data;

  const running = runStart !== null;
  const active = sessionStart !== null;
  const elapsed = accumulated + (runStart ? (now - runStart) / 1000 : 0);
  // a to-do with its own study time sets the Pomodoro focus to exactly that long
  const ownMinutes = (() => {
    if (!target) return undefined;
    if (target.kind === "schedule") return data.schedule.find((x) => x.id === target.id)?.minutes;
    return undefined;
  })();
  const phaseLength = mode === "pomodoro" ? (phase === "focus" ? (ownMinutes ?? data.settings.pomodoroMinutes) : data.settings.breakMinutes) * 60 : null;
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

  // Share the timer with the island window: written only when something changes (not every second); the island counts on its own
  useEffect(() => {
    try {
      localStorage.setItem("orbit-island-timer", JSON.stringify({ running, active, phase, mode, base: accumulated, runStart, phaseLength, title: targetTitle, completed }));
    } catch { /* storage full or blocked */ }
  }, [running, active, phase, mode, accumulated, runStart, phaseLength, targetTitle, completed]);

  // Remember the open session for the next start (written when the window closes or hides, and when the state changes: never every second)
  const snap = useRef<() => void>(() => {});
  snap.current = () => {
    try {
      if (!active) localStorage.removeItem(SAVED);
      else localStorage.setItem(SAVED, JSON.stringify({ mode, target, categoryID, phase, elapsed, sessionStart, note }));
    } catch { /* blocked */ }
  };
  useEffect(() => { snap.current(); }, [running, active, phase, mode, target]);
  useEffect(() => {
    const f = () => snap.current();
    window.addEventListener("beforeunload", f); document.addEventListener("visibilitychange", f);
    return () => { window.removeEventListener("beforeunload", f); document.removeEventListener("visibilitychange", f); };
  }, []);

  // TimerGuard: only while the timer runs, look every 5 s (a light call, no loop when stopped) at how long you have been idle
  // and which program is in front. Only the Windows app can see this; a browser tab does nothing here.
  const GUARD_ANSWER = 60;
  const pauseRef = useRef(pause); pauseRef.current = pause;
  const startRef = useRef(start); startRef.current = start;
  const askedAt = useRef<number | null>(null);
  const lastPresence = useRef(Date.now());   // timer started or the member answered: not asked again before the chosen time has passed
  useEffect(() => {
    const guardMin = data.settings.guardMinutes ?? 0, apps = (data.settings.pauseApps ?? []).map((a) => a.toLowerCase());
    if (!running || !inTauri() || (!guardMin && !apps.length)) { askedAt.current = null; setAskingLeft(null); return; }
    let alive = true;
    lastPresence.current = Date.now();
    const tick = async () => {
      try {
        const { invoke } = await import("@tauri-apps/api/core");
        if (apps.length) {
          const fg = await invoke<string>("foreground_app");
          if (!alive) return;
          if (fg && apps.includes(fg)) { autoPaused.current = true; pauseRef.current(); return; }
        }
        if (guardMin) {
          const idle = await invoke<number>("idle_seconds");
          if (!alive) return;
          if (idle < guardMin * 60 || Date.now() - lastPresence.current < guardMin * 60_000) { if (askedAt.current !== null) { askedAt.current = null; setAskingLeft(null); } return; }
          if (askedAt.current === null) askedAt.current = Date.now();
          const left = GUARD_ANSWER - Math.floor((Date.now() - askedAt.current) / 1000);
          if (left <= 0) { askedAt.current = null; setAskingLeft(null); pauseRef.current(); } else setAskingLeft(left);
        }
      } catch { /* not available */ }
    };
    const id = setInterval(tick, 5000);
    return () => { alive = false; clearInterval(id); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, data.settings.guardMinutes, data.settings.pauseApps]);

  // Paused by a chosen program: carry on when you are back in Orbit's own window
  useEffect(() => {
    const back = () => { if (autoPaused.current && !running && active) { autoPaused.current = false; startRef.current(); } };
    window.addEventListener("focus", back); return () => window.removeEventListener("focus", back);
  }, [running, active]);

  const value: Timer = {
    askingLeft, imHere: () => { askedAt.current = null; lastPresence.current = Date.now(); setAskingLeft(null); },
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

/** "Are you still there?": shown over any page while the guard waits for an answer */
export function TimerGuardPrompt() {
  const t = useTimer();
  if (t.askingLeft === null) return null;
  return (
    <div className="modal-bg"><div className="modal" style={{ width: 340, textAlign: "center" }}>
      <h3>Are you still there?</h3>
      <div className="muted" style={{ margin: "8px 0 14px" }}>The timer will pause in {t.askingLeft}s and keep your time so far.</div>
      <button className="btn" autoFocus onClick={t.imHere}>I'm here</button>
    </div></div>
  );
}
