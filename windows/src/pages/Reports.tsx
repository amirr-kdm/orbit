import { useState } from "react";
import { Stat } from "../components";
import { addDays, dayNum, duration, monthDay, monthDays, monthName, shiftMonth, shortDuration, startOfDay, WEEKDAYS_SHORT, weekdayIndex, weekStart, yearNum } from "../lib/dates";
import { scheduleRows, sessionsIn, subjectOf, todosOn, useStore } from "../lib/store";

export default function Reports() {
  const { data } = useStore();
  const kind = data.settings.primaryCalendar;
  const [period, setPeriod] = useState<"week" | "month">("week");
  const [anchor, setAnchor] = useState(new Date());

  const days = period === "week" ? Array.from({ length: 7 }, (_, i) => addDays(weekStart(anchor), i)) : monthDays(anchor, kind);
  const from = days[0], to = addDays(days[days.length - 1], 1);
  const prevFrom = period === "week" ? addDays(from, -7) : shiftMonth(from, kind, -1);
  const sessions = sessionsIn(data, from, to);
  const total = sessions.reduce((a, s) => a + s.duration, 0);
  const prevTotal = sessionsIn(data, prevFrom, from).reduce((a, s) => a + s.duration, 0);
  const elapsed = Math.max(1, days.filter((d) => d <= new Date()).length);

  const perDay = days.map((d) => {
    const ss = sessionsIn(data, startOfDay(d), addDays(startOfDay(d), 1));
    const by = new Map<string, { color: string; secs: number }>();
    ss.forEach((s) => { const sub = subjectOf(data, s); const c = by.get(sub.name) ?? { color: sub.color, secs: 0 }; c.secs += s.duration; by.set(sub.name, c); });
    return { d, total: ss.reduce((a, s) => a + s.duration, 0), by };
  });
  const best = perDay.reduce((a, b) => (b.total > a.total ? b : a), perDay[0]);
  const max = Math.max(1, ...perDay.map((p) => p.total));
  const subjects = new Map<string, { color: string; secs: number }>();
  sessions.forEach((s) => { const sub = subjectOf(data, s); const c = subjects.get(sub.name) ?? { color: sub.color, secs: 0 }; c.secs += s.duration; subjects.set(sub.name, c); });
  const subjList = [...subjects.entries()].sort((a, b) => b[1].secs - a[1].secs);
  const completed = data.tasks.filter((t) => t.completedAt && new Date(t.completedAt) >= from && new Date(t.completedAt) < to);
  let sDone = 0, sTotal = 0;
  days.filter((d) => d <= new Date()).forEach((d) => { const r = scheduleRows(data, d, ["todo"]); sTotal += r.length; sDone += r.filter((x) => x.isDone).length; });
  // To-dos on days that have already started which were never ticked off
  const undone = days.filter((d) => d <= new Date()).flatMap((d) => todosOn(data, d).filter((t) => !t.isDone).map((t) => ({ ...t, day: d })));
  const pct = prevTotal > 0 ? Math.round(((total - prevTotal) / prevTotal) * 100) : null;

  // donut
  let acc = 0;
  const arcs = subjList.map(([name, v]) => { const a0 = (acc / Math.max(total, 1)) * Math.PI * 2; acc += v.secs; const a1 = (acc / Math.max(total, 1)) * Math.PI * 2; return { name, color: v.color, a0, a1 }; });
  const arc = (a0: number, a1: number) => {
    const r = 80, ri = 48, p = (a: number, rr: number) => `${100 + Math.sin(a) * rr} ${100 - Math.cos(a) * rr}`;
    const large = a1 - a0 > Math.PI ? 1 : 0;
    return `M ${p(a0, r)} A ${r} ${r} 0 ${large} 1 ${p(a1 - 0.0001, r)} L ${p(a1 - 0.0001, ri)} A ${ri} ${ri} 0 ${large} 0 ${p(a0, ri)} Z`;
  };

  return (
    <div className="page">
      <div className="row">
        <div><h1 className="page-title">{period === "week" ? `${monthDay(from, kind)} – ${monthDay(days[6], kind)}, ${yearNum(days[6], kind)}` : `${monthName(from, kind)} ${yearNum(from, kind)}`}</h1></div>
        <span className="spacer" />
        <div className="seg">{(["week", "month"] as const).map((p) => <button key={p} className={period === p ? "on" : ""} onClick={() => setPeriod(p)}>{p === "week" ? "Weekly" : "Monthly"}</button>)}</div>
        <div className="seg"><button onClick={() => setAnchor(period === "week" ? addDays(anchor, -7) : shiftMonth(anchor, kind, -1))}>‹</button><button onClick={() => setAnchor(new Date())}>Now</button><button onClick={() => setAnchor(period === "week" ? addDays(anchor, 7) : shiftMonth(anchor, kind, 1))}>›</button></div>
      </div>
      <div className="grid2">
        <Stat icon="🕐" color="#3B82F6" label="Total studied" value={duration(total)} sub={pct === null ? (total ? `Nothing logged last ${period}` : "—") : `${pct >= 0 ? "↑" : "↓"} ${Math.abs(pct)}% vs last ${period}`} />
        <Stat icon="📈" color="#8B5CF6" label="Daily average" value={duration(total / elapsed)} sub={`${perDay.filter((p) => p.total > 0).length} active of ${days.length} days`} />
        <Stat icon="🏆" color="#F97316" label="Best day" value={best?.total ? duration(best.total) : "—"} sub={best?.total ? monthDay(best.d, kind) : undefined} />
        <Stat icon="✅" color="#22C55E" label="To-dos completed" value={`${sDone + completed.length}`} sub={sTotal ? `Schedule: ${sDone} of ${sTotal}` : undefined} />
      </div>
      <div className="card">
        <h3>📊 Daily study time</h3>
        {!total && <div className="muted" style={{ padding: 30, textAlign: "center" }}>No sessions in this period.</div>}
        {total > 0 && (
          <div style={{ display: "flex", alignItems: "flex-end", gap: period === "week" ? 18 : 4, height: 240, padding: "10px 4px 0" }}>
            {perDay.map((p) => (
              <div key={p.d.toDateString()} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 4, height: "100%", justifyContent: "flex-end" }} title={`${duration(p.total)}`}>
                <div className="small muted">{p.total ? shortDuration(p.total) : ""}</div>
                <div style={{ width: "100%", maxWidth: 70, display: "flex", flexDirection: "column-reverse", height: `${(p.total / max) * 85}%`, borderRadius: 6, overflow: "hidden" }}>
                  {[...p.by.entries()].map(([n, v]) => <div key={n} style={{ background: v.color, height: `${(v.secs / p.total) * 100}%` }} />)}
                </div>
                <div className="small muted">{period === "week" ? WEEKDAYS_SHORT[weekdayIndex(p.d)] : dayNum(p.d, kind)}</div>
              </div>
            ))}
          </div>
        )}
      </div>
      <div className="grid2">
        <div className="card"><h3>🥧 Time by subject</h3>
          {!subjList.length ? <div className="muted">No sessions in this period.</div> : (
            <div className="row" style={{ gap: 20 }}>
              <svg width={200} height={200}>{arcs.map((a) => <path key={a.name} d={arc(a.a0, a.a1)} fill={a.color} />)}</svg>
              <div style={{ flex: 1 }}>{subjList.map(([n, v]) => <div key={n} className="row small" style={{ padding: "3px 0" }}><span className="dot" style={{ background: v.color }} />{n}<span className="spacer" /><b>{shortDuration(v.secs)}</b><span className="muted">({Math.round((v.secs / total) * 100)}%)</span></div>)}</div>
            </div>
          )}
        </div>
        <div className="card"><h3>⚠️ Left undone this {period}</h3>
          {!undone.length ? <div className="muted">{days[0] > new Date() ? `This ${period} hasn't started yet.` : "Everything planned so far was done 🎉"}</div> : <>
            <div className="small muted" style={{ marginBottom: 4 }}>{undone.length} to-do{undone.length === 1 ? "" : "s"} planned for days that have already started weren't ticked off.</div>
            {undone.map((u) => <div key={`${u.ref.kind}:${u.ref.id}|${u.day.toDateString()}`} className="list-row"><span className="dot" style={{ background: u.color }} />
              <div style={{ flex: 1 }}>{u.title} <span className="small muted">{u.detail}</span></div><span className="small muted">{monthDay(u.day, kind, true)}</span></div>)}
          </>}
        </div>
        <div className="card"><h3>✅ Tasks completed</h3>
          {!completed.length && <div className="muted">No one-off tasks completed in this period.</div>}
          {completed.map((t) => <div key={t.id} className="list-row">✅ <div style={{ flex: 1 }}>{t.title}</div><span className="small muted">{monthDay(new Date(t.completedAt!), kind, true)}</span></div>)}
        </div>
      </div>
    </div>
  );
}
