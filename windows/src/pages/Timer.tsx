import { useEffect, useRef, useState } from "react";
import { frameLoop, Modal } from "../components";
import { addDays, clock, duration, startOfDay, time } from "../lib/dates";
import { uid } from "../lib/model";
import { categoryLabel, categoryOf, orderedCategories, refKey, sessionsIn, studyOn, subjectOf, todosOn, useStore } from "../lib/store";
import { useTimer } from "../lib/timer";
import launchUrl from "../assets/timer-launch.png";
import breakUrl from "../assets/timer-break.png";
import earthUrl from "../assets/timer-earth.png";

/** The timer — same as the Mac app: a solar-system clock over a night launch sky, "Today's flights" on the side */
export default function TimerPage() {
  const { data, actions } = useStore();
  const t = useTimer();
  const [manual, setManual] = useState(false);
  const today = new Date();
  // tasks with no day ("No specific time") can be studied too
  const anytime = data.tasks.filter((x) => !x.dueDate && !x.isDone && !x.isSkipped).map((x) => ({
    ref: { kind: "task" as const, id: x.id }, title: x.title, detail: categoryLabel(data, x.categoryID) ?? "Task",
    color: categoryOf(data, x.categoryID)?.colorHex ?? "#8E8E93", isDone: false, isSkipped: false, sortMinute: 9999 }));
  const todayTodos = todosOn(data, today);
  const todos = [...todayTodos, ...anytime.filter((a) => !todayTodos.some((x) => refKey(x.ref) === refKey(a.ref)))];
  const targetItem = t.target && todos.find((x) => refKey(x.ref) === refKey(t.target!));
  const goal = data.settings.dailyGoalMinutes * 60;
  const studied = studyOn(data, today);
  const progress = t.phaseLength ? t.elapsed / t.phaseLength : goal ? (studied + t.elapsed) / goal : 0;
  const lift = goal ? Math.min(1, (studied + (t.phase === "focus" ? t.elapsed : 0)) / goal) : 0;
  const rest = t.phase === "rest";
  const color = rest ? "#7EE081" : targetItem && targetItem.color !== "#8E8E93" ? targetItem.color : categoryOf(data, t.categoryID)?.colorHex ?? "#E8384F";
  const sessions = sessionsIn(data, startOfDay(today), addDays(startOfDay(today), 1)).reverse();
  const label = rest ? "Break · the cow is on a ride" : !t.active ? "Ready for launch" : t.running ? "In orbit · focusing" : "Paused";
  const subtitle = t.mode === "pomodoro"
    ? `${rest ? "until focus" : "left in this focus"} · ${data.settings.pomodoroMinutes}/${data.settings.breakMinutes} min · 🍅 ${t.completed}`
    : `Today ${duration(studied + t.elapsed)} of ${duration(goal)} goal`;
  const glass: React.CSSProperties = { background: "rgba(255,255,255,.08)", backdropFilter: "blur(20px)", border: "1px solid rgba(255,255,255,.12)", color: "white" };
  const glassBtn: React.CSSProperties = { ...glass, height: 40, padding: "0 18px", borderRadius: 99, fontWeight: 600, cursor: "pointer", whiteSpace: "nowrap" };
  const field: React.CSSProperties = { flex: 1, minWidth: 0, background: "#1B1D26", border: "none", color: "white", colorScheme: "dark", borderRadius: 6, padding: "4px 6px" };

  return (
    <div className="timer-page" style={{ display: "flex", height: "100%", color: "white", position: "relative", overflow: "hidden", background: "#05060C" }}>
      {/* night sky with a pale glow from the launch pad that grows as today's study climbs toward the goal; a calm green night on a break */}
      <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
        {/* the launch picture behind the dial, fitted to the height, rising a little as today's study climbs */}
        <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, right: 320, overflow: "hidden" }}>
          <img src={launchUrl} alt="" style={{ position: "absolute", height: "112%", left: "50%", top: 0,
            transform: `translate(-50%, ${6 + 8 * (0.5 - lift)}%)`, transition: "transform 1.2s ease-in-out",
            WebkitMaskImage: "linear-gradient(90deg, transparent 0, black 18%, black 82%, transparent 100%)",
            maskImage: "linear-gradient(90deg, transparent 0, black 18%, black 82%, transparent 100%)" }} />
        </div>
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(90deg, rgba(0,0,0,.55), rgba(0,0,0,.2), rgba(0,0,0,.55))" }} />
        <div style={{ position: "absolute", inset: 0, transition: "opacity .8s", opacity: rest ? 1 : 0, background: "linear-gradient(rgba(11,27,74,.85), rgba(31,95,58,.75))" }} />
      </div>

      <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 12, padding: "18px 28px", position: "relative" }}>
        <div style={{ textAlign: "center", maxWidth: "100%" }}>
          <div style={{ fontSize: 12, fontWeight: 900, letterSpacing: 3, color }}>{label.toUpperCase()}</div>
          <div style={{ fontSize: 30, fontWeight: 800, textShadow: "0 0 8px rgba(0,0,0,.6)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{rest ? "Break time" : t.targetTitle ?? "Free study"}</div>
          {targetItem && !rest && <div style={{ opacity: 0.7 }}>{targetItem.detail}</div>}
        </div>
        <div className="seg" style={{ background: "rgba(255,255,255,.08)", borderColor: "transparent" }}>
          {(["stopwatch", "pomodoro"] as const).map((m) => <button key={m} style={{ color: "white", background: t.mode === m ? color : undefined, fontWeight: t.mode === m ? 600 : undefined }}
            disabled={t.active} onClick={() => t.setMode(m)}>{m === "stopwatch" ? "Stopwatch" : "Pomodoro"}</button>)}
        </div>
        <div style={{ position: "relative", width: "min(330px, 42vh)", aspectRatio: "1", flexShrink: 0 }}>
          <SolarDial time={t.display} spin={t.elapsed} progress={progress} tint={color} moving={t.running} rest={rest} />
          <img src={breakUrl} alt="" style={{ position: "absolute", left: "27%", top: "27%", width: "46%", height: "46%", borderRadius: "50%", objectFit: "cover",
            border: "2px solid rgba(126,224,129,.7)", boxShadow: "0 0 18px rgba(126,224,129,.5)", transition: "transform .5s, opacity .5s",
            transform: rest ? "scale(1)" : "scale(.6)", opacity: rest ? 1 : 0, pointerEvents: "none" }} />
        </div>
        <div style={{ textAlign: "center" }}>
          <div style={{ fontSize: "min(56px, 7vh)", fontWeight: 600, fontFamily: "ui-monospace, Consolas, monospace", fontVariantNumeric: "tabular-nums", lineHeight: 1.1,
            textShadow: t.running ? `0 0 16px ${color}8C` : undefined }}>{clock(t.display)}</div>
          <div className="small" style={{ opacity: 0.6 }}>{subtitle}</div>
        </div>

        <div style={{ ...glass, width: "100%", maxWidth: 440, borderRadius: 16, padding: "4px 0" }}>
          <div className="row" style={{ padding: "5px 14px", gap: 10 }}><span style={{ color, width: 18 }}>📖</span>
            <select disabled={t.active} style={field} value={t.target ? refKey(t.target) : ""} onChange={(e) => {
              const v = e.target.value; const item = todos.find((x) => refKey(x.ref) === v); t.setTarget(item ? item.ref : null);
            }}>
              <option value="">Free study</option>
              {todos.map((x) => <option key={refKey(x.ref)} value={refKey(x.ref)}>{x.isDone ? "✓ " : ""}{x.title} ({x.detail})</option>)}
            </select></div>
          {!t.target && <div className="row" style={{ padding: "5px 14px", gap: 10, borderTop: "1px solid rgba(255,255,255,.08)" }}><span style={{ color, width: 18 }}>🏷</span>
            <select style={field} value={t.categoryID ?? ""} onChange={(e) => t.setCategoryID(e.target.value || undefined)}>
              <option value="">None</option>{orderedCategories(data).map((c) => <option key={c.id} value={c.id}>{c.parentID ? "   " : ""}{categoryLabel(data, c.id)}</option>)}
            </select></div>}
          <div className="row" style={{ padding: "5px 14px", gap: 10, borderTop: "1px solid rgba(255,255,255,.08)" }}><span style={{ color, width: 18 }}>✎</span>
            <input value={t.note} placeholder="Session note (e.g. chapter 3)" style={field} onChange={(e) => t.setNote(e.target.value)} /></div>
        </div>

        <div className="row" style={{ gap: 12 }}>
          <button onClick={() => (t.running ? t.pause() : t.start())} style={{ width: 150, height: 40, borderRadius: 99, border: "none", color: "white", fontWeight: 700, fontSize: 15, cursor: "pointer",
            background: `linear-gradient(${color}, ${color}B3)`, boxShadow: `0 0 ${t.running ? 4 : 14}px ${color}99` }}>
            {t.running ? "⏸ Pause" : t.active ? "▶ Resume" : "🚀 Launch"}</button>
          {t.active && (rest
            ? <button style={glassBtn} onClick={t.skipBreak}>⏭ Skip Break</button>
            : <>
                <button style={glassBtn} onClick={() => t.stop(true)}>🏁 Finish & Save</button>
                <button style={{ ...glassBtn, padding: "0 14px" }} title="Discard without saving" onClick={() => confirm("Discard this session?") && t.stop(false)}>🗑</button>
              </>)}
        </div>
      </div>

      <div style={{ width: 320, flexShrink: 0, padding: 20, position: "relative", background: "rgba(20,20,28,.55)", backdropFilter: "blur(24px)", display: "flex", flexDirection: "column", gap: 12, overflowY: "auto" }}>
        <div className="row"><div><b>Today's flights</b><div style={{ opacity: 0.6 }}>{duration(studied)}</div></div>
          <span className="spacer" /><button style={{ ...glassBtn, height: 30, padding: "0 12px", borderRadius: 8 }} title="Log a session you forgot to time" onClick={() => setManual(true)}>＋ Log Manually</button></div>
        {!sessions.length && <div style={{ textAlign: "center", paddingTop: 40 }}>
          <img src={earthUrl} alt="" style={{ width: 170, imageRendering: "pixelated" }} />
          <div style={{ fontWeight: 600 }}>No flights yet today</div><div className="small" style={{ opacity: 0.6 }}>Press Launch to start your first one 🚀</div></div>}
        {sessions.map((s) => { const sub = subjectOf(data, s); return (
          <div className="row" key={s.id} style={{ gap: 10, padding: "6px 0" }} title="Right-click to delete"
            onContextMenu={(e) => { e.preventDefault(); if (confirm("Delete this session?")) actions.deleteSession(s.id); }}>
            <div style={{ width: 3, alignSelf: "stretch", borderRadius: 2, background: sub.color }} />
            <div style={{ flex: 1, minWidth: 0 }}><div style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{sub.name}</div>
              <div className="small" style={{ opacity: 0.6 }}>{time(new Date(s.start))} – {time(new Date(new Date(s.start).getTime() + s.duration * 1000))}{s.isManual ? " · logged" : ""}{s.note ? ` · ${s.note}` : ""}</div></div>
            <b style={{ fontVariantNumeric: "tabular-nums" }}>{clock(s.duration)}</b>
          </div>
        ); })}
      </div>
      {manual && <ManualSession onClose={() => setManual(false)} />}
    </div>
  );
}

