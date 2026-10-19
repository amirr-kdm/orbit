import { useEffect, useMemo, useRef, useState } from "react";
import { useNav } from "../App";
import { addDays, monthDay, WEEKDAYS, weekStart } from "../lib/dates";
import { AppData } from "../lib/model";
import { categoryOf, isDone, slotOf, slotTitle, titleOf, TodoRef, useStore } from "../lib/store";
import { useTimer } from "../lib/timer";

interface GNode {
  id: string; title: string; color: string; hub: boolean; schedule: boolean; done: boolean; detail: string; ref?: TodoRef;
  x: number; y: number; vx: number; vy: number; pinned: boolean;
}

const radius = (n: GNode) => (n.hub ? 16 : 7);

/** Where a weekly entry falls this week */
const occurrence = (weekday: number) => addDays(weekStart(new Date()), weekday);

function build(d: AppData, catFilter: string, showDone: boolean) {
  const hubs = new Map<string, Omit<GNode, "x" | "y" | "vx" | "vy" | "pinned">>();
  const leaves: Omit<GNode, "x" | "y" | "vx" | "vy" | "pinned">[] = [];
  const edges: [string, string][] = [];
  const hub = (cat?: string) => {
    const id = `cat:${cat ?? "none"}`;
    if (!hubs.has(id)) {
      const c = categoryOf(d, cat);
      hubs.set(id, { id, title: c?.name ?? "No category", color: c?.colorHex ?? "#8E8E93", hub: true, schedule: false, done: false, detail: "" });
    }
    return id;
  };
  const keep = (cat?: string) => !catFilter || cat === catFilter;

  for (const t of d.tasks) {
    if ((!showDone && t.isDone) || !keep(t.categoryID)) continue;
    const h = hub(t.categoryID);
    leaves.push({ id: `task:${t.id}`, title: t.title, color: categoryOf(d, t.categoryID)?.colorHex ?? "#8E8E93", hub: false, schedule: false,
      done: t.isDone, detail: `Task · ${t.dueDate ? monthDay(new Date(t.dueDate), d.settings.primaryCalendar) : "No date"}`, ref: { kind: "task", id: t.id } });
    edges.push([h, `task:${t.id}`]);
  }
  for (const e of d.schedule) {
    if (e.kind !== "todo" || !keep(e.categoryID)) continue;
    const done = isDone(d, { kind: "schedule", id: e.id }, occurrence(e.weekday));
    if (done && !showDone) continue;
    const h = hub(e.categoryID);
    const slot = slotOf(d, e.slotID);
    leaves.push({ id: `entry:${e.id}`, title: titleOf(e), color: e.colorHex ?? categoryOf(d, e.categoryID)?.colorHex ?? "#5B7CFA", hub: false,
      schedule: true, done, detail: `Weekly schedule · ${WEEKDAYS[e.weekday]} ${slot ? slotTitle(slot) : ""}`, ref: { kind: "schedule", id: e.id } });
    edges.push([h, `entry:${e.id}`]);
  }
  return { nodes: [...[...hubs.values()].sort((a, b) => a.title.localeCompare(b.title)), ...leaves], edges };
}

