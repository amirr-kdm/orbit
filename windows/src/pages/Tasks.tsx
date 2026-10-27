import { PageHero } from "../components";
import { useEffect, useState } from "react";
import { useNav } from "../App";
import { Modal, MenuItem, useContextMenu } from "../components";
import { addDays, isToday, monthDay, startOfDay, WEEKDAYS, WEEKDAYS_SHORT, weekDays, weekdayIndex, weekStart } from "../lib/dates";
import { RECURRENCE_BADGE, TaskItem } from "../lib/model";
import { categoryOf, parity, scheduleRows, ScheduleRow, slotTitle, tasksOn, titleOf, useStore, categoryLabel, orderedCategories, isInside, entryColor } from "../lib/store";
import { useTimer } from "../lib/timer";
import Graph from "./Graph";

type Mode = "week" | "day" | "list" | "graph";

export default function Tasks() {
  const { data, actions } = useStore();
  const nav = useNav();
  const [mode, setMode] = useState<Mode>((new URLSearchParams(location.search).get("mode") as Mode) || (localStorage.getItem("tasks-mode") as Mode) || "week");
  const [anchor, setAnchor] = useState(new Date());
  const [catFilter, setCatFilter] = useState("");
  const [editing, setEditing] = useState<TaskItem | null>(null);
  const kind = data.settings.primaryCalendar;
  useEffect(() => { try { localStorage.setItem("tasks-mode", mode); } catch { /* ignore */ } }, [mode]);

  useEffect(() => { if (nav.focusDay) { setAnchor(nav.focusDay); setMode("day"); nav.clearFocus(); } }, [nav]);

  const matchTask = (t: TaskItem) => !catFilter || isInside(data, t.categoryID, catFilter);
  const matchRow = (r: ScheduleRow) => !catFilter || isInside(data, r.entry.categoryID, catFilter);
  const inbox = data.tasks.filter((t) => !t.dueDate && !t.isDone && matchTask(t));
  const shift = (n: number) => setAnchor(addDays(anchor, mode === "day" ? n : n * 7));

  return (
    <div className="page">
      <PageHero icon="✅" kicker="PLAN" title="Tasks" sub="Everything you need to do, by day, week or list" tint="#16A34A" />
      <div className="row">
        <div className="seg">{(["day", "week", "list", "graph"] as Mode[]).map((m) => <button key={m} className={mode === m ? "on" : ""} onClick={() => setMode(m)}>{m[0].toUpperCase() + m.slice(1)}</button>)}</div>
        {mode === "graph" && <b>Tasks and to-dos grouped by category</b>}
        {mode !== "list" && mode !== "graph" && <>
          <div className="seg"><button onClick={() => shift(-1)}>‹</button><button onClick={() => setAnchor(new Date())}>Today</button><button onClick={() => shift(1)}>›</button></div>
          <b>{mode === "day" ? `${WEEKDAYS[weekdayIndex(anchor)]}, ${monthDay(anchor, kind)}` : `${monthDay(weekStart(anchor), kind)} – ${monthDay(addDays(weekStart(anchor), 6), kind)}`}</b>
          <span className="badge" style={{ background: parity(data, anchor) === "even" ? "var(--accent)" : "#F97316" }}>{parity(data, anchor) === "even" ? "EVEN WEEK" : "ODD WEEK"}</span>
        </>}
        <span className="spacer" />
        <select value={catFilter} onChange={(e) => setCatFilter(e.target.value)}><option value="">All categories</option>{orderedCategories(data).map((c) => <option key={c.id} value={c.id}>{c.parentID ? "   " : ""}{categoryLabel(data, c.id)}</option>)}</select>
        <button className="btn primary" onClick={() => setEditing({ id: "", title: "", notes: "", priority: 1, hasTime: false, estimatedMinutes: 30, isDone: false, createdAt: new Date().toISOString(), categoryID: catFilter || undefined, dueDate: mode === "list" ? undefined : startOfDay(anchor).toISOString() })}>＋ New task</button>
      </div>

      {mode === "week" && <>
        <div className="board">
          {weekDays(anchor).map((day) => <DayColumn key={day.toDateString()} day={day} rows={scheduleRows(data, day, ["todo"]).filter(matchRow)} tasks={tasksOn(data, day).filter(matchTask)}
            onOpen={() => { setAnchor(day); setMode("day"); }} onEdit={setEditing} />)}
        </div>
        {inbox.length > 0 && (
          <div className="card" onDragOver={(e) => e.preventDefault()} onDrop={(e) => drop(e, undefined)}>
            <div className="small muted" style={{ marginBottom: 8 }}>📥 No date — drag a task onto a day</div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 8 }}>{inbox.map((t) => <TaskCard key={t.id} t={t} onEdit={setEditing} />)}</div>
          </div>
        )}
      </>}

      {mode === "day" && <DayView day={anchor} matchRow={matchRow} matchTask={matchTask} onEdit={setEditing} inbox={inbox} />}

      {mode === "graph" && <Graph catFilter={catFilter} />}

      {mode === "list" && <ListView matchTask={matchTask} onEdit={setEditing} />}

      {editing && <TaskEditor task={editing} onClose={() => setEditing(null)} />}
    </div>
  );

  function drop(e: React.DragEvent, day?: Date) {
    e.preventDefault();
    const raw = e.dataTransfer.getData("text/plain");
    if (raw.startsWith("occ:")) { const [id, ts] = raw.slice(4).split("|"); actions.moveOccurrence(id, new Date(+ts), day); }
    else if (raw.startsWith("task:")) actions.moveTask(raw.slice(5), day);
  }
}

