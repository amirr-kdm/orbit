import React, { useEffect, useRef, useState } from "react";
import streakUrl from "./assets/streak.png";

/** An animation loop capped at `fps` that pauses while the window is hidden, minimised or in the background.
 *  Uncapped loops kept slow laptops at full CPU/GPU. Returns a stop function. */
export function frameLoop(cb: (t: number) => void, fps = 30) {
  let raf = 0, last = -1e9;
  const f = (t: number) => {
    raf = requestAnimationFrame(f);
    if (document.hidden || !document.hasFocus() || t - last < 1000 / fps - 2) return;
    last = t; cb(t);
  };
  raf = requestAnimationFrame(f);
  return () => cancelAnimationFrame(raf);
}
import { onPictureLoad, PlanetDef, paintPlanet, planetByID, paintSun, SUNS } from "./lib/planets";
import { GalaxyData } from "./lib/friends";
import { useStore } from "./lib/store";

/** Draws a planet; set `animate` to spin its rings and moons */
export function PlanetCanvas({ planet, size = 64, animate = false, locked = false }: { planet: PlanetDef; size?: number; animate?: boolean; locked?: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const cv = ref.current!; const dpr = window.devicePixelRatio || 1;
    cv.width = size * dpr; cv.height = size * dpr;
    const ctx = cv.getContext("2d")!;
    const draw = () => {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, size, size);
      paintPlanet(ctx, planet, size, animate ? performance.now() / 8000 : 0.1);
    };
    draw();
    // a picture planet may still be loading: draw again once it arrives
    const off = onPictureLoad(planet, draw);
    // Store pages show dozens of planets at once: keep each one's animation light
    const stop = animate ? frameLoop(draw, 15) : undefined;
    return () => { off(); stop?.(); };
  }, [planet, size, animate]);
  return (
    <div style={{ position: "relative", width: size, height: size, opacity: locked ? 0.4 : 1, filter: locked ? "grayscale(1)" : undefined }}>
      <canvas ref={ref} style={{ width: size, height: size }} />
      {locked && <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", fontSize: size * 0.22 }}>🔒</div>}
    </div>
  );
}

export function Avatar({ name, planet, size = 36, color = "#6b7280" }: { name: string; planet?: string | null; size?: number; color?: string }) {
  const p = planetByID(planet ?? undefined);
  if (p) return (
    // Same as the Mac app: a dark disc, with the planet (and its picture) drawn a quarter larger so nothing is cut off
    <div style={{ position: "relative", width: size, height: size, borderRadius: "50%", background: "rgba(0,0,0,.85)", flexShrink: 0 }}>
      <div style={{ position: "absolute", left: -size * 0.125, top: -size * 0.125, clipPath: "circle(50%)", pointerEvents: "none" }}>
        <PlanetCanvas planet={p} size={size * 1.25} />
      </div>
    </div>
  );
  return <div style={{ width: size, height: size, borderRadius: "50%", background: color, color: "white", display: "grid", placeItems: "center", fontWeight: 700, fontSize: size * 0.45, flexShrink: 0 }}>{name.slice(0, 1).toUpperCase()}</div>;
}

const LEVEL_COLORS = ["#64748B", "#22C55E", "#14B8A6", "#3B82F6", "#6366F1", "#8B5CF6", "#D946EF", "#EC4899", "#F97316", "#EAB308"];
export const LevelBadge = ({ level, dim = false }: { level: number; dim?: boolean }) => (
  <span className="level" style={{ background: dim ? "#6b7280" : LEVEL_COLORS[Math.min(9, Math.floor((level - 1) / 5))] }}>LV {level}</span>
);

