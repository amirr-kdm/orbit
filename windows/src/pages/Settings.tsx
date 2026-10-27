import { PageHero } from "../components";
import { slotTime } from "../lib/dates";
import { Appearance } from "../lib/model";
import { orderedCategories, useStore } from "../lib/store";
import { ambient, cellLook, FONTS, fontOf, isDarkMode, TEMPLATES, templateOf } from "../lib/themes";

const ACCENTS = ["#5B7CFA", "#0EA5E9", "#E879F9", "#22D3EE", "#C2410C", "#F97316", "#16A34A", "#E11D48"];
const toTime = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const fromTime = (v: string) => { const [h, m] = v.split(":").map(Number); return h * 60 + m; };

export default function Settings() {
  const { data, update, actions } = useStore();
  const s = data.settings;
  const set = (fn: (st: typeof s) => void) => update((d) => fn(d.settings));
  const dark = isDarkMode(data.settings.appearance);

  const exportData = () => {
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "orbit-backup.json"; a.click();
  };
  const importData = (file: File) => file.text().then((t) => { try { const j = JSON.parse(t); if (confirm("Replace all your data with this backup?")) update((d) => Object.assign(d, j)); } catch { alert("That file isn't an Orbit backup."); } });

  return (
    <div className="page" style={{ maxWidth: 900 }}>
      <PageHero icon="⚙️" kicker="APP" title="Settings" sub="Make Orbit yours" tint="#475569" />

      <div className="card"><h3><span className="t2-ico">🎨</span>Appearance</h3>
        <div className="row"><span style={{ width: 140 }}>Mode</span><div className="seg">{(["system", "light", "dark"] as Appearance[]).map((a) => <button key={a} className={s.appearance === a ? "on" : ""} onClick={() => set((x) => { x.appearance = a; })}>{a[0].toUpperCase() + a.slice(1)}</button>)}</div></div>
        <div className="row" style={{ marginTop: 12 }}><span style={{ width: 140 }}>Accent colour</span>{ACCENTS.map((c) => <button key={c} className={`swatch ${s.accent === c ? "on" : ""}`} style={{ background: c }} onClick={() => set((x) => { x.accent = c; })} />)}</div>
      </div>

      <div className="card"><h3><span className="t2-ico">🖼</span>Template</h3>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 14 }}>
          {TEMPLATES.map((t) => {
            const on = templateOf(s.template).id === t.id;
            return (
              <button key={t.id} onClick={() => set((x) => { x.template = t.id; x.accent = t.accent; })}
                style={{ textAlign: "left", padding: 10, borderRadius: 14, cursor: "pointer", color: "inherit", font: "inherit",
                  border: `2px solid ${on ? t.accent : "var(--line)"}`, background: "var(--card2)", display: "flex", flexDirection: "column", gap: 8 }}>
                <div style={{ height: 74, borderRadius: 10, padding: 8, display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: t.fill === "grid" ? 0 : 5,
                  backgroundColor: "var(--bg)", backgroundImage: ambient(t, dark) || undefined }}>
                  {[t.cell, undefined, t.cell, t.cell, t.cell, undefined].map((c, i) => { // the theme's own cell colour, so each card shows its look
                    const filled = i !== 1 && i !== 5, look = cellLook(t, c, filled, dark);
                    return <div key={i} style={{ ...look.style, color: look.text, fontSize: 8, fontWeight: 700, display: "grid", placeItems: "center",
                      ...(filled ? {} : { border: t.fill === "grid" ? look.style.border : "1px dashed var(--line)" }) }}>{filled ? "Math" : ""}</div>;
                  })}
                </div>
                <div className="row" style={{ gap: 6 }}><b>{t.title}</b>{on && <span style={{ color: t.accent }}>✓</span>}</div>
                <div className="small muted" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{t.subtitle}</div>
              </button>
            );
          })}
        </div>
        <div className="small muted" style={{ marginTop: 8 }}>Changes the look of the weekly schedule, the page background and the app's accent colour.</div>
      </div>

      <div className="card"><h3><span className="t2-ico">🔤</span>Font</h3>
        <div className="row"><span style={{ width: 140 }}>Font</span>
          <select value={fontOf(s.font).id} onChange={(e) => set((x) => { x.font = e.target.value; })}>
            <optgroup label="Whole app">{FONTS.filter((f) => f.whole).map((f) => <option key={f.id} value={f.id}>{f.title}</option>)}</optgroup>
            <optgroup label="Weekly schedule">{FONTS.filter((f) => !f.whole).map((f) => <option key={f.id} value={f.id}>{f.title}</option>)}</optgroup>
          </select></div>
        <div className="row" style={{ marginTop: 10 }}><span style={{ width: 140 }}>Cell text size</span>
          <input type="range" min={10} max={28} value={s.scheduleFontSize ?? 14} onChange={(e) => set((x) => { x.scheduleFontSize = +e.target.value; })} style={{ width: 160, padding: 0 }} />
          <span className="muted">{s.scheduleFontSize ?? 14} pt</span></div>
        <div className="row" style={{ marginTop: 10, gap: 10 }}>
          {["Math 2", "Physics class\nRoom 204", "English (TOEFL)"].map((txt, i) => {
            const t = templateOf(s.template), look = cellLook(t, undefined, true, dark);
            return <div key={i} style={{ ...look.style, color: look.text, flex: 1, minHeight: 70, display: "grid", placeItems: "center", textAlign: "center", whiteSpace: "pre-line",
              fontFamily: fontOf(s.font).css, fontSize: s.scheduleFontSize ?? 14, fontWeight: 600, padding: 6 }}>{txt}</div>;
          })}
        </div>
        <div className="small muted" style={{ marginTop: 6 }}>“Whole app” fonts change everything. The others style the weekly schedule. Fonts your computer doesn't have fall back to a similar one.</div>
      </div>

      <div className="card"><h3><span className="t2-ico">📆</span>Calendar</h3>
        <div className="row"><span style={{ width: 140 }}>Primary calendar</span><div className="seg">{(["persian", "gregorian"] as const).map((k) => <button key={k} className={s.primaryCalendar === k ? "on" : ""} onClick={() => set((x) => { x.primaryCalendar = k; })}>{k === "persian" ? "Persian" : "Gregorian"}</button>)}</div></div>
        <div className="small muted" style={{ marginTop: 6 }}>The other calendar is always shown alongside. To swap even and odd weeks, right-click the EVEN/ODD WEEK badge in the weekly schedule.</div>
      </div>

      <div className="card"><div className="row"><h3 style={{ margin: 0 }}>🗓️ Weekly schedule time slots</h3><span className="spacer" />
        <button className="btn small" onClick={() => confirm("Restore the default slots? This also clears the schedule.") && actions.resetSlots()}>Reset to default</button>
        <button className="btn small" onClick={actions.addSlot}>＋ Add</button></div>
        {[...s.timeSlots].sort((a, b) => a.startMinute - b.startMinute).map((sl) => (
          <div key={sl.id} className="list-row">
            <span style={{ width: 60 }}>From</span><input type="time" value={toTime(sl.startMinute)} onChange={(e) => set((x) => { const t = x.timeSlots.find((y) => y.id === sl.id)!; t.startMinute = fromTime(e.target.value); })} />
            <span style={{ width: 30, textAlign: "center" }}>to</span><input type="time" value={toTime(sl.endMinute)} onChange={(e) => set((x) => { const t = x.timeSlots.find((y) => y.id === sl.id)!; t.endMinute = fromTime(e.target.value); })} />
            <span className="muted small">{slotTime(sl.startMinute)}–{slotTime(sl.endMinute)}</span><span className="spacer" />
            <button className="icon-btn" title="Delete slot" onClick={() => confirm("Delete this slot? Everything in this column is removed too.") && actions.deleteSlot(sl.id)}>🗑</button>
          </div>
        ))}
      </div>

      <div className="card"><h3><span className="t2-ico">⏱️</span>Timer & goal</h3>
        {([["Pomodoro focus (min)", "pomodoroMinutes", 5, 120], ["Break (min)", "breakMinutes", 1, 60], ["Daily study goal (min)", "dailyGoalMinutes", 15, 960]] as const).map(([label, key, min, max]) => (
          <div key={key} className="list-row"><span style={{ flex: 1 }}>{label}</span><input type="number" min={min} max={max} value={s[key]} style={{ width: 90 }} onChange={(e) => set((x) => { x[key] = Math.max(min, Math.min(max, +e.target.value || min)); })} /></div>
        ))}
      </div>

      <div className="card"><div className="row"><h3 style={{ margin: 0 }}>🏷 Task categories</h3><span className="spacer" /><button className="btn small" onClick={actions.addCategory}>＋ Add</button></div>
        <div className="small muted" style={{ margin: "4px 0 6px" }}>A category can have subcategories one level down (e.g. IELTS › Speaking). Filters and reports by a category include its subcategories.</div>
        {orderedCategories(data).map((c) => (
          <div key={c.id} className="list-row" style={{ paddingLeft: c.parentID ? 28 : undefined }}>
            {c.parentID && <span className="muted">↳</span>}
            <input type="color" value={c.colorHex} style={{ width: 36, padding: 2 }} onChange={(e) => actions.updateCategory({ ...c, colorHex: e.target.value.toUpperCase() })} />
            <input value={c.name} style={{ flex: 1 }} onChange={(e) => actions.updateCategory({ ...c, name: e.target.value })} />
            {!c.parentID && <button className="btn small" title="Add a subcategory" onClick={() => actions.addSubcategory(c.id)}>＋ Sub</button>}
            <button className="icon-btn" onClick={() => confirm(c.parentID ? `Delete “${c.name}”? Its items move up to the parent category.`
              : `Delete “${c.name}”? Its tasks keep their data, just without a category; its subcategories become categories.`) && actions.deleteCategory(c.id)}>🗑</button>
          </div>
        ))}
        <label className="row" style={{ marginTop: 10, gap: 8, cursor: "pointer" }}>
          <input type="checkbox" checked={!!s.categoryColors} onChange={(e) => set((x) => { x.categoryColors = e.target.checked; })} />
          <span><b>To-dos use their category's colour</b><div className="small muted">Schedule, planner, Today, Tasks, the calendar, reports and Friends show a to-do in its category's colour. Classes keep their own colour.</div></span>
        </label>
      </div>

      <div className="card"><h3><span className="t2-ico">💾</span>Data</h3>
        <div className="small muted" style={{ marginBottom: 10 }}>Your data is stored on this computer. Export a backup to keep it safe or move it to another PC.</div>
        <div className="row"><button className="btn" onClick={exportData}>Export backup…</button>
          <label className="btn">Import backup…<input type="file" accept="application/json" hidden onChange={(e) => e.target.files?.[0] && importData(e.target.files[0])} /></label></div>
      </div>
    </div>
  );
}