const STARFIELD = Array.from({ length: 70 }, (_, i) => {
  const x = (i * 37.7) % 100, y = (i * 61.3) % 100, r = i % 7 === 0 ? 1.6 : 1;
  return `radial-gradient(${r}px ${r}px at ${x.toFixed(1)}% ${y.toFixed(1)}%, rgba(255,255,255,${(0.35 + (i % 5) * 0.12).toFixed(2)}), transparent)`;
}).join(", ");

const PLANETS: [number, string, number, number, number, boolean][] = [
  [0, "#C9763C", 0.022, 0.050, 1.0, false], [1, "#3FB6C8", 0.026, 0.034, 3.7, false],
  [2, "#D9A066", 0.030, 0.026, 5.1, false], [3, "#B5523B", 0.050, 0.019, 2.4, false],
  [4, "#C9A98D", 0.040, 0.014, 0.3, true], [5, "#6E8BD8", 0.034, 0.011, 4.2, false],
  [6, "#5B4FB0", 0.028, 0.008, 1.9, false],
];
// a few fixed stars between the orbits
const STARS = (() => { let s = 7; const r = () => ((s = (s * 16807) % 2147483647) / 2147483647); return Array.from({ length: 40 }, () => [r(), r(), r()]); })();

/** A solar-system clock: planets on blue orbits around a sun, red hands for the time, a dotted rim with markers,
 *  and a glowing arc for progress (daily goal, or the Pomodoro phase). Planets move only while running. */