function moveMenu(from: Date, onMove: (d?: Date) => void): MenuItem[] {
  return [{ header: "Move to" }, ...weekDays(from).map((d) => ({ label: `${WEEKDAYS[weekdayIndex(d)]}`, disabled: d.toDateString() === from.toDateString(), onClick: () => onMove(d) })),
    { label: "Same day next week", onClick: () => onMove(addDays(from, 7)) }, { label: "No date", onClick: () => onMove(undefined) }];
}

function DayColumn({ day, rows, tasks, onOpen, onEdit }: { day: Date; rows: ScheduleRow[]; tasks: TaskItem[]; onOpen: () => void; onEdit: (t: TaskItem) => void }) {
  const { data, actions } = useStore();
  const [over, setOver] = useState(false);
  const [title, setTitle] = useState("");
  const total = rows.length + tasks.length, done = rows.filter((r) => r.isDone).length + tasks.filter((t) => t.isDone).length;
  const today = isToday(day);
  return (
    <div className={`col ${over ? "drop" : ""}`} onDragOver={(e) => { e.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)}
      onDrop={(e) => {
        setOver(false); e.preventDefault(); const raw = e.dataTransfer.getData("text/plain");
        if (raw.startsWith("occ:")) { const [id, ts] = raw.slice(4).split("|"); actions.moveOccurrence(id, new Date(+ts), day); }
        else if (raw.startsWith("task:")) actions.moveTask(raw.slice(5), day);
      }}>
      <div className={`col-head ${today ? "today" : ""}`} onClick={onOpen} title="Open this day">
        <div className="row small" style={{ fontWeight: 800, letterSpacing: 1, color: !today && weekdayIndex(day) === 6 ? "#ef4444" : undefined }}>{WEEKDAYS_SHORT[weekdayIndex(day)].toUpperCase()}<span className="spacer" />{total > 0 && `${done}/${total}`}</div>
        <b style={{ fontSize: 17 }}>{monthDay(day, data.settings.primaryCalendar, true)}</b>
        <div className="small" style={{ opacity: 0.75 }}>{monthDay(day, data.settings.primaryCalendar === "persian" ? "gregorian" : "persian", true)}</div>
        {total > 0 && <div className="progress" style={{ marginTop: 5, height: 3 }}><div style={{ width: `${(done / total) * 100}%`, background: today ? "white" : undefined }} /></div>}
      </div>
      {rows.map((r) => <OccCard key={r.entry.id} r={r} />)}
      {tasks.map((t) => <TaskCard key={t.id} t={t} onEdit={onEdit} />)}
      <input placeholder="＋ Add" value={title} style={{ background: "transparent", border: "1px dashed var(--line)" }} onChange={(e) => setTitle(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && title.trim()) { actions.addTask(title.trim(), day); setTitle(""); } }} />
    </div>
  );
}

