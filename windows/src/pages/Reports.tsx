import { useState } from "react";
import { addDays, dayNum, duration, monthDay, monthDays, monthName, shiftMonth, shortDuration, startOfDay, WEEKDAYS_SHORT, weekdayIndex, weekStart, yearNum } from "../lib/dates";
import { categoryLabel, categoryOf, scheduleRows, sessionsIn, subjectOf, titleOf, todosOn, useStore } from "../lib/store";
import { AppData, StudySession } from "../lib/model";

type Total = { name: string; color: string; secs: number };
const sum = (ss: StudySession[]) => ss.reduce((a, s) => a + s.duration, 0);
function totals(ss: StudySession[], key: (s: StudySession) => { name: string; color: string }): Total[] {
  const m = new Map<string, Total>();
  for (const s of ss) { const k = key(s); const t = m.get(k.name) ?? { ...k, secs: 0 }; t.secs += s.duration; m.set(k.name, t); }
  return [...m.values()].sort((a, b) => b.secs - a.secs);
}
/** What was worked on, for the "most time spent on" list */
const itemTitle = (d: AppData, s: StudySession) => {
  const e = s.scheduleEntryID && d.schedule.find((x) => x.id === s.scheduleEntryID);
  if (e) return titleOf(e);
  const t = s.taskID && d.tasks.find((x) => x.id === s.taskID);
  return t ? t.title : subjectOf(d, s).name;
};

