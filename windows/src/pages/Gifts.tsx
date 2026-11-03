// Gift boxes: the box drawings, the little window in the middle of the screen where a gift is opened, and the sheet for sending one.
// Same as the Mac app.
import { useEffect, useRef, useState } from "react";
import { Avatar, Modal, PlanetCanvas } from "../components";
import { useFriends } from "../lib/friends";
import { BOX_STYLES, BoxStyle, boxStyle, GiftOpened, PlanetGift, useGifts } from "../lib/gifts";
import { PlanetDef, planetByID, storeAvailable } from "../lib/planets";
import { wallet, useStore } from "../lib/store";
import { RocketIcon } from "./Store";

// ---------- Box drawing ----------

const COLORS: Record<BoxStyle, { left: string; right: string; top: string; ribbon: string; ribbonDark: string }> = {
  starry: { left: "#2563EB", right: "#1E40AF", top: "#14B8A6", ribbon: "#FB923C", ribbonDark: "#C2410C" },
  royal: { left: "#38BDF8", right: "#0284C7", top: "#22D3EE", ribbon: "#C084FC", ribbonDark: "#7E22CE" },
  rose: { left: "#F5F3FF", right: "#DDD6FE", top: "#FAF5FF", ribbon: "#EC4899", ribbonDark: "#9D174D" },
  balloon: { left: "#10B981", right: "#047857", top: "#34D399", ribbon: "#FACC15", ribbonDark: "#A16207" },
  treasure: { left: "#B45309", right: "#78350F", top: "#D97706", ribbon: "#FBBF24", ribbonDark: "#92400E" },
};
const hasBow = (s: BoxStyle) => s !== "treasure";
const hasBalloons = (s: BoxStyle) => s === "balloon";
const patternOf = (s: BoxStyle) => (s === "rose" ? "dots" : s === "treasure" ? "planks" : "stars");

type Pt = { x: number; y: number };
const P = (x: number, y: number): Pt => ({ x, y });
/** A face given its origin and two edge vectors */
const face = (o: Pt, a: Pt, b: Pt) => ({
  at: (u: number, v: number) => P(o.x + a.x * u + b.x * v, o.y + a.y * u + b.y * v),
  rect(u0: number, u1: number, v0: number, v1: number) {
    const path = new Path2D();
    const q = [this.at(u0, v0), this.at(u1, v0), this.at(u1, v1), this.at(u0, v1)];
    path.moveTo(q[0].x, q[0].y); q.slice(1).forEach((p) => path.lineTo(p.x, p.y)); path.closePath(); return path;
  },
});
const quad = (a: Pt, b: Pt, c: Pt, d: Pt) => { const p = new Path2D(); p.moveTo(a.x, a.y); p.lineTo(b.x, b.y); p.lineTo(c.x, c.y); p.lineTo(d.x, d.y); p.closePath(); return p; };
const starPath = (c: Pt, r: number) => {
  const p = new Path2D();
  for (let i = 0; i < 10; i++) { const a = (i / 10) * Math.PI * 2 - Math.PI / 2, rr = i % 2 === 0 ? r : r * 0.45; const x = c.x + Math.cos(a) * rr, y = c.y + Math.sin(a) * rr; i ? p.lineTo(x, y) : p.moveTo(x, y); }
  p.closePath(); return p;
};