function OccCard({ r }: { r: ScheduleRow }) {
  const { data, actions } = useStore();
  const timer = useTimer(); const nav = useNav(); const menu = useContextMenu();
  const c = categoryOf(data, r.entry.categoryID);
  const ref = { kind: "schedule" as const, id: r.entry.id };
  return (
    <div className="bcard" draggable style={{ ["--c" as string]: entryColor(data, r.entry) ?? c?.colorHex ?? "var(--accent)" }}
      onDragStart={(e) => e.dataTransfer.setData("text/plain", `occ:${r.entry.id}|${r.date.getTime()}`)} title="Drag to another day to move just this session"
      onContextMenu={(e) => menu.open(e, [{ label: r.isDone ? "Mark as not done" : "Mark as done", onClick: () => actions.toggleDone(ref, r.date) },
        { label: r.isSkipped ? "Bring back to to-do" : "Skip (won't do)", onClick: () => actions.setSkipped(ref, r.date, !r.isSkipped) },
        { label: "▶ Study now", disabled: timer.active, onClick: () => { timer.setTarget(ref); nav.go("timer"); } }, { separator: true },
        ...moveMenu(r.date, (d) => actions.moveOccurrence(r.entry.id, r.date, d))])}>
      <button className={`check ${r.isDone ? "done" : ""}`} style={r.isSkipped ? { background: "#F97316", borderColor: "#F97316" } : undefined} onClick={() => actions.tapStatus(ref, r.date)}>{r.isSkipped ? "✕" : r.isDone ? "✓" : ""}</button>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className={r.isDone || r.isSkipped ? "strike" : ""} style={{ fontWeight: 500 }}>{titleOf(r.entry)}</div>
        <div className="small muted">{slotTitle(r.slot)} {RECURRENCE_BADGE[r.entry.recurrence] ? <b>{RECURRENCE_BADGE[r.entry.recurrence]}</b> : c?.name}</div>
      </div>
      {menu.node}
    </div>
  );
}

function TaskCard({ t, onEdit }: { t: TaskItem; onEdit: (t: TaskItem) => void }) {
  const { data, actions } = useStore();
  const timer = useTimer(); const nav = useNav(); const menu = useContextMenu();
  const c = categoryOf(data, t.categoryID);
  const from = t.dueDate ? new Date(t.dueDate) : new Date();
  return (
    <div className="bcard" draggable style={{ ["--c" as string]: c?.colorHex ?? "#8E8E93" }} onDragStart={(e) => e.dataTransfer.setData("text/plain", `task:${t.id}`)}
      onDoubleClick={() => onEdit(t)}
      onContextMenu={(e) => menu.open(e, [{ label: "Edit", onClick: () => onEdit(t) }, { label: t.isDone ? "Mark as not done" : "Mark as done", onClick: () => actions.toggleDone({ kind: "task", id: t.id }, from) },
        { label: t.isSkipped ? "Bring back to to-do" : "Skip (won't do)", onClick: () => actions.setSkipped({ kind: "task", id: t.id }, from, !t.isSkipped) },
        { label: "▶ Study now", disabled: timer.active, onClick: () => { timer.setTarget({ kind: "task", id: t.id }); nav.go("timer"); } }, { separator: true },
        ...moveMenu(from, (d) => actions.moveTask(t.id, d)), { separator: true }, { label: "Delete", onClick: () => actions.deleteTask(t.id) }])}>
      <button className={`check ${t.isDone ? "done" : ""}`} style={t.isSkipped ? { background: "#F97316", borderColor: "#F97316" } : undefined} onClick={() => actions.tapStatus({ kind: "task", id: t.id }, from)}>{t.isSkipped ? "✕" : t.isDone ? "✓" : ""}</button>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className={t.isDone || t.isSkipped ? "strike" : ""} style={{ fontWeight: 500 }}>{t.title}</div>
        <div className="small muted">{t.hasTime && t.dueDate ? new Date(t.dueDate).toTimeString().slice(0, 5) + " " : ""}{c?.name}{t.priority === 2 ? " 🚩" : ""}</div>
      </div>
      {menu.node}
    </div>
  );
}

function DayView({ day, matchRow, matchTask, onEdit, inbox }: { day: Date; matchRow: (r: ScheduleRow) => boolean; matchTask: (t: TaskItem) => boolean; onEdit: (t: TaskItem) => void; inbox: TaskItem[] }) {
  const { data, actions } = useStore();
  const rows = scheduleRows(data, day, ["todo"]).filter(matchRow);
  const tasks = tasksOn(data, day).filter(matchTask);
  const fixed = scheduleRows(data, day, ["fixed"]);
  return (
    <>
      {fixed.length > 0 && <div className="small muted">📌 {fixed.map((f) => `${titleOf(f.entry)} ${slotTitle(f.slot)}`).join("  ·  ")}</div>}
      <input placeholder="＋ Add a task for this day and press Enter…" onKeyDown={(e) => { const v = e.currentTarget.value.trim(); if (e.key === "Enter" && v) { actions.addTask(v, day); e.currentTarget.value = ""; } }} />
      <div className="card"><h3><span className="t2-ico">🗓️</span>From your weekly schedule</h3>{!rows.length && <div className="muted">No schedule to-dos on this day.</div>}<div style={{ display: "grid", gap: 7 }}>{rows.map((r) => <OccCard key={r.entry.id} r={r} />)}</div></div>
      <div className="card"><h3><span className="t2-ico">📋</span>Tasks</h3>{!tasks.length && <div className="muted">No one-off tasks on this day.</div>}<div style={{ display: "grid", gap: 7 }}>{tasks.map((t) => <TaskCard key={t.id} t={t} onEdit={onEdit} />)}</div></div>
      {inbox.length > 0 && <div className="card"><h3><span className="t2-ico">📥</span>No date</h3>{inbox.map((t) => <div key={t.id} className="list-row"><div style={{ flex: 1 }}>{t.title}</div><button className="btn small" onClick={() => actions.moveTask(t.id, day)}>Move here</button></div>)}</div>}
    </>
  );
}