function SolarDial({ time, spin, progress, tint, moving, rest }: { time: number; spin: number; progress: number; tint: string; moving: boolean; rest: boolean }) {
  const cv = useRef<HTMLCanvasElement>(null);
  const props = useRef({ time, spin, progress, tint, rest }); props.current = { time, spin, progress, tint, rest };
  useEffect(() => {
    const draw = () => {
      const c = cv.current; if (!c) return;
      const { time: t, spin, progress, tint, rest } = props.current;
      const S = 330, dpr = devicePixelRatio || 1;
      if (c.width !== S * dpr) { c.width = S * dpr; c.height = S * dpr; }
      const ctx = c.getContext("2d")!; ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, S, S);
      const cx = S / 2, cy = S / 2, R = S / 2 - 4;
      const pt = (r: number, a: number) => [cx + Math.cos(a) * r, cy + Math.sin(a) * r] as const;
      const disc = (x: number, y: number, r: number, fill: string) => { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = fill; ctx.fill(); };
      disc(cx, cy, R * 0.93, "rgba(0,0,0,.55)");
      for (let i = 0; i < 120; i++) if (i % 10) { const [x, y] = pt(R * 0.97, (i / 120) * Math.PI * 2); disc(x, y, 1, "rgba(255,255,255,.55)"); }
      for (let i = 0; i < 12; i++) {
        const [x, y] = pt(R * 0.97, (i / 12) * Math.PI * 2), s = i % 3 === 0 ? 5.5 : 3.5;
        ctx.beginPath(); ctx.moveTo(x, y - s); ctx.lineTo(x + s * 0.6, y); ctx.lineTo(x, y + s); ctx.lineTo(x - s * 0.6, y); ctx.closePath(); ctx.fillStyle = "rgba(255,255,255,.9)"; ctx.fill();
      }
      const pr = R * 0.89;
      ctx.beginPath(); ctx.arc(cx, cy, pr, 0, Math.PI * 2); ctx.strokeStyle = "rgba(255,255,255,.08)"; ctx.lineWidth = 6; ctx.stroke();
      const p = Math.max(0, Math.min(1, progress));
      if (p > 0) {
        ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, pr, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p);
        ctx.strokeStyle = tint; ctx.lineWidth = 6; ctx.lineCap = "round"; ctx.shadowColor = tint; ctx.shadowBlur = 12; ctx.stroke(); ctx.restore();
      }
      const orbit = rest ? "62,142,94" : "47,111,216";
      const radii = Array.from({ length: 7 }, (_, i) => R * (0.24 + i * 0.095));
      radii.forEach((r, i) => { ctx.beginPath(); ctx.setLineDash(i === 1 ? [2, 4] : []); ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.strokeStyle = `rgba(${orbit},${i === 1 ? 0.35 : 0.75})`; ctx.lineWidth = 1.4; ctx.stroke(); });
      ctx.setLineDash([]);
      for (const [a, r, o] of STARS) { const [x, y] = pt(R * (0.2 + r * 0.68), a * Math.PI * 2); disc(x, y, 0.9, `rgba(255,255,255,${0.35 + o * 0.4})`); }
      for (const [ring, col, size, speed, start, ringed] of PLANETS) {
        const [x, y] = pt(radii[ring], start + spin * speed), s = R * size;
        if (ringed) { ctx.save(); ctx.translate(x, y); ctx.rotate(-0.4); ctx.beginPath(); ctx.ellipse(0, 0, s * 1.9, s * 0.55, 0, 0, Math.PI * 2); ctx.strokeStyle = "#E6D3A3"; ctx.lineWidth = 1.6; ctx.stroke(); ctx.restore(); }
        disc(x, y, s, col); disc(x - s * 0.3, y - s * 0.3, s * 0.45, "rgba(255,255,255,.18)");
      }
      ctx.save(); ctx.shadowColor = "rgba(255,201,64,.9)"; ctx.shadowBlur = 20; disc(cx, cy, R * 0.075, "#FFD447"); ctx.restore();
      ctx.beginPath(); ctx.arc(cx, cy, R * 0.075, 0, Math.PI * 2); ctx.strokeStyle = "#E8384F"; ctx.lineWidth = 2; ctx.stroke();
      const hand = (f: number, len: number, w: number, back = 0.12) => {
        const a = f * Math.PI * 2 - Math.PI / 2, [x0, y0] = pt(-R * back, a), [x1, y1] = pt(R * len, a);
        ctx.lineCap = "round";
        ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.strokeStyle = "rgba(0,0,0,.5)"; ctx.lineWidth = w + 2.5; ctx.stroke();
        ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.strokeStyle = "#E8384F"; ctx.lineWidth = w; ctx.stroke();
      };
      hand(((t / 3600) % 12) / 12, 0.45, 5); hand(((t / 60) % 60) / 60, 0.7, 4); hand((t % 60) / 60, 0.82, 1.6, 0.18);
      disc(cx, cy, R * 0.035, "#FFD447");
    };
    draw();
    if (!moving) return;
    return frameLoop(draw, 20);
  }, [moving, time, progress, tint, rest]);
  return <canvas ref={cv} style={{ width: "100%", height: "100%", display: "block" }} />;
}

