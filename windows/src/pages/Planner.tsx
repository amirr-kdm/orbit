import { rtfToHtml } from "../lib/rtf";
import { cellLook, isDarkMode, templateOf } from "../lib/themes";
import React, { useEffect, useRef, useState } from "react";
import { CellPalette, MenuItem, Modal, useContextMenu } from "../components";
import { addDays, monthDay, WEEKDAYS, WEEKDAYS_SHORT, weekStart } from "../lib/dates";
import { isLight, Planner as PlannerT, PlannerFolder, uid, Recurrence, RECURRENCE_TITLE, ScheduleEntry } from "../lib/model";
import { ApplyResult, applyPlannerTo, categoryOf, ConflictChoice, fixedAt, parity, plannerConflicts, slotOf, slotTitle, titleOf, useStore, categoryLabel, orderedCategories, entryColor } from "../lib/store";

/** Planners: draft weeks with brainstorm notes that can be copied into the weekly schedule */
export default function Planner() {
  const { data, actions, update } = useStore();
  const menu = useContextMenu();
  const [sel, setSel] = useState<string | undefined>(data.planners[0]?.id);
  const current = data.planners.find((p) => p.id === sel);

  const remove = (p: PlannerT) => {
    if (!confirm(`Delete “${p.name}”? Its plan and notes are deleted. Anything already added to the weekly schedule stays there.`)) return;
    actions.deletePlanner(p.id);
    if (sel === p.id) setSel(data.planners.find((x) => x.id !== p.id)?.id);
  };

  const folders = data.plannerFolders ?? [];
  const inFolder = (p: PlannerT) => !!p.folderID && folders.some((f) => f.id === p.folderID);
  const [renaming, setRenaming] = useState<string | null>(null);
  const [over, setOver] = useState<string | null>(null);

  const addFolder = () => {
    const id = uid();
    update((d) => { (d.plannerFolders ??= []).push({ id, name: `Folder ${(d.plannerFolders?.length ?? 0) + 1}`, expanded: true }); });
    setRenaming(id);
  };
  const setFolder = (id: string, fn: (f: PlannerFolder) => void) => update((d) => { const f = d.plannerFolders?.find((x) => x.id === id); if (f) fn(f); });
  const deleteFolder = (id: string) => update((d) => {
    d.planners.forEach((p) => { if (p.folderID === id) delete p.folderID; });
    d.plannerFolders = (d.plannerFolders ?? []).filter((f) => f.id !== id);
  });
  /** Files a planner into a folder (undefined = none), placed before `before` if given */
  const move = (id: string, folder: string | undefined, before?: string) => update((d) => {
    const i = d.planners.findIndex((p) => p.id === id); if (i < 0 || id === before) return;
    const [p] = d.planners.splice(i, 1);
    if (folder) p.folderID = folder; else delete p.folderID;
    const j = before ? d.planners.findIndex((x) => x.id === before) : -1;
    if (j >= 0) d.planners.splice(j, 0, p); else d.planners.push(p);
  });
  const drop = (e: React.DragEvent, folder: string | undefined, before?: string) => {
    e.preventDefault(); e.stopPropagation(); setOver(null);
    const id = e.dataTransfer.getData("text/planner"); if (id) move(id, folder, before);
  };
  const allow = (key: string) => (e: React.DragEvent) => { if (e.dataTransfer.types.includes("text/planner")) { e.preventDefault(); setOver(key); } };

  const row = (p: PlannerT, indent: boolean) => (
    <button key={p.id} className={`nav ${p.id === sel ? "active" : ""}`} draggable
      style={{ flexDirection: "column", alignItems: "flex-start", gap: 0, marginLeft: indent ? 16 : 0, outline: over === p.id ? "2px solid var(--accent)" : undefined }}
      onClick={() => setSel(p.id)}
      onDragStart={(e) => { e.dataTransfer.setData("text/planner", p.id); e.dataTransfer.effectAllowed = "move"; }}
      onDragOver={allow(p.id)} onDragLeave={() => setOver(null)} onDrop={(e) => drop(e, p.folderID, p.id)}
      onContextMenu={(e) => menu.open(e, [
        { label: "Duplicate", onClick: () => setSel(actions.duplicatePlanner(p.id)) },
        ...(folders.length ? [{ separator: true }, { label: "No folder", onClick: () => move(p.id, undefined) },
          ...folders.map((f) => ({ label: `Move to “${f.name}”`, onClick: () => move(p.id, f.id) }))] : []),
        { separator: true }, { label: "Delete…", onClick: () => remove(p) }] as MenuItem[])}>
      <span>{p.name}</span><span className="small" style={{ opacity: 0.7 }}>{p.entries.length} to-dos · {p.notes.length} notes</span>
    </button>
  );

  return (
    <div style={{ display: "flex", minHeight: "100%" }}>
      <div style={{ width: 220, borderRight: "1px solid var(--line)", padding: "18px 10px", display: "flex", flexDirection: "column", gap: 4, flexShrink: 0 }}>
        <div className="row" style={{ padding: "0 6px 8px" }}><b>🧠 Notes & Brainstorm</b><span className="spacer" />
          <button className="icon-btn" title="New folder" onClick={addFolder}>📁</button>
          <button className="icon-btn" title="New planner" onClick={() => setSel(actions.addPlanner())}>＋</button></div>
        {folders.map((f) => {
          const inside = data.planners.filter((p) => p.folderID === f.id);
          return (
            <div key={f.id}>
              <div className="nav" style={{ fontWeight: 600, background: over === f.id ? "color-mix(in srgb, var(--accent) 25%, transparent)" : undefined }}
                onClick={() => setFolder(f.id, (x) => { x.expanded = !x.expanded; })}
                onDragOver={allow(f.id)} onDragLeave={() => setOver(null)}
                onDrop={(e) => { drop(e, f.id); if (!f.expanded) setFolder(f.id, (x) => { x.expanded = true; }); }}
                onContextMenu={(e) => menu.open(e, [
                  { label: "New planner here", onClick: () => { const id = actions.addPlanner(); move(id, f.id); setSel(id); } },
                  { label: "Rename…", onClick: () => setRenaming(f.id) },
                  { separator: true }, { label: "Delete folder", onClick: () => deleteFolder(f.id) }] as MenuItem[])}>
                <span style={{ display: "inline-block", transform: f.expanded ? "rotate(90deg)" : undefined, fontSize: 10 }}>▶</span>
                <span>{f.expanded ? "📂" : "📁"}</span>
                {renaming === f.id
                  ? <input autoFocus defaultValue={f.name} onClick={(e) => e.stopPropagation()} style={{ flex: 1, minWidth: 0 }}
                      onBlur={(e) => { const v = e.target.value.trim(); if (v) setFolder(f.id, (x) => { x.name = v; }); setRenaming(null); }}
                      onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); if (e.key === "Escape") setRenaming(null); }} />
                  : <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{f.name}</span>}
                <span className="small muted">{inside.length}</span>
              </div>
              {f.expanded && inside.map((p) => row(p, true))}
              {f.expanded && !inside.length && <div className="small muted" style={{ padding: "2px 0 6px 40px" }}>Drag planners here</div>}
            </div>
          );
        })}
        {data.planners.filter((p) => !inFolder(p)).map((p) => row(p, false))}
        {/* Drop here to take a planner out of its folder */}
        <div style={{ flex: 1, minHeight: 60, borderRadius: 9, background: over === "root" ? "color-mix(in srgb, var(--accent) 12%, transparent)" : undefined }}
          onDragOver={allow("root")} onDragLeave={() => setOver(null)} onDrop={(e) => drop(e, undefined)} />
      </div>
      {current ? <PlannerDetail key={current.id} planner={current} /> : (
        <div style={{ flex: 1, display: "grid", placeItems: "center" }}>
          <div style={{ textAlign: "center", display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
            <div style={{ width: 80, height: 80, borderRadius: "50%", background: "var(--accent)", display: "grid", placeItems: "center", fontSize: 38 }}>🧠</div>
            <h2 style={{ margin: 0 }}>Plan a week, brainstorm, then add it to your schedule</h2>
            <div className="muted" style={{ maxWidth: 420 }}>Each planner has its own weekly plan and notes. Class times from your weekly schedule are locked.</div>
            <button className="btn primary" onClick={() => setSel(actions.addPlanner())}>New planner</button>
          </div>
        </div>
      )}
      {menu.node}
    </div>
  );
}