/** One gift box. `part` is the body or the lid (they are separate so a planet can rise between them); `lift` raises the lid (0…1) */
export function drawBox(ctx: CanvasRenderingContext2D, style: BoxStyle, part: "body" | "lid", lift: number, time: number, w: number, h0: number) {
  const s = Math.min(w, h0) * (hasBalloons(style) ? 0.37 : 0.46);
  const cx = w / 2, yb = h0 * 0.8, h = s * 0.56, col = COLORS[style];
  const B = P(cx, yb), BL = P(cx - s * 0.5, yb - s * 0.25), BR = P(cx + s * 0.5, yb - s * 0.25);
  const up = (p: Pt, d: number) => P(p.x, p.y - d);
  const lw = (v: number) => { ctx.lineWidth = v; };

  const decorate = (f: ReturnType<typeof face>, path: Path2D, light: boolean) => {
    ctx.save(); ctx.clip(path);
    const pat = patternOf(style);
    if (pat === "stars") {
      for (const [u, v, r] of [[0.18, 0.3, 0.09], [0.74, 0.22, 0.07], [0.35, 0.72, 0.1], [0.85, 0.7, 0.08], [0.58, 0.45, 0.06]]) {
        ctx.fillStyle = `rgba(255,255,255,${light ? 0.28 : 0.2})`; ctx.fill(starPath(f.at(u, v), s * r));
      }
    } else if (pat === "dots") {
      ctx.fillStyle = "rgba(196,181,253,0.9)";
      for (let u = 0.12; u <= 0.9; u += 0.2) for (let v = 0.15; v <= 0.9; v += 0.25) { const q = f.at(u, v); ctx.beginPath(); ctx.arc(q.x, q.y, s * 0.02, 0, Math.PI * 2); ctx.fill(); }
    } else {
      ctx.strokeStyle = "rgba(0,0,0,0.25)"; lw(s * 0.012);
      for (const v of [0.33, 0.66]) { const a = f.at(0, v), b = f.at(1, v); ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke(); }
    }
    ctx.restore();
  };

  if (part === "body") {
    const inner = quad(up(BL, h), up(B, h), up(BR, h), up(P(cx, yb - s * 0.5), h));
    const left = face(BL, P(B.x - BL.x, B.y - BL.y), P(0, -h)), right = face(B, P(BR.x - B.x, BR.y - B.y), P(0, -h));
    ctx.fillStyle = col.right + "8C"; ctx.fill(inner); ctx.fillStyle = "rgba(0,0,0,0.5)"; ctx.fill(inner);
    const lp = left.rect(0, 1, 0, 1), rp = right.rect(0, 1, 0, 1);
    let g = ctx.createLinearGradient(BL.x, BL.y, B.x, B.y); g.addColorStop(0, col.left); g.addColorStop(1, col.left + "D9"); ctx.fillStyle = g; ctx.fill(lp);
    g = ctx.createLinearGradient(B.x, B.y, BR.x, BR.y); g.addColorStop(0, col.right); g.addColorStop(1, col.right + "D9"); ctx.fillStyle = g; ctx.fill(rp);
    decorate(left, lp, true); decorate(right, rp, false);
    ctx.fillStyle = col.ribbon; ctx.fill(left.rect(0.43, 0.57, 0, 1));
    ctx.fillStyle = col.ribbonDark; ctx.fill(right.rect(0.43, 0.57, 0, 1));
    if (!hasBow(style)) { ctx.fillStyle = col.ribbon; ctx.fill(left.rect(0.05, 0.14, 0, 1)); ctx.fillStyle = col.ribbonDark; ctx.fill(right.rect(0.86, 0.95, 0, 1)); }
    ctx.strokeStyle = "rgba(0,0,0,0.25)"; lw(s * 0.015); ctx.stroke(lp); ctx.stroke(rp);
    ctx.save(); ctx.filter = `blur(${s * 0.06}px)`; ctx.fillStyle = "rgba(0,0,0,0.28)"; ctx.beginPath(); ctx.ellipse(cx, yb + s * 0.12, s * 0.62, s * 0.1, 0, 0, Math.PI * 2); ctx.fill(); ctx.restore();
    return;
  }

  // ----- the lid (with the bow, and the balloons) -----
  const k = 1.07, lidH = s * 0.2, base = h - s * 0.04 + lift * s * 1.1;
  const yc = yb - s * 0.25 - base - lidH;
  const grow = (p: Pt) => P(cx + (p.x - cx) * k, yc + (p.y - yc) * k);
  const Tb = grow(up(B, base + lidH)), Tl = grow(up(BL, base + lidH)), Tr = grow(up(BR, base + lidH)), Tk = grow(up(P(cx, yb - s * 0.5), base + lidH));
  const sl = quad(Tl, Tb, P(Tb.x, Tb.y + lidH), P(Tl.x, Tl.y + lidH)), sr = quad(Tb, Tr, P(Tr.x, Tr.y + lidH), P(Tb.x, Tb.y + lidH));
  const top = quad(Tl, Tb, Tr, Tk);
  ctx.fillStyle = col.left; ctx.fill(sl); ctx.fillStyle = col.right; ctx.fill(sr);
  ctx.strokeStyle = "rgba(0,0,0,0.25)"; lw(s * 0.012); ctx.stroke(sl); ctx.stroke(sr);
  const g = ctx.createLinearGradient(Tk.x, Tk.y, Tb.x, Tb.y); g.addColorStop(0, col.top); g.addColorStop(1, col.top + "CC"); ctx.fillStyle = g; ctx.fill(top);
  ctx.strokeStyle = "rgba(255,255,255,0.35)"; ctx.stroke(top);
  const tf = face(Tl, P(Tb.x - Tl.x, Tb.y - Tl.y), P(Tk.x - Tl.x, Tk.y - Tl.y));
  ctx.fillStyle = col.ribbon; ctx.fill(tf.rect(0.43, 0.57, 0, 1)); ctx.fill(tf.rect(0, 1, 0.43, 0.57));
  ctx.fill(face(Tl, P(Tb.x - Tl.x, Tb.y - Tl.y), P(0, lidH)).rect(0.43, 0.57, 0, 1));
  ctx.fillStyle = col.ribbonDark; ctx.fill(face(Tb, P(Tr.x - Tb.x, Tr.y - Tb.y), P(0, lidH)).rect(0.43, 0.57, 0, 1));
  const mid = tf.at(0.5, 0.5);

  if (hasBow(style)) {
    for (const dir of [-1, 1]) {   // two loops
      ctx.save(); ctx.translate(mid.x, mid.y); ctx.rotate((dir * 28 * Math.PI) / 180); ctx.translate(-mid.x, -mid.y);
      const path = new Path2D();
      path.ellipse(mid.x + (dir > 0 ? s * 0.18 : -s * 0.18), mid.y - s * 0.2, s * 0.18, s * 0.14, 0, 0, Math.PI * 2);
      path.ellipse(mid.x + (dir > 0 ? s * 0.18 : -s * 0.18), mid.y - s * 0.215, s * 0.11, s * 0.085, 0, 0, Math.PI * 2);
      const lg = ctx.createLinearGradient(mid.x, mid.y - s * 0.35, mid.x, mid.y); lg.addColorStop(0, col.ribbon); lg.addColorStop(1, col.ribbonDark);
      ctx.fillStyle = lg; ctx.fill(path, "evenodd");
      ctx.strokeStyle = "rgba(0,0,0,0.2)"; lw(s * 0.012); ctx.stroke(path); ctx.restore();
    }
    ctx.fillStyle = col.ribbonDark;
    for (const dir of [-1, 1]) { ctx.beginPath(); ctx.moveTo(mid.x, mid.y); ctx.lineTo(mid.x + dir * s * 0.22, mid.y + s * 0.2); ctx.lineTo(mid.x + dir * s * 0.08, mid.y + s * 0.16); ctx.closePath(); ctx.fill(); }
    ctx.beginPath(); ctx.ellipse(mid.x, mid.y - s * 0.01, s * 0.07, s * 0.06, 0, 0, Math.PI * 2); ctx.fillStyle = col.ribbon; ctx.fill(); ctx.strokeStyle = "rgba(0,0,0,0.2)"; lw(s * 0.01); ctx.stroke();
  } else {   // a chest's clasp
    ctx.beginPath(); ctx.roundRect(Tb.x - s * 0.07, Tb.y + lidH * 0.1, s * 0.14, s * 0.2, s * 0.03); ctx.fillStyle = col.ribbon; ctx.fill(); ctx.strokeStyle = col.ribbonDark; lw(s * 0.015); ctx.stroke();
    ctx.beginPath(); ctx.arc(Tb.x, Tb.y + lidH * 0.1 + s * 0.08, s * 0.02, 0, Math.PI * 2); ctx.fillStyle = col.ribbonDark; ctx.fill();
  }

  if (hasBalloons(style)) {
    const sway = Math.sin(time * 1.6) * s * 0.03, anchor = P(mid.x, mid.y - s * 0.12), floatUp = lift * s * 2.6;
    for (const [dx, dy, br, hex] of [[-0.34, -0.7, 0.2, "#A855F7"], [0, -0.95, 0.22, "#D946EF"], [0.34, -0.72, 0.2, "#C084FC"], [-0.12, -0.74, 0.19, "#E879F9"], [0.18, -0.8, 0.18, "#A78BFA"]] as [number, number, number, string][]) {
      const p = P(anchor.x + s * dx + sway, anchor.y + s * dy - floatUp);
      ctx.beginPath(); ctx.moveTo(anchor.x, anchor.y); ctx.quadraticCurveTo((p.x + anchor.x) / 2 - sway, (p.y + anchor.y) / 2, p.x, p.y + s * br * 1.2);
      ctx.strokeStyle = "rgba(255,255,255,0.55)"; lw(s * 0.01); ctx.stroke();
      const bg = ctx.createRadialGradient(p.x - s * br * 0.3, p.y - s * br * 0.4, 0, p.x - s * br * 0.3, p.y - s * br * 0.4, s * br * 1.4);
      bg.addColorStop(0, hex + "BF"); bg.addColorStop(1, hex);
      ctx.beginPath(); ctx.ellipse(p.x, p.y, s * br * 0.82, s * br, 0, 0, Math.PI * 2); ctx.fillStyle = bg; ctx.fill();
      ctx.beginPath(); ctx.ellipse(p.x - s * br * 0.3, p.y - s * br * 0.4, s * br * 0.2, s * br * 0.3, 0, 0, Math.PI * 2); ctx.fillStyle = "rgba(255,255,255,0.4)"; ctx.fill();
    }
  }
}