export default function Reports() {
  const { data } = useStore();
  const kind = data.settings.primaryCalendar, other = kind === "persian" ? "gregorian" : "persian";
  const [period, setPeriod] = useState<"week" | "month">("week");
  const [anchor, setAnchor] = useState(new Date());
  const accent = data.settings.accent;
  // Charts show each subcategory on its own (default), or roll subcategories up into their main category
  const [mainOnly, setMainOnlyRaw] = useState(() => localStorage.getItem("reports-main-only") === "1");
  const setMainOnly = (v: boolean) => { setMainOnlyRaw(v); localStorage.setItem("reports-main-only", v ? "1" : "0"); };
  const hasSub = data.categories.some((c) => c.parentID && categoryOf(data, c.parentID));
  const mainOf = (s: StudySession) => { const c = categoryOf(data, s.categoryID); return c ? categoryOf(data, c.parentID) ?? c : undefined; };

  const days = period === "week" ? Array.from({ length: 7 }, (_, i) => addDays(weekStart(anchor), i)) : monthDays(anchor, kind);
  const from = days[0], to = addDays(days[days.length - 1], 1), now = new Date();
  const prevFrom = period === "week" ? addDays(from, -7) : shiftMonth(from, kind, -1);
  const sessions = sessionsIn(data, from, to);
  const total = sum(sessions), prevTotal = sum(sessionsIn(data, prevFrom, from));
  const past = days.filter((d) => d <= now), elapsed = Math.max(1, past.length);
  const goal = data.settings.dailyGoalMinutes * 60;

  // The daily chart's colours: with "to-dos use their category's colour" on, several subjects share a colour,
  // so the chart groups by category (one colour = one legend entry); otherwise by subject
  const group = (s: StudySession) => {
    const top = mainOnly ? mainOf(s) : undefined;
    if (top) return { name: top.name, color: top.colorHex };
    const c = categoryOf(data, s.categoryID);
    return data.settings.categoryColors && c ? { name: categoryLabel(data, c.id) ?? c.name, color: c.colorHex } : subjectOf(data, s);
  };
  const perDay = days.map((d) => { const ss = sessionsIn(data, startOfDay(d), addDays(startOfDay(d), 1)); return { d, total: sum(ss), by: totals(ss, group) }; });
  const groups = totals(sessions, group), subjects = totals(sessions, (s) => { const top = mainOnly ? mainOf(s) : undefined; return top ? { name: top.name, color: top.colorHex } : subjectOf(data, s); });
  const items = totals(sessions, (s) => ({ name: itemTitle(data, s), color: subjectOf(data, s).color }));
  const best = perDay.reduce((a, b) => (b.total > a.total ? b : a), perDay[0]);
  const active = perDay.filter((p) => p.total > 0).length;
  const max = Math.max(1, goal, ...perDay.map((p) => p.total));
  const completed = data.tasks.filter((t) => t.completedAt && new Date(t.completedAt) >= from && new Date(t.completedAt) < to);
  let sDone = 0, sTotal = 0;
  past.forEach((d) => { const r = scheduleRows(data, d, ["todo"]); sTotal += r.length; sDone += r.filter((x) => x.isDone).length; });
  const undone = past.flatMap((d) => todosOn(data, d).filter((t) => !t.isDone).map((t) => ({ ...t, day: d })));
  const skipped = undone.filter((u) => u.isSkipped).length;
  const pct = prevTotal > 0 ? Math.round(((total - prevTotal) / prevTotal) * 100) : null;
  const target = goal * days.length;
  const hours = Array.from({ length: 24 }, () => 0);
  for (const s of sessions) {
    // spread each session over the hours it covers
    let t = new Date(s.start).getTime(); const end = t + s.duration * 1000;
    while (t < end) { const d = new Date(t), next = new Date(d); next.setMinutes(60, 0, 0); const stop = Math.min(end, next.getTime()); hours[d.getHours()] += (stop - t) / 60000; t = stop; }
  }
  const hourMax = Math.max(1, ...hours);
  const title = (k: typeof kind) => period === "month" && k === kind ? `${monthName(from, k)} ${yearNum(from, k)}`
    : `${monthDay(from, k)} – ${monthDay(days[days.length - 1], k)}, ${yearNum(days[days.length - 1], k)}`;
  const label = (d: Date) => (period === "week" ? `${WEEKDAYS_SHORT[weekdayIndex(d)]} ${dayNum(d, kind)}` : String(dayNum(d, kind)));
  const shift = (n: number) => setAnchor(period === "week" ? addDays(anchor, 7 * n) : shiftMonth(anchor, kind, n));

  // trend line of daily totals
  const tMax = Math.max(1, ...perDay.map((p) => p.total)), TW = 260, TH = 100;
  const pts = perDay.map((p, i) => [(i / Math.max(1, perDay.length - 1)) * TW, TH - 6 - (p.total / tMax) * (TH - 16)] as const);
  const line = pts.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join(" ");

  // donut
  let acc = 0;
  const arcs = subjects.map((v) => { const a0 = (acc / Math.max(total, 1)) * Math.PI * 2; acc += v.secs; const a1 = (acc / Math.max(total, 1)) * Math.PI * 2; return { ...v, a0, a1 }; });
  const arc = (a0: number, a1: number) => {
    const r = 80, ri = 52, p = (a: number, rr: number) => `${100 + Math.sin(a) * rr} ${100 - Math.cos(a) * rr}`;
    const large = a1 - a0 > Math.PI ? 1 : 0;
    return `M ${p(a0, r)} A ${r} ${r} 0 ${large} 1 ${p(a1 - 0.0001, r)} L ${p(a1 - 0.0001, ri)} A ${ri} ${ri} 0 ${large} 0 ${p(a0, ri)} Z`;
  };

  return (
    <div className="page">
      {/* hero */}
      <div className="row" style={{ gap: 24, padding: 22, borderRadius: 22, color: "white", position: "relative", overflow: "hidden", flexWrap: "wrap",
        background: `linear-gradient(135deg, ${accent}, #6D28D9, #1E1B4B)`, boxShadow: `0 8px 18px ${accent}59` }}>
        <div style={{ position: "absolute", width: 220, height: 220, borderRadius: "50%", background: "rgba(255,255,255,.08)", right: -60, top: -90 }} />
        <div style={{ flex: 1, minWidth: 280, display: "flex", flexDirection: "column", gap: 10, position: "relative" }}>
          <div className="row" style={{ gap: 10 }}>
            <div className="seg" style={{ background: "rgba(255,255,255,.15)", borderColor: "transparent" }}>{(["week", "month"] as const).map((p) => <button key={p} className={period === p ? "on" : ""} style={{ color: "white" }} onClick={() => setPeriod(p)}>{p === "week" ? "Weekly" : "Monthly"}</button>)}</div>
            <div className="seg" style={{ background: "rgba(255,255,255,.15)", borderColor: "transparent" }}>
              <button style={{ color: "white" }} title={`Previous ${period}`} onClick={() => shift(-1)}>‹</button><button style={{ color: "white" }} onClick={() => setAnchor(new Date())}>Now</button><button style={{ color: "white" }} title={`Next ${period}`} onClick={() => shift(1)}>›</button></div>
          </div>
          <div><div style={{ fontSize: 20, fontWeight: 700 }}>{title(kind)}</div><div style={{ opacity: 0.75 }}>{title(other)}</div></div>
          <div className="row" style={{ alignItems: "baseline", gap: 10 }}><span style={{ fontSize: 46, fontWeight: 900 }}>{duration(total)}</span><span style={{ fontSize: 18, opacity: 0.75 }}>studied</span></div>
          <span style={{ alignSelf: "flex-start", padding: "4px 10px", borderRadius: 99, background: "rgba(255,255,255,.18)", fontWeight: 600 }}>
            {pct === null ? (total ? `✨ Nothing logged last ${period}` : "✨ Nothing logged yet") : pct === 0 ? `Same as last ${period}` : `${pct > 0 ? "↗" : "↘"} ${Math.abs(pct)}% ${pct > 0 ? "more" : "less"} than last ${period}`}</span>
        </div>
        <svg width={TW} height={TH} style={{ position: "relative" }}>
          <defs><linearGradient id="trend" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor="white" stopOpacity=".45" /><stop offset="1" stopColor="white" stopOpacity=".02" /></linearGradient></defs>
          <path d={`${line} L${TW},${TH} L0,${TH} Z`} fill="url(#trend)" /><path d={line} fill="none" stroke="white" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <div style={{ width: 112, height: 112, position: "relative" }}>
          <svg width={112} height={112} style={{ transform: "rotate(-90deg)" }}>
            <circle cx={56} cy={56} r={48} fill="none" stroke="rgba(255,255,255,.18)" strokeWidth={12} />
            <circle cx={56} cy={56} r={48} fill="none" stroke="white" strokeWidth={12} strokeLinecap="round"
              strokeDasharray={`${2 * Math.PI * 48 * (target > 0 ? Math.min(1, total / target) : 0)} 999`} /></svg>
          <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", textAlign: "center" }}>
            <div><div style={{ fontSize: 20, fontWeight: 900 }}>{target > 0 ? `${Math.round((total / target) * 100)}%` : "—"}</div><div style={{ fontSize: 10, opacity: 0.8 }}>of {shortDuration(target)} goal</div></div></div>
        </div>
      </div>

      {hasSub && (
        <div className="card row" style={{ gap: 12, flexWrap: "wrap" }}>
          <b>📚 Categories in the charts</b>
          <div className="seg"><button className={!mainOnly ? "on" : ""} onClick={() => setMainOnly(false)}>Each subcategory</button><button className={mainOnly ? "on" : ""} onClick={() => setMainOnly(true)}>Main categories only</button></div>
          <span className="small muted">{mainOnly ? "Subcategories are added up under their main category." : "IELTS › Speaking and IELTS › Writing show separately."}</span>
        </div>
      )}

      {/* insights */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 14 }}>
        <Tile icon="📈" tint="#A855F7" title="Daily average" value={duration(total / elapsed)} caption={goal > 0 ? `per day so far · daily goal ${shortDuration(goal)}` : "per day so far"}>
          <Meter v={goal > 0 ? total / elapsed / goal : 0} tint="#A855F7" /></Tile>
        <Tile icon="🔥" tint="#F97316" title="Active days" value={`${active} / ${days.length}`} caption={active === past.length && active > 0 ? "every day so far 🔥" : "days with study"}>
          <div style={{ display: "flex", gap: 3, flexWrap: "wrap" }}>{perDay.map((p) => <span key={p.d.toDateString()} style={{ width: period === "week" ? 18 : 7, height: 7, borderRadius: 4, background: p.total > 0 ? "#F97316" : "color-mix(in srgb, var(--text) 10%, transparent)" }} />)}</div></Tile>
        <Tile icon="🏆" tint="#EAB308" title="Best day" value={best?.total ? duration(best.total) : "—"} caption={best?.total ? `${monthDay(best.d, kind)}${goal > 0 && best.total >= goal ? " · goal reached ✓" : ""}` : "no study yet"}>
          <Meter v={best?.total && goal > 0 ? best.total / goal : 0} tint="#EAB308" /></Tile>
        <Tile icon="✅" tint="#22C55E" title="Schedule to-dos" value={sTotal ? `${sDone} / ${sTotal}` : "—"} caption={`ticked off so far${completed.length ? ` · +${completed.length} task${completed.length === 1 ? "" : "s"} done` : ""}`}>
          <Meter v={sTotal ? sDone / sTotal : 0} tint="#22C55E" /></Tile>
      </div>

      {/* daily chart */}
      <Card title="Daily study time" icon="📊" tint={accent}>
        {!total ? <Empty /> : <>
          <div style={{ position: "relative", display: "flex", alignItems: "flex-end", gap: period === "week" ? 18 : 4, height: 250, padding: "18px 4px 0" }}>
            {goal > 0 && <div style={{ position: "absolute", left: 0, right: 0, bottom: `calc(${(goal / max) * 85}% * 232 / 250 + 18px)`, borderTop: "1.2px dashed var(--muted)", opacity: 0.6, pointerEvents: "none" }}>
              <span className="small muted" style={{ position: "absolute", right: 0, top: -16 }}>goal {shortDuration(goal)}</span></div>}
            {perDay.map((p) => {
              const today = startOfDay(p.d).getTime() === startOfDay(now).getTime();
              return (
                <div key={p.d.toDateString()} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 4, height: "100%", justifyContent: "flex-end", borderRadius: 8,
                  background: today ? `${accent}14` : undefined }} title={`${duration(p.total)}${p.by.length ? "\n" + p.by.map((b) => `${b.name} ${duration(b.secs)}`).join("\n") : ""}`}>
                  {today && <div style={{ fontSize: 9, fontWeight: 900, letterSpacing: 1, color: accent }}>TODAY</div>}
                  <div className="small muted">{p.total && period === "week" ? shortDuration(p.total) : ""}</div>
                  <div style={{ width: "100%", maxWidth: 70, display: "flex", flexDirection: "column-reverse", height: `${(p.total / max) * 85}%`, borderRadius: 5, overflow: "hidden" }}>
                    {p.by.map((v) => <div key={v.name} style={{ background: v.color, height: `${(v.secs / Math.max(1, p.total)) * 100}%` }} />)}
                  </div>
                  <div className="small muted" style={{ whiteSpace: "nowrap" }}>{label(p.d)}</div>
                </div>
              );
            })}
          </div>
          <div className="row small" style={{ flexWrap: "wrap", gap: 12, marginTop: 10 }}>{groups.map((g) => <span key={g.name} className="row" style={{ gap: 5 }}><span className="dot" style={{ background: g.color }} />{g.name}</span>)}</div>
        </>}
      </Card>

      <div className="grid2" style={{ alignItems: "start" }}>
        <Card title="Study rhythm" icon="▦" tint={accent}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 5 }}>
            {period === "month" && Array.from({ length: weekdayIndex(days[0]) }, (_, i) => <span key={`pad${i}`} />)}
            {perDay.map((p) => {
              const k = goal > 0 ? Math.min(1, p.total / goal) : p.total / tMax;
              return <div key={p.d.toDateString()} title={`${monthDay(p.d, kind)} · ${p.total ? duration(p.total) : "no study"}`}
                style={{ aspectRatio: "1", borderRadius: 7, display: "grid", placeItems: "center", fontSize: 11, fontWeight: 600,
                  background: p.total ? `color-mix(in srgb, ${accent} ${Math.round(20 + 80 * k)}%, transparent)` : "color-mix(in srgb, var(--text) 5%, transparent)",
                  color: k > 0.5 ? "white" : undefined, opacity: p.d > now ? 0.4 : 1 }}>{dayNum(p.d, kind)}</div>;
            })}
          </div>
          <div className="small muted" style={{ marginTop: 8 }}>{goal > 0 ? "Darker = closer to your daily goal." : "Darker = more study."}</div>
        </Card>
        <Card title="When you study · minutes per hour of the day" icon="🕐" tint="#14B8A6">
          {!total ? <Empty /> : <>
            <div style={{ display: "flex", alignItems: "flex-end", gap: 2, height: 140 }}>
              {hours.map((m, h) => <div key={h} title={`${h}:00 · ${Math.round(m)}m`} style={{ flex: 1, height: `${(m / hourMax) * 100}%`, minHeight: m ? 2 : 0, borderRadius: 3, background: "#14B8A6", opacity: 0.35 + 0.65 * (m / hourMax) }} />)}
            </div>
            <div className="row small muted" style={{ justifyContent: "space-between", marginTop: 4 }}>{[0, 6, 12, 18, 23].map((h) => <span key={h}>{h}:00</span>)}</div>
            <div className="small muted" style={{ marginTop: 6 }}>Busiest hour: <b>{hours.indexOf(Math.max(...hours))}:00</b></div>
          </>}
        </Card>
        <Card title="Time by subject" icon="🥧" tint="#EC4899">
          {!subjects.length ? <Empty /> : (
            <div className="row" style={{ gap: 20, alignItems: "center", flexWrap: "wrap" }}>
              <div style={{ position: "relative", width: 170, height: 170, flexShrink: 0 }}>
                <svg width={170} height={170} viewBox="0 0 200 200">{arcs.map((a) => <path key={a.name} d={arc(a.a0, a.a1)} fill={a.color} stroke="var(--card)" strokeWidth={2} />)}</svg>
                <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", textAlign: "center" }}><div><b style={{ fontSize: 18 }}>{shortDuration(total)}</b><div className="small muted">{subjects.length} subjects</div></div></div>
              </div>
              <div style={{ flex: 1, minWidth: 200, display: "flex", flexDirection: "column", gap: 10 }}>{subjects.slice(0, 7).map((v) => <Rank key={v.name} t={v} share={v.secs / Math.max(1, total)} pct />)}</div>
            </div>
          )}
        </Card>
        <Card title="Most time spent on" icon="🔢" tint="#6366F1">
          {!items.length && <div className="muted">No sessions in this period.</div>}
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {items.slice(0, 7).map((t, i) => (
              <div key={t.name} className="row" style={{ gap: 10 }}>
                <span style={{ width: 22, height: 22, borderRadius: "50%", display: "grid", placeItems: "center", fontSize: 11, fontWeight: 900, flexShrink: 0,
                  background: i < 3 ? ["#EAB30840", "#9CA3AF40", "#F9731640"][i] : "color-mix(in srgb, var(--text) 6%, transparent)" }}>{i + 1}</span>
                <div style={{ flex: 1, minWidth: 0 }}><Rank t={t} share={t.secs / Math.max(1, items[0].secs)} /></div>
              </div>
            ))}
          </div>
        </Card>
      </div>

      <Card title={`Left undone this ${period}`} icon="⚠️" tint="#F97316">
        {!undone.length ? <div className="muted">{days[0] > now ? `This ${period} hasn't started yet.` : "Everything planned so far was done 🎉"}</div> : <>
          <div className="small muted" style={{ marginBottom: 4 }}>{undone.length - skipped} not ticked off{skipped ? `, ${skipped} skipped (won't do)` : ""} on days that have already started.</div>
          {undone.map((u) => <div key={`${u.ref.kind}:${u.ref.id}|${u.day.toDateString()}`} className="list-row">
            <span style={{ color: u.isSkipped ? "#F97316" : u.color }}>{u.isSkipped ? "⊗" : "○"}</span>
            <div style={{ flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{u.title} <span className="small muted">{u.detail}</span></div>
            {u.isSkipped && <span className="small" style={{ color: "#F97316", fontWeight: 600 }}>Skipped</span>}
            <span className="small muted">{monthDay(u.day, kind, true)}</span></div>)}
        </>}
      </Card>
      {completed.length > 0 && (
        <Card title={`Tasks completed this ${period}`} icon="✅" tint="#22C55E">
          {[...completed].sort((a, b) => a.completedAt!.localeCompare(b.completedAt!)).map((t) => {
            const c = categoryOf(data, t.categoryID);
            return <div key={t.id} className="list-row"><span style={{ color: "#22C55E" }}>✔</span><div style={{ flex: 1 }}>{t.title}
              {c && <span className="small" style={{ marginLeft: 8, padding: "1px 7px", borderRadius: 99, background: c.colorHex + "33" }}>{categoryLabel(data, c.id)}</span>}</div>
              <span className="small muted">{monthDay(new Date(t.completedAt!), kind, true)}</span></div>;
          })}
        </Card>
      )}
    </div>
  );
}