type Key = { day: number; slot: string };

function PlannerDetail({ planner }: { planner: PlannerT }) {
  const { data, actions } = useStore();
  const tpl = templateOf(data.settings.template);
  const menu = useContextMenu();
  const [offset, setOffset] = useState(1);
  const [editing, setEditing] = useState<Key | null>(null);
  const [selected, setSelected] = useState<Key | null>(null);
  const [draft, setDraft] = useState("");
  const [editColor, setEditColor] = useState<string>();
  const [paletteColor, setPaletteColor] = useState<string>();
  const [newCat, setNewCat] = useState<string>();
  const [applying, setApplying] = useState(false);

  const target = addDays(new Date(), offset * 7);
  const ws = weekStart(target);
  const slots = [...data.settings.timeSlots].sort((a, b) => a.startMinute - b.startMinute);
  const at = (k: Key) => planner.entries.find((e) => e.weekday === k.day && e.slotID === k.slot);
  const same = (a?: Key | null, b?: Key | null) => !!a && !!b && a.day === b.day && a.slot === b.slot;
  const selectedEntry = selected ? at(selected) : undefined;

  const commit = (k: Key | null = editing) => {
    if (!k || !same(k, editing)) return;
    actions.setPlannerCell(planner.id, k.day, k.slot, draft, editColor, newCat);
    setEditing(null);
  };
  const begin = (k: Key) => {
    if (same(k, editing)) return;
    if (editing) commit();
    const e = at(k);
    setDraft(e?.text ?? ""); setEditColor(e ? e.colorHex : paletteColor); setSelected(k); setEditing(k);
  };
  const setEntry = (id: string, fn: (e: ScheduleEntry) => void) => actions.updatePlanner(planner.id, (p) => { const e = p.entries.find((x) => x.id === id); if (e) fn(e); });
  const applyColor = (hex?: string) => {
    setPaletteColor(hex);
    if (editing) setEditColor(hex); else if (selectedEntry) setEntry(selectedEntry.id, (e) => { e.colorHex = hex; });
  };
  const cat = selectedEntry ? selectedEntry.categoryID : newCat;
  const par = parity(data, target);

  return (
    <div className="page" style={{ flex: 1, maxWidth: 1400 }} onClick={() => editing && commit()}>
      <div className="row">
        <input value={planner.name} onChange={(e) => actions.updatePlanner(planner.id, (p) => { p.name = e.target.value; })}
          style={{ fontSize: 26, fontWeight: 800, background: "none", border: "none", boxShadow: "none", padding: 0, flex: 1, minWidth: 120 }} />
        <button className="btn" title={planner.planHidden ? "Show the weekly plan table" : "Hide the weekly plan table so the notes move up"}
          onClick={(e) => { e.stopPropagation(); actions.updatePlanner(planner.id, (p) => { p.planHidden = !p.planHidden; }); }}>
          {planner.planHidden ? "▦ Show table" : "▦ Hide table"}</button>
        <div className="seg" title="Which week's classes are locked in the plan">
          <button className={offset === 0 ? "on" : ""} onClick={() => setOffset(0)}>This week</button>
          <button className={offset === 1 ? "on" : ""} onClick={() => setOffset(1)}>Next week</button>
        </div>
        <span className="badge" style={{ background: par === "even" ? "var(--accent)" : "#F97316" }}>{par === "even" ? "EVEN WEEK" : "ODD WEEK"}</span>
        <button className="btn primary" disabled={!planner.entries.length} onClick={(e) => { e.stopPropagation(); commit(); setApplying(true); }}>⤓ Add to Weekly Schedule…</button>
      </div>

      {!planner.planHidden && <>
      <div className="sched-wrap">
        <div className="sched" style={{ gridTemplateColumns: `100px repeat(${slots.length}, minmax(76px, 1fr))` }}>
          <div />
          {slots.map((s) => <div key={s.id} className="slot-head">{slotTitle(s)}</div>)}
          {WEEKDAYS.map((name, day) => [
            <div key={name} className={`day-label ${day === 6 ? "friday" : ""}`}>{name}<small>{monthDay(addDays(ws, day), data.settings.primaryCalendar, true)}</small></div>,
            ...slots.map((s) => {
              const k = { day, slot: s.id };
              const e = at(k);
              const fixed = fixedAt(data, day, s.id, target);
              if (fixed) return (
                <div key={s.id} className="cell locked" title={e ? `Class time. Your planned “${titleOf(e)}” here will be skipped.` : "Class time from your weekly schedule. Nothing can be planned here."}>
                  <span className="small">🔒</span><div className="small" style={{ fontWeight: 600 }}>{titleOf(fixed)}</div>
                  {e && <span className="corner" style={{ color: "#F97316" }}>⚠</span>}
                </div>
              );
              const isEdit = same(k, editing);
              const hex = isEdit ? editColor : e ? entryColor(data, e) : undefined;
              const color = hex ?? (e || isEdit ? tpl.cell : undefined);
              const look = cellLook(tpl, color, !!(e || isEdit), isDarkMode(data.settings.appearance));
              const textColor = e || isEdit ? look.text : undefined;
              const c = categoryOf(data, e?.categoryID);
              return (
                <div key={s.id} className={`cell ${e || isEdit ? "filled" : ""} ${same(k, selected) ? "selected" : ""}`}
                  style={{ ...look.style, color: textColor }}
                  onClick={(ev) => { ev.stopPropagation(); begin(k); }}
                  onContextMenu={(ev) => menu.open(ev, [
                    { label: "Edit", onClick: () => begin(k) },
                    ...(e ? [{ header: "Category" }, { label: `${!e.categoryID ? "✓ " : ""}No category`, onClick: () => setEntry(e.id, (x) => { x.categoryID = undefined; }) },
                      ...orderedCategories(data).map((cc) => ({ label: `${e.categoryID === cc.id ? "✓ " : ""}${categoryLabel(data, cc.id)}`, onClick: () => setEntry(e.id, (x) => { x.categoryID = cc.id; }) })),
                      { separator: true }, { label: "Clear cell", onClick: () => actions.updatePlanner(planner.id, (p) => { p.entries = p.entries.filter((x) => x.id !== e.id); }) }] : []),
                  ] as MenuItem[])}>
                  {isEdit ? (
                    <textarea autoFocus value={draft} style={{ fontSize: 14, color: textColor }} onChange={(ev) => setDraft(ev.target.value)} onClick={(ev) => ev.stopPropagation()}
                      onKeyDown={(ev) => { if (ev.key === "Enter" && !ev.shiftKey) { ev.preventDefault(); commit(k); } if (ev.key === "Escape") setEditing(null); }} />
                  ) : e ? <>
                    <div className="text" style={{ fontSize: 14, color: textColor }}>{e.text}</div>
                    {c && <div className="cat">🏷 {c.name}</div>}
                  </> : null}
                </div>
              );
            }),
          ])}
        </div>
      </div>

      <div className="toolbar" onClick={(e) => e.stopPropagation()}>
        <CellPalette selection={editing ? editColor : selectedEntry?.colorHex ?? paletteColor} onPick={applyColor} />
        <select value={cat ?? ""} title="Category of the selected cell (and new cells)" onChange={(e) => { const v = e.target.value || undefined; setNewCat(v); if (selectedEntry) setEntry(selectedEntry.id, (x) => { x.categoryID = v; }); }}>
          <option value="">🏷 No category</option>
          {orderedCategories(data).map((c) => <option key={c.id} value={c.id}>🏷 {categoryLabel(data, c.id)}</option>)}
        </select>
        <span className="spacer" />
        <span className="small muted">🔒 Class times from your weekly schedule are locked</span>
      </div>
      </>}

      <Notes planner={planner} />

      {applying && <ApplyDialog planner={planner} offset={offset} onClose={() => setApplying(false)} />}
      {menu.node}
    </div>
  );
}

