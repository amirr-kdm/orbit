import { useEffect, useRef, useState } from "react";
import { cellLook, fontOf, isDarkMode, templateOf } from "../lib/themes";
import { useNav } from "../App";
import { AnytimeBox } from "../lib/anytime";
import { CellPalette, useContextMenu, MenuItem } from "../components";
import { addDays, dualDate, minuteOfDay, monthDay, WEEKDAYS, weekdayIndex, weekStart } from "../lib/dates";
import { EntryKind, isLight, Recurrence, RECURRENCE_BADGE, RECURRENCE_TITLE, ScheduleEntry } from "../lib/model";
import { categoryOf, currentSlot, entryAt, isDone, parity, slotTitle, titleOf, useStore, categoryLabel, orderedCategories, entryColor } from "../lib/store";
import { useTimer } from "../lib/timer";

type Key = { day: number; slot: string };
const same = (a?: Key | null, b?: Key | null) => !!a && !!b && a.day === b.day && a.slot === b.slot;

export default function Schedule() {
  const { data, actions, update } = useStore();
  const timer = useTimer();
  const nav = useNav();
  const menu = useContextMenu();
  const [offset, setOffset] = useState(0);
  const [editing, setEditing] = useState<Key | null>(null);
  const [selected, setSelected] = useState<Key | null>(null);
  const [draft, setDraft] = useState("");
  const [editColor, setEditColor] = useState<string>();
  const [paletteColor, setPaletteColor] = useState<string>();
  const [newKind, setNewKind] = useState<EntryKind>("todo");
  const [newCat, setNewCat] = useState<string>();
  const [newRec, setNewRec] = useState<Recurrence>("weekly");
  const [now, setNow] = useState(new Date());
  // the template, font and cell text size from Settings (same as the Mac app)
  const tpl = templateOf(data.settings.template), font = fontOf(data.settings.font).css;
  const fontSize = data.settings.scheduleFontSize ?? 14;
  const setFontSize = (n: number) => update((d) => { d.settings.scheduleFontSize = n; });
  const dark = isDarkMode(data.settings.appearance);
  useEffect(() => { const t = setInterval(() => setNow(new Date()), 30_000); return () => clearInterval(t); }, []);

  const viewDate = addDays(now, offset * 7);
  const ws = weekStart(viewDate);
  const slots = [...data.settings.timeSlots].sort((a, b) => a.startMinute - b.startMinute);
  const todayIdx = offset === 0 ? weekdayIndex(now) : -1;
  const cur = offset === 0 ? currentSlot(data, now) : undefined;
  const par = parity(data, viewDate);
  const entry = (k: Key) => entryAt(data, k.day, k.slot, viewDate);
  const selectedEntry = selected ? entry(selected) : undefined;

  const commit = (k: Key | null = editing) => {
    if (!k || !same(k, editing)) return;
    actions.setCell(k.day, k.slot, viewDate, draft, editColor, newKind, newCat, newRec);
    setEditing(null);
  };
  const begin = (k: Key) => {
    if (same(k, editing)) return;
    if (editing) commit();
    const e = entry(k);
    setDraft(e?.text ?? ""); setEditColor(e ? e.colorHex : paletteColor); setSelected(k); setEditing(k);
  };
  const applyColor = (hex?: string) => {
    setPaletteColor(hex);
    if (editing) setEditColor(hex);
    else if (selectedEntry) actions.updateEntry(selectedEntry.id, (e) => { e.colorHex = hex; });
  };

  const cellMenu = (k: Key, e?: ScheduleEntry): MenuItem[] => {
    const items: MenuItem[] = [{ label: "Edit", onClick: () => begin(k) }];
    if (!e) return items;
    const day = addDays(ws, k.day);
    return [...items,
      { header: "Type" }, ...(["fixed", "todo"] as EntryKind[]).map((kind) => ({ label: `${e.kind === kind ? "✓ " : ""}${kind === "fixed" ? "Fixed" : "To-do"}`, onClick: () => actions.updateEntry(e.id, (x) => { x.kind = kind; }) })),
      { header: "Repeat" }, ...(Object.keys(RECURRENCE_TITLE) as Recurrence[]).map((r) => ({ label: `${e.recurrence === r ? "✓ " : ""}${RECURRENCE_TITLE[r]}`, onClick: () => actions.setRecurrence(e.id, r, viewDate) })),
      { header: "Category" }, { label: `${!e.categoryID ? "✓ " : ""}No category`, onClick: () => actions.updateEntry(e.id, (x) => { x.categoryID = undefined; }) },
      ...orderedCategories(data).map((c) => ({ label: `${e.categoryID === c.id ? "✓ " : ""}${categoryLabel(data, c.id)}`, onClick: () => actions.updateEntry(e.id, (x) => { x.categoryID = c.id; }) })),
      { separator: true },
      ...(e.kind === "todo" ? [
        { label: isDone(data, { kind: "schedule", id: e.id }, day) ? "Mark as not done" : "Mark as done", onClick: () => actions.toggleDone({ kind: "schedule", id: e.id }, day) },
        { label: "▶ Study this now", disabled: timer.active, onClick: () => { timer.setTarget({ kind: "schedule", id: e.id }); nav.go("timer"); } },
      ] : []),
      { label: "Clear cell", onClick: () => { actions.deleteEntry(e.id); setSelected(null); } },
    ];
  };

  const kind = selectedEntry?.kind ?? newKind;
  const rec = selectedEntry?.recurrence ?? newRec;
  const cat = selectedEntry ? selectedEntry.categoryID : newCat;
  const curColor = editing ? editColor : selectedEntry?.colorHex ?? paletteColor;
  const minute = minuteOfDay(now);

  return (
    <div className="page" onClick={() => editing && commit()}>
      <div className="row" style={{ alignItems: "flex-end" }}>
        <div>
          <div className="small" style={{ color: "var(--accent)", fontWeight: 800, letterSpacing: 2 }}>WEEKLY SCHEDULE</div>
          <h1 className="page-title">{dualDate(now)}</h1>
          <div className="subtitle">Today · {WEEKDAYS[weekdayIndex(now)]} · {parity(data, now) === "even" ? "Even week" : "Odd week"}</div>
        </div>
        <span className="spacer" />
        {cur ? (() => { const e = entryAt(data, weekdayIndex(now), cur.id, now); return (
          <div className="card" style={{ background: "var(--accent)", color: "white", minWidth: 260 }}>
            <div className="small" style={{ fontWeight: 700, letterSpacing: 1 }}>NOW · {slotTitle(cur)} <span style={{ float: "right" }}>{cur.endMinute - minute}m left</span></div>
            <b style={{ fontSize: 17 }}>{e ? titleOf(e) : "Free slot"}</b>
            <div className="progress" style={{ background: "rgba(255,255,255,.3)", marginTop: 6 }}><div style={{ width: `${((minute - cur.startMinute) / (cur.endMinute - cur.startMinute)) * 100}%`, background: "white" }} /></div>
          </div>
        ); })() : (() => {
          const next = slots.find((s) => s.startMinute > minute && entryAt(data, weekdayIndex(now), s.id, now));
          const e = next && entryAt(data, weekdayIndex(now), next.id, now);
          return <div className="card" style={{ minWidth: 260 }}><div className="small muted" style={{ fontWeight: 700, letterSpacing: 1 }}>OUTSIDE SCHEDULE HOURS</div><b>{e ? `Next: ${titleOf(e)}` : "Nothing else today"}</b></div>;
        })()}
      </div>

      <div className="row">
        <div className="seg"><button onClick={(e) => { e.stopPropagation(); commit(); setOffset((o) => o - 1); }}>‹</button><button onClick={(e) => { e.stopPropagation(); commit(); setOffset((o) => o + 1); }}>›</button></div>
        <div><b style={{ fontSize: 17 }}>{monthDay(ws, data.settings.primaryCalendar)} – {monthDay(addDays(ws, 6), data.settings.primaryCalendar)}</b>
          <div className="small muted">{monthDay(ws, data.settings.primaryCalendar === "persian" ? "gregorian" : "persian", true)} – {monthDay(addDays(ws, 6), data.settings.primaryCalendar === "persian" ? "gregorian" : "persian", true)}</div></div>
        <span className="badge" style={{ background: par === "even" ? "var(--accent)" : "#F97316" }} title="Right-click to swap even and odd weeks"
          onContextMenu={(e) => menu.open(e, [{ label: "Swap even and odd weeks", onClick: actions.swapParity }])}>{par === "even" ? "EVEN WEEK" : "ODD WEEK"}</span>
        {offset !== 0 && <><span className="small muted">{Math.abs(offset)} week{Math.abs(offset) > 1 ? "s" : ""} {offset > 0 ? "ahead" : "ago"}</span><button className="btn small" onClick={() => setOffset(0)}>Back to this week</button></>}
      </div>

      <div className="sched-wrap">
        <div className="sched" style={{ gridTemplateColumns: `110px repeat(${slots.length}, minmax(80px, 1fr))`, gap: tpl.fill === "grid" ? 0 : tpl.spacing, fontFamily: font }}>
          <div />
          {slots.map((s) => <div key={s.id} className={`slot-head ${cur?.id === s.id ? "now" : ""}`}>{slotTitle(s)}</div>)}
          {WEEKDAYS.map((name, day) => {
            const date = addDays(ws, day);
            return [
              <div key={name} className={`day-label ${day === todayIdx ? "today" : ""} ${day === 6 && day !== todayIdx ? "friday" : ""}`}>{name}<small>{monthDay(date, data.settings.primaryCalendar, true)}</small></div>,
              ...slots.map((s) => {
                const k = { day, slot: s.id };
                const e = entry(k);
                const isEdit = same(k, editing);
                const hex = isEdit ? editColor : e ? entryColor(data, e) : undefined;
                const color = hex ?? (e || isEdit ? tpl.cell : undefined);
                const look = cellLook(tpl, color, !!(e || isEdit), dark);
                const done = e?.kind === "todo" && isDone(data, { kind: "schedule", id: e.id }, date);
                const isNow = day === todayIdx && cur?.id === s.id;
                const textColor = e || isEdit ? look.text : undefined;
                const c = categoryOf(data, e?.categoryID);
                return (
                  <div key={s.id} className={`cell ${e || isEdit ? "filled" : ""} ${day === todayIdx ? "today-row" : ""} ${isNow ? "now" : ""} ${same(k, selected) && !isNow ? "selected" : ""}`}
                    style={{ ...look.style, color: textColor }}
                    onClick={(ev) => { ev.stopPropagation(); begin(k); }}
                    onContextMenu={(ev) => menu.open(ev, cellMenu(k, e))}>
                    {isEdit ? (
                      <textarea autoFocus value={draft} style={{ fontSize, color: textColor }} onChange={(ev) => setDraft(ev.target.value)}
                        onClick={(ev) => ev.stopPropagation()}
                        onKeyDown={(ev) => {
                          if (ev.key === "Enter" && !ev.shiftKey) { ev.preventDefault(); commit(k); }
                          if (ev.key === "Escape") setEditing(null);
                        }} />
                    ) : e ? (
                      <>
                        {RECURRENCE_BADGE[e.recurrence] && <span className="tag">{RECURRENCE_BADGE[e.recurrence]}</span>}
                        <span className="corner" onClick={(ev) => { if (e.kind === "todo") { ev.stopPropagation(); actions.toggleDone({ kind: "schedule", id: e.id }, date); } }}>
                          {e.kind === "fixed" ? "📌" : done ? "✅" : "○"}
                        </span>
                        <div className={`text ${done ? "strike" : ""}`} style={{ fontSize, color: done ? undefined : textColor }}>{e.text}</div>
                        {c && <div className="cat">🏷 {c.name}</div>}
                      </>
                    ) : (() => {
                      // Empty this week but used in other weeks (e.g. an every-other-week class)
                      const others = data.schedule.filter((x) => x.weekday === day && x.slotID === s.id && (x.recurrence === "even" || x.recurrence === "odd"));
                      return others.length ? <div className="small muted" style={{ opacity: 0.7, whiteSpace: "pre-line" }}>{others.map((x) => `${RECURRENCE_TITLE[x.recurrence]}: ${titleOf(x)}`).join("\n")}</div> : null;
                    })()}
                  </div>
                );
              }),
            ];
          })}
        </div>
      </div>

      <div onClick={(e) => e.stopPropagation()}>
        <AnytimeBox compact onStudy={(id) => { timer.setTarget({ kind: "task", id }); nav.go("timer"); }} />
      </div>

      <div className="toolbar" onClick={(e) => e.stopPropagation()}>
        <CellPalette selection={curColor} onPick={applyColor} />
        <div className="seg">
          {(["fixed", "todo"] as EntryKind[]).map((k) => <button key={k} className={kind === k ? "on" : ""} onClick={() => { setNewKind(k); if (selectedEntry) actions.updateEntry(selectedEntry.id, (x) => { x.kind = k; }); }}>{k === "fixed" ? "📌 Fixed" : "☑ To-do"}</button>)}
        </div>
        <select value={cat ?? ""} title="Category of the selected cell (and new cells)" onChange={(e) => { const v = e.target.value || undefined; setNewCat(v); if (selectedEntry) actions.updateEntry(selectedEntry.id, (x) => { x.categoryID = v; }); }}>
          <option value="">🏷 No category</option>
          {orderedCategories(data).map((c) => <option key={c.id} value={c.id}>🏷 {categoryLabel(data, c.id)}</option>)}
        </select>
        <select value={rec} title="Which weeks the cell appears in" onChange={(e) => { const r = e.target.value as Recurrence; setNewRec(r); if (selectedEntry) actions.setRecurrence(selectedEntry.id, r, viewDate); }}>
          {(Object.keys(RECURRENCE_TITLE) as Recurrence[]).map((r) => <option key={r} value={r}>🔁 {RECURRENCE_TITLE[r]}</option>)}
        </select>
        <label className="row small muted" title="Text size">A<input type="range" min={10} max={28} value={fontSize} onChange={(e) => setFontSize(+e.target.value)} style={{ width: 90, padding: 0 }} />A</label>
        <span className="spacer" />
        <span className="small muted">Click a cell to type · Enter saves · Shift+Enter new line · Esc cancels · Right-click for more</span>
      </div>
      {menu.node}
    </div>
  );
}
