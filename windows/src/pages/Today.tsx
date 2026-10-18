import { useNav } from "../App";
import { QuickAdd, Ring, Stat } from "../components";
import { addDays, dualDate, duration, isToday, time, WEEKDAYS, weekdayIndex, weekStart } from "../lib/dates";
import { currentSlot, entryAt, sessionsIn, slotTitle, studyOn, studyTime, subjectOf, titleOf, todosOn, TodoItem, refKey, useStore, parity } from "../lib/store";
import { useTimer } from "../lib/timer";

export function TodoRow({ item, day }: { item: TodoItem; day: Date }) {
  const { actions } = useStore();
  const timer = useTimer();
  const nav = useNav();
  const current = timer.target && refKey(timer.target) === refKey(item.ref);
  return (
    <div className="list-row">
      <button className={`check ${item.isDone ? "done" : ""}`} onClick={() => actions.toggleDone(item.ref, day)}>{item.isDone ? "✓" : ""}</button>
      <div className="bar" style={{ background: item.color }} />
      <div style={{ flex: 1 }}>
        <div className={item.isDone ? "strike" : ""}>{item.title}</div>
        <div className="small muted">{item.ref.kind === "schedule" ? "🕘" : "🏷"} {item.detail}</div>
      </div>
      {!item.isDone && (
        <button className={`btn small ${current && timer.active ? "" : "primary"}`} disabled={timer.active && !current}
          onClick={() => { timer.setTarget(item.ref); nav.go("timer"); }}>
          {current && timer.active ? "⏱ In progress" : "▶ Study"}
        </button>
      )}
    </div>
  );
}

export default function Today() {
  const { data, actions } = useStore();
  const timer = useTimer();
  const nav = useNav();
  const today = new Date();
  const todos = todosOn(data, today);
  const sched = todos.filter((t) => t.ref.kind === "schedule");
  const tasks = todos.filter((t) => t.ref.kind === "task");
  const studied = studyOn(data, today) + (timer.phase === "focus" ? timer.elapsed : 0);
  const goal = data.settings.dailyGoalMinutes * 60;
  const ws = weekStart(today);
  const sessions = sessionsIn(data, new Date(today.toDateString()), addDays(new Date(today.toDateString()), 1));
  const overdue = data.tasks.filter((t) => !t.isDone && t.dueDate && new Date(t.dueDate) < new Date(today.toDateString()));
  const slot = currentSlot(data, today);
  const now = slot ? entryAt(data, weekdayIndex(today), slot.id, today) : undefined;

  return (
    <div className="page">
      <div>
        <h1 className="page-title">To-do · {WEEKDAYS[weekdayIndex(today)]}</h1>
        <div className="subtitle">{dualDate(today)}, {today.getFullYear()} · {parity(data, today) === "even" ? "Even week" : "Odd week"}</div>
      </div>

      <div className="grid2">
        <div className="card stat">
          <Ring progress={goal ? studied / goal : 0}><b className="small">{Math.round(goal ? Math.min(999, (studied / goal) * 100) : 0)}%</b></Ring>
          <div><div className="label">Studied today</div><div className="value">{duration(studied)}</div><div className="sub">Goal: {duration(goal)}</div></div>
        </div>
        <Stat icon="✅" color="#22C55E" label="To-dos done" value={`${todos.filter((t) => t.isDone).length} of ${todos.length}`} sub={todos.length ? undefined : "Nothing planned yet"} />
        <Stat icon="📅" color="#8B5CF6" label="This week" value={duration(studyTime(data, ws, addDays(ws, 7)))} sub="Total time logged" />
      </div>

      {slot && now && (
        <div className="card row" style={{ borderColor: "#22C55E66", background: "color-mix(in srgb, #22C55E 10%, var(--card))" }}>
          <span>📡</span>
          <div style={{ flex: 1 }}><div className="small muted">Now · {slotTitle(slot)}</div><b>{titleOf(now)}</b></div>
          {now.kind === "todo" && <button className="btn primary" disabled={timer.active} onClick={() => { timer.setTarget({ kind: "schedule", id: now.id }); nav.go("timer"); }}>▶ Study now</button>}
        </div>
      )}

      <div className="card">
        <h3>🗓️ From your weekly schedule</h3>
        {!sched.length && <div className="row muted">No To-do cells for today. Mark cells as “To-do” in the weekly schedule and they appear here.<span className="spacer" /><button className="btn" onClick={() => nav.go("schedule")}>Open Schedule</button></div>}
        {sched.map((t) => <TodoRow key={refKey(t.ref)} item={t} day={today} />)}
      </div>

      <div className="card">
        <h3>📋 Other tasks today</h3>
        <QuickAdd onAdd={(t) => actions.addTask(t, today)} />
        {tasks.map((t) => <TodoRow key={refKey(t.ref)} item={t} day={today} />)}
      </div>

      {overdue.length > 0 && (
        <div className="card">
          <h3>⚠️ Overdue</h3>
          {overdue.map((t) => (
            <div className="list-row" key={t.id}>
              <button className="check" onClick={() => actions.toggleDone({ kind: "task", id: t.id }, today)} />
              <div style={{ flex: 1 }}>{t.title}<div className="small muted">{new Date(t.dueDate!).toLocaleDateString()}</div></div>
              <button className="btn small" onClick={() => actions.moveTask(t.id, today)}>Move to Today</button>
            </div>
          ))}
        </div>
      )}

      <div className="card">
        <h3>⏱️ Today's sessions</h3>
        {!sessions.length && <div className="muted">No sessions yet. Pick a to-do above and press Study.</div>}
        {sessions.map((s) => { const sub = subjectOf(data, s); return (
          <div className="list-row" key={s.id}>
            <div className="bar" style={{ background: sub.color }} />
            <div style={{ flex: 1 }}>{sub.name}<div className="small muted">{time(new Date(s.start))} – {time(new Date(new Date(s.start).getTime() + s.duration * 1000))}{s.note ? ` · ${s.note}` : ""}</div></div>
            <b>{duration(s.duration)}</b>
          </div>
        ); })}
      </div>
      {isToday(today) && null}
    </div>
  );
}