// ---------- Add to schedule ----------

function ApplyDialog({ planner, offset: initial, onClose }: { planner: PlannerT; offset: number; onClose: () => void }) {
  const { data, actions } = useStore();
  const [offset, setOffset] = useState(initial);
  const [rec, setRec] = useState<Recurrence>("once");
  const [result, setResult] = useState<ApplyResult | null>(null);
  const date = addDays(new Date(), offset * 7);
  const conflicts = plannerConflicts(data, planner, date);
  const locked = planner.entries.filter((e) => fixedAt(data, e.weekday, e.slotID, date));

  const apply = (choice: ConflictChoice) => {
    // Work out the summary on a copy; the store applies the very same function
    setResult(applyPlannerTo(structuredClone(data), structuredClone(planner), date, rec, choice));
    actions.applyPlanner(planner.id, date, rec, choice);
  };
  const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;

  return (
    <Modal onClose={onClose} width={540}>
      {result ? (
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <h2 style={{ margin: 0, color: "#22C55E" }}>✓ Added to your weekly schedule</h2>
          <div>{plural(result.added, "new to-do")} added</div>
          {result.replaced > 0 && <div>{plural(result.replaced, "old to-do")} replaced</div>}
          {result.keptOld > 0 && <div>{plural(result.keptOld, "clashing to-do")} skipped (old ones kept)</div>}
          {result.skippedFixed > 0 && <div>{result.skippedFixed} skipped because of class times</div>}
          <div className="muted">Repeat: {RECURRENCE_TITLE[rec]}</div>
          <div className="row"><span className="spacer" /><button className="btn primary" onClick={onClose}>Done</button></div>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <h2 style={{ margin: 0 }}>Add “{planner.name}” to the weekly schedule</h2>
          <div className="row"><span style={{ width: 70 }}>Week</span>
            <select value={offset} onChange={(e) => setOffset(+e.target.value)} style={{ flex: 1 }}>
              <option value={0}>This week · {parity(data, new Date()) === "even" ? "Even week" : "Odd week"}</option>
              <option value={1}>Next week · {parity(data, addDays(new Date(), 7)) === "even" ? "Even week" : "Odd week"}</option>
            </select></div>
          <div className="row"><span style={{ width: 70 }}>Repeat</span>
            <select value={rec} onChange={(e) => setRec(e.target.value as Recurrence)} style={{ flex: 1 }}>
              {(Object.keys(RECURRENCE_TITLE) as Recurrence[]).map((r) => <option key={r} value={r}>{RECURRENCE_TITLE[r]}</option>)}
            </select></div>
          <div>☑ {plural(planner.entries.length, "planned to-do")}</div>
          {locked.length > 0 && <div className="muted">🔒 {locked.length} sit on class times and will be skipped</div>}
          {!conflicts.length ? <>
            <div style={{ color: "#22C55E" }}>✓ No clashes with your existing to-dos</div>
            <div className="row"><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button><button className="btn primary" onClick={() => apply("replaceOld")}>Add to schedule</button></div>
          </> : <>
            <div style={{ color: "#F97316", fontWeight: 600 }}>⚠ {plural(conflicts.length, "clash")} with to-dos already in the schedule</div>
            <div style={{ maxHeight: 160, overflow: "auto", background: "var(--card2)", borderRadius: 10, padding: "4px 10px" }}>
              {conflicts.map((c) => {
                const s = slotOf(data, c.new.slotID);
                return <div key={c.new.id} className="list-row small"><span className="muted" style={{ width: 100 }}>{WEEKDAYS_SHORT[c.new.weekday]} {s ? slotTitle(s) : ""}</span>
                  <span className="strike">{titleOf(c.old)}</span><span className="muted">→</span><b>{titleOf(c.new)}</b></div>;
              })}
            </div>
            <b>What should happen to these?</b>
            <Choice primary title="Replace the old to-dos" detail="The old to-dos are removed and the planner's to-dos take their place." onClick={() => apply("replaceOld")} />
            <Choice title="Keep the old to-dos" detail="Skip the planner's clashing to-dos and add everything else." onClick={() => apply("keepOld")} />
            <Choice title="Cancel" detail="Don't change the weekly schedule." onClick={onClose} />
          </>}
        </div>
      )}
    </Modal>
  );
}

