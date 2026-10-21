import { useEffect, useMemo, useRef, useState } from "react";
import { frameLoop } from "../components";
import { useNav } from "../App";
import { addDays, duration, fullDate, monthDay, monthDays, shiftMonth, startOfDay, WEEKDAYS, weekStart } from "../lib/dates";
import { AppData, RECURRENCE_TITLE } from "../lib/model";
import { applies, categoryOf, isDone, isSkipped, scheduleRows, slotOf, slotTitle, titleOf, TodoRef, useStore } from "../lib/store";
import { useTimer } from "../lib/timer";

type Period = "all" | "day" | "week" | "month";

interface GInfo { id: string; title: string; color: string; hub: boolean; schedule: boolean; done: boolean; skipped: boolean; ref?: TodoRef; date?: Date }
interface GNode extends GInfo { x: number; y: number; vx: number; vy: number; pinned: boolean; degree: number; birth: number; anchor?: [number, number] }

// Shared across visits so the layout, zoom and dropped categories survive switching pages
const shared = {
  sim: { nodes: [] as GNode[], links: [] as [number, number][], alpha: 1 },
  view: { scale: 1, panX: 0, panY: 0 },
};
const load = <T,>(k: string, d: T): T => { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } };
const keep = (k: string, v: unknown) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* ignore */ } };

function range(period: Period, anchor: Date, kind: AppData["settings"]["primaryCalendar"]): Date[] | null {
  if (period === "all") return null;
  if (period === "day") return [startOfDay(anchor)];
  if (period === "week") return Array.from({ length: 7 }, (_, i) => addDays(weekStart(anchor), i));
  return monthDays(anchor, kind);
}

function build(d: AppData, catFilter: string, showDone: boolean, days: Date[] | null, period: Period) {
  const hubs = new Map<string, GInfo>();
  const leaves: GInfo[] = [];
  const edges: [string, string][] = [];
  const kind = d.settings.primaryCalendar;
  const hub = (cat?: string) => {
    const id = `cat:${cat ?? "none"}`;
    if (!hubs.has(id)) { const c = categoryOf(d, cat); hubs.set(id, { id, title: c?.name ?? "No category", color: c?.colorHex ?? "#8E8E93", hub: true, schedule: false, done: false, skipped: false }); }
    return id;
  };
  const ok = (cat?: string) => !catFilter || cat === catFilter;
  const first = days?.[0], end = days ? addDays(days[days.length - 1], 1) : undefined;

  for (const t of d.tasks) {
    if ((!showDone && (t.isDone || t.isSkipped)) || !ok(t.categoryID)) continue;
    if (days && (!t.dueDate || new Date(t.dueDate) < first! || new Date(t.dueDate) >= end!)) continue;
    const h = hub(t.categoryID);
    leaves.push({ id: `task:${t.id}`, title: t.title, color: categoryOf(d, t.categoryID)?.colorHex ?? "#8E8E93", hub: false, schedule: false,
      done: t.isDone, skipped: !!t.isSkipped, ref: { kind: "task", id: t.id }, date: t.dueDate ? new Date(t.dueDate) : undefined });
    edges.push([h, `task:${t.id}`]);
  }
  if (days) {
    for (const day of days) for (const r of scheduleRows(d, day, ["todo"])) {
      if (!ok(r.entry.categoryID) || ((r.isDone || r.isSkipped) && !showDone)) continue;
      const id = `entry:${r.entry.id}|${day.toDateString()}`;
      const multi = period !== "day";
      leaves.push({ id, title: multi ? `${titleOf(r.entry)} · ${monthDay(day, kind, true)}` : titleOf(r.entry),
        color: r.entry.colorHex ?? categoryOf(d, r.entry.categoryID)?.colorHex ?? "#5B7CFA", hub: false, schedule: true,
        done: r.isDone, skipped: !!r.isSkipped, ref: { kind: "schedule", id: r.entry.id }, date: day });
      edges.push([hub(r.entry.categoryID), id]);
    }
  } else {
    for (const e of d.schedule) {
      if (e.kind !== "todo" || !ok(e.categoryID)) continue;
      const day = addDays(weekStart(new Date()), e.weekday);
      const done = isDone(d, { kind: "schedule", id: e.id }, day), sk = isSkipped(d, { kind: "schedule", id: e.id }, day);
      if ((done || sk) && !showDone) continue;
      leaves.push({ id: `entry:${e.id}`, title: titleOf(e), color: e.colorHex ?? categoryOf(d, e.categoryID)?.colorHex ?? "#5B7CFA", hub: false, schedule: true,
        done, skipped: sk, ref: { kind: "schedule", id: e.id } });
      edges.push([hub(e.categoryID), `entry:${e.id}`]);
    }
  }
  return { nodes: [...[...hubs.values()].sort((a, b) => a.title.localeCompare(b.title)), ...leaves], edges };
}

