import { useCallback, useEffect, useRef, useState } from "react";
import { PlanetCanvas } from "../components";
import { planetByID, PLANETS } from "../lib/planets";
import { clock } from "../lib/dates";
import type { IslandCmd } from "../lib/island";

/** The Orbit island: the Mac app's Notchbit for Windows. A black shape hanging from the top edge of the screen, with the planet on the
 *  left and the timer (or headphones while music plays) on the right. Rest the pointer on it to peek, click to open the big view.
 *  It lives in its own small window and never polls: it wakes on storage events (the main window's data) and on media events from Windows.
 *  The shape animates inside the window; the window itself is resized first when opening and after the shape has shrunk when closing. */

interface TimerState { running: boolean; active: boolean; phase: "focus" | "rest"; mode: "stopwatch" | "pomodoro"; base: number; runStart: number | null; phaseLength: number | null; title: string | null; completed: number }
interface Todo { kind: "schedule" | "task"; id: string; title: string; color: string }
interface NextUp { key: string; title: string; color: string; timeText: string; startsAt: number; canStart: boolean; id: string }
interface Cfg { motion: boolean; due: boolean; music: boolean; clickOnly: boolean; speed: number; openDelay: number; closeDelay: number; planetSize: number; musicHold: number }
interface Info { planet: string; cfg?: Cfg; todos: Todo[]; due: number; countdown?: { title: string; emoji: string; color: string; when: number; text: string }; nextUp?: NextUp;
  dateTag: { a: string; b: string; even: boolean }; pomodoro: number; accent: string }
interface Media { has_track: boolean; title: string; artist: string; app: string; playing: boolean; art: string }

type Level = "closed" | "peek" | "full";
type Tab = "Timer" | "Tasks" | "Music" | "Days";
const NOTCH_W = 170, NOTCH_H = 32, WING = 52;
const sizeOf = (l: Level, tab: Tab) => l === "closed" ? { w: NOTCH_W + 2 * WING, h: NOTCH_H }
  : l === "peek" ? { w: Math.max(336, NOTCH_W + 150), h: NOTCH_H + 60 }
  : { w: 372, h: NOTCH_H + (tab === "Timer" ? 160 : tab === "Tasks" ? 176 : 120) };

const inApp = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
/** In a plain browser (no Windows app) there is nothing to read: show sample data so the look can be checked */
const DEMO: Record<string, unknown> = {
  "orbit-island-info": { planet: "terra", due: 7, pomodoro: 25, accent: "#5B7CFA", dateTag: { a: "Aban 18", b: "Mon · Even wk", even: true },
    todos: [{ kind: "task", id: "1", title: "Read chapter 3", color: "#4F7CF7" }, { kind: "task", id: "2", title: "IELTS writing", color: "#F28C38" }],
    countdown: { title: "IELTS exam", emoji: "🎯", color: "#6366F1", when: Date.now() + 9 * 86_400_000, text: "1405/08/24 · Sunday · 09:00" } },
  "orbit-island-timer": { running: true, active: true, phase: "focus", mode: "pomodoro", base: 300, runStart: Date.now(), phaseLength: 1500, title: "Read chapter 3", completed: 0 },
};
const read = <T,>(k: string): T | null => { try { return JSON.parse(localStorage.getItem(k) ?? "null") ?? (inApp ? null : (DEMO[k] as T)); } catch { return null; } };
const invoke = async (cmd: string, args?: Record<string, unknown>) => { try { return await (await import("@tauri-apps/api/core")).invoke(cmd, args); } catch { return undefined; } };
const send = (c: Omit<IslandCmd, "n">) => { try { localStorage.setItem("orbit-island-cmd", JSON.stringify({ ...c, n: `${Date.now()}-${Math.random()}` })); } catch { /* blocked */ } };

const DEF: Cfg = { motion: true, due: true, music: true, clickOnly: false, speed: 1, openDelay: 0.12, closeDelay: 0.35, planetSize: 30, musicHold: 30 };
const SPRING = "cubic-bezier(.34,1.35,.5,1)";
const WHITE = (a: number) => `rgba(255,255,255,${a})`;

