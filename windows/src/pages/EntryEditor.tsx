import { useState } from "react";
import { createPortal } from "react-dom";
import { Modal } from "../components";
import { WEEKDAYS, weekStart } from "../lib/dates";
import { ANYTIME_ID, Recurrence, RECURRENCE_TITLE, ScheduleEntry } from "../lib/model";
import { categoryLabel, normalized, orderedCategories, slotTitle, useStore } from "../lib/store";

/** Edits a to-do of the weekly schedule from the Tasks page: text, category, day and time in the week (or no specific time), repeat, study time, notes */
export default function EntryEditor({ entryID, day, onClose }: { entryID: string; day: Date; onClose: () => void }) {
  const { data, update } = useStore();
  const e = data.schedule.find((x) => x.id === entryID);
  const [text, setText] = useState(e?.text ?? "");
  const [cat, setCat] = useState(e?.categoryID ?? "");
  const [weekday, setWeekday] = useState(e?.weekday ?? 0);
  const [slot, setSlot] = useState(e?.slotID ?? ANYTIME_ID);
  const [rec, setRec] = useState<Recurrence>(e?.recurrence ?? "weekly");
  const [hasMin, setHasMin] = useState(e?.minutes != null);
  const [minutes, setMinutes] = useState(e?.minutes ?? 30);
  const [notes, setNotes] = useState(e?.notes ?? "");
  if (!e) return null;
  const slots = [...data.settings.timeSlots].sort((a, b) => a.startMinute - b.startMinute);
  // only two cells that repeat the same way fight for one cell
  const clash = slot === ANYTIME_ID ? undefined : data.schedule.find((x) => x.id !== entryID && x.weekday === weekday && x.slotID === slot && x.recurrence === rec);

  const save = () => {
    update((d) => {
      if (clash) d.schedule = d.schedule.filter((x) => x.id !== clash.id);
      const t = d.schedule.find((x) => x.id === entryID); if (!t) return;
      t.text = text.trim(); t.categoryID = cat || undefined; t.weekday = weekday; t.slotID = slot; t.recurrence = rec;
      t.weekStart = rec === "once" ? (t.weekStart ?? weekStart(day).toISOString()) : undefined;
      t.minutes = hasMin ? minutes : undefined; t.notes = notes || undefined;
      d.schedule = normalized(d.schedule);
    });
    onClose();
  };
  const row = (label: string, el: React.ReactNode) => <div className="row" style={{ margin: "8px 0" }}><span style={{ width: 110 }}>{label}</span><div style={{ flex: 1 }}>{el}</div></div>;
  return createPortal(
    <Modal onClose={onClose} width={440}>
      <h3>Edit to-do</h3>
      <textarea rows={2} value={text} onChange={(ev) => setText(ev.target.value)} style={{ width: "100%" }} />
      {row("Category", <select value={cat} onChange={(ev) => setCat(ev.target.value)} style={{ width: "100%" }}><option value="">None</option>
        {orderedCategories(data).map((c) => <option key={c.id} value={c.id}>{categoryLabel(data, c.id)}</option>)}</select>)}
      <div className="small muted" style={{ marginTop: 10, fontWeight: 700 }}>When in the week</div>
      {row("Day", <select value={weekday} onChange={(ev) => setWeekday(+ev.target.value)} style={{ width: "100%" }}>{WEEKDAYS.map((n, i) => <option key={n} value={i}>{n}</option>)}</select>)}
      {row("Time", <select value={slot} onChange={(ev) => setSlot(ev.target.value)} style={{ width: "100%" }}><option value={ANYTIME_ID}>No specific time</option>
        {slots.map((s) => <option key={s.id} value={s.id}>{slotTitle(s)}</option>)}</select>)}
      {row("Repeats", <select value={rec} onChange={(ev) => setRec(ev.target.value as Recurrence)} style={{ width: "100%" }}>
        {(Object.keys(RECURRENCE_TITLE) as Recurrence[]).map((r) => <option key={r} value={r}>{RECURRENCE_TITLE[r]}</option>)}</select>)}
      {clash && <div className="small" style={{ color: "#F59E0B" }}>⚠ This cell already has “{clash.text.split("\n")[0]}”. Saving replaces it.</div>}
      {row("Study time", <span className="row"><input type="checkbox" checked={hasMin} onChange={(ev) => setHasMin(ev.target.checked)} />
        {hasMin && <><input type="number" min={1} max={180} value={minutes} style={{ width: 70 }} onChange={(ev) => setMinutes(Math.max(1, Math.min(180, +ev.target.value || 1)))} /> min</>}</span>)}
      <textarea rows={3} placeholder="Notes" value={notes} onChange={(ev) => setNotes(ev.target.value)} style={{ width: "100%" }} />
      <div className="row" style={{ marginTop: 12 }}>
        <button className="btn" onClick={() => { update((d) => { d.schedule = d.schedule.filter((x) => x.id !== entryID); }); onClose(); }}>Delete</button>
        <span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" disabled={!text.trim()} onClick={save}>Save</button>
      </div>
    </Modal>, document.body);
}
