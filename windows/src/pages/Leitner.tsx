import { useMemo, useState } from "react";
import { dayKey } from "../lib/dates";
import { dueWords, isDue, learnedCount, LEARNED, parseWords, review, SECTION_DAYS, SEP, shortName, topicOf } from "../lib/leitner";
import { LeitnerBox, uid } from "../lib/model";
import { useStore } from "../lib/store";

const SECTION_COLORS = ["#EF4444", "#F97316", "#EAB308", "#22C55E", "#0EA5E9"];
type Tab = "Review" | "Words" | "Learned";

export default function Leitner() {
  const { data, update } = useStore();
  const boxes = data.leitner ?? [];
  const goal = data.leitnerGoal ?? 20;
  const today = dayKey(new Date());
  const done = data.leitnerToday?.day === today ? data.leitnerToday.n : 0;
  const [sel, setSel] = useState<string | null>(() => localStorage.getItem("leitner.box"));
  const [tab, setTab] = useState<Tab>("Review");
  const [collapsed, setCollapsed] = useState<string[]>([]);
  const [queue, setQueue] = useState<{ boxID: string; ids: string[] } | null>(null);
  const box = boxes.find((b) => b.id === sel) ?? boxes[0];

  const mutate = (fn: (l: LeitnerBox[]) => void) => update((d) => { fn(d.leitner ?? (d.leitner = [])); });
  const pick = (id: string) => { setSel(id); localStorage.setItem("leitner.box", id); setQueue(null); };
  const addBox = (topic?: string) => {
    const name = prompt(topic ? `New box in "${topic}":` : "Name, e.g. IELTS vocabulary")?.trim(); if (!name) return;
    const b = { id: uid(), name: topic ? topic + SEP + name.replace("›", "-") : name.replace("›", "-"), words: [] };
    mutate((l) => { l.push(b); }); pick(b.id); setTab("Words");
  };
  const rename = (b: LeitnerBox) => {
    const n = prompt("Name:", shortName(b.name))?.trim(); if (!n) return;
    const t = topicOf(b.name); mutate((l) => { const x = l.find((y) => y.id === b.id); if (x) x.name = t ? t + SEP + n : n; });
  };
  const renameTopic = (t: string) => {
    const n = prompt("Topic name:", t)?.trim(); if (!n || n === t) return;
    mutate((l) => l.forEach((b) => { if (topicOf(b.name) === t) b.name = n + SEP + shortName(b.name); }));
  };
  const moveToTopic = (b: LeitnerBox) => {
    const t = prompt("Move to topic (new or existing name, empty = no topic):", topicOf(b.name) ?? "")?.trim();
    if (t === undefined) return;
    mutate((l) => { const x = l.find((y) => y.id === b.id); if (x) x.name = t ? t.replace("›", "-") + SEP + shortName(b.name) : shortName(b.name); });
  };
  const del = (b: LeitnerBox) => { if (confirm(`Delete "${shortName(b.name)}" and its ${b.words.length} words?`)) mutate((l) => { l.splice(l.findIndex((x) => x.id === b.id), 1); }); };

  const rows = useMemo(() => {
    const out: ({ box: LeitnerBox } | { topic: string; kids: LeitnerBox[] })[] = [], seen = new Set<string>();
    for (const b of boxes) {
      const t = topicOf(b.name);
      if (!t) out.push({ box: b });
      else if (!seen.has(t)) { seen.add(t); out.push({ topic: t, kids: boxes.filter((x) => topicOf(x.name) === t) }); }
    }
    return out;
  }, [boxes]);

  const totalDue = boxes.reduce((n, b) => n + dueWords(b).length, 0);
  const learnedTotal = boxes.reduce((n, b) => n + learnedCount(b), 0);
  const wordsTotal = boxes.reduce((n, b) => n + b.words.length, 0);
  const ringP = Math.min(1, done / Math.max(1, goal));

  const answer = (ok: boolean) => {
    if (!queue) return;
    const id = queue.ids[0];
    update((d) => {
      const b = d.leitner?.find((x) => x.id === queue.boxID); if (!b) return;
      b.words = b.words.map((w) => (w.id === id ? review(w, ok) : w));
      const t = d.leitnerToday?.day === today ? d.leitnerToday.n : 0; d.leitnerToday = { day: today, n: t + 1 };
    });
    setQueue(queue.ids.length > 1 ? { ...queue, ids: queue.ids.slice(1) } : null);
  };
  const startReview = (b: LeitnerBox) => { const ids = dueWords(b).map((w) => w.id); if (ids.length) { pick(b.id); setQueue({ boxID: b.id, ids }); setTab("Review"); } };
  const dailyReview = () => { const b = boxes.find((x) => dueWords(x).length); if (b) startReview(b); };

  const chip = (v: number, label: string, icon: string) => (
    <div style={{ background: "rgba(255,255,255,.17)", borderRadius: 12, padding: "7px 11px", display: "flex", gap: 7, alignItems: "center" }}>
      <span>{icon}</span><div><b style={{ fontSize: 16 }}>{v}</b><div style={{ fontSize: 10, opacity: 0.8 }}>{label}</div></div>
    </div>
  );

  const tile = (b: LeitnerBox, inTopic = false) => {
    const on = box?.id === b.id, due = dueWords(b).length;
    return (
      <button key={b.id} onClick={() => pick(b.id)} onDoubleClick={() => rename(b)}
        style={{ textAlign: "left", cursor: "pointer", color: on ? "#fff" : "inherit", font: "inherit", padding: "10px 12px", borderRadius: 14, border: "none", marginLeft: inTopic ? 14 : 0,
          background: on ? "linear-gradient(135deg,#4F46E5,#7C3AED)" : "var(--card2)", display: "block", width: inTopic ? "calc(100% - 14px)" : "100%" }}>
        <div className="row" style={{ justifyContent: "space-between" }}><b>{shortName(b.name)}</b>
          {due > 0 && <span style={{ fontSize: 10, fontWeight: 800, padding: "1px 8px", borderRadius: 99, background: on ? "rgba(255,255,255,.3)" : "#EA580C", color: "#fff" }}>{due} due</span>}</div>
        <div className="small" style={{ opacity: 0.75 }}>{b.words.length} in the box · {learnedCount(b)} learned</div>
        <div style={{ display: "flex", gap: 3, marginTop: 6 }}>{[1, 2, 3, 4, 5].map((s) => <i key={s} style={{ flex: 1, height: 4, borderRadius: 2, background: SECTION_COLORS[s - 1], opacity: b.words.some((w) => w.box === s) ? 1 : 0.25 }} />)}</div>
      </button>
    );
  };

  return (
    <div className="page" style={{ maxWidth: 1100 }}>
      <div style={{ borderRadius: 26, padding: 24, color: "#fff", display: "flex", gap: 26, alignItems: "center", flexWrap: "wrap",
        background: "linear-gradient(135deg,#4F46E5,#7C3AED,#DB2777)", boxShadow: "0 10px 22px rgba(124,58,237,.4)" }}>
        <div style={{ position: "relative", width: 122, height: 122, flexShrink: 0 }}>
          <svg width="122" height="122" viewBox="0 0 122 122"><circle cx="61" cy="61" r="54" fill="none" stroke="rgba(255,255,255,.22)" strokeWidth="11" />
            <circle cx="61" cy="61" r="54" fill="none" stroke="#fff" strokeWidth="11" strokeLinecap="round" strokeDasharray={`${ringP * 339.3} 339.3`} transform="rotate(-90 61 61)" /></svg>
          <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", textAlign: "center", lineHeight: 1 }}>
            <div><div style={{ fontSize: 36, fontWeight: 800 }}>{done}</div><div style={{ fontSize: 12, opacity: 0.8 }}>of {goal}</div></div></div>
        </div>
        <div style={{ flex: 1, minWidth: 260 }}>
          <div style={{ fontSize: 12, fontWeight: 900, letterSpacing: 2.5, opacity: 0.75 }}>LEITNER BOX</div>
          <div style={{ fontSize: 22, fontWeight: 700, margin: "6px 0 10px" }}>{done >= goal ? "Minimum reached — you're on fire 🔥" : `${goal - done} more word${goal - done === 1 ? "" : "s"} to reach today's minimum`}</div>
          <div className="row" style={{ gap: 10, flexWrap: "wrap" }}>{chip(done, "reviewed today", "✅")}{chip(totalDue, "left to review", "⏳")}{chip(learnedTotal, "learned", "🎓")}{chip(wordsTotal - learnedTotal, "in the boxes", "📚")}</div>
        </div>
        <div style={{ display: "grid", gap: 8, justifyItems: "end" }}>
          <button onClick={dailyReview} disabled={!totalDue} style={{ border: "none", borderRadius: 99, padding: "11px 18px", fontWeight: 700, background: "#fff", color: "#6D28D9", cursor: "pointer", opacity: totalDue ? 1 : 0.6 }}>⚡ Daily review</button>
          <label className="small" style={{ fontWeight: 600 }}>Minimum <input type="number" min={1} max={1000} value={goal} style={{ width: 62 }}
            onChange={(e) => update((d) => { d.leitnerGoal = Math.max(1, Math.min(1000, +e.target.value || 20)); })} />/day</label>
        </div>
      </div>

      <div style={{ display: "flex", gap: 18, marginTop: 18, alignItems: "flex-start" }}>
        <div style={{ width: 250, flexShrink: 0, display: "grid", gap: 10 }}>
          {rows.map((r) => "box" in r ? tile(r.box) : (
            <div key={r.topic} className="card" style={{ padding: 10, display: "grid", gap: 8 }}>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <button className="icon-btn" onClick={() => setCollapsed((c) => c.includes(r.topic) ? c.filter((x) => x !== r.topic) : [...c, r.topic])}>{collapsed.includes(r.topic) ? "▸" : "▾"} <b>{r.topic}</b></button>
                <span><button className="icon-btn" title="New box in this topic" onClick={() => addBox(r.topic)}>＋</button><button className="icon-btn" title="Rename topic" onClick={() => renameTopic(r.topic)}>✎</button></span>
              </div>
              {!collapsed.includes(r.topic) && r.kids.map((b) => tile(b, true))}
            </div>
          ))}
          <button onClick={() => addBox()} style={{ padding: 12, borderRadius: 16, border: "1.5px dashed var(--line)", background: "transparent", color: "var(--muted, inherit)", cursor: "pointer", font: "inherit", fontWeight: 600 }}>⊕ New box</button>
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          {!box ? (
            <div className="card" style={{ textAlign: "center", padding: 40 }}>
              <div style={{ fontSize: 40 }}>🗂</div><h2>Make your first Leitner box</h2>
              <div className="muted">A box is a list of words. Words move through 5 sections: 1, 2, 4, 8 and 16 days.</div>
            </div>
          ) : (
            <div className="card">
              <div className="row" style={{ justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
                <div><h2 style={{ margin: 0 }}>{shortName(box.name)}</h2>{topicOf(box.name) && <div className="small muted">in {topicOf(box.name)}</div>}</div>
                <div className="row" style={{ gap: 4 }}>
                  <button className="btn" onClick={() => rename(box)}>Rename</button>
                  <button className="btn" onClick={() => moveToTopic(box)}>Topic…</button>
                  <button className="btn" onClick={() => del(box)}>Delete</button>
                </div>
              </div>
              <div className="seg" style={{ margin: "12px 0" }}>
                {(["Review", "Words", "Learned"] as Tab[]).map((t) => <button key={t} className={tab === t ? "on" : ""} onClick={() => { setTab(t); setQueue(null); }}>{t}</button>)}
              </div>
              {tab === "Review" && <ReviewTab box={box} queue={queue?.boxID === box.id ? queue : null} onStart={() => startReview(box)} onAnswer={answer} onStop={() => setQueue(null)} />}
              {tab === "Words" && <WordsTab box={box} mutate={mutate} />}
              {tab === "Learned" && <LearnedTab box={box} mutate={mutate} />}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function ReviewTab({ box, queue, onStart, onAnswer, onStop }: { box: LeitnerBox; queue: { ids: string[] } | null; onStart: () => void; onAnswer: (ok: boolean) => void; onStop: () => void }) {
  const [shown, setShown] = useState(false);
  const w = queue && box.words.find((x) => x.id === queue.ids[0]);
  if (queue && w) {
    return (
      <div style={{ textAlign: "center", padding: "10px 0" }}>
        <div className="small muted">{queue.ids.length} left · section {w.box}</div>
        <div style={{ fontSize: 34, fontWeight: 800, margin: "22px 0" }}>{w.term}</div>
        {shown ? <div style={{ fontSize: 22, marginBottom: 18 }}>{w.meaning || "—"}</div> : <button className="btn" onClick={() => setShown(true)}>Show answer</button>}
        {shown && <div className="row" style={{ justifyContent: "center" }}>
          <button className="btn" onClick={() => { setShown(false); onAnswer(false); }}>❌ Didn't know</button>
          <button className="btn" onClick={() => { setShown(false); onAnswer(true); }}>✅ Knew it</button></div>}
        <div style={{ marginTop: 14 }}><button className="btn" onClick={() => { setShown(false); onStop(); }}>Stop</button></div>
      </div>
    );
  }
  const counts = [1, 2, 3, 4, 5].map((s) => ({ s, n: box.words.filter((x) => x.box === s).length, due: dueWords(box).filter((x) => x.box === s).length }));
  const due = dueWords(box).length;
  return (
    <div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 10 }}>
        {counts.map(({ s, n, due: d }) => (
          <div key={s} style={{ borderRadius: 14, padding: "10px 6px", textAlign: "center", background: "var(--card2)", borderTop: `4px solid ${SECTION_COLORS[s - 1]}` }}>
            <div className="small muted">Section {s}</div>
            <div style={{ fontSize: 24, fontWeight: 800 }}>{n}</div>
            <div className="small">{SECTION_DAYS[s - 1]} day{SECTION_DAYS[s - 1] > 1 ? "s" : ""}</div>
            {d > 0 ? <span style={{ fontSize: 10, fontWeight: 800, padding: "1px 6px", borderRadius: 99, background: SECTION_COLORS[s - 1], color: "#fff" }}>{d} due</span> : <span style={{ fontSize: 10 }}>&nbsp;</span>}
          </div>
        ))}
      </div>
      {box.words.length === 0
        ? <div style={{ textAlign: "center", padding: 24 }}><h3>No words yet</h3><div className="muted">Open the Words tab and add some.</div></div>
        : <div style={{ textAlign: "center", marginTop: 18 }}><button className="btn" disabled={!due} onClick={onStart}>{due ? `Review ${due} due word${due === 1 ? "" : "s"}` : "Nothing due today 🎉"}</button></div>}
    </div>
  );
}

function WordsTab({ box, mutate }: { box: LeitnerBox; mutate: (fn: (l: LeitnerBox[]) => void) => void }) {
  const [text, setText] = useState("");
  const add = () => { const ws = parseWords(text); if (!ws.length) return; mutate((l) => { l.find((x) => x.id === box.id)!.words.push(...ws); }); setText(""); };
  const sections = [1, 2, 3, 4, 5];
  return (
    <div>
      <textarea rows={3} placeholder={"word - meaning   (meaning is optional)\none word per line"} value={text} onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); add(); } }} style={{ width: "100%" }} />
      <div className="small muted">Enter adds · Shift+Enter new line</div>
      {sections.map((s) => {
        const list = box.words.filter((w) => w.box === s); if (!list.length) return null;
        return (
          <div key={s} style={{ marginTop: 12 }}>
            <div className="row" style={{ gap: 8 }}><i style={{ width: 10, height: 10, borderRadius: 5, background: SECTION_COLORS[s - 1] }} /><b>Section {s}</b>
              <span className="small muted">{SECTION_DAYS[s - 1]} day{SECTION_DAYS[s - 1] > 1 ? "s" : ""} · {list.length}</span></div>
            {list.map((w) => (
              <div key={w.id} className="list-row row" style={{ justifyContent: "space-between" }}>
                <span><b>{w.term}</b> <span className="muted">{w.meaning}</span></span>
                <span className="row"><span className="small muted">{isDue(w) ? "due" : w.due}</span>
                  <button className="icon-btn" onClick={() => mutate((l) => { const b = l.find((x) => x.id === box.id)!; b.words = b.words.filter((x) => x.id !== w.id); })}>✕</button></span>
              </div>
            ))}
          </div>
        );
      })}
    </div>
  );
}

function LearnedTab({ box, mutate }: { box: LeitnerBox; mutate: (fn: (l: LeitnerBox[]) => void) => void }) {
  const list = box.words.filter((w) => w.box >= LEARNED);
  if (!list.length) return <div style={{ textAlign: "center", padding: 24 }}><h3>No learned words yet</h3><div className="muted">A word is learned when you know it in section 5.</div></div>;
  return <div>{list.map((w) => (
    <div key={w.id} className="list-row row" style={{ justifyContent: "space-between" }}>
      <span>🎓 <b>{w.term}</b> <span className="muted">{w.meaning}</span></span>
      <button className="btn" onClick={() => mutate((l) => { const b = l.find((x) => x.id === box.id)!; b.words = b.words.map((x) => (x.id === w.id ? { ...x, box: 1, due: dayKey(new Date()) } : x)); })}>Back to section 1</button>
    </div>))}</div>;
}
