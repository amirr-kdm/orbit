import React, { useEffect, useRef, useState } from "react";
import { PlanetDef, paintPlanet, planetByID, paintSun, SUNS } from "./lib/planets";
import { GalaxyData } from "./lib/friends";

/** Draws a planet; set `animate` to spin its rings and moons */
export function PlanetCanvas({ planet, size = 64, animate = false, locked = false }: { planet: PlanetDef; size?: number; animate?: boolean; locked?: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const cv = ref.current!; const dpr = window.devicePixelRatio || 1;
    cv.width = size * dpr; cv.height = size * dpr;
    const ctx = cv.getContext("2d")!;
    let raf = 0;
    const draw = () => {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, size, size);
      paintPlanet(ctx, planet, size, animate ? performance.now() / 8000 : 0.1);
      if (animate) raf = requestAnimationFrame(draw);
    };
    draw();
    return () => cancelAnimationFrame(raf);
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
    <div style={{ width: size, height: size, borderRadius: "50%", background: "#0b0d16", overflow: "hidden", display: "grid", placeItems: "center", flexShrink: 0 }}>
      <PlanetCanvas planet={p} size={size * 1.25} />
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

const slots = (n: number) => Array.from({ length: n }, (_, i) => ({ radius: 70 + i * 30, offset: i * 2.1, speed: (0.9 / Math.sqrt(i + 1)) * (i % 3 === 2 ? -1 : 1) }));

function drawStars(ctx: CanvasRenderingContext2D, w: number, h: number, seed = 7) {
  let s = seed;
  const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < Math.floor((w * h) / 2500); i++) {
    ctx.fillStyle = `rgba(255,255,255,${0.25 + rnd() * 0.6})`;
    const r = rnd() < 0.92 ? 0.7 : 1.5; ctx.fillRect(rnd() * w, rnd() * h, r, r);
  }
}

/** Paint a solar system into a w×h area at time t (seconds) */
export function paintSystem(ctx: CanvasRenderingContext2D, sys: GalaxyData["systems"][number], w: number, h: number, t: number, large: boolean, cache: Map<string, HTMLCanvasElement>) {
  const sl = slots(sys.planets.length);
  const maxR = sl.length ? sl[sl.length - 1].radius : 60;
  const scale = Math.min(large ? 1.6 : 1, (Math.min(w, h * 1.5) / 2 - 20) / (maxR + 30));
  const cx = w / 2, cy = h / 2, ps = (large ? 64 : 44) * Math.max(scale, 0.7);
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
  paintSun(ctx, sys.sun, cx, cy, (large ? 24 : 14) * (SUNS[sys.sun]?.scale ?? 1) * Math.max(scale, 0.75), t);
  items.filter((i) => i.z >= 0).forEach(draw);
  if (!large) { ctx.fillStyle = "rgba(255,255,255,0.9)"; ctx.font = "bold 15px 'Segoe UI', sans-serif"; ctx.textAlign = "center"; ctx.fillText(sys.name, cx, h - 8); }
}

export function SystemCanvas({ sys, width, height, large }: { sys: GalaxyData["systems"][number]; width: number; height: number; large: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const cv = ref.current!; const dpr = window.devicePixelRatio || 1;
    cv.width = width * dpr; cv.height = height * dpr;
    const ctx = cv.getContext("2d")!; const cache = new Map<string, HTMLCanvasElement>();
    let raf = 0;
    const loop = () => {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, width, height);
      if (large) drawStars(ctx, width, height);
      paintSystem(ctx, sys, width, height, performance.now() / 1000, large, cache);
      raf = requestAnimationFrame(loop);
    };
    loop();
    return () => cancelAnimationFrame(raf);
  }, [sys, width, height, large]);
  return <canvas ref={ref} style={{ width, height, display: "block" }} />;
}