export default function Island() {
  const [timer, setTimer] = useState<TimerState | null>(() => read("orbit-island-timer"));
  const [info, setInfo] = useState<Info | null>(() => read("orbit-island-info"));
  const [media, setMedia] = useState<Media | null>(null);
  const [now, setNow] = useState(Date.now());
  const [level, setLevel] = useState<Level>("closed");
  const [tab, setTab] = useState<Tab>("Timer");
  const [shape, setShape] = useState(sizeOf("closed", "Timer"));
  const [typing, setTyping] = useState(false);
  const [picking, setPicking] = useState(false);
  const [newTask, setNewTask] = useState("");
  const [dismissed, setDismissed] = useState<string[]>([]);
  const cfg = info?.cfg ?? DEF;
  const [lastPlay, setLastPlay] = useState(0);
  useEffect(() => { if (media?.playing) setLastPlay(Date.now()); }, [media?.playing, media?.title]);
  const timers = useRef<{ enter?: number; leave?: number; shrink?: number }>({});

  // ---- data from the main window and from Windows' media controls (events only) ----
  useEffect(() => {
    document.documentElement.style.background = "transparent"; document.body.style.background = "transparent";
    const on = (e: StorageEvent) => {
      if (e.key === "orbit-island-timer") setTimer(read("orbit-island-timer"));
      if (e.key === "orbit-island-info") setInfo(read("orbit-island-info"));
    };
    window.addEventListener("storage", on);
    let off: (() => void) | undefined;
    void invoke("media_current").then((m) => m && setMedia(m as Media));
    void import("@tauri-apps/api/event").then(({ listen }) => listen<Media>("media-changed", (e) => setMedia(e.payload))).then((u) => { off = u; }).catch(() => {});
    return () => { window.removeEventListener("storage", on); off?.(); };
  }, []);
  // a 1 s clock only while something on screen needs it: a running timer, or the countdown tab
  const needsClock = !!timer?.running || (level === "full" && tab === "Days");
  useEffect(() => { if (!needsClock) return; setNow(Date.now()); const id = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(id); }, [needsClock]);
  // "Next up": open the peek by itself when it is time, then go away on its own
  const nextUp = info?.nextUp && !dismissed.includes(info.nextUp.key) ? info.nextUp : undefined;
  useEffect(() => { if (nextUp && level === "closed") { setLevel("peek"); timers.current.leave = window.setTimeout(() => setLevel((l) => (l === "peek" ? "closed" : l)), 12_000); } }, [nextUp?.key]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---- size: window first when growing, shape first when shrinking ----
  const target = sizeOf(level, tab);
  useEffect(() => {
    window.clearTimeout(timers.current.shrink);
    const growing = target.w >= shape.w && target.h >= shape.h;
    const placeShape = () => requestAnimationFrame(() => setShape(target));
    if (growing) { void invoke("island_resize", { width: target.w, height: target.h }).then(placeShape); }
    else { setShape(target); timers.current.shrink = window.setTimeout(() => void invoke("island_resize", { width: target.w, height: target.h }), 420); }
  }, [target.w, target.h]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---- pointer ----
  const set = useCallback((l: Level) => setLevel(l), []);
  const enter = () => {
    window.clearTimeout(timers.current.leave);
    if (level === "closed" && !cfg.clickOnly) timers.current.enter = window.setTimeout(() => set("peek"), cfg.openDelay * 1000);
  };
  const leave = () => {
    window.clearTimeout(timers.current.enter);
    if (typing) return;
    timers.current.leave = window.setTimeout(() => { setPicking(false); set("closed"); }, level === "full" ? Math.max(700, cfg.closeDelay * 1000) : cfg.closeDelay * 1000);
  };
  const elapsed = timer ? timer.base + (timer.runStart ? (now - timer.runStart) / 1000 : 0) : 0;
  const shown = timer?.phaseLength ? Math.max(0, timer.phaseLength - elapsed) : elapsed;
  const progress = timer?.phaseLength ? Math.min(1, elapsed / timer.phaseLength) : (elapsed % 3600) / 3600;
  const accent = info?.accent ?? "#5B7CFA";
  const planet = planetByID(info?.planet) ?? PLANETS[0];
  // music view stays a while after pausing, in case you play again
  const musicOn = cfg.music && !!media?.has_track && (media.playing || Date.now() - lastPlay < cfg.musicHold * 1000);
  const open = level !== "closed";
  const round = open ? 26 : 12;

  // ---- pieces ----
  const btn = (label: string, onClick: () => void, o: { primary?: boolean; danger?: boolean; title?: string; small?: boolean } = {}) => (
    <button title={o.title} onClick={(e) => { e.stopPropagation(); onClick(); }}
      style={{ border: "none", cursor: "pointer", font: "inherit", fontWeight: 700, fontSize: o.small ? 11 : 12, borderRadius: 99, padding: "5px 12px", whiteSpace: "nowrap",
        background: o.primary ? "#fff" : o.danger ? "rgba(239,68,68,.28)" : WHITE(0.14), color: o.primary ? "#000" : "#fff" }}>{label}</button>
  );
  const round2 = (sym: string, onClick: () => void, primary = false) => (
    <button onClick={(e) => { e.stopPropagation(); onClick(); }} style={{ width: primary ? 30 : 26, height: primary ? 30 : 26, borderRadius: 99, border: "none", cursor: "pointer", color: primary ? "#000" : "#fff",
      background: primary ? "#fff" : WHITE(0.14), fontSize: 11, display: "grid", placeItems: "center" }}>{sym}</button>
  );
  const cover = (side: number) => media?.art
    ? <img src={media.art} alt="" style={{ width: side, height: side, borderRadius: side * 0.27, objectFit: "cover" }} />
    : <div style={{ width: side, height: side, borderRadius: side * 0.27, display: "grid", placeItems: "center", background: `linear-gradient(135deg, ${accent}, #6366F1)`, fontSize: side * 0.45 }}>♪</div>;
  const musicButtons = (compact: boolean) => (
    <div style={{ display: "flex", gap: compact ? 6 : 10, alignItems: "center" }}>
      {round2("⏮", () => invoke("media_command", { cmd: "previous" }))}
      {round2(media?.playing ? "⏸" : "▶", () => invoke("media_command", { cmd: "toggle" }), true)}
      {round2("⏭", () => invoke("media_command", { cmd: "next" }))}
    </div>
  );
  const startLabel = (
    <button onClick={(e) => { e.stopPropagation(); send({ cmd: "start" }); }} style={{ border: "none", cursor: "pointer", font: "inherit", fontWeight: 700, fontSize: 12, color: "#fff", borderRadius: 99, padding: "7px 13px",
      background: `linear-gradient(90deg, ${accent}, #6366F1)` }}>▶ Start</button>
  );

  const topRow = (
    <div style={{ display: "flex", height: NOTCH_H, width: shape.w, flexShrink: 0, alignItems: "center", justifyContent: "space-between" }}>
      <div style={{ width: open ? undefined : WING, display: "flex", alignItems: "center", justifyContent: open ? "flex-start" : "flex-end", gap: 6, paddingLeft: open ? 12 : 0 }}>
        {cfg.due && info && info.due > 0 && <span title="Words to review today" onClick={(e) => { e.stopPropagation(); send({ cmd: "leitner" }); }}
          style={{ fontSize: 10, fontWeight: 800, color: "#fff", background: "#F97316", borderRadius: 99, padding: "0 5px", minWidth: 16, height: 16, display: "grid", placeItems: "center", cursor: "pointer" }}>{info.due}</span>}
        <div style={{ width: cfg.planetSize, height: cfg.planetSize, animation: cfg.motion ? "island-bob 3.2s ease-in-out infinite" : undefined }}>
          {musicOn && !open && media?.art ? cover(Math.round(cfg.planetSize * 0.74)) : <PlanetCanvas planet={planet} size={cfg.planetSize} />}
        </div>
      </div>
      {open ? (
        <div style={{ textAlign: "right", paddingRight: 12, lineHeight: 1.15 }}>
          <div style={{ fontSize: 10.5, fontWeight: 600, color: WHITE(0.9) }}>{info?.dateTag.a}</div>
          <div style={{ fontSize: 9, fontWeight: 700, color: info?.dateTag.even ? "#22D3EE" : "#F472B6" }}>{info?.dateTag.b}</div>
        </div>
      ) : (
        <div style={{ width: WING, display: "flex", alignItems: "center", paddingLeft: 2 }}>
          {musicOn ? <span style={{ fontSize: 17, color: "#F97316" }}>🎧</span>
            : timer?.active ? (
              <span style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 12, fontWeight: 600, fontVariantNumeric: "tabular-nums", opacity: timer.running ? 1 : 0.6 }}>
                <i style={{ width: timer.running ? 5 : 3, height: timer.running ? 5 : 8, borderRadius: timer.running ? 5 : 1, background: timer.phase === "focus" ? "#F97316" : "#22C55E" }} />
                {clock(shown)}
              </span>) : null}
        </div>
      )}
    </div>
  );

  const peek = (
    <div style={{ padding: "0 16px 10px", height: "100%", display: "flex", alignItems: "center", gap: 11 }} onClick={() => { set("full"); setTab(media?.has_track ? "Music" : timer?.active ? "Timer" : "Tasks"); }}>
      {nextUp ? (<>
        <i style={{ width: 4, height: 38, borderRadius: 2, background: nextUp.color }} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 9, fontWeight: 800, letterSpacing: 1.4, color: nextUp.color }}>{Math.ceil((nextUp.startsAt - now) / 60_000) <= 0 ? "NOW" : `NEXT · IN ${Math.ceil((nextUp.startsAt - now) / 60_000)} MIN`}</div>
          <div style={{ fontSize: 13, fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{nextUp.title}</div>
          <div style={{ fontSize: 11, color: WHITE(0.6) }}>{nextUp.timeText}</div>
        </div>
        {nextUp.canStart && !timer?.active && btn("▶ Start", () => { send({ cmd: "start", kind: "schedule", id: nextUp.id }); setDismissed([...dismissed, nextUp.key]); })}
        {round2("✕", () => setDismissed([...dismissed, nextUp.key]))}
      </>) : cfg.music && media?.has_track ? (<>
        {cover(42)}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 13, fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{media.title}</div>
          <div style={{ fontSize: 11, color: WHITE(0.6), whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{media.artist}</div>
        </div>
        {musicButtons(true)}
      </>) : timer?.active ? (<>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 26, fontWeight: 700, fontVariantNumeric: "tabular-nums", lineHeight: 1.1 }}>{clock(shown)}</div>
          <div style={{ fontSize: 11, color: WHITE(0.6), whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{timer.title ?? (timer.phase === "focus" ? "Focus" : "Break")}</div>
        </div>
        {round2(timer.running ? "⏸" : "▶", () => send({ cmd: "toggle" }), true)}{round2("⏹", () => send({ cmd: "stop" }))}{!timer.running && round2("🗑", () => send({ cmd: "discard" }))}
      </>) : (<>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13, fontWeight: 600 }}>Ready to focus?</div>
          <div style={{ fontSize: 11, color: WHITE(0.6) }}>{timer?.mode === "pomodoro" ? `${info?.pomodoro ?? 25} min Pomodoro` : "Stopwatch"}</div>
        </div>
        {startLabel}
      </>)}
    </div>
  );

  const TABS: [Tab, string][] = [["Timer", "⏱"], ["Tasks", "☑"], ["Music", "♪"], ["Days", "⏳"]];
  const timerTab = picking && !timer?.active ? (
    <div style={{ overflow: "auto", height: "100%", display: "grid", gap: 4, alignContent: "start" }}>
      {[{ kind: undefined, id: "", title: "Free study", color: "#8E8E93" } as unknown as Todo, ...(info?.todos ?? [])].map((t) => (
        <button key={t.kind + t.id} onClick={(e) => { e.stopPropagation(); send({ cmd: "start", kind: t.kind, id: t.id || undefined }); setPicking(false); }}
          style={{ display: "flex", alignItems: "center", gap: 8, textAlign: "left", border: "none", cursor: "pointer", color: "#fff", font: "inherit", fontSize: 12, padding: "5px 10px", borderRadius: 10, background: WHITE(0.07) }}>
          <i style={{ width: 7, height: 7, borderRadius: 4, background: t.color }} />{t.title}</button>
      ))}
    </div>
  ) : (
    <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
      <div style={{ position: "relative", width: 76, height: 76, flexShrink: 0 }}>
        <svg width="76" height="76" viewBox="0 0 76 76"><circle cx="38" cy="38" r="35" fill="none" stroke={WHITE(0.1)} strokeWidth="4" />
          <defs><linearGradient id="ig" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor={accent} /><stop offset="1" stopColor="#EC4899" /></linearGradient></defs>
          <circle cx="38" cy="38" r="35" fill="none" stroke="url(#ig)" strokeWidth="4" strokeLinecap="round" strokeDasharray={`${(timer?.active ? progress : 0) * 219.9} 219.9`} transform="rotate(-90 38 38)" /></svg>
        <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", textAlign: "center", lineHeight: 1.1 }}>
          <div><div style={{ fontSize: 16, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>{clock(timer?.active ? shown : (timer?.mode === "pomodoro" ? (info?.pomodoro ?? 25) * 60 : 0))}</div>
            <div style={{ fontSize: 9, fontWeight: 600, color: WHITE(0.55) }}>{timer?.mode === "stopwatch" ? "Stopwatch" : timer?.phase === "rest" ? "Break" : "Focus"}</div></div>
        </div>
      </div>
      <div style={{ display: "grid", gap: 6, minWidth: 0 }}>
        {timer?.active
          ? <div style={{ fontSize: 12, fontWeight: 500, color: WHITE(0.9) }}>{timer.title ?? "Free study"}</div>
          : <button onClick={(e) => { e.stopPropagation(); setPicking(true); }} style={{ border: "none", cursor: "pointer", color: "#fff", font: "inherit", fontSize: 11, fontWeight: 600, padding: "5px 10px", borderRadius: 99, background: WHITE(0.1), textAlign: "left" }}>☑ Free study — pick a task ⌄</button>}
        <div style={{ display: "flex", gap: 6 }}>
          {btn(timer?.running ? "⏸ Pause" : timer?.active ? "▶ Resume" : "▶ Start", () => send({ cmd: "toggle" }), { primary: true })}
          {timer?.active && btn("⏹ Finish", () => send({ cmd: "stop" }), { small: true })}
          {timer?.active && !timer.running && btn("🗑 Discard", () => send({ cmd: "discard" }), { danger: true, small: true, title: "Throw this timer away without saving the time" })}
        </div>
        {!timer?.active && <div style={{ display: "inline-flex", background: WHITE(0.07), borderRadius: 99, width: "fit-content" }}>
          {(["stopwatch", "pomodoro"] as const).map((m) => <button key={m} onClick={(e) => { e.stopPropagation(); send({ cmd: "mode", mode: m }); }}
            style={{ border: "none", cursor: "pointer", font: "inherit", fontSize: 10, fontWeight: 600, padding: "3px 10px", borderRadius: 99, color: timer?.mode === m ? "#fff" : WHITE(0.5), background: timer?.mode === m ? WHITE(0.18) : "transparent" }}>{m === "stopwatch" ? "Stopwatch" : "Pomodoro"}</button>)}
        </div>}
      </div>
    </div>
  );

  const tasksTab = (
    <div style={{ display: "flex", flexDirection: "column", gap: 8, height: "100%" }}>
      {info?.todos.length ? (
        <div style={{ overflow: "auto", flex: 1, display: "grid", gap: 4, alignContent: "start" }}>
          {info.todos.map((t) => (
            <div key={t.kind + t.id} style={{ display: "flex", alignItems: "center", gap: 9, padding: "5px 10px", borderRadius: 10, background: WHITE(0.06), fontSize: 12, fontWeight: 500 }}>
              <i style={{ width: 7, height: 7, borderRadius: 4, background: t.color, flexShrink: 0 }} />
              <span style={{ flex: 1, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t.title}</span>
              {timer?.active ? null : <button title="Start the timer on this" onClick={(e) => { e.stopPropagation(); send({ cmd: "start", kind: t.kind, id: t.id }); }} style={miniBtn}>▶</button>}
              <button title="Mark done" onClick={(e) => { e.stopPropagation(); send({ cmd: "toggleDone", kind: t.kind, id: t.id }); }} style={{ ...miniBtn, background: WHITE(0.08) }}>✓</button>
            </div>))}
        </div>
      ) : <div style={{ flex: 1, display: "grid", placeItems: "center", fontSize: 12, color: WHITE(0.55) }}>Nothing left for today ✨</div>}
      <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", borderRadius: 99, background: WHITE(0.09) }}>
        <span style={{ color: WHITE(0.5), fontSize: 11 }}>＋</span>
        <input value={newTask} placeholder="Add a task for today" onChange={(e) => setNewTask(e.target.value)} onFocus={() => setTyping(true)} onBlur={() => setTyping(false)}
          onKeyDown={(e) => { if (e.key === "Enter" && newTask.trim()) { send({ cmd: "addTask", title: newTask.trim() }); setNewTask(""); } }}
          style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "#fff", font: "inherit", fontSize: 12 }} />
      </div>
    </div>
  );

  const musicTab = media?.has_track ? (
    <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
      <div style={{ filter: `drop-shadow(0 2px 8px ${accent}80)` }}>{cover(62)}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 700, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{media.title}</div>
        <div style={{ fontSize: 12, color: WHITE(0.65), whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{media.artist}</div>
        <div style={{ fontSize: 10, fontWeight: 600, color: WHITE(0.4) }}>{media.app.replace(/\.exe$/i, "")}</div>
      </div>
      {musicButtons(false)}
    </div>
  ) : (
    <div style={{ height: "100%", display: "grid", placeItems: "center", textAlign: "center" }}>
      <div><div style={{ fontSize: 22, color: WHITE(0.4) }}>♪</div><div style={{ fontSize: 12, fontWeight: 600 }}>Nothing playing</div>
        <div style={{ fontSize: 10, color: WHITE(0.45) }}>Play something in Spotify, your browser or any music app</div></div>
    </div>
  );

  const daysTab = info?.countdown ? (() => {
    const c = info.countdown, ms = c.when - now, past = ms <= 0, secs = Math.floor(Math.abs(ms) / 1000);
    const days = Math.floor(secs / 86400), p2 = (n: number) => String(n).padStart(2, "0");
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
        <span style={{ fontSize: 44 }}>{c.emoji}</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14, fontWeight: 700, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{c.title}</div>
          <div style={{ fontSize: 11, color: WHITE(0.55) }}>{c.text}</div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: c.color }}>{past ? (days === 0 ? "Happening now" : `${days} day${days === 1 ? "" : "s"} ago`) : days === 0 ? "Today" : `${days} day${days === 1 ? "" : "s"}`}</div>
          {!past && <div style={{ fontSize: 14, fontWeight: 500, color: WHITE(0.65), fontVariantNumeric: "tabular-nums" }}>{p2(Math.floor((secs % 86400) / 3600))}:{p2(Math.floor((secs % 3600) / 60))}:{p2(secs % 60)}</div>}
        </div>
      </div>);
  })() : (
    <div style={{ height: "100%", display: "grid", placeItems: "center", textAlign: "center" }}>
      <div><div style={{ fontSize: 12, fontWeight: 600, marginBottom: 8 }}>No event yet</div>{btn("＋ Add one", () => send({ cmd: "countdown" }), { small: true })}</div>
    </div>
  );

  const full = (
    <div style={{ padding: "3px 14px 10px", height: "100%", display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ display: "flex", gap: 3, alignItems: "center" }}>
        {TABS.map(([t, ic]) => (
          <button key={t} onClick={(e) => { e.stopPropagation(); setTyping(false); setPicking(false); setTab(t); }}
            style={{ border: "none", cursor: "pointer", font: "inherit", display: "flex", alignItems: "center", gap: 5, padding: tab === t ? "4px 10px" : "4px 8px", borderRadius: 99, fontSize: 11, fontWeight: 600,
              color: tab === t ? "#fff" : WHITE(0.55), background: tab === t ? WHITE(0.16) : "transparent", whiteSpace: "nowrap" }}>
            {ic}{tab === t && t}{t === "Music" && musicOn && <i style={{ width: 5, height: 5, borderRadius: 3, background: "#22C55E" }} />}</button>))}
        <span style={{ flex: 1 }} />
        <button title="Island settings" onClick={(e) => { e.stopPropagation(); send({ cmd: "settings" }); invoke("open_main"); }} style={{ ...miniBtn, width: 24, background: "transparent", color: WHITE(0.5) }}>⚙</button>
        <button onClick={(e) => { e.stopPropagation(); set("peek"); }} style={{ ...miniBtn, width: 24, background: "transparent", color: WHITE(0.5) }}>⌃</button>
      </div>
      <div style={{ flex: 1, minHeight: 0 }}>{tab === "Timer" ? timerTab : tab === "Tasks" ? tasksTab : tab === "Music" ? musicTab : daysTab}</div>
    </div>
  );

  return (
    <div style={inApp ? undefined : { position: "fixed", inset: 0, background: "linear-gradient(135deg,#e2e8f0,#cbd5e1)" }}>
    {!inApp && <div style={{ position: "absolute", top: 120, width: "100%", textAlign: "center", color: "#475569", font: "14px system-ui" }}>Preview with sample data. Move the pointer onto the black bar at the top centre, then click it.</div>}
    <div onMouseEnter={enter} onMouseLeave={leave} onClick={() => { if (level === "closed") set("peek"); }} style={{ width: "100vw", height: "100vh", display: "flex", justifyContent: "center", alignItems: "flex-start", overflow: "hidden", color: "#fff", userSelect: "none",
      font: "500 13px 'Segoe UI Variable', 'Segoe UI', system-ui, sans-serif" }}>
      <style>{`@keyframes island-bob{0%,100%{transform:translateY(-1px)}50%{transform:translateY(1.5px)}}`}</style>
      <div style={{ position: "relative", width: shape.w, height: shape.h, overflow: "hidden", background: "#000",
        borderRadius: `0 0 ${round}px ${round}px`, transition: `width ${0.42 / cfg.speed}s ${SPRING}, height ${0.42 / cfg.speed}s ${SPRING}, border-radius .3s` }}>
        {open && <div style={{ position: "absolute", inset: 0, pointerEvents: "none", background:
          `linear-gradient(45deg, ${accent}4D, rgba(99,102,241,.12) 55%, transparent), radial-gradient(circle at 100% 100%, rgba(236,72,153,.16), transparent 200px)` }} />}
        <div style={{ position: "relative", width: sizeOf(level, tab).w, height: sizeOf(level, tab).h, display: "flex", flexDirection: "column" }}>
          {topRow}
          <div style={{ flex: 1, minHeight: 0, opacity: open ? 1 : 0, transition: open ? "opacity .2s .12s" : "opacity .08s", pointerEvents: open ? "auto" : "none" }}>
            {level === "peek" ? peek : level === "full" ? full : null}
          </div>
        </div>
      </div>
    </div>
    </div>
  );
}

const miniBtn: React.CSSProperties = { width: 22, height: 22, borderRadius: 99, border: "none", cursor: "pointer", color: "#fff", background: "rgba(255,255,255,.14)", fontSize: 10, display: "grid", placeItems: "center", padding: 0 };
