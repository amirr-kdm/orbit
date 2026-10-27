// Tasks with no day and no time ("whenever"): a small pool you can add to from anywhere
import { useState } from "react";
import { Modal, QuickAdd } from "../components";
import { TaskItem, uid } from "./model";
import { startOfDay } from "./dates";
import { categoryLabel, orderedCategories, useStore } from "./store";
import { useTimer } from "./timer";

export const anytimeTasks = (tasks: TaskItem[]) => tasks.filter((t) => !t.dueDate && !t.isDone && !t.isSkipped).sort((a, b) => a.createdAt.localeCompare(b.createdAt));

export function useAddTask() {
  const { actions } = useStore();
  /** `today`: planned for today; otherwise no day at all. Returns the new task. */
  return (title: string, opts: { today?: boolean; category?: string } = {}) => {
    const t: TaskItem = { id: uid(), title, notes: "", categoryID: opts.category, priority: 1, dueDate: opts.today ? startOfDay(new Date()).toISOString() : undefined,
      hasTime: false, estimatedMinutes: 30, isDone: false, createdAt: new Date().toISOString() };
    actions.upsertTask(t);
    return t;
  };
}

/** The "No specific time" box: quick add + the open tasks without a day (Today page, and a slim strip under the weekly schedule) */
export function AnytimeBox({ compact = false, today = new Date(), onStudy }: { compact?: boolean; today?: Date; onStudy: (id: string) => void }) {
  const { data, actions } = useStore();
  const add = useAddTask();
  const items = anytimeTasks(data.tasks);
  if (compact) return (
    <div className="row" style={{ gap: 10, padding: "6px 2px", flexWrap: "wrap" }}>
      <b className="small muted">🗂 No specific time</b>
      <div style={{ width: 280 }}><QuickAdd placeholder="Add a task for whenever…" onAdd={(t) => add(t)} /></div>
      {items.map((t) => (
        <span key={t.id} className="row small" style={{ gap: 6, padding: "3px 9px", borderRadius: 99, background: "color-mix(in srgb, var(--text) 8%, transparent)" }}>
          <button className="check" style={{ width: 16, height: 16 }} onClick={() => actions.toggleDone({ kind: "task", id: t.id }, today)} />
          {t.title}
          <button className="icon-btn" title="Study this" onClick={() => onStudy(t.id)}>▶</button>
        </span>
      ))}
    </div>
  );
  return (
    <>
      <QuickAdd placeholder="Add a task with no specific time…" onAdd={(t) => add(t)} />
      {!items.length && <div className="muted small" style={{ padding: "6px 0" }}>Nothing waiting. Things you add here have no day or time; move them to today when you're ready.</div>}
      {items.map((t) => (
        <div className="list-row" key={t.id}>
          <button className="check" onClick={() => actions.toggleDone({ kind: "task", id: t.id }, today)} />
          <div style={{ flex: 1 }}>{t.title}<div className="small muted">🏷 {categoryLabel(data, t.categoryID) ?? "No category"}</div></div>
          <button className="btn small" onClick={() => actions.moveTask(t.id, today)}>Do today</button>
          <button className="icon-btn" title="Study this" onClick={() => onStudy(t.id)}>▶</button>
        </div>
      ))}
    </>
  );
}

/** Ctrl+N / the + button: type a task, choose when (or "whenever") and a category; optionally start studying it */
export function QuickTaskModal({ onClose, onStudy }: { onClose: () => void; onStudy: (id: string) => void }) {
  const { data } = useStore();
  const timer = useTimer();
  const add = useAddTask();
  const [title, setTitle] = useState("");
  const [today, setToday] = useState(false);
  const [cat, setCat] = useState("");
  const go = (start: boolean) => {
    const t = title.trim(); if (!t) return;
    const item = add(t, { today, category: cat || undefined });
    onClose();
    if (start) onStudy(item.id);
  };
  return (
    <Modal onClose={onClose} width={400}>
      <h3 style={{ marginTop: 0 }}>New task</h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <input autoFocus placeholder="What do you need to do?" value={title} onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go(false); }} />
        <div className="seg" style={{ alignSelf: "flex-start" }}>
          <button className={!today ? "on" : ""} onClick={() => setToday(false)}>No specific time</button>
          <button className={today ? "on" : ""} onClick={() => setToday(true)}>Today</button>
        </div>
        <select value={cat} onChange={(e) => setCat(e.target.value)}>
          <option value="">🏷 No category</option>
          {orderedCategories(data).map((c) => <option key={c.id} value={c.id}>🏷 {categoryLabel(data, c.id)}</option>)}
        </select>
        <div className="row"><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn" disabled={!title.trim() || timer.active} onClick={() => go(true)}>Add & start</button>
          <button className="btn primary" disabled={!title.trim()} onClick={() => go(false)}>Add</button></div>
      </div>
    </Modal>
  );
}
