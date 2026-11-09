import { useEffect, useRef, useState } from "react";
import { dayKey, addDays } from "../lib/dates";
import { SECTION_DAYS, shortName } from "../lib/leitner";
import { LeitnerBox } from "../lib/model";
import { useStore } from "../lib/store";

const SECTION_COLORS = ["#EF4444", "#F97316", "#EAB308", "#22C55E", "#0EA5E9", "#14B8A6"];
const today = () => dayKey(new Date());
const sBoxOf = (w: { sBox?: number }) => w.sBox ?? 1;
const sDue = (w: { sBox?: number; sDue?: string }) => sBoxOf(w) < 6 && (!w.sDue || w.sDue <= today());

interface Result { word: string; typed: string; ok: boolean }

function say(word: string, rate: number): Promise<void> {
  return new Promise((res) => {
    try {
      const u = new SpeechSynthesisUtterance(word); u.lang = "en-US"; u.rate = rate; u.onend = () => res(); u.onerror = () => res();
      speechSynthesis.cancel(); speechSynthesis.speak(u);
    } catch { res(); }
  });
}

/** Spelling practice by ear. The browser's own speech voice reads each word; only the wait between words runs a timer. */
export default function Spelling() {
  const { data, update } = useStore();
  const boxes = data.leitner ?? [];
  const [picked, setPicked] = useState(() => localStorage.getItem("spell.box") ?? "");
  const box = boxes.find((b) => b.id === picked) ?? boxes[0];
  if (!box) return <div className="page" style={{ textAlign: "center", paddingTop: 80 }}><div style={{ fontSize: 46 }}>👂</div><h2>No Leitner box yet</h2>
    <div className="muted">Make a box in Leitner Box and add words. Then come back to practise their spelling.</div></div>;
  return (
    <div className="page" style={{ maxWidth: 900 }}>
      <div className="muted" style={{ fontWeight: 600, marginBottom: 8 }}>Practise the spelling of</div>
      <div className="row" style={{ gap: 10, flexWrap: "wrap", marginBottom: 16 }}>
        {boxes.map((b) => {
          const on = b.id === box.id, due = b.words.filter(sDue).length;
          return <button key={b.id} onClick={() => { setPicked(b.id); localStorage.setItem("spell.box", b.id); }}
            style={{ border: "none", cursor: "pointer", font: "inherit", fontWeight: 600, padding: "10px 16px", borderRadius: 99, color: on ? "#fff" : "inherit",
              background: on ? "linear-gradient(135deg,#0891B2,#4F46E5)" : "var(--card2)" }}>
            {shortName(b.name)} {due > 0 && <span style={{ marginLeft: 6, fontSize: 11, fontWeight: 800, padding: "1px 7px", borderRadius: 99, background: on ? "rgba(255,255,255,.3)" : "#fff", color: on ? "#fff" : "#0891B2" }}>{due}</span>}</button>;
        })}
      </div>
      <Practice key={box.id} box={box} update={update} />
    </div>
  );
}