export function Ring({ progress, size = 52, width = 6, color = "var(--accent)", children }: { progress: number; size?: number; width?: number; color?: string; children?: React.ReactNode }) {
  const r = (size - width) / 2, c = 2 * Math.PI * r;
  return (
    <div style={{ position: "relative", width: size, height: size }}>
      <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
        <circle cx={size / 2} cy={size / 2} r={r} stroke="color-mix(in srgb, var(--text) 10%, transparent)" strokeWidth={width} fill="none" />
        <circle cx={size / 2} cy={size / 2} r={r} stroke={color} strokeWidth={width} fill="none" strokeLinecap="round"
          strokeDasharray={c} strokeDashoffset={c * (1 - Math.min(1, Math.max(0, progress)))} style={{ transition: "stroke-dashoffset .3s" }} />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center" }}>{children}</div>
    </div>
  );
}

export function Stat({ icon, color, label, value, sub }: { icon: string; color: string; label: string; value: string; sub?: string }) {
  return (
    <div className="card stat">
      <div className="bubble" style={{ background: color + "26" }}>{icon}</div>
      <div><div className="label">{label}</div><div className="value">{value}</div>{sub && <div className="sub">{sub}</div>}</div>
    </div>
  );
}

export function QuickAdd({ placeholder = "Add a task and press Enter…", onAdd }: { placeholder?: string; onAdd: (t: string) => void }) {
  const [t, setT] = useState("");
  return (
    <div className="quick-add">
      <span style={{ color: "var(--accent)", fontWeight: 800 }}>＋</span>
      <input value={t} placeholder={placeholder} onChange={(e) => setT(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && t.trim()) { onAdd(t.trim()); setT(""); } }} />
    </div>
  );
}

// ---------- Context menu ----------
export interface MenuItem { label?: string; onClick?: () => void; disabled?: boolean; separator?: boolean; header?: string }
export function useContextMenu() {
  const [menu, setMenu] = useState<{ x: number; y: number; items: MenuItem[] } | null>(null);
  useEffect(() => {
    if (!menu) return;
    const close = () => setMenu(null);
    window.addEventListener("click", close); window.addEventListener("blur", close);
    return () => { window.removeEventListener("click", close); window.removeEventListener("blur", close); };
  }, [menu]);
  const open = (e: React.MouseEvent, items: MenuItem[]) => {
    e.preventDefault(); e.stopPropagation();
    setMenu({ x: Math.min(e.clientX, window.innerWidth - 220), y: Math.min(e.clientY, window.innerHeight - items.length * 30 - 20), items });
  };
  const node = menu && (
    <div className="menu" style={{ left: menu.x, top: menu.y }} onClick={(e) => e.stopPropagation()}>
      {menu.items.map((it, i) => it.separator ? <hr key={i} /> : it.header ? <div className="head" key={i}>{it.header}</div> : (
        <button key={i} disabled={it.disabled} style={{ opacity: it.disabled ? 0.4 : 1 }} onClick={() => { it.onClick?.(); setMenu(null); }}>{it.label}</button>
      ))}
    </div>
  );
  return { open, node };
}

export function Modal({ onClose, children, width }: { onClose: () => void; children: React.ReactNode; width?: number }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", k); return () => window.removeEventListener("keydown", k);
  }, [onClose]);
  return <div className="modal-bg" onMouseDown={onClose}><div className="modal" style={{ width }} onMouseDown={(e) => e.stopPropagation()}>{children}</div></div>;
}

// ---------- Galaxy / solar systems ----------

const slots = (n: number) => { const L = galaxyLook(); return Array.from({ length: n }, (_, i) => ({ radius: 100 * Math.max(1, L.sun * 0.95) + i * 32 * L.orbit, offset: i * 2.1, speed: (0.35 / Math.sqrt(i + 1)) * (i % 3 === 2 ? -1 : 1) })); };

function drawStars(ctx: CanvasRenderingContext2D, w: number, h: number, seed = 7) {
  let s = seed;
  const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < Math.floor((w * h) / 2500); i++) {
    ctx.fillStyle = `rgba(255,255,255,${0.25 + rnd() * 0.6})`;
    const r = rnd() < 0.92 ? 0.7 : 1.5; ctx.fillRect(rnd() * w, rnd() * h, r, r);
  }
}