const Choice = ({ title, detail, primary, onClick }: { title: string; detail: string; primary?: boolean; onClick: () => void }) => (
  <button className={`btn ${primary ? "primary" : ""}`} style={{ textAlign: "left", padding: "10px 14px", borderRadius: 10 }} onClick={onClick}>
    <b>{title}</b><div className="small" style={{ opacity: 0.8 }}>{detail}</div>
  </button>
);

// ---------- Notes ----------

function Notes({ planner }: { planner: PlannerT }) {
  const { data, actions } = useStore();
  const menu = useContextMenu();
  const [noteID, setNoteID] = useState(planner.notes[0]?.id);
  const note = planner.notes.find((n) => n.id === noteID) ?? planner.notes[0];
  const editor = useRef<HTMLDivElement>(null);
  const pending = useRef<number>();
  const loaded = useRef<string>();
  const shown = useRef<string>();
  const [inTable, setInTable] = useState(false);

  const save = () => {
    window.clearTimeout(pending.current);
    const id = loaded.current, html = editor.current?.innerHTML;
    if (!id || html === undefined || html === shown.current) return;   // opened but not edited: leave it as it is
    actions.updatePlanner(planner.id, (p) => { const n = p.notes.find((x) => x.id === id); shown.current = html; if (n && n.html !== html) { n.html = html; delete n.rtf; n.updatedAt = new Date().toISOString(); } });
  };

  // Load the note into the editor only when switching notes, so typing never jumps the caret
  useEffect(() => {
    if (!note || loaded.current === note.id || !editor.current) return;
    if (loaded.current) save();
    // (older builds saved the word "undefined" when opening a Mac note: ignore it)
    const html = note.html === "undefined" ? undefined : note.html;
    editor.current.innerHTML = html ?? (note.rtf ? rtfToHtml(note.rtf) : "");
    shown.current = editor.current.innerHTML;
    loaded.current = note.id;
  });
  useEffect(() => () => save(), []); // eslint-disable-line react-hooks/exhaustive-deps

  const saved = useRef<Range | null>(null);
  const [fg, setFg] = useState<string | null>(null);
  const [bg, setBg] = useState<string | null>(null);
  const cmd = (name: string, value?: string) => {
    editor.current?.focus();
    const sel = window.getSelection();
    if (saved.current && sel && !editor.current?.contains(sel.anchorNode)) { sel.removeAllRanges(); sel.addRange(saved.current); }
    document.execCommand(name, false, value); save(); readColors();
  };
  /** Remember the selection (so the colour popover can apply to it) and show the colours under the cursor */
  const readColors = () => {
    const sel = window.getSelection();
    if (sel && sel.rangeCount && editor.current?.contains(sel.anchorNode)) saved.current = sel.getRangeAt(0).cloneRange();
    const toHex = (v: string) => { const m = v.match(/\d+/g); return m && m.length >= 3 ? "#" + m.slice(0, 3).map((x) => (+x).toString(16).padStart(2, "0")).join("").toUpperCase() : null; };
    const f = toHex(document.queryCommandValue("foreColor")), b = toHex(document.queryCommandValue("hiliteColor") || document.queryCommandValue("backColor"));
    const text = toHex(getComputedStyle(editor.current ?? document.body).color);
    setFg(f && f !== text ? f : null); setBg(b && b !== "#000000" ? b : null);
  };
  /** Right-to-left (Persian) or left-to-right for the paragraphs in the selection */
  const direction = (dir: "rtl" | "ltr") => {
    editor.current?.focus();
    const sel = window.getSelection();
    let el = sel?.anchorNode instanceof Element ? sel.anchorNode : sel?.anchorNode?.parentElement;
    if (!el || el === editor.current || !editor.current?.contains(el)) { document.execCommand("formatBlock", false, "<p>"); el = window.getSelection()?.anchorNode?.parentElement; }
    const block = el?.closest("p, div, li, h1, h2, blockquote, td, th") as HTMLElement | null;
    if (block && editor.current?.contains(block) && block !== editor.current) { block.dir = dir; block.style.textAlign = dir === "rtl" ? "right" : "left"; }
    save();
  };
  const cellOf = () => { const n = window.getSelection()?.anchorNode; const el = n instanceof Element ? n : n?.parentElement; return el?.closest("td, th") as HTMLTableCellElement | null; };

  const checklist = () => {
    cmd("insertUnorderedList");
    const n = window.getSelection()?.anchorNode;
    const ul = (n instanceof Element ? n : n?.parentElement)?.closest("ul");
    if (ul) ul.classList.toggle("checklist");
    save();
  };
  const table = (rows: number, cols: number) => {
    const head = `<tr>${Array.from({ length: cols }, (_, c) => `<th>Column ${c + 1}</th>`).join("")}</tr>`;
    const body = Array.from({ length: rows - 1 }, () => `<tr>${"<td><br></td>".repeat(cols)}</tr>`).join("");
    cmd("insertHTML", `<table><tbody>${head}${body}</tbody></table><p><br></p>`);
  };
  const tableEdit = (op: "row+" | "row-" | "col+" | "col-" | "del") => {
    const cell = cellOf();
    if (!cell) return;
    const tr = cell.parentElement as HTMLTableRowElement, tbl = cell.closest("table")!;
    const ci = cell.cellIndex;
    if (op === "row+") { const r = tr.cloneNode(true) as HTMLTableRowElement; r.querySelectorAll("th, td").forEach((c) => { const td = document.createElement("td"); td.innerHTML = "<br>"; c.replaceWith(td); }); tr.after(r); }
    if (op === "row-" && tbl.rows.length > 1) tr.remove();
    if (op === "col+") [...tbl.rows].forEach((r, i) => { const c = document.createElement(i === 0 && r.cells[0]?.tagName === "TH" ? "th" : "td"); c.innerHTML = i === 0 && c.tagName === "TH" ? "Column" : "<br>"; r.cells[ci].after(c); });
    if (op === "col-" && tr.cells.length > 1) [...tbl.rows].forEach((r) => r.cells[ci]?.remove());
    if (op === "del") tbl.remove();
    save();
  };

  const add = () => {
    const id = crypto.randomUUID().toUpperCase();
    actions.updatePlanner(planner.id, (p) => { p.notes.push({ id, title: `Note ${p.notes.length + 1}`, html: "", updatedAt: new Date().toISOString() }); });
    setNoteID(id);
  };
  const colors = data.settings.cellPalette.filter((c) => c !== "#FFFFFF");
  const B = ({ t, title, on }: { t: string; title: string; on: () => void }) => (
    <button className="icon-btn" title={title} onMouseDown={(e) => { e.preventDefault(); on(); }} style={{ minWidth: 28, fontWeight: 600 }}>{t}</button>
  );

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }} onClick={(e) => e.stopPropagation()}>
      <h2 style={{ margin: "6px 0 0", fontSize: 20 }}>🧠 Notes & brainstorm</h2>
      <div className="row" style={{ flexWrap: "wrap", gap: 6 }}>
        {planner.notes.map((n) => (
          <button key={n.id} className={`btn ${n.id === note?.id ? "primary" : ""}`} style={{ borderRadius: 99 }} onClick={() => setNoteID(n.id)}
            onContextMenu={(e) => menu.open(e, [
              { label: "Duplicate", onClick: () => actions.updatePlanner(planner.id, (p) => { p.notes.push({ ...n, id: crypto.randomUUID().toUpperCase(), title: `${n.title} copy` }); }) },
              { label: "Delete note", onClick: () => { if (confirm(`Delete “${n.title}”?`)) actions.updatePlanner(planner.id, (p) => { p.notes = p.notes.filter((x) => x.id !== n.id); }); } },
            ])}>📄 {n.title || "Untitled"}</button>
        ))}
        <button className="btn" style={{ borderRadius: 99, borderStyle: "dashed" }} onClick={add}>＋ New note</button>
      </div>
      {note ? (
        <div className="card" style={{ padding: 0 }}>
          <div className="row" style={{ padding: "12px 16px 0" }}>
            <input value={note.title} placeholder="Title" onChange={(e) => actions.updatePlanner(planner.id, (p) => { const n = p.notes.find((x) => x.id === note.id); if (n) n.title = e.target.value; })}
              style={{ fontSize: 18, fontWeight: 700, background: "none", border: "none", boxShadow: "none", padding: 0, flex: 1 }} />
            <span className="small muted">Edited {new Date(note.updatedAt).toLocaleString()}</span>
          </div>
          <div className="row note-bar">
            <select value="" title="Text style" onChange={(e) => { cmd("formatBlock", e.target.value); e.target.value = ""; }} style={{ padding: "3px 6px" }}>
              <option value="" disabled>Style</option><option value="<h1>">Title</option><option value="<h2>">Heading</option><option value="<p>">Body</option><option value="<blockquote>">Quote</option>
            </select>
            <span className="sep" />
            <B t="B" title="Bold" on={() => cmd("bold")} /><B t="I" title="Italic" on={() => cmd("italic")} />
            <B t="U" title="Underline" on={() => cmd("underline")} /><B t="S" title="Strikethrough" on={() => cmd("strikeThrough")} />
            <span className="sep" />
            <B t="•" title="Bulleted list" on={() => cmd("insertUnorderedList")} /><B t="1." title="Numbered list" on={() => cmd("insertOrderedList")} />
            <B t="☑" title="Checklist (click a box to tick it)" on={checklist} />
            <span className="sep" />
            <B t="⇤" title="Align left" on={() => cmd("justifyLeft")} /><B t="↔" title="Centre" on={() => cmd("justifyCenter")} />
            <B t="⇥" title="Align right" on={() => cmd("justifyRight")} /><B t="☰" title="Justify" on={() => cmd("justifyFull")} />
            <span className="sep" />
            <B t="LTR" title="Left to right (English)" on={() => direction("ltr")} /><B t="RTL" title="Right to left (Persian / فارسی)" on={() => direction("rtl")} />
            <span className="sep" />
            <NoteColor highlight={false} current={fg} colors={colors} onPick={(c) => cmd("foreColor", c ?? "inherit")} onAddColor={actions.addColor} />
            <NoteColor highlight current={bg} colors={colors} onPick={(c) => cmd("hiliteColor", c ? `${c}59` : "transparent")} onAddColor={actions.addColor} />
            <span className="sep" />
            <select value="" title="Insert a table" onChange={(e) => { const [r, c] = e.target.value.split("x").map(Number); table(r, c); e.target.value = ""; }} style={{ padding: "3px 6px" }}>
              <option value="" disabled>▦ Table</option><option value="3x2">2 × 3</option><option value="3x3">3 × 3</option><option value="4x3">3 × 4</option><option value="5x4">4 × 5</option>
            </select>
            {inTable && <>
              <B t="+ Row" title="Add a row below" on={() => tableEdit("row+")} /><B t="− Row" title="Delete this row" on={() => tableEdit("row-")} />
              <B t="+ Col" title="Add a column to the right" on={() => tableEdit("col+")} /><B t="− Col" title="Delete this column" on={() => tableEdit("col-")} />
              <B t="✕ Table" title="Delete the table" on={() => tableEdit("del")} />
            </>}
            <B t="―" title="Divider line" on={() => cmd("insertHorizontalRule")} />
          </div>
          <div ref={editor} className="note-editor" contentEditable suppressContentEditableWarning data-placeholder="Brainstorm here… headings, lists, checklists and tables"
            onInput={() => { window.clearTimeout(pending.current); pending.current = window.setTimeout(save, 500); }}
            onBlur={save}
            onKeyUp={() => { setInTable(!!cellOf()); readColors(); }}
            onMouseUp={() => { setInTable(!!cellOf()); readColors(); }}
            onClick={(e) => {
              // Tick a checklist item by clicking its box
              const li = (e.target as HTMLElement).closest("ul.checklist > li") as HTMLElement | null;
              if (li && e.clientX - li.getBoundingClientRect().left < 24) { li.classList.toggle("done"); save(); }
            }} />
        </div>
      ) : <button className="btn" onClick={add}>New note</button>}
      {menu.node}
    </div>
  );
}