function Practice({ box, update }: { box: LeitnerBox; update: (fn: (d: import("../lib/model").AppData) => void) => void }) {
  const [filter, setFilter] = useState<"due" | "all">("due");
  const [gap, setGap] = useState(() => Number(localStorage.getItem("spell.gap") ?? 3));
  const [rate, setRate] = useState(() => Number(localStorage.getItem("spell.rate") ?? 0.9));
  const [twice, setTwice] = useState(() => localStorage.getItem("spell.twice") === "1");
  const [shuffle, setShuffle] = useState(() => localStorage.getItem("spell.shuffle") !== "0");
  const [phase, setPhase] = useState<"idle" | "running" | "finished">("idle");
  const [queue, setQueue] = useState<string[]>([]);
  const [index, setIndex] = useState(0);
  const [typed, setTyped] = useState("");
  const [progress, setProgress] = useState(0);
  const [results, setResults] = useState<Result[]>([]);
  const [last, setLast] = useState<Result | null>(null);
  const typedRef = useRef(""); typedRef.current = typed;
  const skip = useRef(false), stop = useRef(false);
  const cards = box.words.filter((w) => (filter === "all" ? true : sDue(w)));
  const save = (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* blocked */ } };

  useEffect(() => () => { stop.current = true; try { speechSynthesis.cancel(); } catch { /* none */ } }, []);

  const mark = (id: string, ok: boolean) => update((d) => {
    const b = d.leitner?.find((x) => x.id === box.id); if (!b) return;
    b.words = b.words.map((w) => {
      if (w.id !== id) return w;
      const nb = ok ? Math.min(6, sBoxOf(w) + 1) : 1;
      return { ...w, sBox: nb, sDue: nb >= 6 ? w.sDue : dayKey(addDays(new Date(), ok ? SECTION_DAYS[nb - 1] : 1)) };
    });
  });

  const run = async (ids: string[]) => {
    stop.current = false; skip.current = false;
    const order = shuffle ? [...ids].sort(() => Math.random() - 0.5) : ids;
    setQueue(order); setResults([]); setLast(null); setPhase("running");
    const out: Result[] = [];
    for (let i = 0; i < order.length; i++) {
      if (stop.current) return;
      const w = box.words.find((x) => x.id === order[i]); if (!w) continue;
      setIndex(i); setTyped(""); setProgress(0); skip.current = false;
      await say(w.term, rate);
      if (twice && !stop.current) { await new Promise((r) => setTimeout(r, 700)); await say(w.term, rate); }
      let t = 0;
      while (t < gap && !skip.current && !stop.current) { await new Promise((r) => setTimeout(r, 100)); t += 0.1; setProgress(Math.min(1, t / gap)); }
      if (stop.current) return;
      const typedNow = typedRef.current.trim(), ok = typedNow.toLowerCase() === w.term.toLowerCase();
      const r = { word: w.term, typed: typedNow, ok }; out.push(r); setResults([...out]); setLast(r); mark(w.id, ok);
    }
    setPhase("finished");
  };
  const start = (list = cards) => { if (list.length) void run(list.map((w) => w.id)); };
  const word = phase === "running" ? box.words.find((w) => w.id === queue[index]) : undefined;
  const counts = [1, 2, 3, 4, 5, 6].map((s) => ({ s, n: box.words.filter((w) => sBoxOf(w) === s).length, due: box.words.filter((w) => sBoxOf(w) === s && sDue(w)).length }));

  return (
    <div className="card">
      <div className="row" style={{ gap: 12 }}><span style={{ fontSize: 28 }}>👂</span>
        <div><div style={{ fontSize: 22, fontWeight: 800 }}>Spelling</div><div className="small muted">Listen, then type the word. Words you spell right move to the next spelling section.</div></div></div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 8, margin: "14px 0" }}>
        {counts.map(({ s, n, due }) => <div key={s} style={{ borderRadius: 12, padding: "8px 4px", textAlign: "center", background: "var(--card2)", borderTop: `4px solid ${SECTION_COLORS[s - 1]}` }}>
          <div className="small muted">{s === 6 ? "Spelled" : `Spelling ${s}`}</div><div style={{ fontSize: 20, fontWeight: 800 }}>{n}</div>
          <div style={{ fontSize: 10 }}>{due > 0 ? `${due} due` : " "}</div></div>)}
      </div>

      {phase === "idle" && <>
        <div className="row" style={{ gap: 10, flexWrap: "wrap" }}>
          <div className="seg">{(["due", "all"] as const).map((f) => <button key={f} className={filter === f ? "on" : ""} onClick={() => setFilter(f)}>{f === "due" ? "Due" : "All words"}</button>)}</div>
          <span className="muted">{cards.length} word{cards.length === 1 ? "" : "s"}</span>
        </div>
        <div className="row" style={{ gap: 18, flexWrap: "wrap", margin: "12px 0" }}>
          <label>Wait between words: {gap} s <input type="range" min={1} max={30} value={gap} onChange={(e) => { setGap(+e.target.value); save("spell.gap", e.target.value); }} /></label>
          <label>Speed <input type="range" min={0.5} max={1.4} step={0.05} value={rate} onChange={(e) => { setRate(+e.target.value); save("spell.rate", e.target.value); }} style={{ width: 120 }} /></label>
          <label><input type="checkbox" checked={twice} onChange={(e) => { setTwice(e.target.checked); save("spell.twice", e.target.checked ? "1" : "0"); }} /> Say each word twice</label>
          <label><input type="checkbox" checked={shuffle} onChange={(e) => { setShuffle(e.target.checked); save("spell.shuffle", e.target.checked ? "1" : "0"); }} /> Mix the order</label>
        </div>
        <button className="btn" disabled={!cards.length} onClick={() => start()}>{cards.length ? "▶ Start" : "Nothing due 🎉"}</button>
      </>}

      {phase === "running" && word && (
        <div style={{ textAlign: "center", padding: "10px 0" }}>
          <div style={{ fontWeight: 700 }}>Word {index + 1} of {queue.length}</div>
          <div style={{ fontSize: 46, margin: "12px 0" }}>🔊</div>
          <input autoFocus value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="Type what you hear"
            onKeyDown={(e) => { if (e.key === "Enter") skip.current = true; }} autoCapitalize="off" autoCorrect="off" spellCheck={false}
            style={{ width: "100%", maxWidth: 520, fontSize: 24, padding: "10px 16px", textAlign: "center", borderRadius: 16 }} />
          <div style={{ maxWidth: 520, margin: "10px auto", height: 6, borderRadius: 3, background: "rgba(128,128,128,.2)" }}>
            <div style={{ height: "100%", borderRadius: 3, width: `${(1 - progress) * 100}%`, background: progress > 0.75 ? "#F97316" : "#06B6D4" }} /></div>
          <div className="row" style={{ justifyContent: "center", gap: 10 }}>
            <button className="btn" onClick={() => void say(word.term, rate)}>↺ Hear again</button>
            <button className="btn" onClick={() => { skip.current = true; }}>Next word ⏎</button>
            <button className="btn" onClick={() => { stop.current = true; try { speechSynthesis.cancel(); } catch { /* none */ } setPhase("idle"); }}>Stop</button>
          </div>
          {last && <div style={{ marginTop: 12, fontWeight: 600 }}>{last.ok ? "✅" : "❌"} {last.ok ? last.word : `${last.typed || "(nothing)"} → ${last.word}`} <span className="small muted">previous word</span></div>}
        </div>
      )}

      {phase === "finished" && (() => {
        const right = results.filter((r) => r.ok).length, wrong = results.filter((r) => !r.ok);
        return <div>
          <div className="row" style={{ gap: 14 }}><span style={{ fontSize: 40 }}>{right === results.length && results.length > 0 ? "🎉" : "📝"}</span>
            <div><b style={{ fontSize: 18 }}>{right} of {results.length} spelled right</b><div className="muted">{wrong.length ? "The words you missed go back to Spelling 1." : "Perfect round!"}</div></div></div>
          {results.map((r, i) => <div key={i} className="list-row" style={{ background: r.ok ? "rgba(34,197,94,.1)" : "rgba(239,68,68,.1)", borderRadius: 10, margin: "4px 0" }}>
            {r.ok ? "✅" : "❌"} <b>{r.word}</b> {!r.ok && <span style={{ color: "#EF4444" }}>you wrote: {r.typed || "nothing"}</span>}</div>)}
          <div className="row" style={{ marginTop: 12, gap: 8 }}>
            {wrong.length > 0 && <button className="btn" onClick={() => { const ids = new Set(wrong.map((r) => r.word.toLowerCase())); start(box.words.filter((w) => ids.has(w.term.toLowerCase()))); }}>Practise the {wrong.length} missed again</button>}
            <button className="btn" onClick={() => setPhase("idle")}>Done</button></div>
        </div>;
      })()}
    </div>
  );
}