function BoxCanvas({ style, part, lift = 0, time = 0, size, extra }: { style: BoxStyle; part: "body" | "lid"; lift?: number; time?: number; size: number; extra?: React.CSSProperties }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const cv = ref.current!, dpr = window.devicePixelRatio || 1;
    cv.width = size * dpr; cv.height = size * dpr;
    const ctx = cv.getContext("2d")!; ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, size, size);
    drawBox(ctx, style, part, lift, time, size, size);
  });
  return <canvas ref={ref} style={{ position: "absolute", inset: 0, width: size, height: size, ...extra }} />;
}

/** The box with its lid, for small previews */
export function GiftBoxPreview({ style, size = 96 }: { style: BoxStyle; size?: number }) {
  return <div style={{ position: "relative", width: size, height: size }}><BoxCanvas style={style} part="body" size={size} /><BoxCanvas style={style} part="lid" time={0.4} size={size} /></div>;
}

// ---------- Receiving ----------

const ease = (t: number) => { const x = Math.min(1, Math.max(0, t)); return 1 - Math.pow(1 - x, 3); };
const back = (t: number) => { const x = Math.min(1, Math.max(0, t)); const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); };
const rnd = (seed: number) => { let s = seed; return () => ((s = (s * 16807) % 2147483647) / 2147483647); };