function ListView({ matchTask, onEdit }: { matchTask: (t: TaskItem) => boolean; onEdit: (t: TaskItem) => void }) {
  const { data } = useStore();
  const [filter, setFilter] = useState<"today" | "upcoming" | "inbox" | "all" | "done">("all");
  const [q, setQ] = useState("");
  const today = startOfDay(new Date()), tomorrow = addDays(today, 1);
  const list = data.tasks.filter(matchTask).filter((t) => !q || t.title.toLowerCase().includes(q.toLowerCase())).filter((t) => {
    const d = t.dueDate ? new Date(t.dueDate) : undefined;
    switch (filter) {
      case "today": return !!d && d >= today && d < tomorrow;
      case "upcoming": return !t.isDone && !!d && d >= tomorrow;
      case "inbox": return !t.isDone && !d;
      case "all": return !t.isDone;
      case "done": return t.isDone;
    }
  }).sort((a, b) => (a.dueDate ?? "9").localeCompare(b.dueDate ?? "9"));
  return (
    <>
      <div className="row"><div className="seg">{(["today", "upcoming", "inbox", "all", "done"] as const).map((f) => <button key={f} className={filter === f ? "on" : ""} onClick={() => setFilter(f)}>{{ today: "Today", upcoming: "Upcoming", inbox: "No Date", all: "All Open", done: "Done" }[f]}</button>)}</div>
        <span className="spacer" /><input placeholder="🔎 Search tasks" value={q} onChange={(e) => setQ(e.target.value)} /></div>
      <div className="card" style={{ display: "grid", gap: 7 }}>{!list.length && <div className="muted">Nothing here.</div>}{list.map((t) => <TaskCard key={t.id} t={t} onEdit={onEdit} />)}</div>
    </>
  );
}

export function TaskEditor({ task, onClose }: { task: TaskItem; onClose: () => void }) {
  const { data, actions } = useStore();
  const [t, setT] = useState<TaskItem>(task);
  const isNew = !task.id;
  const dateVal = t.dueDate ? new Date(new Date(t.dueDate).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, t.hasTime ? 16 : 10) : "";
  return (
    <Modal onClose={onClose} width={460}>
      <h3 style={{ marginTop: 0 }}>{isNew ? "New task" : "Edit task"}</h3>
      <div style={{ display: "grid", gridTemplateColumns: "110px 1fr", gap: 10, alignItems: "center" }}>
        <span>Title</span><input autoFocus value={t.title} onChange={(e) => setT({ ...t, title: e.target.value })} />
        <span>Category</span><select value={t.categoryID ?? ""} onChange={(e) => setT({ ...t, categoryID: e.target.value || undefined })}><option value="">None</option>{orderedCategories(data).map((c) => <option key={c.id} value={c.id}>{c.parentID ? "   " : ""}{categoryLabel(data, c.id)}</option>)}</select>
        <span>Priority</span><div className="seg">{([0, 1, 2] as const).map((p) => <button key={p} className={t.priority === p ? "on" : ""} onClick={() => setT({ ...t, priority: p })}>{["Low", "Medium", "High"][p]}</button>)}</div>
        <span>Date</span><div className="row"><input type={t.hasTime ? "datetime-local" : "date"} value={dateVal} onChange={(e) => setT({ ...t, dueDate: e.target.value ? new Date(e.target.value).toISOString() : undefined })} />
          <label className="row small"><input type="checkbox" checked={t.hasTime} onChange={(e) => setT({ ...t, hasTime: e.target.checked })} /> time</label></div>
        <span>Estimate (min)</span><input type="number" min={5} step={5} value={t.estimatedMinutes} onChange={(e) => setT({ ...t, estimatedMinutes: +e.target.value })} />
        <span>Notes</span><textarea rows={3} value={t.notes} onChange={(e) => setT({ ...t, notes: e.target.value })} />
      </div>
      <div className="row" style={{ marginTop: 16 }}>
        {!isNew && <button className="btn danger" onClick={() => { actions.deleteTask(t.id); onClose(); }}>Delete</button>}
        <span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" disabled={!t.title.trim()} onClick={() => { actions.upsertTask({ ...t, id: t.id || crypto.randomUUID().toUpperCase(), title: t.title.trim() }); onClose(); }}>Save</button>
      </div>
    </Modal>
  );
}
