import { useState } from "react";
import { useNav } from "../App";
import { QuickAdd } from "../components";
import { addDays, dayNum, duration, fullDate, isToday, monthDays, monthName, monthDay, sameDay, shiftMonth, shortDuration, startOfDay, WEEKDAYS, weekdayIndex, yearNum } from "../lib/dates";
import { categoryOf, parity, scheduleRows, sessionsIn, slotTitle, studyOn, subjectOf, tasksOn, titleOf, useStore } from "../lib/store";

export default function Calendar() {
  const { data, update, actions } = useStore();
  const nav = useNav();
  const kind = data.settings.primaryCalendar;
  const other = kind === "persian" ? "gregorian" : "persian";
  const [anchor, setAnchor] = useState(new Date());
  const [sel, setSel] = useState(startOfDay(new Date()));
  const days = monthDays(anchor, kind);
  const lead = weekdayIndex(days[0]);
  const last = days[days.length - 1];

  const fixed = scheduleRows(data, sel, ["fixed"]);
  const todos = scheduleRows(data, sel, ["todo"]);
  const tasks = tasksOn(data, sel);
  const sessions = sessionsIn(data, sel, addDays(sel, 1));

  return (
    <div className="page" style={{ maxWidth: "none" }}>
      <div className="row" style={{ alignItems: "flex-start", gap: 20 }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 12 }}>
          <div className="row">
            <div><h1 className="page-title">{monthName(anchor, kind)} {yearNum(days[0], kind)}</h1>
              <div className="subtitle">{monthName(days[0], other)}{monthName(days[0], other) !== monthName(last, other) ? ` – ${monthName(last, other)}` : ""} {yearNum(last, other)}</div></div>
            <span className="spacer" />
            <div className="seg">{(["persian", "gregorian"] as const).map((k) => <button key={k} className={kind === k ? "on" : ""} onClick={() => update((d) => { d.settings.primaryCalendar = k; })}>{k === "persian" ? "Persian" : "Gregorian"}</button>)}</div>
            <div className="seg"><button onClick={() => setAnchor(shiftMonth(anchor, kind, -1))}>‹</button><button onClick={() => { setAnchor(new Date()); setSel(startOfDay(new Date())); }}>Today</button><button onClick={() => setAnchor(shiftMonth(anchor, kind, 1))}>›</button></div>
          </div>
          <div className="row small muted"><span>○ To-do</span><span>📌 Class</span><span>⏱ Studied</span><span className="spacer" />Click a day for details · double-click to open it in Tasks</div>
          <div className="cal">
            {WEEKDAYS.map((w) => <div key={w} className="small" style={{ textAlign: "center", fontWeight: 600, color: w === "Friday" ? "#ef4444" : "var(--muted)" }}>{w}</div>)}
            {Array.from({ length: lead }, (_, i) => <div key={"e" + i} />)}
            {days.map((d) => {
              const td = scheduleRows(data, d, ["todo"]), fx = scheduleRows(data, d, ["fixed"]), tk = tasksOn(data, d);
              const lines = [...td.map((r) => ({ id: r.entry.id, t: titleOf(r.entry), c: r.entry.colorHex ?? categoryOf(data, r.entry.categoryID)?.colorHex ?? "var(--accent)", done: r.isDone })),
                ...tk.map((t) => ({ id: t.id, t: t.title, c: categoryOf(data, t.categoryID)?.colorHex ?? "#8E8E93", done: t.isDone }))];
              const done = lines.filter((l) => l.done).length, st = studyOn(data, d);
              return (
                <div key={d.toDateString()} className={`cal-cell ${sameDay(d, sel) ? "sel" : ""}`} onClick={() => setSel(d)} onDoubleClick={() => nav.go("tasks", d)}>
                  <div className="row"><span className={`num ${isToday(d) ? "today" : ""}`} style={{ color: !isToday(d) && weekdayIndex(d) === 6 ? "#ef4444" : undefined }}>{dayNum(d, kind)}</span><span className="spacer" /><span className="muted">{dayNum(d, other) === 1 ? monthDay(d, other, true) : dayNum(d, other)}</span></div>
                  {lines.slice(0, 2).map((l) => <div key={l.id} className={l.done ? "strike" : ""} style={{ borderLeft: `3px solid ${l.c}`, paddingLeft: 4, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{l.t}</div>)}
                  {lines.length > 2 && <div className="muted">+{lines.length - 2} more</div>}
                  <div className="row muted" style={{ marginTop: "auto", gap: 6 }}>
                    {fx.length > 0 && <span>📌{fx.length}</span>}
                    {lines.length > 0 && <span style={{ color: done === lines.length ? "#22C55E" : undefined }}>{done}/{lines.length}</span>}
                    <span className="spacer" />{st > 0 && <span style={{ color: "var(--accent)" }}>⏱{shortDuration(st)}</span>}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        <div className="card" style={{ width: 340, display: "flex", flexDirection: "column", gap: 14 }}>
          <div><h2 style={{ margin: 0, fontSize: 19 }}>{fullDate(sel, kind)}</h2><div className="muted">{fullDate(sel, other)}</div>
            <div className="row" style={{ marginTop: 8 }}><span className="badge" style={{ background: parity(data, sel) === "even" ? "var(--accent)" : "#F97316" }}>{parity(data, sel) === "even" ? "EVEN WEEK" : "ODD WEEK"}</span><span className="spacer" /><button className="btn small" onClick={() => nav.go("tasks", sel)}>↗ Open in Tasks</button></div></div>
          <QuickAdd placeholder="Add a task for this day…" onAdd={(t) => actions.addTask(t, sel)} />
          {fixed.length > 0 && <div><b>📌 Classes</b>{fixed.map((r) => <div key={r.entry.id} className="list-row"><div className="bar" style={{ background: r.entry.colorHex ?? "#999" }} /><div>{titleOf(r.entry)}<div className="small muted">{slotTitle(r.slot)}</div></div></div>)}</div>}
          <div><b>☑ To-do</b>
            {!todos.length && !tasks.length && <div className="muted small">Nothing to do on this day.</div>}
            {todos.map((r) => <div key={r.entry.id} className="list-row"><button className={`check ${r.isDone ? "done" : ""}`} onClick={() => actions.toggleDone({ kind: "schedule", id: r.entry.id }, sel)}>{r.isDone ? "✓" : ""}</button><div className={r.isDone ? "strike" : ""}>{titleOf(r.entry)}<div className="small muted">{slotTitle(r.slot)}</div></div></div>)}
            {tasks.map((t) => <div key={t.id} className="list-row"><button className={`check ${t.isDone ? "done" : ""}`} onClick={() => actions.toggleDone({ kind: "task", id: t.id }, sel)}>{t.isDone ? "✓" : ""}</button><div className={t.isDone ? "strike" : ""}>{t.title}</div></div>)}
          </div>
          <div><b>⏱ Study sessions</b> <span className="muted">{sessions.length ? duration(sessions.reduce((a, s) => a + s.duration, 0)) : ""}</span>
            {!sessions.length && <div className="muted small">No sessions.</div>}
            {sessions.map((s) => <div key={s.id} className="list-row"><div className="bar" style={{ background: subjectOf(data, s).color }} /><div style={{ flex: 1 }}>{subjectOf(data, s).name}</div><b>{duration(s.duration)}</b></div>)}
          </div>
        </div>
      </div>
    </div>
  );
}