/** Obsidian-style graph: categories are hubs with their tasks and weekly to-dos around them */
export default function Graph({ catFilter }: { catFilter: string }) {
  const { data } = useStore();
  const [showDone, setShowDone] = useState<boolean>(() => load("graph-show-done", false));
  const [period, setPeriod] = useState<Period>(() => load("graph-period", "week"));
  const [anchor, setAnchor] = useState(new Date());
  const [look, setLook] = useState<{ hub: number; leaf: number; link: number }>(() => load("graph-look", { hub: 1, leaf: 1, link: 1 }));
  const [showLook, setShowLook] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const wrap = useRef<HTMLDivElement>(null);
  const hover = useRef<string | null>(null);
  const focus = useRef({ level: 0, last: null as string | null });
  const lookRef = useRef(look); lookRef.current = look;
  const selRef = useRef(selected); selRef.current = selected;
  const kind = data.settings.primaryCalendar;
  useEffect(() => keep("graph-show-done", showDone), [showDone]);
  useEffect(() => keep("graph-period", period), [period]);
  useEffect(() => { keep("graph-look", look); shared.sim.alpha = Math.max(shared.sim.alpha, 0.5); }, [look]);

  const days = useMemo(() => range(period, anchor, kind), [period, anchor, kind]);
  const graph = useMemo(() => build(data, catFilter, showDone, days, period), [data, catFilter, showDone, days, period]);

  // Keep positions of nodes that already exist; new ones pop in near their category
  useEffect(() => {
    const s = shared.sim;
    const old = new Map(s.nodes.map((n) => [n.id, n]));
    const parent = new Map(graph.edges.map(([a, b]) => [b, a]));
    const hubs = graph.nodes.filter((n) => n.hub);
    const centers = new Map<string, [number, number]>();
    hubs.forEach((h, i) => { const o = old.get(h.id); const a = (i / Math.max(1, hubs.length)) * Math.PI * 2; centers.set(h.id, o ? [o.x, o.y] : [Math.cos(a) * 160, Math.sin(a) * 160]); });
    const now = performance.now();
    s.nodes = graph.nodes.map((n, i) => {
      const o = old.get(n.id);
      if (o) return { ...n, x: o.x, y: o.y, vx: o.vx, vy: o.vy, pinned: false, degree: 0, birth: o.birth, anchor: o.anchor };
      const [cx, cy] = n.hub ? centers.get(n.id)! : centers.get(parent.get(n.id) ?? "") ?? [0, 0];
      const a = i * Math.PI * (3 - Math.sqrt(5)), r = n.hub ? 0 : 30 + 4 * Math.sqrt(i);
      return { ...n, x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r, vx: 0, vy: 0, pinned: false, degree: 0, birth: now + (n.hub ? 0 : 150 + Math.min(1000, i * 20)) };
    });
    const index = new Map(s.nodes.map((n, i) => [n.id, i]));
    s.links = graph.edges.flatMap(([a, b]) => (index.has(a) && index.has(b) ? [[index.get(a)!, index.get(b)!] as [number, number]] : []));
    for (const [a, b] of s.links) { s.nodes[a].degree++; s.nodes[b].degree++; }
    s.alpha = Math.max(s.alpha, old.size ? 0.3 : 1);
  }, [graph]);

  const radius = (n: GNode) => (n.hub ? Math.min(30, 11 + 2.2 * Math.sqrt(n.degree)) * lookRef.current.hub : 6.2 * lookRef.current.leaf);
  const appear = (n: GNode, now: number) => {
    const t = Math.min(1, Math.max(0, (now - n.birth) / 550));
    if (t >= 1) return 1;
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * (t - 1) ** 3 + c1 * (t - 1) ** 2;
  };
  const minDist = (a: GNode, b: GNode) => {
    if (a.hub && b.hub) { const reach = (n: GNode) => radius(n) + (40 + 3 * Math.sqrt(n.degree)) * lookRef.current.link + 14 * lookRef.current.leaf; return reach(a) + reach(b) + 10; }
    return radius(a) + radius(b) + 5;
  };

  // Simulation + drawing loop
  // Once the layout has settled and nothing changes, stop redrawing (saves CPU and battery)
  const quiet = useRef({ key: "", since: 0 });
  useEffect(() => {
    quiet.current.since = performance.now();   // something re-rendered: draw for a moment
    return frameLoop((now) => {
      step();
      const { sim, view } = shared;
      const key = `${hover.current}|${selRef.current}|${view.scale}|${view.panX}|${view.panY}|${sim.nodes.length}|${innerWidth}x${innerHeight}|${lookRef.current ? JSON.stringify(lookRef.current) : ""}`;
      if (key !== quiet.current.key) { quiet.current = { key, since: now }; }
      if (sim.alpha < 0.003 && !drag.current && now - quiet.current.since > 1500) return;
      draw();
    }, 30);
  });

  function step() {
    const s = shared.sim, { nodes, links } = s, n = nodes.length;
    const target = nodes.some((x) => x.pinned) ? 0.3 : 0;
    s.alpha += (target - s.alpha) * 0.016;
    if (s.alpha < 0.003 || !n) return;
    const L = lookRef.current.link;
    for (const [a, b] of links) {
      const A = nodes[a], B = nodes[b];
      const want = (34 + 3 * Math.sqrt(A.degree)) * L + radius(A) + radius(B);
      let dx = B.x + B.vx - A.x - A.vx, dy = B.y + B.vy - A.y - A.vy;
      if (!dx && !dy) { dx = Math.random() - 0.5; dy = Math.random() - 0.5; }
      const l = Math.hypot(dx, dy), k = ((l - want) / l) * s.alpha * (0.7 / Math.max(1, Math.min(A.degree, B.degree)));
      const bias = A.degree / (A.degree + B.degree);
      B.vx -= dx * k * bias; B.vy -= dy * k * bias; A.vx += dx * k * (1 - bias); A.vy += dy * k * (1 - bias);
    }
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) {
      const A = nodes[i], B = nodes[j];
      let dx = B.x - A.x, dy = B.y - A.y, d2 = dx * dx + dy * dy;
      if (d2 > 360000) continue;
      if (d2 < 1) { dx = Math.random() - 0.5; dy = Math.random() - 0.5; d2 = 1; }
      d2 = Math.max(d2, 100);
      const si = A.hub ? -520 : -55, sj = B.hub ? -520 : -55;
      A.vx += (dx * sj * s.alpha) / d2; A.vy += (dy * sj * s.alpha) / d2; B.vx -= (dx * si * s.alpha) / d2; B.vy -= (dy * si * s.alpha) / d2;
    }
    for (const p of nodes) {
      if (p.anchor) { p.vx += (p.anchor[0] - p.x) * 0.12; p.vy += (p.anchor[1] - p.y) * 0.12; continue; }
      const k = p.hub ? 0.05 : 0.02; p.vx -= p.x * k * s.alpha; p.vy -= p.y * k * s.alpha;
    }
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) {
      const A = nodes[i], B = nodes[j], dx = B.x - A.x, dy = B.y - A.y, m = minDist(A, B), d2 = dx * dx + dy * dy;
      if (d2 >= m * m) continue;
      const d = Math.max(0.01, Math.sqrt(d2)), push = (m - d) / d;
      const wi = A.pinned ? 0 : B.pinned ? 1 : 0.5, wj = B.pinned ? 0 : A.pinned ? 1 : 0.5;
      A.x -= dx * push * wi; A.y -= dy * push * wi; B.x += dx * push * wj; B.y += dy * push * wj;
      if (A.anchor) A.anchor = [A.x, A.y]; if (B.anchor) B.anchor = [B.x, B.y];
    }
    for (const p of nodes) { if (p.pinned) { p.vx = p.vy = 0; continue; } p.vx *= 0.58; p.vy *= 0.58; p.x += p.vx; p.y += p.vy; }
  }

  const size = () => ({ w: wrap.current?.clientWidth ?? 800, h: wrap.current?.clientHeight ?? 600 });
  const toScreen = (x: number, y: number): [number, number] => { const { w, h } = size(), v = shared.view; return [w / 2 + v.panX + x * v.scale, h / 2 + v.panY + y * v.scale]; };
  const toWorld = (sx: number, sy: number): [number, number] => { const { w, h } = size(), v = shared.view; return [(sx - w / 2 - v.panX) / v.scale, (sy - h / 2 - v.panY) / v.scale]; };
  const hit = (sx: number, sy: number) => {
    const [x, y] = toWorld(sx, sy);
    let best = -1, bd = Infinity;
    shared.sim.nodes.forEach((n, i) => { const d = Math.hypot(n.x - x, n.y - y) - radius(n); if (d < bd) { bd = d; best = i; } });
    return bd <= 5 / shared.view.scale ? best : -1;
  };
  const zoom = (f: number, sx?: number, sy?: number) => {
    const { w, h } = size(), v = shared.view;
    const px = sx ?? w / 2, py = sy ?? h / 2, [wx, wy] = toWorld(px, py);
    v.scale = Math.min(5, Math.max(0.2, v.scale * f));
    v.panX = px - w / 2 - wx * v.scale; v.panY = py - h / 2 - wy * v.scale;
  };

  function draw() {
    const c = canvas.current;
    if (!c) return;
    const { w, h } = size(), dpr = window.devicePixelRatio || 1;
    if (c.width !== w * dpr || c.height !== h * dpr) { c.width = w * dpr; c.height = h * dpr; c.style.width = `${w}px`; c.style.height = `${h}px`; }
    const ctx = c.getContext("2d")!;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
    const css = getComputedStyle(document.documentElement);
    const text = css.getPropertyValue("--text").trim() || "#000", muted = css.getPropertyValue("--muted").trim() || "#888", bg = css.getPropertyValue("--card").trim() || "#222";
    const { nodes, links } = shared.sim, scale = shared.view.scale, now = performance.now();

    // dot grid
    const sp = 30 * scale;
    if (sp > 10) {
      ctx.fillStyle = text; ctx.globalAlpha = 0.07;
      const ox = (w / 2 + shared.view.panX) % sp, oy = (h / 2 + shared.view.panY) % sp;
      for (let x = ox; x < w; x += sp) for (let y = oy; y < h; y += sp) ctx.fillRect(x - 0.7, y - 0.7, 1.4, 1.4);
      ctx.globalAlpha = 1;
    }

    const f0 = hover.current ?? selRef.current;
    if (f0) focus.current.last = f0;
    focus.current.level += ((f0 ? 1 : 0) - focus.current.level) * 0.18;
    if (!f0 && focus.current.level < 0.01) focus.current.last = null;
    const f = focus.current.level, shown = f0 ?? focus.current.last;
    const near = new Set<string>();
    if (shown) { near.add(shown); for (const [a, b] of links) if (nodes[a].id === shown || nodes[b].id === shown) { near.add(nodes[a].id); near.add(nodes[b].id); } }
    const dim = (id: string) => (near.has(id) ? 1 : 1 - 0.8 * f);

    for (const [a, b] of links) {
      const A = nodes[a], B = nodes[b], g = Math.min(appear(A, now), appear(B, now));
      if (g < 0.02) continue;
      const [x1, y1] = toScreen(A.x, A.y), [x2, y2] = toScreen(B.x, B.y);
      const dx = x2 - x1, dy = y2 - y1, k = Math.min(1, g);
      const lit = !!shown && near.has(A.id) && near.has(B.id);
      const base = lit ? 0.32 + 0.45 * f : 0.3 * (1 - 0.75 * f);
      const grad = ctx.createLinearGradient(x1, y1, x2, y2); grad.addColorStop(0, A.color); grad.addColorStop(1, B.color);
      ctx.globalAlpha = base; ctx.strokeStyle = grad; ctx.lineWidth = (lit ? 1 + 0.8 * f : 1) * Math.min(1.5, Math.max(0.7, scale)); ctx.lineCap = "round";
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.quadraticCurveTo((x1 + x2) / 2 - dy * 0.08, (y1 + y2) / 2 + dx * 0.08, x1 + dx * k, y1 + dy * k); ctx.stroke();
    }
    ctx.globalAlpha = 1;

    for (const n of nodes) {
      const g = appear(n, now);
      if (g < 0.01) continue;
      const [x, y] = toScreen(n.x, n.y), r = radius(n) * scale * g, o = dim(n.id);
      const haloR = r * (n.hub ? 2.4 : 1.9) * (n.id === hover.current ? 1.25 : 1);
      const halo = ctx.createRadialGradient(x, y, r * 0.5, x, y, haloR);
      halo.addColorStop(0, n.color + (n.hub ? "52" : "2e")); halo.addColorStop(1, n.color + "00");
      ctx.globalAlpha = o; ctx.fillStyle = halo; ctx.beginPath(); ctx.arc(x, y, haloR, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2);
      if (n.done || n.skipped) {
        ctx.fillStyle = bg; ctx.fill();
        const ring = n.skipped ? "#F97316" : n.color;
        ctx.strokeStyle = ring; ctx.lineWidth = Math.max(1.2, r * 0.24); ctx.beginPath(); ctx.arc(x, y, r * 0.88, 0, Math.PI * 2); ctx.stroke();
        if (r > 5) { ctx.fillStyle = ring; ctx.font = `bold ${r * 0.9}px sans-serif`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(n.skipped ? "✕" : "✓", x, y); }
      } else {
        ctx.fillStyle = n.color; ctx.fill();
        const shine = ctx.createRadialGradient(x - r * 0.35, y - r * 0.4, 0, x - r * 0.35, y - r * 0.4, r * 1.6);
        shine.addColorStop(0, "rgba(255,255,255,0.45)"); shine.addColorStop(0.5, "rgba(255,255,255,0)"); shine.addColorStop(1, "rgba(0,0,0,0.18)");
        ctx.fillStyle = shine; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
        if (n.schedule) { ctx.strokeStyle = "rgba(255,255,255,0.8)"; ctx.lineWidth = Math.max(0.8, r * 0.16); ctx.beginPath(); ctx.arc(x, y, r * 0.42, 0, Math.PI * 2); ctx.stroke(); }
      }
      if (n.id === selRef.current) { ctx.strokeStyle = text; ctx.lineWidth = 1.6; ctx.beginPath(); ctx.arc(x, y, r + 4, 0, Math.PI * 2); ctx.stroke(); }
      if ((n.hub || scale >= 1.15 || n.id === shown || (shown && near.has(n.id) && f > 0.3)) && g > 0.6) {
        ctx.font = n.hub ? "600 12.5px 'Segoe UI', system-ui, sans-serif" : "10.5px 'Segoe UI', system-ui, sans-serif";
        ctx.textAlign = "center"; ctx.textBaseline = "top"; ctx.fillStyle = n.hub ? text : muted;
        ctx.fillText(n.title.length > 26 ? n.title.slice(0, 25) + "…" : n.title, x, y + r + (n.hub ? 7 : 5));
      }
      ctx.globalAlpha = 1;
    }
  }

  /** ✨: everything gathers in the middle, then the categories bloom out and their items pop in */
  const rearrange = () => {
    const s = shared.sim, now = performance.now();
    let leaf = 0;
    const hubs = s.nodes.filter((n) => n.hub);
    hubs.forEach((n, k) => { const a = (k / Math.max(1, hubs.length)) * Math.PI * 2; n.anchor = undefined; n.x = Math.cos(a) * 6; n.y = Math.sin(a) * 6; n.vx = Math.cos(a) * 14; n.vy = Math.sin(a) * 14; n.birth = now + k * 80; });
    for (const n of s.nodes) if (!n.hub) { const a = Math.random() * Math.PI * 2; n.x = Math.cos(a) * 3; n.y = Math.sin(a) * 3; n.vx = n.vy = 0; n.birth = now + 250 + Math.min(1400, leaf++ * 35); }
    s.alpha = 1;
  };

  const drag = useRef<{ node: number; sx: number; sy: number; px: number; py: number; moved: boolean } | null>(null);
  const local = (e: { clientX: number; clientY: number }): [number, number] => { const r = canvas.current!.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
  const shift = (k: number) => setAnchor((a) => (period === "day" ? addDays(a, k) : period === "week" ? addDays(a, 7 * k) : shiftMonth(a, kind, k)));
  const title = !days ? "Everything" : period === "day" ? fullDate(days[0], kind) : period === "month" ? `${monthDay(days[0], kind)} – ${monthDay(days[days.length - 1], kind)}` : `${monthDay(days[0], kind)} – ${monthDay(days[6], kind)}`;

  const node = graph.nodes.find((n) => n.id === selected);
  const items = node?.hub ? graph.edges.filter(([a]) => a === node.id).map(([, b]) => graph.nodes.find((n) => n.id === b)!).filter(Boolean) : [];

  return (
    <div className="row" style={{ alignItems: "stretch", gap: 14 }}>
      <div ref={wrap} className="card" style={{ flex: 1, height: "calc(100vh - 150px)", minHeight: 460, padding: 0, position: "relative", overflow: "hidden" }}>
        <canvas ref={canvas} style={{ display: "block", cursor: "grab", touchAction: "none" }}
          onPointerDown={(e) => { const [x, y] = local(e); (e.target as HTMLElement).setPointerCapture(e.pointerId); drag.current = { node: hit(x, y), sx: x, sy: y, px: shared.view.panX, py: shared.view.panY, moved: false }; }}
          onPointerMove={(e) => {
            const [x, y] = local(e), d = drag.current;
            if (!d) { const i = hit(x, y); hover.current = i >= 0 ? shared.sim.nodes[i].id : null; return; }
            if (Math.hypot(x - d.sx, y - d.sy) > 4) d.moved = true;
            if (d.node >= 0) {
              const n = shared.sim.nodes[d.node];
              let [wx, wy] = toWorld(x, y);
              if (n.hub) for (let it = 0; it < 4; it++) for (const o of shared.sim.nodes) {
                if (o === n || !o.hub) continue;
                const dx = wx - o.x, dy = wy - o.y, dist = Math.max(0.01, Math.hypot(dx, dy)), m = minDist(n, o);
                if (dist < m) { wx = o.x + (dx / dist) * m; wy = o.y + (dy / dist) * m; }
              }
              n.x = wx; n.y = wy; n.pinned = true; if (n.hub) n.anchor = [wx, wy];
              shared.sim.alpha = Math.max(shared.sim.alpha, 0.3);
            } else { shared.view.panX = d.px + x - d.sx; shared.view.panY = d.py + y - d.sy; }
          }}
          onPointerUp={(e) => {
            const d = drag.current; drag.current = null;
            if (!d) return;
            if (d.node >= 0) shared.sim.nodes[d.node].pinned = false;
            if (!d.moved) { const [x, y] = local(e); const i = hit(x, y); setSelected(i >= 0 ? shared.sim.nodes[i].id : null); }
          }}
          onPointerLeave={() => { hover.current = null; }}
          onWheel={(e) => {
            const [x, y] = local(e);
            if (e.ctrlKey) zoom(Math.exp(-e.deltaY / 100), x, y); // pinch on a touchpad
            else if (Math.abs(e.deltaX) > 0 || e.deltaMode === 0 && Math.abs(e.deltaY) < 50) { shared.view.panX -= e.deltaX; shared.view.panY -= e.deltaY; } // two-finger scroll
            else zoom(e.deltaY < 0 ? 1.1 : 1 / 1.1, x, y); // mouse wheel
          }}
        />
        <div className="card small muted" style={{ position: "absolute", top: 12, left: 12, padding: 10, display: "flex", flexDirection: "column", gap: 6 }}>
          <span className="row" style={{ gap: 6 }}><span className="dot" style={{ width: 12, height: 12, background: "var(--muted)" }} />Category</span>
          <span className="row" style={{ gap: 6 }}><span className="dot" style={{ background: "var(--muted)", margin: "0 2px" }} />Task</span>
          <span className="row" style={{ gap: 6 }}><span className="dot" style={{ background: "var(--muted)", boxShadow: "inset 0 0 0 2px var(--card)", margin: "0 2px" }} />Weekly to-do</span>
          <span className="row" style={{ gap: 6 }}><span className="dot" style={{ border: "1.5px solid var(--muted)", margin: "0 2px" }} />Done / ✕ skipped</span>
          <label className="row" style={{ gap: 6 }}><input type="checkbox" checked={showDone} onChange={(e) => setShowDone(e.target.checked)} />Show done</label>
        </div>
        <div className="row" style={{ position: "absolute", top: 12, left: "50%", transform: "translateX(-50%)", background: "var(--card)", padding: "6px 10px", borderRadius: 99, boxShadow: "var(--shadow)" }}>
          <div className="seg">{(["all", "day", "week", "month"] as Period[]).map((p) => <button key={p} className={period === p ? "on" : ""} onClick={() => setPeriod(p)}>{p[0].toUpperCase() + p.slice(1)}</button>)}</div>
          {period !== "all" && <div className="seg"><button onClick={() => shift(-1)}>‹</button><button onClick={() => setAnchor(new Date())}>Today</button><button onClick={() => shift(1)}>›</button></div>}
          <b className="small">{title}</b>
        </div>
        <div className="seg" style={{ position: "absolute", right: 12, bottom: 12 }}>
          <button title="Zoom out" onClick={() => zoom(1 / 1.25)}>－</button>
          <button title="Re-centre" onClick={() => { shared.view.scale = 1; shared.view.panX = shared.view.panY = 0; }}>◎</button>
          <button title="Zoom in" onClick={() => zoom(1.25)}>＋</button>
          <button title="Re-arrange with an animation" onClick={rearrange}>✨</button>
          <button title="Node size and link length" onClick={() => setShowLook((v) => !v)}>⚙</button>
        </div>
        {showLook && (
          <div className="popover" style={{ right: 12, bottom: 54 }}>
            <b>Graph look</b>
            {([["Category size", "hub", 0.5, 2.2], ["To-do size", "leaf", 0.5, 2.8], ["Link length", "link", 0.4, 3]] as const).map(([label, key, min, max]) => (
              <label key={key} className="small" style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                <span className="row">{label}<span className="spacer" />{Math.round(look[key] * 100)}%</span>
                <input type="range" min={min} max={max} step={0.05} value={look[key]} onChange={(e) => setLook({ ...look, [key]: +e.target.value })} />
              </label>
            ))}
            <div className="row"><button className="btn small" onClick={() => setLook({ hub: 1, leaf: 1, link: 1 })}>Reset</button><span className="spacer" /><button className="btn small" onClick={rearrange}>Re-arrange ✨</button></div>
          </div>
        )}
        {!graph.nodes.length && <div className="muted" style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center" }}>Nothing to show. Add tasks or To-do cells with a category.</div>}
        <div className="small muted" style={{ position: "absolute", left: 12, bottom: 14 }}>Pinch to zoom · two-finger scroll to move · drag nodes</div>
      </div>

      {node && <Details node={node} items={items} showDone={showDone} onSelect={setSelected} onClose={() => setSelected(null)} />}
    </div>
  );
}

/** Everything about the clicked item: dates in both calendars, time, repeat, study time and notes */
function Details({ node, items, showDone, onSelect, onClose }: { node: GInfo; items: GInfo[]; showDone: boolean; onSelect: (id: string) => void; onClose: () => void }) {
  const { data, actions, update } = useStore();
  const timer = useTimer(); const nav = useNav();
  const kind = data.settings.primaryCalendar, other = kind === "persian" ? "gregorian" : "persian";
  const Row = ({ k, v }: { k: string; v: string }) => <div className="row small"><span className="muted">{k}</span><span className="spacer" /><span>{v}</span></div>;
  const Sec = ({ t, children }: { t: string; children: React.ReactNode }) => <div style={{ display: "flex", flexDirection: "column", gap: 5 }}><div className="small" style={{ fontWeight: 800, letterSpacing: 1, color: "var(--faint)" }}>{t.toUpperCase()}</div>{children}</div>;

  const studied = (ref: TodoRef) => {
    const list = data.sessions.filter((s) => (ref.kind === "schedule" ? s.scheduleEntryID === ref.id : s.taskID === ref.id));
    const ws = weekStart(new Date()), we = addDays(ws, 7);
    const week = list.filter((s) => new Date(s.start) >= ws && new Date(s.start) < we).reduce((a, s) => a + s.duration, 0);
    const last = list.map((s) => new Date(s.start)).sort((a, b) => b.getTime() - a.getTime())[0];
    return <Sec t="Study time">
      <Row k="Total" v={list.length ? duration(list.reduce((a, s) => a + s.duration, 0)) : "Not studied yet"} />
      {list.length > 0 && <><Row k="This week" v={week ? duration(week) : "—"} /><Row k="Sessions" v={String(list.length)} />{last && <Row k="Last studied" v={monthDay(last, kind)} />}</>}
    </Sec>;
  };

  let body: React.ReactNode = null;
  if (node.hub) {
    const open = items.filter((i) => !i.done && !i.skipped), closed = items.filter((i) => i.done || i.skipped);
    const list = (xs: GInfo[]) => xs.map((i) => <button key={i.id} className="list-row" style={{ background: "none", border: "none", textAlign: "left", padding: "4px 0" }} onClick={() => onSelect(i.id)}>
      <span style={{ color: i.skipped ? "#F97316" : i.color }}>{i.skipped ? "✕" : i.done ? "✔" : "○"}</span><span style={{ flex: 1 }}>{i.title}</span><span className="muted">›</span></button>);
    body = <>
      <Sec t="Overview"><Row k="Items" v={String(items.length)} /><Row k="Done" v={String(items.filter((i) => i.done).length)} /></Sec>
      <Sec t={`To do (${open.length})`}>{open.length ? list(open) : <span className="small muted">Nothing left 🎉</span>}</Sec>
      {closed.length > 0 ? <Sec t={`Done (${closed.length})`}>{list(closed)}</Sec> : !showDone && <span className="small muted">Turn on “Show done” to list finished items.</span>}
    </>;
  } else if (node.ref) {
    const ref = node.ref;
    const e = ref.kind === "schedule" ? data.schedule.find((x) => x.id === ref.id) : undefined;
    const t = ref.kind === "task" ? data.tasks.find((x) => x.id === ref.id) : undefined;
    let day = node.date ?? (t?.dueDate ? new Date(t.dueDate) : new Date());
    if (e && !node.date) { for (let k = 0; k < 3; k++) { const w = addDays(new Date(), 7 * k); if (applies(data, e, w)) { day = addDays(weekStart(w), e.weekday); break; } } }
    const done = isDone(data, ref, day), sk = isSkipped(data, ref, day);
    const status = sk ? ["Skipped (won't do)", "#F97316"] : done ? ["Done", "#22C55E"] : day < startOfDay(new Date()) && (e || t?.dueDate) ? ["Not done (day has passed)", "#F97316"] : ["To do", "var(--accent)"];
    const slot = e ? slotOf(data, e.slotID) : undefined;
    body = <>
      <span className="chip" style={{ alignSelf: "flex-start", background: `color-mix(in srgb, ${status[1]} 18%, transparent)`, color: status[1], fontWeight: 700 }}>{status[0]}</span>
      <Sec t="When">
        {(e || t?.dueDate) ? <><Row k="Date" v={`${WEEKDAYS[(day.getDay() + 1) % 7]}, ${monthDay(day, kind)}`} /><Row k={other === "persian" ? "Persian" : "Gregorian"} v={monthDay(day, other)} /></> : <Row k="Date" v="No date" />}
        {slot && <Row k="Time" v={`${slotTitle(slot)} · ${slot.endMinute - slot.startMinute} min`} />}
        {e && <Row k="Repeats" v={RECURRENCE_TITLE[e.recurrence]} />}
        <Row k="Category" v={categoryOf(data, (e ?? t)?.categoryID)?.name ?? "None"} />
        {t && <Row k="Estimate" v={`${t.estimatedMinutes} min`} />}
      </Sec>
      {studied(ref)}
      <Sec t="Notes">
        <textarea rows={4} placeholder="Add a note…" value={(e ? e.notes : t?.notes) ?? ""} style={{ width: "100%", resize: "vertical" }}
          onChange={(ev) => update((d) => { const v = ev.target.value; if (e) { const x = d.schedule.find((y) => y.id === e.id); if (x) x.notes = v; } else if (t) { const x = d.tasks.find((y) => y.id === t.id); if (x) x.notes = v; } })} />
      </Sec>
      <div className="row">
        <button className="btn" onClick={() => actions.toggleDone(ref, day)}>{done ? "Mark not done" : "Mark done"}</button>
        <button className="btn primary" disabled={timer.active} onClick={() => { timer.setTarget(ref); nav.go("timer"); }}>▶ Study</button>
      </div>
      <button className="btn small" style={{ alignSelf: "flex-start", color: "#F97316" }} onClick={() => actions.setSkipped(ref, day, !sk)}>{sk ? "Bring back to to-do" : "Skip (won't do)"}</button>
      <div className="row small">{e && <button className="btn small" onClick={() => nav.go("schedule")}>Open in Schedule</button>}<button className="btn small" onClick={() => nav.go("tasks", day)}>Open day</button></div>
    </>;
  }

  return (
    <div className="card" style={{ width: 300, display: "flex", flexDirection: "column", gap: 12, alignSelf: "flex-start", maxHeight: "calc(100vh - 150px)", overflow: "auto" }}>
      <div className="row"><span className="small muted">{node.hub ? "🏷 Category" : node.schedule ? "🗓 Weekly to-do" : "☑ Task"}</span><span className="spacer" /><button className="icon-btn" onClick={onClose}>✕</button></div>
      <div className="row"><span className="dot" style={{ width: 12, height: 12, background: node.color }} /><b style={{ fontSize: 17 }}>{node.title}</b></div>
      {body}
    </div>
  );
}