/** Paint a solar system into a w×h area at time t (seconds) */
export function paintSystem(ctx: CanvasRenderingContext2D, sys: GalaxyData["systems"][number], w: number, h: number, t: number, large: boolean, cache: Map<string, HTMLCanvasElement>, hideName = false) {
  const L = galaxyLook();
  const sl = slots(sys.planets.length);
  const maxR = sl.length ? sl[sl.length - 1].radius : 60;
  const scale = Math.min(large ? 1.6 : 1, (Math.min(w, h * 1.5) / 2 - 20) / (maxR + 30));
  const cx = w / 2, cy = h / 2, ps = (large ? 42 : 30) * Math.max(scale, 0.7) * L.planet;
  ctx.strokeStyle = "rgba(255,255,255,0.14)"; ctx.lineWidth = 1;
  for (const s of sl) { ctx.beginPath(); ctx.ellipse(cx, cy, s.radius * scale, s.radius * scale * 0.55, 0, 0, Math.PI * 2); ctx.stroke(); }
  const items = sys.planets.map((id, i) => {
    const a = sl[i].offset + t * sl[i].speed;
    return { id, i, x: cx + Math.cos(a) * sl[i].radius * scale, y: cy + Math.sin(a) * sl[i].radius * scale * 0.55, z: Math.sin(a) };
  });
  const draw = (it: typeof items[number]) => {
    const p = planetByID(it.id); if (!p) return;
    // Planets with rings/moons are redrawn each frame; others are cached
    const animated = !!p.ring || !!p.moons;
    let img = cache.get(it.id + ps);
    if (!img || animated) {
      img = img ?? document.createElement("canvas");
      img.width = img.height = Math.ceil(ps * 2);
      const c = img.getContext("2d")!; c.setTransform(2, 0, 0, 2, 0, 0); c.clearRect(0, 0, ps, ps);
      paintPlanet(c, p, ps, t / 7 + it.i * 0.13); cache.set(it.id + ps, img);
    }
    ctx.drawImage(img, it.x - ps / 2, it.y - ps / 2, ps, ps);
  };
  items.filter((i) => i.z < 0).forEach(draw);
  paintSun(ctx, sys.sun, cx, cy, (large ? 46 : 30) * (SUNS[sys.sun]?.scale ?? 1) * Math.max(scale, 0.75) * L.sun, t);
  items.filter((i) => i.z >= 0).forEach(draw);
  if (!large && !hideName) { ctx.fillStyle = "rgba(255,255,255,0.9)"; ctx.font = "bold 15px 'Segoe UI', sans-serif"; ctx.textAlign = "center"; ctx.fillText(sys.name, cx, h - 8); }
}

export function SystemCanvas({ sys, width, height, large, res = 1, hideName = false }: { sys: GalaxyData["systems"][number]; width: number; height: number; large: boolean; res?: number; hideName?: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    // res > 1: drawn extra sharp because it is shown zoomed in
    const cv = ref.current!; const dpr = (window.devicePixelRatio || 1) * res;
    cv.width = width * dpr; cv.height = height * dpr;
    const ctx = cv.getContext("2d")!; const cache = new Map<string, HTMLCanvasElement>();
    const paint = () => {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, width, height);
      if (large) drawStars(ctx, width, height);
      paintSystem(ctx, sys, width, height, performance.now() / 1000, large && !hideName, cache, hideName);
    };
    paint();
    return frameLoop(paint, large || res > 1 ? 30 : 15);
  }, [sys, width, height, large, res, hideName]);
  return <canvas ref={ref} style={{ width, height, display: "block" }} />;
}

/** How solar systems are drawn (sliders, kept on this computer) — same as the Mac app */
export const LOOK_DEFAULTS = { orbit: 1, sun: 1, planet: 1.35 };
export function galaxyLook(): typeof LOOK_DEFAULTS {
  try { return { ...LOOK_DEFAULTS, ...JSON.parse(localStorage.getItem("galaxy-look") ?? "{}") }; } catch { return LOOK_DEFAULTS; }
}

