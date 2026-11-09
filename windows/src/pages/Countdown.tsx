import { useEffect, useState } from "react";
import { clockText, headline, parts, shown, sorted, when } from "../lib/countdown";
import { dayKey, dayNum, monthDays, monthName, shiftMonth, WEEKDAYS_SHORT, weekdayIndex, WEEKDAYS, yearNum, CalendarKind } from "../lib/dates";
import { Countdown as CD, uid } from "../lib/model";
import { useStore } from "../lib/store";

export const EMOJIS = ["🎯", "📝", "📚", "🎓", "✈️", "🏆", "🎉", "🎂", "💼", "🧪", "💻", "🎤", "🏁", "🚀", "⭐️", "❤️", "🔥", "📅", "🌙", "🏖️", "🧠", "🩺", "⚽️", "🎮", "🎬", "🎵", "🏠", "💍", "🤖", "🌍"];
export const COLORS = ["#6366F1", "#EC4899", "#F97316", "#22C55E", "#06B6D4", "#EAB308", "#EF4444", "#A855F7", "#14B8A6", "#64748B"];
const p2 = (n: number) => String(n).padStart(2, "0");

export function EmojiChoice({ value, onPick }: { value: string; onPick: (e: string) => void }) {
  const [open, setOpen] = useState(false);
  return (
    <span style={{ position: "relative" }}>
      <button className="btn" style={{ fontSize: 20, width: 48 }} title="Change the picture" onClick={() => setOpen(!open)}>{value}</button>
      {open && <div className="popover" style={{ position: "absolute", zIndex: 30, top: 38, left: 0, display: "grid", gridTemplateColumns: "repeat(6, 38px)", gap: 6, padding: 12, background: "var(--card)", border: "1px solid var(--line)", borderRadius: 12 }}>
        {EMOJIS.map((e) => <button key={e} className="btn" style={{ fontSize: 20, outline: e === value ? "2px solid var(--accent)" : undefined }} onClick={() => { onPick(e); setOpen(false); }}>{e}</button>)}
      </div>}
    </span>
  );
}
export function ColorChoice({ value, onPick }: { value: string; onPick: (c: string) => void }) {
  const [open, setOpen] = useState(false);
  return (
    <span style={{ position: "relative" }}>
      <button className="swatch on" title="Change the colour" style={{ background: value }} onClick={() => setOpen(!open)} />
      {open && <div className="popover" style={{ position: "absolute", zIndex: 30, top: 34, left: 0, width: 190, padding: 12, background: "var(--card)", border: "1px solid var(--line)", borderRadius: 12 }}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 }}>
          {COLORS.map((c) => <button key={c} className={`swatch ${c === value ? "on" : ""}`} style={{ background: c }} onClick={() => { onPick(c); setOpen(false); }} />)}
        </div>
        <label className="small" style={{ display: "block", marginTop: 10 }}>Custom colour <input type="color" value={value} onChange={(e) => onPick(e.target.value.toUpperCase())} /></label>
      </div>}
    </span>
  );
}

/** "1405/08/24 · Sunday · 01:34" */
export function dateText(d: Date, kind: CalendarKind) {
  return `${yearNum(d, kind)}/${p2(Number(monthNumOf(d, kind)))}/${p2(dayNum(d, kind))}  ·  ${WEEKDAYS[weekdayIndex(d)]}  ·  ${p2(d.getHours())}:${p2(d.getMinutes())}`;
}
const monthNumOf = (d: Date, kind: CalendarKind) => new Intl.DateTimeFormat("en-US-u-ca-" + (kind === "persian" ? "persian" : "gregory") + "-nu-latn", { month: "numeric" }).format(d);

/** A day and time picker (Persian months, weeks from Saturday) */
export function DateTimePicker({ value, onChange, kind }: { value: Date; onChange: (d: Date) => void; kind: CalendarKind }) {
  const [open, setOpen] = useState(false);
  const [shownMonth, setShown] = useState(value);
  const days = monthDays(shownMonth, kind), lead = weekdayIndex(days[0]);
  const set = (d: Date, h = value.getHours(), m = value.getMinutes()) => onChange(new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m));
  return (
    <span style={{ position: "relative" }}>
      <button className="btn" onClick={() => { setShown(value); setOpen(!open); }}>📅 {dateText(value, kind)}</button>
      {open && <div className="popover" style={{ position: "absolute", zIndex: 30, top: 38, left: 0, width: 300, padding: 16, background: "var(--card)", border: "1px solid var(--line)", borderRadius: 14 }}>
        <div className="row" style={{ justifyContent: "space-between", marginBottom: 8 }}>
          <button className="icon-btn" onClick={() => setShown(shiftMonth(shownMonth, kind, -1))}>‹</button>
          <b>{monthName(shownMonth, kind)} {yearNum(shownMonth, kind)}</b>
          <button className="icon-btn" onClick={() => setShown(shiftMonth(shownMonth, kind, 1))}>›</button>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4, textAlign: "center" }}>
          {WEEKDAYS_SHORT.map((w) => <div key={w} className="small muted">{w}</div>)}
          {Array.from({ length: lead }, (_, i) => <div key={"b" + i} />)}
          {days.map((d) => {
            const on = dayKey(d) === dayKey(value), isToday = dayKey(d) === dayKey(new Date());
            return <button key={dayKey(d)} onClick={() => set(d)} style={{ height: 30, borderRadius: 15, cursor: "pointer", font: "inherit", border: isToday && !on ? "1.5px solid var(--accent)" : "none",
              background: on ? "var(--accent)" : "transparent", color: on ? "#fff" : "inherit", fontWeight: on ? 700 : 400 }}>{dayNum(d, kind)}</button>;
          })}
        </div>
        <div className="row" style={{ marginTop: 10, gap: 6 }}>
          🕐 <select value={value.getHours()} onChange={(e) => set(value, +e.target.value)}>{Array.from({ length: 24 }, (_, h) => <option key={h} value={h}>{p2(h)}</option>)}</select> :
          <select value={value.getMinutes()} onChange={(e) => set(value, value.getHours(), +e.target.value)}>{Array.from({ length: 60 }, (_, m) => <option key={m} value={m}>{p2(m)}</option>)}</select>
          <span className="spacer" /><button className="btn small" onClick={() => { onChange(new Date()); setShown(new Date()); }}>Today</button>
          <button className="btn small" onClick={() => setOpen(false)}>Done</button>
        </div>
      </div>}
    </span>
  );
}