function Card({ title, icon, tint, children }: { title: string; icon: string; tint: string; children: React.ReactNode }) {
  return (
    <div className="card" style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <div className="row" style={{ gap: 8 }}><span style={{ width: 26, height: 26, borderRadius: 8, display: "grid", placeItems: "center", background: tint + "26", fontSize: 13 }}>{icon}</span><b>{title}</b></div>
      {children}
    </div>
  );
}
function Tile({ icon, tint, title, value, caption, children }: { icon: string; tint: string; title: string; value: string; caption: string; children: React.ReactNode }) {
  return (
    <div className="card" style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div className="row small muted" style={{ gap: 6 }}><span style={{ width: 24, height: 24, borderRadius: 7, display: "grid", placeItems: "center", background: tint + "26" }}>{icon}</span>{title}</div>
      <div style={{ fontSize: 24, fontWeight: 800 }}>{value}</div>
      {children}
      <div className="small muted">{caption}</div>
    </div>
  );
}
const Meter = ({ v, tint }: { v: number; tint: string }) => (
  <div style={{ height: 7, borderRadius: 99, background: "color-mix(in srgb, var(--text) 8%, transparent)", overflow: "hidden" }}>
    <div style={{ width: `${Math.min(1, Math.max(0, v)) * 100}%`, height: "100%", borderRadius: 99, background: tint }} /></div>
);
const Rank = ({ t, share, pct }: { t: Total; share: number; pct?: boolean }) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
    <div className="row small" style={{ gap: 6 }}><span className="dot" style={{ background: t.color }} />
      <span style={{ flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={t.name}>{t.name}</span>
      <b style={{ flexShrink: 0 }}>{shortDuration(t.secs)}</b>{pct && <span className="muted" style={{ width: 36, flexShrink: 0, textAlign: "right" }}>{Math.round(share * 100)}%</span>}</div>
    <Meter v={share} tint={t.color} />
  </div>
);
const Empty = () => <div className="muted" style={{ padding: 30, textAlign: "center" }}>No sessions in this period.</div>;