/** The little window in the middle of the screen: tap the box and the planet (or a fountain of rockets) comes out */
export function GiftPopup({ gift }: { gift: PlanetGift }) {
  const gifts = useGifts();
  const style = boxStyle(gift.box), planet = gift.planet_id ? planetByID(gift.planet_id) : undefined, isRockets = !gift.planet_id;
  const [openedAt, setOpenedAt] = useState<number | null>(null);
  const [result, setResult] = useState<GiftOpened | null>(null);
  const [failed, setFailed] = useState(false);
  const [now, setNow] = useState(performance.now());
  const fx = useRef<HTMLCanvasElement>(null);
  useEffect(() => { let id = 0; const loop = () => { setNow(performance.now()); id = requestAnimationFrame(loop); }; id = requestAnimationFrame(loop); return () => cancelAnimationFrame(id); }, []);

  const T = now / 1000;
  const p = openedAt != null ? Math.min(1.3, (now - openedAt) / 2100) : 0;
  const lift = ease((p - 0.2) / 0.28), rise = back((p - 0.38) / 0.5);
  const bob = openedAt == null ? Math.sin(T * 2.2) * 5 : 0;
  const shake = openedAt != null && p < 0.2 ? Math.sin(p * 140) * 3 * (1 - p / 0.2) : 0;
  const SIZE = 330;

  // twinkling stars, light rays and confetti behind the box
  useEffect(() => {
    const cv = fx.current; if (!cv) return;
    const dpr = window.devicePixelRatio || 1; cv.width = SIZE * dpr; cv.height = SIZE * dpr;
    const ctx = cv.getContext("2d")!; ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, SIZE, SIZE);
    const r = rnd(7);
    for (let k = 0; k < 26; k++) { const x = r() * SIZE, y = r() * SIZE, sz = 1 + r() * 2.4, a = 0.25 + 0.55 * (0.5 + 0.5 * Math.sin(T * (0.8 + r()) + k)); ctx.fillStyle = `rgba(255,255,255,${a})`; ctx.fillRect(x, y, sz, sz); }
    if (p > 0.22) {
      const cx = SIZE / 2, cy = SIZE * 0.55, t2 = (p - 0.22) / 0.9;
      for (let i = 0; i < 14; i++) {
        const a = (i / 14) * Math.PI * 2 + T * 0.4, len = SIZE * (0.18 + 0.4 * Math.min(1, t2));
        ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(a - 0.06) * len, cy + Math.sin(a - 0.06) * len); ctx.lineTo(cx + Math.cos(a + 0.06) * len, cy + Math.sin(a + 0.06) * len); ctx.closePath();
        ctx.fillStyle = `rgba(253,230,138,${Math.max(0, 0.3 - 0.25 * t2)})`; ctx.fill();
      }
      const r2 = rnd(13), colors = ["#FDE047", "#F472B6", "#38BDF8", "#A78BFA", "#4ADE80"];
      for (let i = 0; i < 34; i++) {
        const a = r2() * Math.PI * 2, sp = 0.35 + r2() * 0.9, d = SIZE * sp * Math.min(1, t2) * 0.62;
        const px = cx + Math.cos(a) * d, py = cy + Math.sin(a) * d + t2 * t2 * 30;
        ctx.save(); ctx.translate(px, py); ctx.rotate(a + t2 * 6.28); ctx.globalAlpha = Math.max(0, 1 - Math.max(0, t2 - 0.6) * 2.4);
        ctx.fillStyle = colors[Math.floor(r2() * 5) % 5]; ctx.fillRect(-3, -4.5, 6, 9); ctx.restore();
      }
    }
  });

  const open = async () => {
    if ((openedAt != null && !failed) || result) return;
    setFailed(false); setOpenedAt(performance.now());
    const r = await gifts.open(gift);
    if (r) { await new Promise((res) => setTimeout(res, 1700)); setResult(r); } else { setOpenedAt(null); setFailed(true); }
  };

  const title = !result ? "🎁 A gift for you!" : result.result === "rockets" ? "You already had it!" : "It's yours! 🎉";
  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 400, background: "rgba(0,0,0,.55)", display: "grid", placeItems: "center" }}>
      <div style={{ width: 430, padding: "24px 20px", borderRadius: 28, color: "white", textAlign: "center", display: "flex", flexDirection: "column", alignItems: "center", gap: 10,
        background: "linear-gradient(#3B1D78, #1B0F44, #0B0720)", border: "1px solid rgba(255,255,255,.18)", boxShadow: "0 0 40px rgba(124,58,237,.5)", animation: "giftIn .45s cubic-bezier(.2,1.3,.4,1)" }}>
        <style>{"@keyframes giftIn { from { transform: scale(.85); opacity: 0 } to { transform: scale(1); opacity: 1 } }"}</style>
        <div style={{ fontSize: 22, fontWeight: 800 }}>{title}</div>
        <div style={{ opacity: 0.75, fontWeight: 600 }}>from @{gift.from_name}</div>
        {gift.note && <div style={{ opacity: 0.85, fontStyle: "italic", padding: "0 24px" }}>“{gift.note}”</div>}
        <div style={{ position: "relative", width: SIZE, height: SIZE, cursor: openedAt == null ? "pointer" : "default" }} onClick={open}>
          <canvas ref={fx} style={{ position: "absolute", inset: 0, width: SIZE, height: SIZE }} />
          <BoxCanvas style={style} part="body" time={T} size={SIZE} extra={{ transform: `translate(${shake}px, ${bob}px)` }} />
          {openedAt != null && isRockets && (
            <div style={{ position: "absolute", inset: 0, transform: `translateY(${70 - 150 * rise + bob}px) scale(${0.25 + 0.8 * rise})`, opacity: Math.min(1, Math.max(0, (p - 0.36) * 8)), display: "grid", placeItems: "center", filter: "drop-shadow(0 0 24px rgba(253,224,71,.5))" }}>
              <div style={{ textAlign: "center" }}>
                <div style={{ transform: `rotate(${Math.sin(T * 3) * 4}deg)` }}><RocketIcon size={110} /></div>
                <div style={{ fontSize: 34, fontWeight: 800, color: "#FDE68A", fontVariantNumeric: "tabular-nums" }}>+{Math.round((gift.rockets ?? 0) * ease((p - 0.5) / 0.6)).toLocaleString()}</div>
              </div>
            </div>
          )}
          {openedAt != null && isRockets && Array.from({ length: 12 }, (_, i) => {
            const a = -Math.PI / 2 + ((i - 5.5) / 11) * 2.3, d = 60 + ((i * 37) % 70), t = Math.min(1, Math.max(0, (p - 0.34 - i * 0.012) / 0.7));
            return <div key={i} style={{ position: "absolute", left: SIZE / 2 - 15, top: SIZE / 2 - 15, opacity: t > 0 && t < 1 ? 1 : 0,
              transform: `translate(${Math.cos(a) * d * ease(t) * 1.7}px, ${Math.sin(a) * d * ease(t) * 1.7 + t * t * 55}px) rotate(${a + Math.PI / 2}rad)` }}><RocketIcon size={26 + (i % 3) * 7} /></div>;
          })}
          {openedAt != null && planet && (
            <div style={{ position: "absolute", left: SIZE / 2 - 95, top: SIZE / 2 - 95, transform: `translateY(${70 - 175 * rise + bob}px) scale(${0.25 + 0.8 * rise})`, opacity: Math.min(1, Math.max(0, (p - 0.36) * 8)), filter: `drop-shadow(0 0 22px rgba(255,255,255,${0.4 * rise}))` }}>
              <PlanetCanvas planet={planet} size={190} animate />
            </div>
          )}
          <BoxCanvas style={style} part="lid" lift={lift} time={T} size={SIZE} extra={{ transform: `translate(${shake + lift * 70}px, ${bob - lift * 20}px) rotate(${lift * 24}deg)`, opacity: 1 - Math.max(0, (p - 0.5) * 3) }} />
        </div>
        <div style={{ minHeight: 70, display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
          {result?.result === "rocketbox" ? <>
            <div className="row" style={{ gap: 6, justifyContent: "center" }}>You got <RocketIcon size={18} /> <b>{result.amount.toLocaleString()} rockets</b> from @{gift.from_name}</div>
            <button className="btn primary" onClick={() => gifts.finish(gift)}>Done</button>
          </> : result && planet ? <>
            {result.result === "rockets"
              ? <div className="row" style={{ gap: 6, justifyContent: "center" }}>{planet.name} was already yours, so you got <RocketIcon size={18} /> <b>{result.amount.toLocaleString()} 🚀</b></div>
              : <div>{planet.name} is waiting on your shelf: My Galaxy → Your Store Planets.</div>}
            <button className="btn primary" onClick={() => gifts.finish(gift)}>Done</button>
          </> : failed ? <>
            <div style={{ color: "#FB923C" }}>Couldn't open it right now. Check your connection and tap the box again.</div>
          </> : openedAt == null ? <>
            <div style={{ opacity: 0.8, fontWeight: 600 }}>👆 Tap the box to open it</div>
          </> : <div style={{ opacity: 0.6 }}>…</div>}
        </div>
      </div>
    </div>
  );
}