/** Sliders for orbit spacing, sun size and planet size */
export function GalaxyLookButton() {
  const [open, setOpen] = useState(false);
  const [look, setLook] = useState(galaxyLook());
  const set = (k: keyof typeof LOOK_DEFAULTS, v: number) => { const n = { ...look, [k]: v }; setLook(n); localStorage.setItem("galaxy-look", JSON.stringify(n)); };
  const row = (label: string, k: keyof typeof LOOK_DEFAULTS, min: number, max: number) => (
    <label style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      <span className="row small"><span>{label}</span><span className="spacer" /><span className="muted">{Math.round(look[k] * 100)}%</span></span>
      <input type="range" min={min} max={max} step={0.01} value={look[k]} onChange={(e) => set(k, +e.target.value)} style={{ padding: 0 }} />
    </label>
  );
  return (
    <div style={{ position: "relative" }}>
      <button className="btn small" title="Orbit spacing, sun size and planet size" onClick={() => setOpen((o) => !o)}>☰</button>
      {open && (
        <div className="popover" style={{ top: 34, right: 0, width: 260, color: "var(--text)" }} onMouseDown={(e) => e.stopPropagation()}>
          <b>Solar system look</b>
          {row("◌ Orbit spacing", "orbit", 0.6, 2.2)}
          {row("☀️ Sun size", "sun", 0.5, 2)}
          {row("🌍 Planet size", "planet", 0.6, 2.6)}
          <div className="row"><span className="spacer" /><button className="btn small" onClick={() => { setLook(LOOK_DEFAULTS); localStorage.setItem("galaxy-look", JSON.stringify(LOOK_DEFAULTS)); }}>Reset</button>
            <button className="btn small" onClick={() => setOpen(false)}>Close</button></div>
        </div>
      )}
    </div>
  );
}

const WORLD_W = 2600, WORLD_H = 1700;
/** How big a solar system is drawn on the map */
export const TILE_SCALE = 1.265;
export const ZOOM_MIN = 0.35, ZOOM_MAX = 1.3;
const spiralPos = (i: number) => {
  if (i === 0) return { x: WORLD_W / 2 + 260, y: WORLD_H / 2 - 60 };
  const k = Math.floor((i + 1) / 2), arm = i % 2 === 0 ? 0 : Math.PI, a = arm + 0.25 + k * 1.05, r = 300 + k * 190;
  return { x: WORLD_W / 2 + Math.cos(a) * r * 1.25, y: WORLD_H / 2 + Math.sin(a) * r * 0.78 };
};
/** A system's place: where it was dragged to, or its spot on the spiral */
export const systemPos = (s: { x?: number | null; y?: number | null }, i: number) => (s.x != null && s.y != null ? { x: s.x, y: s.y } : spiralPos(i));

/** Endless starfield as a repeating tile (drawn once) */
let starTile: string | null = null;
function starTileURL() {
  if (starTile) return starTile;
  const c = document.createElement("canvas"); c.width = c.height = 400; const ctx = c.getContext("2d")!;
  let s = 5; const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < 70; i++) { ctx.fillStyle = `rgba(255,255,255,${0.25 + rnd() * 0.5})`; const r = rnd() < 0.9 ? 1 : 2; ctx.fillRect(rnd() * 400, rnd() * 400, r, r); }
  return (starTile = c.toDataURL());
}

/** The galaxy: endless, systems on a spiral (or where you dragged them). Drag the sky to move, drag a system to place it,
 *  pinch (Ctrl + wheel) or the slider to zoom. Opening a system is the camera zooming in on it — one continuous view. */
