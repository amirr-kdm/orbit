import { useState } from "react";
import { Modal, Ring } from "../components";
import { addDays, clock, duration, startOfDay, time } from "../lib/dates";
import { uid } from "../lib/model";
import { refKey, sessionsIn, studyOn, subjectOf, todosOn, useStore, categoryLabel, orderedCategories } from "../lib/store";
import { useTimer } from "../lib/timer";

export default function TimerPage() {
  const { data, actions } = useStore();
  const t = useTimer();
  const [manual, setManual] = useState(false);
  const today = new Date();
  const todos = todosOn(data, today);
  const targetItem = t.target && todos.find((x) => refKey(x.ref) === refKey(t.target!));
  const goal = data.settings.dailyGoalMinutes * 60;
  const progress = t.phaseLength ? t.elapsed / t.phaseLength : goal ? (studyOn(data, today) + t.elapsed) / goal : 0;
  const color = t.phase === "rest" ? "#22C55E" : targetItem?.color ?? "var(--accent)";
  const sessions = sessionsIn(data, startOfDay(today), addDays(startOfDay(today), 1)).reverse();

  return (
    <div className="page">
      <div className="row" style={{ alignItems: "flex-start", gap: 24 }}>
        <div className="card" style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 20, padding: 28 }}>
          <div style={{ textAlign: "center" }}>
            <h2 style={{ margin: 0 }}>{t.phase === "rest" ? "Break ☕️" : t.targetTitle ?? "Free study"}</h2>
            {targetItem && <div className="muted">{targetItem.detail}</div>}
          </div>
          <div className="seg">
            {(["stopwatch", "pomodoro"] as const).map((m) => <button key={m} className={t.mode === m ? "on" : ""} disabled={t.active} onClick={() => t.setMode(m)}>{m === "stopwatch" ? "Stopwatch" : "Pomodoro"}</button>)}
          </div>
          <div className="ring-wrap">
            <Ring progress={progress} size={280} width={16} color={color}>
              <div className="ring-center">
                <div className="muted" style={{ fontWeight: 600 }}>{t.phase === "rest" ? "Break" : !t.active ? "Ready" : t.running ? "Focusing" : "Paused"}</div>
                <div className="big-time">{clock(t.display)}</div>
                {t.mode === "stopwatch" && <div className="small muted">Ring: daily goal progress</div>}
              </div>
            </Ring>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "110px 300px", gap: 10, alignItems: "center" }}>
            <span className="muted">Studying</span>
            <select disabled={t.active} value={t.target ? refKey(t.target) : ""} onChange={(e) => {
              const v = e.target.value; const item = todos.find((x) => refKey(x.ref) === v); t.setTarget(item ? item.ref : null);
            }}>
              <option value="">Free study</option>
              {todos.map((x) => <option key={refKey(x.ref)} value={refKey(x.ref)}>{x.isDone ? "✓ " : ""}{x.title} ({x.detail})</option>)}
            </select>
            {!t.target && <><span className="muted">Category</span>
              <select value={t.categoryID ?? ""} onChange={(e) => t.setCategoryID(e.target.value || undefined)}>
                <option value="">None</option>{orderedCategories(data).map((c) => <option key={c.id} value={c.id}>{c.parentID ? "   " : ""}{categoryLabel(data, c.id)}</option>)}
              </select></>}
            <span className="muted">Note</span>
            <input value={t.note} placeholder="e.g. chapter 3" onChange={(e) => t.setNote(e.target.value)} />
          </div>
          <div className="row">
            <button className="btn primary" style={{ padding: "10px 28px", fontSize: 15 }} onClick={() => (t.running ? t.pause() : t.start())}>
              {t.running ? "⏸ Pause" : t.active ? "▶ Resume" : "▶ Start"}
            </button>
            {t.active && (t.phase === "rest"
              ? <button className="btn" onClick={t.skipBreak}>Skip break</button>
              : <>
                  <button className="btn" style={{ padding: "10px 18px" }} onClick={() => t.stop(true)}>⏹ Finish & Save</button>
                  <button className="btn danger" title="Discard without saving" onClick={() => confirm("Discard this session?") && t.stop(false)}>🗑</button>
                </>)}
          </div>
          {t.mode === "pomodoro" && <div className="small muted">Pomodoro: {data.settings.pomodoroMinutes} min focus, {data.settings.breakMinutes} min break · completed: {t.completed}</div>}
        </div>

        <div className="card" style={{ width: 330 }}>
          <div className="row"><div><h3 style={{ marginBottom: 2 }}>Today's sessions</h3><div className="muted">{duration(studyOn(data, today))}</div></div>
            <span className="spacer" /><button className="btn small" onClick={() => setManual(true)}>＋ Log manually</button></div>
          {!sessions.length && <div className="muted" style={{ marginTop: 10 }}>No sessions yet.</div>}
          {sessions.map((s) => { const sub = subjectOf(data, s); return (
            <div className="list-row" key={s.id} onContextMenu={(e) => { e.preventDefault(); if (confirm("Delete this session?")) actions.deleteSession(s.id); }}>
              <div className="bar" style={{ background: sub.color }} />
              <div style={{ flex: 1 }}>{sub.name}<div className="small muted">{time(new Date(s.start))}{s.note ? ` · ${s.note}` : ""}</div></div>
              <b>{duration(s.duration)}</b>
            </div>
          ); })}
        </div>
      </div>
      {manual && <ManualSession onClose={() => setManual(false)} />}
    </div>
  );
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