/** Obsidian-style graph: categories are hubs with their tasks and weekly to-dos around them */
export default function Graph({ catFilter }: { catFilter: string }) {
  const { data, actions } = useStore();
  const timer = useTimer();
  const nav = useNav();
  const [showDone, setShowDone] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const wrap = useRef<HTMLDivElement>(null);
  const sim = useRef({ nodes: [] as GNode[], links: [] as [number, number][], heat: 1 });
  const view = useRef({ scale: 1, panX: 0, panY: 0 });
  const hover = useRef<string | null>(null);
  const selRef = useRef<string | null>(null);
  selRef.current = selected;
  const [, redraw] = useState(0);

  const graph = useMemo(() => build(data, catFilter, showDone), [data, catFilter, showDone]);

  // Keep positions of nodes that already exist
  useEffect(() => {
    const old = new Map(sim.current.nodes.map((n) => [n.id, n]));
    const nodes: GNode[] = graph.nodes.map((n) => {
      const p = old.get(n.id);
      return { ...n, x: p?.x ?? (Math.random() - 0.5) * 400, y: p?.y ?? (Math.random() - 0.5) * 300, vx: 0, vy: 0, pinned: false };
    });
    const index = new Map(nodes.map((n, i) => [n.id, i]));
    sim.current.nodes = nodes;
    sim.current.links = graph.edges.flatMap(([a, b]) => (index.has(a) && index.has(b) ? [[index.get(a)!, index.get(b)!] as [number, number]] : []));
    sim.current.heat = Math.max(sim.current.heat, 0.6);
    redraw((x) => x + 1);
  }, [graph]);

  // Simulation + drawing loop
  useEffect(() => {
    let raf = 0;
    const tick = () => {
      step(sim.current);
      draw();
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  const size = () => ({ w: wrap.current?.clientWidth ?? 800, h: wrap.current?.clientHeight ?? 600 });
  const toScreen = (x: number, y: number) => { const { w, h } = size(), v = view.current; return [w / 2 + v.panX + x * v.scale, h / 2 + v.panY + y * v.scale]; };
  const toWorld = (sx: number, sy: number) => { const { w, h } = size(), v = view.current; return [(sx - w / 2 - v.panX) / v.scale, (sy - h / 2 - v.panY) / v.scale]; };
  const hit = (sx: number, sy: number) => {
    const [x, y] = toWorld(sx, sy);
    let best = -1, bd = Infinity;
    sim.current.nodes.forEach((n, i) => { const d = Math.hypot(n.x - x, n.y - y); if (d < bd) { bd = d; best = i; } });
    return best >= 0 && bd <= radius(sim.current.nodes[best]) + 6 / view.current.scale ? best : -1;
  };

  function draw() {
    const c = canvas.current;
    if (!c) return;
    const { w, h } = size();
    const dpr = window.devicePixelRatio || 1;
    if (c.width !== w * dpr || c.height !== h * dpr) { c.width = w * dpr; c.height = h * dpr; c.style.width = `${w}px`; c.style.height = `${h}px`; }
    const ctx = c.getContext("2d")!;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const css = getComputedStyle(document.documentElement);
    const text = css.getPropertyValue("--text").trim() || "#000", muted = css.getPropertyValue("--muted").trim() || "#888";
    const { nodes, links } = sim.current;
    const focus = hover.current ?? selRef.current;
    const near = new Set<string>();
    if (focus) {
      near.add(focus);
      for (const [a, b] of links) if (nodes[a].id === focus || nodes[b].id === focus) { near.add(nodes[a].id); near.add(nodes[b].id); }
    }
    const scale = view.current.scale;

    for (const [a, b] of links) {
      const A = nodes[a], B = nodes[b];
      const lit = focus && near.has(A.id) && near.has(B.id);
      const [x1, y1] = toScreen(A.x, A.y), [x2, y2] = toScreen(B.x, B.y);
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
      ctx.strokeStyle = lit ? A.color : text; ctx.globalAlpha = lit ? 0.8 : focus ? 0.06 : 0.16; ctx.lineWidth = lit ? 1.6 : 1; ctx.stroke();
    }
    ctx.globalAlpha = 1;
    for (const n of nodes) {
      const [x, y] = toScreen(n.x, n.y);
      const r = radius(n) * scale;
      const dim = focus && !near.has(n.id);
      if (n.hub) { ctx.beginPath(); ctx.arc(x, y, r * 1.5, 0, Math.PI * 2); ctx.fillStyle = n.color; ctx.globalAlpha = dim ? 0.03 : 0.14; ctx.fill(); }
      ctx.globalAlpha = dim ? 0.2 : n.done ? 0.35 : 1;
      ctx.fillStyle = n.color;
      ctx.beginPath();
      if (n.schedule) ctx.roundRect(x - r * 0.9, y - r * 0.9, r * 1.8, r * 1.8, r * 0.35); else ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
      if (n.id === selRef.current) { ctx.beginPath(); ctx.arc(x, y, r + 4, 0, Math.PI * 2); ctx.strokeStyle = text; ctx.lineWidth = 2; ctx.stroke(); }
      if (n.done) { ctx.fillStyle = "white"; ctx.font = `bold ${Math.max(7, r)}px sans-serif`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText("✓", x, y); }
      if (n.hub || scale > 1.3 || n.id === focus || (focus && near.has(n.id))) {
        ctx.font = n.hub ? "bold 13px 'Segoe UI', system-ui, sans-serif" : "11px 'Segoe UI', system-ui, sans-serif";
        ctx.textAlign = "center"; ctx.textBaseline = "top";
        ctx.fillStyle = n.hub ? text : muted; ctx.globalAlpha = dim ? 0.4 : 1;
        ctx.fillText(n.title, x, y + r + 4);
        ctx.globalAlpha = 1;
      }
    }
  }

  // Pointer: drag nodes, pan the background, click to select
  const drag = useRef<{ node: number; startX: number; startY: number; panX: number; panY: number; moved: boolean } | null>(null);
  const local = (e: React.PointerEvent | React.WheelEvent) => { const r = canvas.current!.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };

  const selNode = sim.current.nodes.find((n) => n.id === selected);
  const hubItems = selNode?.hub ? sim.current.links.filter(([a]) => sim.current.nodes[a].id === selNode.id).map(([, b]) => sim.current.nodes[b]) : [];

  return (
    <div className="row" style={{ alignItems: "stretch", gap: 14 }}>
      <div ref={wrap} className="card" style={{ flex: 1, height: "calc(100vh - 150px)", minHeight: 460, padding: 0, position: "relative", overflow: "hidden" }}>
        <canvas ref={canvas} style={{ display: "block", cursor: "grab", touchAction: "none" }}
          onPointerDown={(e) => {
            const [x, y] = local(e);
            (e.target as HTMLElement).setPointerCapture(e.pointerId);
            drag.current = { node: hit(x, y), startX: x, startY: y, panX: view.current.panX, panY: view.current.panY, moved: false };
          }}
          onPointerMove={(e) => {
            const [x, y] = local(e);
            const d = drag.current;
            if (!d) { const i = hit(x, y); hover.current = i >= 0 ? sim.current.nodes[i].id : null; return; }
            if (Math.hypot(x - d.startX, y - d.startY) > 4) d.moved = true;
            if (d.node >= 0) {
              const n = sim.current.nodes[d.node];
              [n.x, n.y] = toWorld(x, y); n.pinned = true;
              sim.current.heat = Math.max(sim.current.heat, 0.6);
            } else {
              view.current.panX = d.panX + x - d.startX; view.current.panY = d.panY + y - d.startY;
            }
          }}
          onPointerUp={(e) => {
            const d = drag.current;
            drag.current = null;
            if (!d) return;
            if (d.node >= 0) sim.current.nodes[d.node].pinned = false;
            if (!d.moved) { const [x, y] = local(e); const i = hit(x, y); setSelected(i >= 0 ? sim.current.nodes[i].id : null); }
          }}
          onPointerLeave={() => { hover.current = null; }}
          onWheel={(e) => { view.current.scale = Math.min(4, Math.max(0.25, view.current.scale * (e.deltaY < 0 ? 1.1 : 1 / 1.1))); }}
        />
        <div className="card small muted" style={{ position: "absolute", top: 12, left: 12, padding: 10, display: "flex", flexDirection: "column", gap: 6 }}>
          <span className="row" style={{ gap: 6 }}><span className="dot" style={{ width: 12, height: 12, background: "var(--muted)" }} />Category</span>
          <span className="row" style={{ gap: 6 }}><span className="dot" style={{ background: "var(--muted)", margin: "0 2px" }} />Task</span>
          <span className="row" style={{ gap: 6 }}><span className="dot" style={{ background: "var(--muted)", borderRadius: 2, margin: "0 2px" }} />Weekly to-do</span>
          <label className="row" style={{ gap: 6 }}><input type="checkbox" checked={showDone} onChange={(e) => setShowDone(e.target.checked)} />Show done</label>
        </div>
        <div className="seg" style={{ position: "absolute", right: 12, bottom: 12 }}>
          <button title="Zoom out" onClick={() => { view.current.scale = Math.max(0.25, view.current.scale / 1.25); }}>－</button>
          <button title="Re-centre" onClick={() => { view.current = { scale: 1, panX: 0, panY: 0 }; }}>◎</button>
          <button title="Zoom in" onClick={() => { view.current.scale = Math.min(4, view.current.scale * 1.25); }}>＋</button>
          <button title="Re-arrange" onClick={() => { sim.current.nodes.forEach((n) => { n.x = (Math.random() - 0.5) * 500; n.y = (Math.random() - 0.5) * 360; }); sim.current.heat = 1; }}>✨</button>
        </div>
        {!graph.nodes.length && <div className="muted" style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center" }}>Nothing to show. Add tasks or To-do cells with a category.</div>}
        <div className="small muted" style={{ position: "absolute", left: 12, bottom: 14 }}>Drag nodes · drag the background to pan · scroll to zoom · hover to highlight</div>
      </div>

      {selNode && (
        <div className="card" style={{ width: 270, display: "flex", flexDirection: "column", gap: 10, alignSelf: "flex-start" }}>
          <div className="small muted">{selNode.hub ? "Category" : selNode.schedule ? "Weekly to-do" : "Task"}</div>
          <div className="row"><span className="dot" style={{ width: 12, height: 12, background: selNode.color }} /><b style={{ fontSize: 16 }}>{selNode.title}</b></div>
          {selNode.hub ? <>
            <div className="small muted">{hubItems.length} item{hubItems.length === 1 ? "" : "s"}, {hubItems.filter((i) => i.done).length} done</div>
            {hubItems.map((i) => <button key={i.id} className="list-row" style={{ background: "none", border: "none", textAlign: "left", padding: "5px 0" }} onClick={() => setSelected(i.id)}>
              <span style={{ color: i.color }}>{i.done ? "✔" : "○"}</span><span style={{ flex: 1 }}>{i.title}</span></button>)}
          </> : selNode.ref && <>
            <div className="small muted">{selNode.detail}</div>
            <div className="row">
              <button className="btn" onClick={() => {
                const ref = selNode.ref!;
                const e = ref.kind === "schedule" ? data.schedule.find((x) => x.id === ref.id) : undefined;
                actions.toggleDone(ref, e ? occurrence(e.weekday) : new Date());
              }}>{selNode.done ? "Mark not done" : "Mark done"}</button>
              <button className="btn primary" disabled={timer.active} onClick={() => { timer.setTarget(selNode.ref!); nav.go("timer"); }}>▶ Study</button>
            </div>
          </>}
          <button className="btn small" style={{ alignSelf: "flex-start" }} onClick={() => setSelected(null)}>Close</button>
        </div>
      )}
    </div>
  );
}

/** One step of the force layout: nodes repel, links pull, everything drifts to the centre */
function step(s: { nodes: GNode[]; links: [number, number][]; heat: number }) {
  const { nodes, links } = s;
  if (s.heat < 0.01 || !nodes.length) return;
  const n = nodes.length;
  const fx = new Float64Array(n), fy = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      let dx = nodes[i].x - nodes[j].x, dy = nodes[i].y - nodes[j].y;
      let d2 = dx * dx + dy * dy;
      if (d2 < 0.01) { dx = Math.random() - 0.5; dy = Math.random() - 0.5; d2 = 1; }
      const f = (nodes[i].hub && nodes[j].hub ? 9000 : 1400) / d2, d = Math.sqrt(d2);
      fx[i] += (dx / d) * f; fy[i] += (dy / d) * f; fx[j] -= (dx / d) * f; fy[j] -= (dy / d) * f;
    }
  }
  for (const [a, b] of links) {
    const dx = nodes[b].x - nodes[a].x, dy = nodes[b].y - nodes[a].y;
    const d = Math.max(1, Math.hypot(dx, dy)), f = (d - 60) * 0.05;
    fx[a] += (dx / d) * f; fy[a] += (dy / d) * f; fx[b] -= (dx / d) * f; fy[b] -= (dy / d) * f;
  }
  for (let i = 0; i < n; i++) {
    const p = nodes[i];
    fx[i] -= p.x * 0.008; fy[i] -= p.y * 0.008;
    if (p.pinned) { p.vx = p.vy = 0; continue; }
    p.vx = (p.vx + fx[i] * s.heat) * 0.82; p.vy = (p.vy + fy[i] * s.heat) * 0.82;
    const sp = Math.hypot(p.vx, p.vy);
    if (sp > 30) { p.vx *= 30 / sp; p.vy *= 30 / sp; }
    p.x += p.vx; p.y += p.vy;
  }
  s.heat *= 0.992;
}