export function GalaxyMap({ data, height = 560, focused = null, onSelect, onMove }: {
  data: GalaxyData; height?: number; focused?: string | null; onSelect: (id: string) => void; onMove?: (id: string, x: number, y: number) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [zoom, setZoom] = useState(0.62);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  /** Camera override while flying to / sitting on a system */
  const [cam, setCam] = useState<{ z: number; x: number; y: number } | null>(null);
  const [size, setSize] = useState({ w: 900, h: height });
  const drag = useRef<{ x: number; y: number; px: number; py: number; moved: boolean; sys?: string; sx?: number; sy?: number } | null>(null);
  const [moving, setMoving] = useState<{ id: string; dx: number; dy: number } | null>(null);
  const bg = useRef<HTMLCanvasElement>(null);
  const flight = useRef(0);
  useEffect(() => {
    const el = box.current; if (!el) return;
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight })); ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const z = cam?.z ?? zoom, px = cam?.x ?? pan.x, py = cam?.y ?? pan.y;
  const fitZoom = () => Math.max(1.5, Math.min(size.w / (330 * TILE_SCALE), size.h / (260 * TILE_SCALE)) * 0.95);

  // Fly: zoom on a log scale while the system glides on screen, so the camera never swings through empty space
  useEffect(() => {
    const id = focused ?? null;
    const target = id ?? lastFocus.current;
    const i = data.systems.findIndex((s) => s.id === target);
    if (i < 0) { setCam(null); return; }
    const p = systemPos(data.systems[i], i), rel = { x: p.x - WORLD_W / 2, y: p.y - WORLD_H / 2 };
    const z0 = cam?.z ?? zoom, z1 = id ? fitZoom() : zoom;
    const s0 = { x: px + rel.x * z0, y: py + rel.y * z0 }, s1 = id ? { x: 0, y: 0 } : { x: s0.x * 0.4, y: s0.y * 0.4 };
    lastFocus.current = id;
    const start = performance.now(), dur = 850, run = ++flight.current;
    const step = (now: number) => {
      if (run !== flight.current) return;
      const t = Math.min(1, (now - start) / dur), e = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
      const zz = Math.exp(Math.log(z0) + (Math.log(z1) - Math.log(z0)) * e);
      const sx = s0.x + (s1.x - s0.x) * e, sy = s0.y + (s1.y - s0.y) * e;
      const next = { z: zz, x: sx - rel.x * zz, y: sy - rel.y * zz };
      if (t < 1) { setCam(next); requestAnimationFrame(step); }
      else if (id) setCam(next);
      else { setCam(null); setPan({ x: next.x, y: next.y }); }
    };
    requestAnimationFrame(step);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focused]);
  const lastFocus = useRef<string | null>(null);

  useEffect(() => {
    const cv = bg.current!; cv.width = WORLD_W / 2; cv.height = WORLD_H / 2;
    const ctx = cv.getContext("2d")!; ctx.scale(0.5, 0.5);
    let s = 3; const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
    const g = ctx.createRadialGradient(WORLD_W / 2, WORLD_H / 2, 0, WORLD_W / 2, WORLD_H / 2, WORLD_W * 0.6);
    g.addColorStop(0, "#1E1B4B"); g.addColorStop(0.5, "#0B1023"); g.addColorStop(1, "#020617"); ctx.fillStyle = g; ctx.fillRect(0, 0, WORLD_W, WORLD_H);
    const neb = ["#7C3AED", "#DB2777", "#0EA5E9", "#14B8A6"];
    for (let i = 0; i < 14; i++) { const x = rnd() * WORLD_W, y = rnd() * WORLD_H, r = 120 + rnd() * 260; const n = ctx.createRadialGradient(x, y, 0, x, y, r); n.addColorStop(0, neb[i % 4] + "2e"); n.addColorStop(1, "transparent"); ctx.fillStyle = n; ctx.fillRect(x - r, y - r, r * 2, r * 2); }
    for (let a = 0; a < 2; a++) for (let j = 0; j < 1400; j++) {
      const t = (j / 1400) * 4.2, ang = a * Math.PI + t * 1.25 + 0.25, rad = 60 + t * 290, sp = 14 + t * 26;
      const x = WORLD_W / 2 + Math.cos(ang) * rad * 1.25 + (rnd() - 0.5) * sp * 2, y = WORLD_H / 2 + Math.sin(ang) * rad * 0.78 + (rnd() - 0.5) * sp * 2;
      const hue = rnd(); ctx.fillStyle = hue < 0.15 ? "#F9A8D4" : hue < 0.3 ? "#93C5FD" : "#FFFFFF"; ctx.globalAlpha = 0.35 + rnd() * 0.55;
      const d = rnd() < 0.92 ? 2 : 4; ctx.fillRect(x, y, d, d);
    }
    ctx.globalAlpha = 1; drawStars(ctx, WORLD_W, WORLD_H, 11);
  }, []);

  /** Drags follow the mouse on the whole window until the button is released — leaving the map, or moving
   *  fast, no longer drops a system halfway (it used to stop and lose the move) */
  const zRef = useRef(z); zRef.current = z;
  const startDrag = (e: React.MouseEvent, d: NonNullable<typeof drag.current>) => {
    if (e.button !== 0) return;
    e.preventDefault();
    drag.current = d;
    const move = (ev: MouseEvent) => {
      if (Math.abs(ev.clientX - d.x) + Math.abs(ev.clientY - d.y) > 4) d.moved = true;
      if (!d.moved) return;
      if (d.sys && onMove) setMoving({ id: d.sys, dx: ev.clientX - d.x, dy: ev.clientY - d.y });
      else setPan({ x: d.px + ev.clientX - d.x, y: d.py + ev.clientY - d.y });
    };
    const up = (ev: MouseEvent) => {
      window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); window.removeEventListener("blur", cancel);
      if (d.sys) {
        if (d.moved && onMove) onMove(d.sys, d.sx! + (ev.clientX - d.x) / zRef.current, d.sy! + (ev.clientY - d.y) / zRef.current);
        else if (!d.moved) onSelect(d.sys);
      }
      setMoving(null); drag.current = null;
    };
    const cancel = () => { window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); window.removeEventListener("blur", cancel); setMoving(null); drag.current = null; };
    window.addEventListener("mousemove", move); window.addEventListener("mouseup", up); window.addEventListener("blur", cancel);
  };

  const w = WORLD_W * z, h = WORLD_H * z;
  // world origin on screen
  const ox = size.w / 2 + px - w / 2, oy = size.h / 2 + py - h / 2;
  const tile = 400 * z;
  return (
    <div ref={box} className="space" style={{ height, cursor: focused ? "default" : drag.current ? "grabbing" : "grab", userSelect: "none",
      backgroundColor: "#020617", backgroundImage: `url(${starTileURL()})`, backgroundSize: `${tile}px ${tile}px`, backgroundPosition: `${ox}px ${oy}px` }}
      onWheel={(e) => {
        // Windows touchpads send a pinch as Ctrl + wheel; a plain wheel scrolls the page
        if (!e.ctrlKey || focused || cam) return;
        e.preventDefault();
        const nz = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoom * (1 - e.deltaY * 0.01)));
        setPan((p) => ({ x: p.x * nz / zoom, y: p.y * nz / zoom })); setZoom(nz);
      }}
      onMouseDown={(e) => { if (focused) return; startDrag(e, { x: e.clientX, y: e.clientY, px: pan.x, py: pan.y, moved: false }); }}>
      <div style={{ position: "absolute", left: ox, top: oy, width: w, height: h }}>
        <canvas ref={bg} style={{ position: "absolute", inset: 0, width: "100%", height: "100%",
          maskImage: "radial-gradient(ellipse at center, black 55%, transparent 72%)", WebkitMaskImage: "radial-gradient(ellipse at center, black 55%, transparent 72%)" }} />
        {data.systems.map((s, i) => {
          const p0 = systemPos(s, i);
          const mv = moving?.id === s.id ? moving : null;
          const p = { x: p0.x + (mv ? mv.dx / z : 0), y: p0.y + (mv ? mv.dy / z : 0) };
          const tw = 330 * zoom * TILE_SCALE, th = 260 * zoom * TILE_SCALE, k = z / zoom;
          const open = focused === s.id;
          return (
            <div key={s.id} title={focused ? undefined : `Open ${s.name} · drag to move it`}
              style={{ position: "absolute", left: p.x * z - tw / 2, top: p.y * z - th / 2, width: tw, height: th, transform: `scale(${k})`,
                cursor: focused ? "default" : "pointer", opacity: !focused || open ? 1 : 0, transition: "opacity .4s", zIndex: mv ? 2 : 1 }}
              onMouseDown={(e) => { if (focused) return; e.stopPropagation(); startDrag(e, { x: e.clientX, y: e.clientY, px: pan.x, py: pan.y, moved: false, sys: s.id, sx: p0.x, sy: p0.y }); }}>
              <SystemCanvas sys={s} width={tw} height={th} large={false} res={open ? Math.min(4, k) : 1} hideName={!!focused} />
            </div>
          );
        })}
      </div>
      {!focused && (
        <div style={{ position: "absolute", right: 16, bottom: 14, display: "flex", gap: 8, alignItems: "center", background: "rgba(0,0,0,.35)", padding: "6px 12px", borderRadius: 99 }}>
          <span className="small">🔍</span>
          <input type="range" min={ZOOM_MIN} max={ZOOM_MAX} step={0.01} value={zoom} onChange={(e) => { const nz = +e.target.value; setPan((p) => ({ x: p.x * nz / zoom, y: p.y * nz / zoom })); setZoom(nz); }} style={{ width: 120, padding: 0 }} />
        </div>
      )}
    </div>
  );
}