/** Shows the waiting gift box (if any) in the middle of the screen */
export function GiftHost() {
  const gifts = useGifts();
  const g = gifts.next;
  return g ? <GiftPopup key={g.id} gift={g} /> : null;
}

// ---------- Sending ----------

/** Opened from a friend's profile (friend fixed: planet or rockets) or from a planet (planet fixed: pick the friend) */
export function GiftSendModal({ friendId, friendName, planet, onClose }: { friendId?: string; friendName?: string; planet?: PlanetDef; onClose: () => void }) {
  const gifts = useGifts();
  const { data } = useStore();
  const friends = useFriends();
  const balance = wallet(data).balance;
  const [rocketMode, setRocketMode] = useState(false);
  const [planetID, setPlanetID] = useState<string | null>(null);
  const [amount, setAmount] = useState(100);
  const [toFriend, setToFriend] = useState<string | null>(null);
  const [box, setBox] = useState<BoxStyle>("starry");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  const chosen = planet ?? (planetID ? storeAvailable().find((p) => p.id === planetID) : undefined);
  const recipient = friendId ?? toFriend;
  const name = friendId ? friendName ?? "friend" : friends.friends.find((f) => f.profile.id === toFriend)?.profile.name ?? "a friend";
  const canSend = !!recipient && !busy && (rocketMode ? amount >= 10 && amount <= balance : !!chosen);
  const title = planet ? `Gift ${planet.name}` : rocketMode ? `Gift rockets to @${friendName}` : `Gift a planet to @${friendName}`;
  const who = planet ? "your friend" : `@${friendName}`;
  const send = async () => {
    if (!recipient) return;
    setBusy(true); setError(null);
    const e = rocketMode ? await gifts.sendRockets(recipient, amount, box, note.slice(0, 120)) : await gifts.sendPlanet(recipient, chosen!.id, box, note.slice(0, 120));
    if (e) setError(e); else setSent(true);
    setBusy(false);
  };
  const sel = (on: boolean): React.CSSProperties => ({ borderRadius: 12, padding: 8, cursor: "pointer", background: on ? "color-mix(in srgb, var(--text) 14%, transparent)" : "color-mix(in srgb, var(--text) 5%, transparent)", outline: on ? "2px solid var(--accent)" : undefined });

  return (
    <Modal onClose={onClose} width={560}>
      {sent ? (
        <div style={{ textAlign: "center", padding: "24px 0", display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
          <GiftBoxPreview style={box} size={150} />
          <h1 style={{ margin: 0 }}>Sent! 🎁</h1>
          <div className="muted">@{name} will see the box the next time they open Orbit.</div>
          <button className="btn primary" onClick={onClose}>Done</button>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div className="row"><h2 style={{ margin: 0 }}>🎁 {title}</h2><span className="spacer" /><span className="muted"><RocketIcon size={16} /> {balance.toLocaleString()}</span></div>
          {friendId && <div className="seg" style={{ alignSelf: "flex-start" }}><button className={!rocketMode ? "on" : ""} onClick={() => setRocketMode(false)}>Planet</button><button className={rocketMode ? "on" : ""} onClick={() => setRocketMode(true)}>Rockets</button></div>}
          {planet ? <>
            <div className="row" style={{ gap: 12 }}><PlanetCanvas planet={planet} size={70} />
              <div><b>{planet.name}</b><div><RocketIcon size={13} /> <b>{planet.price}</b></div></div></div>
            <b>1 · Pick a friend</b>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(150px, 1fr))", gap: 8, maxHeight: 130, overflow: "auto" }}>
              {friends.friends.map((f) => <div key={f.profile.id} className="row" style={{ gap: 8, ...sel(toFriend === f.profile.id) }} onClick={() => setToFriend(f.profile.id)}>
                <Avatar name={f.profile.name} planet={f.profile.avatar ?? undefined} size={30} /><b className="small" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{f.profile.name}</b></div>)}
            </div>
          </> : rocketMode ? <>
            <b>1 · How many rockets?</b>
            <div className="row" style={{ gap: 8 }}>
              <input type="number" value={amount} min={10} onChange={(e) => setAmount(Math.round(+e.target.value))} style={{ width: 120 }} /><RocketIcon size={20} />
              {[50, 100, 250, 500, 1000].map((n) => <button key={n} className="btn small" onClick={() => setAmount(n)}>{n}</button>)}
            </div>
            {amount > balance ? <div className="small" style={{ color: "#F97316" }}>You only have {balance.toLocaleString()} rockets.</div> : amount < 10 ? <div className="small" style={{ color: "#F97316" }}>At least 10 rockets.</div> : null}
          </> : <>
            <b>1 · Pick a planet</b>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(104px, 1fr))", gap: 10, height: 230, overflow: "auto", alignContent: "start" }}>
              {storeAvailable().sort((a, b) => a.price! - b.price!).map((p) => {
                const ok = balance >= p.price!;
                return <div key={p.id} style={{ ...sel(planetID === p.id), textAlign: "center", opacity: ok ? 1 : 0.4 }} title={ok ? p.blurb : `You need ${(p.price! - balance).toLocaleString()} more rockets`}
                  onClick={() => ok && setPlanetID(p.id)}>
                  <PlanetCanvas planet={p} size={74} /><div className="small" style={{ fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{p.name}</div>
                  <div className="small"><RocketIcon size={11} /> <b>{p.price}</b></div></div>;
              })}
            </div>
          </>}
          <b>2 · Pick a gift box</b>
          <div className="row" style={{ gap: 8 }}>
            {BOX_STYLES.map((b) => <div key={b.id} style={{ ...sel(box === b.id), flex: 1, textAlign: "center", padding: "4px 0" }} onClick={() => setBox(b.id)}>
              <div style={{ display: "grid", placeItems: "center" }}><GiftBoxPreview style={b.id} size={78} /></div><div className="small" style={{ fontWeight: 600 }}>{b.name}</div></div>)}
          </div>
          <input value={note} maxLength={120} onChange={(e) => setNote(e.target.value)} placeholder="Add a short note (optional)" />
          <div className="small muted">ℹ️ {rocketMode ? `The rockets leave your balance now and go to ${who} when they open the box.` : `If ${who} already has this planet, they get its price in rockets instead.`}</div>
          {error && <div className="small" style={{ color: "#ef4444" }}>{error}</div>}
          <div className="row"><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
            <button className="btn primary" disabled={!canSend} onClick={send}>
              {rocketMode ? `✈️ Send · ${amount.toLocaleString()} 🚀` : chosen && recipient ? `✈️ Send · ${chosen.price!.toLocaleString()} 🚀` : planet ? "Pick a friend" : "Pick a planet"}</button></div>
        </div>
      )}
    </Modal>
  );
}