function ManualSession({ onClose }: { onClose: () => void }) {
  const { data, actions } = useStore();
  const [cat, setCat] = useState<string>();
  const [subject, setSubject] = useState("");
  const [start, setStart] = useState(() => { const d = new Date(Date.now() - 3600_000); return d.toISOString().slice(0, 16); });
  const [mins, setMins] = useState(60);
  return (
    <Modal onClose={onClose} width={420}>
      <h3 style={{ marginTop: 0 }}>Log a session</h3>
      <div style={{ display: "grid", gridTemplateColumns: "100px 1fr", gap: 10, alignItems: "center" }}>
        <span>What</span><input value={subject} placeholder="e.g. Math 2" onChange={(e) => setSubject(e.target.value)} />
        <span>Category</span><select value={cat ?? ""} onChange={(e) => setCat(e.target.value || undefined)}><option value="">None</option>{orderedCategories(data).map((c) => <option key={c.id} value={c.id}>{c.parentID ? "   " : ""}{categoryLabel(data, c.id)}</option>)}</select>
        <span>Started</span><input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
        <span>Minutes</span><input type="number" min={1} max={720} value={mins} onChange={(e) => setMins(+e.target.value)} />
      </div>
      <div className="row" style={{ marginTop: 16 }}><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={() => {
          const c = data.categories.find((x) => x.id === cat);
          actions.addSession({ id: uid(), categoryID: cat, subject: subject || categoryLabel(data, cat) || "Free study", colorHex: c?.colorHex ?? "#8E8E93",
            start: new Date(start).toISOString(), duration: mins * 60, note: "", isManual: true });
          onClose();
        }}>Log</button></div>
    </Modal>
  );
}