/** Cell colour swatches. "+" creates a custom colour; right-click a swatch to delete it. */
export function CellPalette({ selection, onPick }: { selection?: string; onPick: (hex?: string) => void }) {
  const { data, actions } = useStore();
  const menu = useContextMenu();
  const [adding, setAdding] = useState(false);
  const [color, setColor] = useState("#22C55E");
  return (
    <div className="row" style={{ gap: 6, position: "relative" }} onClick={(e) => e.stopPropagation()}>
      <button className={`swatch ${selection === undefined ? "on" : ""}`} title="Default colour" style={{ background: "transparent" }} onClick={() => onPick(undefined)}>✨</button>
      {data.settings.cellPalette.map((p) => (
        <button key={p} className={`swatch ${selection === p ? "on" : ""}`} style={{ background: p }} title={`${p} · right-click to delete`}
          onClick={() => onPick(p)}
          onContextMenu={(e) => menu.open(e, [{ label: "Use this colour", onClick: () => onPick(p) }, { separator: true }, { label: "Delete colour", onClick: () => actions.removeColor(p) }])} />
      ))}
      <button className="swatch add" title="Create a colour" onClick={() => setAdding((a) => !a)}>＋</button>
      {adding && (
        <div className="popover" style={{ top: 34, left: 0 }}>
          <b>New colour</b>
          <div className="row"><input type="color" value={color} onChange={(e) => setColor(e.target.value.toUpperCase())} style={{ width: 54, height: 34, padding: 2 }} />
            <code className="small muted">{color.toUpperCase()}</code><span className="spacer" />
            <button className="btn primary" onClick={() => { const hex = color.toUpperCase(); actions.addColor(hex); onPick(hex); setAdding(false); }}>Add</button></div>
          <div className="row"><button className="btn small" onClick={actions.resetColors}>Restore default colours</button><span className="spacer" />
            <button className="btn small" onClick={() => setAdding(false)}>Close</button></div>
          <div className="small muted">Right-click any swatch to delete it. Cells keep their colour.</div>
        </div>
      )}
      {menu.node}
    </div>
  );
}

/** The streak lightning bolt */
export const StreakIcon = ({ size = 16 }: { size?: number }) => <img src={streakUrl} alt="" style={{ width: size, height: size, objectFit: "contain", verticalAlign: "-3px" }} />;