/** Re-render once a second while this is on screen (only the little clocks use it) */
function useTick(ms: number) { const [n, setN] = useState(new Date()); useEffect(() => { const id = setInterval(() => setN(new Date()), ms); return () => clearInterval(id); }, [ms]); return n; }

function Clock({ c }: { c: CD }) {
  const now = useTick(1000), past = parts(c, now).past;
  return (
    <div style={{ textAlign: "right", minWidth: 150 }}>
      <div style={{ fontSize: 26, fontWeight: 800, color: past ? "var(--muted, #888)" : c.colorHex }}>{headline(c, now)}</div>
      {!past && <div style={{ fontVariantNumeric: "tabular-nums", opacity: 0.7 }}>{clockText(c, now)}</div>}
    </div>
  );
}

export default function Countdown() {
  const { data, update } = useStore();
  const kind = data.settings.primaryCalendar;
  const [title, setTitle] = useState("");
  const [emoji, setEmoji] = useState("🎯");
  const [color, setColor] = useState(COLORS[0]);
  const [date, setDate] = useState(() => new Date(Date.now() + 7 * 86_400_000));
  const list = sorted(data.countdowns), pinned = shown(data);
  const edit = (id: string, fn: (c: CD) => void) => update((d) => { const c = d.countdowns?.find((x) => x.id === id); if (c) fn(c); });
  const add = () => {
    if (!title.trim()) return;
    update((d) => { (d.countdowns ?? (d.countdowns = [])).push({ id: uid(), title: title.trim(), date: date.toISOString(), emoji, colorHex: color }); });
    setTitle("");
  };
  return (
    <div className="page" style={{ maxWidth: 760, margin: "0 auto" }}>
      <div className="card">
        <h3>⏳ New event</h3>
        <div className="row" style={{ gap: 10 }}>
          <EmojiChoice value={emoji} onPick={setEmoji} /><ColorChoice value={color} onPick={setColor} />
          <input style={{ flex: 1 }} placeholder="What are you counting down to?" value={title} onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} />
        </div>
        <div className="row" style={{ marginTop: 12, gap: 10 }}>
          <span>Day and time</span><DateTimePicker value={date} onChange={setDate} kind={kind} />
          <span className="spacer" /><button className="btn" disabled={!title.trim()} onClick={add}>Add</button>
        </div>
      </div>
      <label className="row" style={{ margin: "14px 4px", gap: 10 }}>
        <input type="checkbox" checked={data.settings.countdownSidebar !== false} onChange={(e) => update((d) => { d.settings.countdownSidebar = e.target.checked; })} />
        Show the countdown at the top of the sidebar
      </label>
      {list.length === 0 && <div className="muted" style={{ textAlign: "center", padding: 30 }}>No events yet. Add an exam, a trip, a deadline…</div>}
      <div style={{ display: "grid", gap: 12 }}>
        {list.map((c) => {
          const isPinned = pinned?.id === c.id && data.countdownPinned === c.id;
          return (
            <div key={c.id} className="row" style={{ gap: 14, padding: 16, borderRadius: 16, border: `1px solid ${c.colorHex}8C`, opacity: when(c) <= new Date() ? 0.6 : 1,
              background: `linear-gradient(90deg, ${c.colorHex}66, ${c.colorHex}1A)` }}>
              <EmojiChoice value={c.emoji} onPick={(e) => edit(c.id, (x) => { x.emoji = e; })} />
              <ColorChoice value={c.colorHex} onPick={(h) => edit(c.id, (x) => { x.colorHex = h; })} />
              <div style={{ flex: 1, minWidth: 0 }}><b style={{ fontSize: 16 }}>{c.title}</b><div className="small muted">{dateText(when(c), kind)}</div></div>
              <Clock c={c} />
              <button className="icon-btn" title="Show this one in the sidebar and the island" style={{ color: isPinned ? "#F59E0B" : undefined }}
                onClick={() => update((d) => { d.countdownPinned = d.countdownPinned === c.id ? undefined : c.id; })}>{isPinned ? "📌" : "📍"}</button>
              <button className="icon-btn" title="Delete" onClick={() => update((d) => { d.countdowns = (d.countdowns ?? []).filter((x) => x.id !== c.id); if (d.countdownPinned === c.id) d.countdownPinned = undefined; })}>🗑</button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