/** Text colour / highlight picker: swatches, the colour at the cursor, and custom colours */
function NoteColor({ highlight, current, colors, onPick, onAddColor }: { highlight: boolean; current: string | null; colors: string[]; onPick: (c: string | null) => void; onAddColor: (c: string) => void }) {
  const [open, setOpen] = useState(false);
  const [custom, setCustom] = useState("#22C55E");
  const same = (a: string | null, b: string) => !!a && a.slice(0, 7).toUpperCase() === b.toUpperCase();
  return (
    <span style={{ position: "relative" }}>
      <button className="icon-btn" title={highlight ? "Highlight" : "Text colour"} onMouseDown={(e) => { e.preventDefault(); setOpen((o) => !o); }}
        style={{ display: "inline-flex", flexDirection: "column", alignItems: "center", gap: 1, minWidth: 30 }}>
        <span>{highlight ? "🖍" : "A"}</span>
        <span style={{ width: 16, height: 3.5, borderRadius: 2, background: current ?? (highlight ? "transparent" : "var(--text)"), border: !current && highlight ? "1px solid var(--muted)" : undefined }} />
      </button>
      {open && (
        <div className="popover" style={{ top: 34, left: 0, width: 240 }} onMouseDown={(e) => { if ((e.target as HTMLElement).tagName !== "INPUT") e.preventDefault(); }}>
          <b>{highlight ? "Highlight" : "Text colour"}</b>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 28px)", gap: 8 }}>
            <button className="swatch" title={highlight ? "No highlight" : "Default colour"} style={{ background: "transparent", outline: !current ? "2px solid var(--accent)" : undefined, outlineOffset: 2 }}
              onClick={() => { onPick(null); setOpen(false); }}>{highlight ? "⌀" : "A"}</button>
            {colors.map((c) => <button key={c} className="swatch" title={c} style={{ background: c, outline: same(current, c) ? "2px solid var(--accent)" : undefined, outlineOffset: 2 }}
              onClick={() => { onPick(c); setOpen(false); }}>{same(current, c) ? "✓" : ""}</button>)}
          </div>
          <div className="row"><input type="color" value={custom} onChange={(e) => setCustom(e.target.value.toUpperCase())} style={{ width: 48, height: 30, padding: 2 }} />
            <span className="small muted">{custom}</span><span className="spacer" />
            <button className="btn primary small" onClick={() => { onAddColor(custom); onPick(custom); setOpen(false); }}>Use</button></div>
          <div className="small muted">Custom colours are saved with your other colours.</div>
        </div>
      )}
    </span>
  );
}