/** Spiral galaxy: systems placed along two arms; drag to pan, wheel/slider to zoom, click a system */
export function GalaxyMap({ data, height = 560, onSelect }: { data: GalaxyData; height?: number; onSelect: (id: string) => void }) {
  const [zoom, setZoom] = useState(0.62);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const drag = useRef<{ x: number; y: number; px: number; py: number; moved: boolean } | null>(null);
  const W = 2600, H = 1700;
  const bg = useRef<HTMLCanvasElement>(null);
  const pos = (i: number) => {
    if (i === 0) return { x: W / 2 + 260, y: H / 2 - 60 };
    const k = Math.floor((i + 1) / 2), arm = i % 2 === 0 ? 0 : Math.PI, a = arm + 0.25 + k * 1.05, r = 300 + k * 190;
    return { x: W / 2 + Math.cos(a) * r * 1.25, y: H / 2 + Math.sin(a) * r * 0.78 };
  };
  useEffect(() => {
    const cv = bg.current!; cv.width = W / 2; cv.height = H / 2;
    const ctx = cv.getContext("2d")!; ctx.scale(0.5, 0.5);
    let s = 3; const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
    const g = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, W * 0.6);
    g.addColorStop(0, "#1E1B4B"); g.addColorStop(0.5, "#0B1023"); g.addColorStop(1, "#020617"); ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    const neb = ["#7C3AED", "#DB2777", "#0EA5E9", "#14B8A6"];
    for (let i = 0; i < 14; i++) { const x = rnd() * W, y = rnd() * H, r = 120 + rnd() * 260; const n = ctx.createRadialGradient(x, y, 0, x, y, r); n.addColorStop(0, neb[i % 4] + "2e"); n.addColorStop(1, "transparent"); ctx.fillStyle = n; ctx.fillRect(x - r, y - r, r * 2, r * 2); }
    for (let a = 0; a < 2; a++) for (let j = 0; j < 1400; j++) {
      const t = (j / 1400) * 4.2, ang = a * Math.PI + t * 1.25 + 0.25, rad = 60 + t * 290, sp = 14 + t * 26;
      const x = W / 2 + Math.cos(ang) * rad * 1.25 + (rnd() - 0.5) * sp * 2, y = H / 2 + Math.sin(ang) * rad * 0.78 + (rnd() - 0.5) * sp * 2;
      const hue = rnd(); ctx.fillStyle = hue < 0.15 ? "#F9A8D4" : hue < 0.3 ? "#93C5FD" : "#FFFFFF"; ctx.globalAlpha = 0.35 + rnd() * 0.55;
      const d = rnd() < 0.92 ? 2 : 4; ctx.fillRect(x, y, d, d);
    }
    ctx.globalAlpha = 1; drawStars(ctx, W, H, 11);
  }, []);
  return (
    <div className="space" style={{ height, cursor: drag.current ? "grabbing" : "grab" }}
      onWheel={(e) => setZoom((z) => Math.min(1.3, Math.max(0.35, z - e.deltaY * 0.001)))}
      onMouseDown={(e) => { drag.current = { x: e.clientX, y: e.clientY, px: pan.x, py: pan.y, moved: false }; }}
      onMouseMove={(e) => { const d = drag.current; if (!d) return; if (Math.abs(e.clientX - d.x) + Math.abs(e.clientY - d.y) > 4) d.moved = true; setPan({ x: d.px + e.clientX - d.x, y: d.py + e.clientY - d.y }); }}
      onMouseUp={() => { setTimeout(() => (drag.current = null), 0); }} onMouseLeave={() => (drag.current = null)}>
      <div style={{ position: "absolute", left: "50%", top: "50%", width: W * zoom, height: H * zoom, transform: `translate(calc(-50% + ${pan.x}px), calc(-50% + ${pan.y}px))` }}>
        <canvas ref={bg} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
        {data.systems.map((s, i) => {
          const p = pos(i), w = 330 * zoom * 1.1, h = 260 * zoom * 1.1;
          return (
            <div key={s.id} title={`Open ${s.name}`} style={{ position: "absolute", left: p.x * zoom - w / 2, top: p.y * zoom - h / 2, width: w, height: h, cursor: "pointer" }}
              onClick={() => { if (!drag.current?.moved) onSelect(s.id); }}>
              <SystemCanvas sys={s} width={w} height={h} large={false} />
            </div>
          );
        })}
      </div>
      <div style={{ position: "absolute", right: 16, bottom: 14, display: "flex", gap: 8, alignItems: "center", background: "rgba(0,0,0,.35)", padding: "6px 12px", borderRadius: 99 }}>
        <span className="small">🔍</span>
        <input type="range" min={0.35} max={1.3} step={0.01} value={zoom} onChange={(e) => setZoom(+e.target.value)} style={{ width: 120, padding: 0 }} />
      </div>
    </div>
  );
}
