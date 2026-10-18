import React, { createContext, useContext, useEffect, useRef, useState } from "react";
import { uid } from "./model";
import { categoryOf, TodoRef, titleOf, useStore } from "./store";
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

function beep() {
  try {
    const a = new AudioContext(); const o = a.createOscillator(); const g = a.createGain();
    o.frequency.value = 880; o.connect(g); g.connect(a.destination); g.gain.setValueAtTime(0.25, a.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001, a.currentTime + 1.2); o.start(); o.stop(a.currentTime + 1.2);
  } catch { /* no audio */ }
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
      const c = categoryOf(d, cat); subject = c?.name ?? t?.title ?? ""; colorHex = c?.colorHex ?? "#8E8E93";
    } else {
      const c = categoryOf(d, cat); subject = c?.name ?? "Free study"; colorHex = c?.colorHex ?? "#8E8E93";
    }
    actions.addSession({ id: uid(), categoryID: cat, taskID, scheduleEntryID, subject, colorHex,
      start: new Date(sessionStart).toISOString(), duration: Math.round(seconds), note });
    setNote("");
  };

  const reset = () => { setAccumulated(0); setRunStart(null); setSessionStart(null); };
  const start = () => { if (running) return; if (!active) setSessionStart(Date.now()); setRunStart(Date.now()); setNow(Date.now()); };
  const pause = () => { if (!running) return; setAccumulated(elapsed); setRunStart(null); };
  const stop = (save = true) => { if (save && phase === "focus") saveSession(elapsed); reset(); setPhase("focus"); };

  useEffect(() => {
    if (!running) return;
    const t = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(t);
  }, [running]);

  // Pomodoro phase end
  useEffect(() => {
    if (!phaseLength || !running || elapsed < phaseLength) return;
    beep();
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
