import { useEffect, useRef, useState } from "react";
import { Avatar, frameLoop } from "../components";
import { Boss, isWorld, prizeOf, useFightClub } from "../lib/fightclub";
import { useFriends } from "../lib/friends";
import { categoryLabel, useStore } from "../lib/store";
import { RocketIcon } from "./Store";
import { OrbiterProfile } from "./Orbiters";
import m1 from "../assets/boss1.png";
import m2 from "../assets/boss2.png";
import m3 from "../assets/boss3.png";
import m4 from "../assets/boss4.png";
import m5 from "../assets/boss5.png";
import m6 from "../assets/boss6.png";
import m7 from "../assets/boss7.png";
import grave from "../assets/boss-grave.png";
import slayer from "../assets/badge-slayer.png";
import fighter from "../assets/fighter.png";

const MONSTERS = [m1, m2, m3, m4, m5, m6, m7];
export const monsterImg = (n: number) => MONSTERS[Math.min(7, Math.max(1, n)) - 1];
const hm = (m: number) => { const h = Math.floor(m / 60), r = m % 60; return h === 0 ? `${r}m` : r === 0 ? `${h}h` : `${h}h ${r}m`; };
const rel = (d: Date) => {
  const m = Math.round((d.getTime() - Date.now()) / 60000), a = Math.abs(m);
  const t = a < 60 ? `${a}m` : a < 1440 ? `${Math.round(a / 60)}h` : `${Math.round(a / 1440)}d`;
  return m >= 0 ? `in ${t}` : `${t} ago`;
};
const RED = "linear-gradient(#FF4D4D, #B91C1C)";
const panel: React.CSSProperties = { padding: 18, borderRadius: 18, background: "rgba(255,255,255,.05)", border: "1px solid rgba(255,255,255,.06)" };

/** Fight Club: this week's World Boss for every Orbiter */
export default function FightClubPage() {
  const fc = useFightClub();
  const [battle, setBattle] = useState<string | null>(null);
  const [showing, setShowing] = useState<string | null>(null);
  useEffect(() => { fc.load(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const w = fc.worldBoss;
  const older = fc.bosses.filter((b) => !isWorld(b) && b.status === "alive" && (fc.fighters[b.id] ?? []).some((x) => x.user_id === fc.me));

  return (
    <div className="page" style={{ color: "white", background: "#0B0F1E", minHeight: "100%" }}>
      <div className="row" style={{ gap: 14 }}>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 12, fontWeight: 900, letterSpacing: 3, color: "#EF4444" }}>FIGHT CLUB</div>
          <h1 style={{ margin: "2px 0" }}>A monster attacks Orbit every week</h1>
          <div style={{ opacity: 0.65 }}>Every Orbiter fights it together. Study to earn bullets, shoot it down before Friday ends.</div>
        </div>
        <img src={fighter} alt="" style={{ width: 84, transform: "rotate(-12deg)", filter: "drop-shadow(0 0 12px rgba(34,211,238,.4))" }} />
      </div>

      {w ? <>
        <Hero b={w} onFight={() => setBattle(w.id)} />
        <div className="row" style={{ gap: 12, alignItems: "stretch" }}>
          {([["⏱", "#22D3EE", "1 · Study", "Every minute you study with the timer this week is one bullet."],
            ["🎯", "#EF4444", "2 · Fight", "Fly with ← →, fire with Space. Only hits do damage."],
            ["🏆", "#FACC15", "3 · Share", "Beat it before Friday ends: 1,000 🚀 split by damage."]] as const).map(([icon, tint, title, text]) => (
            <div key={title} className="row" style={{ ...panel, flex: 1, padding: 14, alignItems: "flex-start", gap: 12 }}>
              <span style={{ width: 36, height: 36, borderRadius: "50%", display: "grid", placeItems: "center", background: `${tint}26`, flexShrink: 0 }}>{icon}</span>
              <div><b>{title}</b><div className="small" style={{ opacity: 0.65 }}>{text}</div></div>
            </div>
          ))}
        </div>
        <div className="row" style={{ gap: 16, alignItems: "flex-start" }}>
          <Leaderboard b={w} onOpen={setShowing} />
          <Graveyard current={w} />
        </div>
      </> : (
        <div style={{ minHeight: 300, display: "grid", placeItems: "center", opacity: 0.65 }}>
          {fc.error ?? "Looking for this week's monster…"}
        </div>
      )}

      {older.length > 0 && (
        <div style={panel}>
          <b>Older monsters you're still fighting</b>
          {older.map((b) => (
            <div key={b.id} className="row" style={{ gap: 12, padding: "8px 0", cursor: "pointer" }} onClick={() => setBattle(b.id)}>
              <img src={monsterImg(b.monster)} alt="" style={{ width: 44 }} />
              <div style={{ flex: 1 }}><b>{b.title}</b><div className="small" style={{ opacity: 0.6 }}>{hm(fc.healthLeft(b))} of {hm(b.hp)} left · escapes {rel(new Date(b.deadline))}</div></div>
              <span>›</span>
            </div>
          ))}
        </div>
      )}
      {fc.error && w && <div className="small" style={{ color: "#ef4444" }}>{fc.error}</div>}

      {battle && <Battle bossID={battle} onClose={() => setBattle(null)} />}
      {showing && <OrbiterProfile userID={showing} onClose={() => setShowing(null)} />}
    </div>
  );
}

function Hero({ b, onFight }: { b: Boss; onFight: () => void }) {
  const fc = useFightClub();
  const left = fc.healthLeft(b), ammo = fc.ammo(b), alive = b.status === "alive";
  const mine = (fc.fighters[b.id] ?? []).find((x) => x.user_id === fc.me);
  const people = (fc.fighters[b.id] ?? []).filter((x) => x.minutes > 0 || x.damage > 0).length;
  const share = left / Math.max(1, b.hp);
  const chip = (icon: string, value: string, label: string) => (
    <div style={{ padding: "8px 12px", borderRadius: 12, background: "rgba(255,255,255,.06)" }}>
      <b>{icon} {value}</b><div className="small" style={{ opacity: 0.6 }}>{label}</div></div>
  );
  return (
    <div className="row" style={{ gap: 28, padding: 24, borderRadius: 26, border: "1px solid rgba(239,68,68,.35)",
      background: "linear-gradient(135deg, rgba(42,10,18,.92), rgba(11,16,32,.92))", flexWrap: "wrap" }}>
      <div style={{ width: 260, height: 260, display: "grid", placeItems: "center", position: "relative",
        background: `radial-gradient(circle, rgba(239,68,68,${alive ? 0.45 : 0.15}), transparent 60%)` }}>
        {alive ? <img className="monster-idle" src={monsterImg(b.monster)} alt="" style={{ width: 210, height: 210, objectFit: "contain" }} />
          : <img src={grave} alt="" style={{ width: 200, height: 200, objectFit: "cover", borderRadius: 28 }} />}
        <div style={{ position: "absolute", bottom: 8, width: 150, height: 18, borderRadius: "50%", background: "rgba(0,0,0,.45)", filter: "blur(6px)" }} />
      </div>
      <div style={{ flex: 1, minWidth: 320, display: "flex", flexDirection: "column", gap: 14 }}>
        <div className="row">
          <span style={{ fontSize: 12, fontWeight: 900, letterSpacing: 2, color: b.status === "defeated" ? "#22C55E" : "#EF4444" }}>
            {b.status === "defeated" ? "DEFEATED 🏆" : b.status === "escaped" ? "ESCAPED 💨" : "WORLD BOSS · ALIVE"}</span>
          <span className="spacer" />{alive && <Countdown end={new Date(b.deadline)} />}
        </div>
        <div style={{ fontSize: 30, fontWeight: 900 }}>{b.title}</div>
        <div>
          <div style={{ height: 16, borderRadius: 99, background: "rgba(255,255,255,.08)", overflow: "hidden" }}>
            <div style={{ width: `${share * 100}%`, height: "100%", borderRadius: 99, background: "linear-gradient(90deg,#FF4D4D,#B91C1C)", boxShadow: "0 0 8px rgba(239,68,68,.6)" }} /></div>
          <div className="row" style={{ marginTop: 6, fontWeight: 600 }}><span style={{ color: "#EF4444" }}>❤️ {hm(left)} of {hm(b.hp)} health left</span><span className="spacer" />
            <span style={{ opacity: 0.6 }}>{Math.round((1 - share) * 100)}% down</span></div>
        </div>
        <div className="row" style={{ gap: 10, flexWrap: "wrap" }}>
          {chip("👥", String(people), "fighting")}{chip("⚡", String(ammo), "your bullets")}
          {chip("🎯", String(mine?.damage ?? 0), "your damage")}{chip("🎁", "1,000 🚀", "prize")}
        </div>
        <div className="row" style={{ gap: 12 }}>
          <button onClick={onFight} style={{ width: 170, height: 44, borderRadius: 99, border: "none", color: "white", fontWeight: 700, fontSize: 15,
            background: RED, boxShadow: "0 0 14px rgba(239,68,68,.55)", cursor: "pointer" }}>🎯 {alive ? "Fight" : "View the fight"}</button>
          <span style={{ opacity: 0.65 }}>{alive ? (ammo > 0 ? "Hold Space for rapid fire" : "No bullets yet — study with the timer to reload") : "A new monster arrives on Saturday."}</span>
        </div>
      </div>
    </div>
  );
}

function Countdown({ end }: { end: Date }) {
  const [, tick] = useState(0);
  useEffect(() => { const t = setInterval(() => tick((n) => n + 1), 30_000); return () => clearInterval(t); }, []);
  const s = Math.max(0, Math.floor((end.getTime() - Date.now()) / 1000));
  return (
    <span className="row" style={{ gap: 6 }}>⏳{([[Math.floor(s / 86400), "d"], [Math.floor((s % 86400) / 3600), "h"], [Math.floor((s % 3600) / 60), "m"]] as const).map(([v, u]) => (
      <b key={u} style={{ padding: "3px 8px", borderRadius: 7, background: "rgba(255,255,255,.08)" }}>{v}{u}</b>))}<span className="small" style={{ opacity: 0.6 }}>left</span></span>
  );
}

function Leaderboard({ b, onOpen }: { b: Boss; onOpen: (id: string) => void }) {
  const fc = useFightClub();
  const f = useFriends();
  const list = (fc.fighters[b.id] ?? []).filter((x) => x.damage > 0).sort((a, c) => c.damage - a.damage);
  const total = Math.max(1, list.reduce((a, x) => a + x.damage, 0));
  return (
    <div style={{ ...panel, flex: 1 }}>
      <b style={{ color: "#FACC15" }}>🏆 Most damage this week</b>
      {!list.length && <div style={{ opacity: 0.6, padding: "20px 0", textAlign: "center" }}>No hits yet — be the first!</div>}
      {list.map((x, i) => {
        const isMe = x.user_id === fc.me;
        const name = isMe ? "You" : f.people[x.user_id]?.profile.name ?? fc.names[x.user_id] ?? "Orbiter";
        return (
          <div key={x.user_id} className="row" style={{ gap: 10, padding: "6px 0", cursor: "pointer" }} onClick={() => onOpen(x.user_id)}>
            <span style={{ width: 26, textAlign: "center" }}>{i < 3 ? ["🥇", "🥈", "🥉"][i] : i + 1}</span>
            <Avatar name={isMe ? f.me?.name ?? name : name} planet={isMe ? f.me?.avatar ?? undefined : f.people[x.user_id]?.profile.avatar ?? undefined} size={30} color="#EF4444" />
            <b style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{name}</b>
            {i === 0 && <img src={slayer} alt="" title="Top damage" style={{ height: 22 }} />}
            <span className="spacer" />
            <div style={{ textAlign: "right" }}><b>{x.damage} dmg</b><div className="small" style={{ opacity: 0.6 }}>~{Math.floor(prizeOf(b) * x.damage / total)} 🚀</div></div>
          </div>
        );
      })}
    </div>
  );
}

/** Earlier weeks' monsters and how they ended */
function Graveyard({ current }: { current: Boss }) {
  const fc = useFightClub();
  const past = fc.bosses.filter((b) => isWorld(b) && b.id !== current.id);
  return (
    <div style={{ ...panel, width: 280 }}>
      <b style={{ color: "#F97316" }}>🌙 Graveyard</b>
      {!past.length && <div style={{ textAlign: "center", padding: "10px 0" }}><img src={grave} alt="" style={{ width: 120, height: 90, objectFit: "cover", borderRadius: 14, opacity: 0.85 }} />
        <div className="small" style={{ opacity: 0.6 }}>Beaten monsters rest here.</div></div>}
      {past.map((p) => (
        <div key={p.id} className="row" style={{ gap: 10, padding: "6px 0" }}>
          <img src={monsterImg(p.monster)} alt="" style={{ width: 40, height: 40, objectFit: "contain", filter: "grayscale(1)" }} />
          <div><b className="small">{p.title}</b><div className="small" style={{ color: p.status === "defeated" ? "#22C55E" : undefined, opacity: p.status === "defeated" ? 1 : 0.6 }}>
            {p.status === "defeated" ? "Defeated 🏆" : p.status === "escaped" ? "Escaped 💨" : "Still alive"}</div></div>
        </div>
      ))}
    </div>
  );
}

const FLIGHT = 550; // ms from ship to monster height
const W = 760, H = 420;

/** The fight: fly with ← → (A D), Space to fire, hold Space for rapid fire. Only hits count. */
function Battle({ bossID, onClose }: { bossID: string; onClose: () => void }) {
  const fc = useFightClub();
  const f = useFriends();
  const { data } = useStore();
  const b = fc.bosses.find((x) => x.id === bossID);
  const cv = useRef<HTMLCanvasElement>(null);
  // shots/hits: fired but not sent yet; flyShots/flyHits: sent, no answer yet — both still counted,
  // so health and bullets never jump back
  const state = useRef({ shipX: 0.5, left: false, right: false, fire: false, fireSeen: 0, bullets: [] as { x: number; t0: number; hit: boolean }[],
    shots: 0, hits: 0, flyShots: 0, flyHits: 0, last: 0, flushing: false });
  const [, force] = useState(0);
  const start = useRef(performance.now());
  const monsterEl = useRef(new Image());
  const shipEl = useRef(new Image());
  // The monster's pace for this visit: fixed, so its path never jumps when its health changes
  const fixedPace = useRef<number | null>(null);
  const [aspect, setAspect] = useState(1);
  useEffect(() => { shipEl.current.src = fighter; }, []);
  useEffect(() => {
    if (!b) return;
    monsterEl.current.onload = () => setAspect(Math.min(1, monsterEl.current.naturalWidth / Math.max(1, monsterEl.current.naturalHeight)));
    monsterEl.current.src = monsterImg(b.monster);
  }, [b?.monster]); // eslint-disable-line react-hooks/exhaustive-deps

  const s0 = state.current;
  const left = b ? Math.max(0, fc.healthLeft(b) - s0.hits - s0.flyHits) : 0;
  const ammo = b ? Math.max(0, fc.ammo(b) - s0.shots - s0.flyShots) : 0;
  const size = b ? (isWorld(b) ? Math.min(H * 0.5, 190) : Math.min(H * 0.5, 120 + b.monster * 18)) : 120;
  const pace = () => fixedPace.current ?? (b ? 0.55 + 0.12 * b.monster + 0.9 * (1 - left / Math.max(1, b.hp)) : 1);
  if (b && fixedPace.current === null) fixedPace.current = pace();
  const monsterX = (t: number) => { const p = pace(); return 0.5 + (Math.sin(t * p) * 0.7 + Math.sin(t * p * 2.3 + 1.1) * 0.25 + Math.sin(t * p * 0.37 + 2) * 0.2) * 0.33; };
  // any bullet touching the visible body or arms counts (a tall picture is narrower than its square), plus the bullet's width
  const hitHalf = size * aspect / 2 + 4;

  const latest = useRef({ b, left, ammo }); latest.current = { b, left, ammo };
  const shoot = () => {
    const { b, left, ammo } = latest.current;
    if (!b || b.status !== "alive" || ammo <= 0 || left <= 0) return;
    const s = state.current, now = performance.now();
    if (now - s.last < 120) return;
    s.last = now;
    const t = (now - start.current) / 1000;
    const target = monsterX(t + FLIGHT / 1000) * W;
    const hit = Math.abs(s.shipX * W - target) < hitHalf;
    s.bullets.push({ x: s.shipX, t0: now, hit });
    s.shots++; if (hit) s.hits++;
    force((n) => n + 1);
  };

  // keyboard: hold ← → (A D) to fly; Space fires, hold it for a steady stream
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      const s = state.current;
      if (e.key === "ArrowLeft" || e.key === "a") s.left = true;
      if (e.key === "ArrowRight" || e.key === "d") s.right = true;
      if (e.key === " ") { e.preventDefault(); s.fireSeen = performance.now(); if (!e.repeat) { s.fire = true; shoot(); } }
      if (e.key === "Escape") onClose();
    };
    const up = (e: KeyboardEvent) => {
      const s = state.current;
      if (e.key === "ArrowLeft" || e.key === "a") s.left = false;
      if (e.key === "ArrowRight" || e.key === "d") s.right = false;
      if (e.key === " ") s.fire = false;
    };
    const blur = () => { const s = state.current; s.left = s.right = s.fire = false; };
    window.addEventListener("keydown", down); window.addEventListener("keyup", up); window.addEventListener("blur", blur);
    return () => { window.removeEventListener("keydown", down); window.removeEventListener("keyup", up); window.removeEventListener("blur", blur); };
  });

  // send what was fired every 1.2 s (and when closing)
  useEffect(() => {
    const flush = async () => {
      const s = state.current, b = latest.current.b; if (!b || !s.shots || s.flushing) return;
      s.flushing = true;
      const shots = s.shots, hits = s.hits; s.shots = 0; s.hits = 0; s.flyShots = shots; s.flyHits = hits;
      await fc.fire(b, shots, hits);
      s.flyShots = 0; s.flyHits = 0; s.flushing = false; force((n) => n + 1);
    };
    const t = setInterval(flush, 1200);
    return () => { clearInterval(t); state.current.fire = false; flush(); };
  }, [b?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // draw loop
  useEffect(() => {
    // capped at 60 fps (fast monitors would draw 144+), paused in the background
    const stop = frameLoop((now) => draw(now), 60);
    function draw(now: number) {
      const c = cv.current, b = latest.current.b; if (!c || !b) return;
      const s = state.current, ctx = c.getContext("2d")!, dpr = devicePixelRatio || 1;
      if (c.width !== W * dpr) { c.width = W * dpr; c.height = H * dpr; }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
      const dir = (s.right ? 1 : 0) - (s.left ? 1 : 0);
      if (dir) s.shipX = Math.min(0.96, Math.max(0.04, s.shipX + dir * 0.011));
      // rapid fire while Space is held (if the key's release is ever missed, it stops once the repeats stop)
      if (s.fire && now - s.fireSeen > 1000) s.fire = false;
      if (s.fire) shoot();
      const t = (now - start.current) / 1000, p = pace(), alive = b.status === "alive";
      const mx = alive ? monsterX(t) * W : W / 2, my = size / 2 + 16;
      const hitNow = s.bullets.some((x) => x.hit && now - (x.t0 + FLIGHT) >= 0 && now - (x.t0 + FLIGHT) < 180);
      // the monster: breathing, swaying, hopping; flinches red when hit
      ctx.save();
      ctx.translate(mx + (hitNow ? (Math.random() - 0.5) * 12 : 0), my + (alive ? -Math.abs(Math.sin(t * 2.2 * p)) * 7 : 0) + size / 2);
      ctx.rotate(((alive ? 5 * Math.sin(t * 1.7 * p) : 18) * Math.PI) / 180);
      const breath = 1 + 0.045 * Math.sin(t * 3.1 * p);
      ctx.scale(2 - breath, breath);
      ctx.globalAlpha = b.status === "defeated" ? 0.35 : 1;
      if (b.status === "defeated") ctx.filter = "grayscale(1)";
      const img = monsterEl.current;
      if (img.complete && img.naturalWidth) {
        const k = Math.min(size / img.naturalWidth, size / img.naturalHeight), iw = img.naturalWidth * k, ih = img.naturalHeight * k;
        ctx.drawImage(img, -iw / 2, -ih, iw, ih);
        if (hitNow) { ctx.globalCompositeOperation = "source-atop"; ctx.fillStyle = "rgba(255,60,60,.45)"; ctx.fillRect(-iw / 2, -ih, iw, ih); }
      }
      ctx.restore();
      // bullets and hits
      const shipY = H - 56;
      for (const bl of s.bullets) {
        const k = (now - bl.t0) / FLIGHT;
        if (bl.hit && k >= 1) {
          const e = (now - bl.t0 - FLIGHT) / 500; if (e >= 1) continue;
          const hx = monsterX((bl.t0 + FLIGHT - start.current) / 1000) * W, r = 8 + 18 * e;
          ctx.fillStyle = `rgba(249,115,22,${0.7 * (1 - e)})`; ctx.beginPath(); ctx.arc(hx, my, r, 0, Math.PI * 2); ctx.fill();
          ctx.fillStyle = `rgba(250,204,21,${1 - e})`; ctx.font = "800 18px system-ui"; ctx.fillText("-1", hx + 18, my - 20 - 30 * e);
          continue;
        }
        const y = shipY - 30 - (shipY - my) * k; if (y < -20) continue;
        const g = ctx.createLinearGradient(0, y - 9, 0, y + 9); g.addColorStop(0, "#FDE047"); g.addColorStop(1, "#F97316");
        ctx.fillStyle = g; ctx.fillRect(bl.x * W - 2.5, y - 9, 5, 18);
      }
      s.bullets = s.bullets.filter((x) => now - x.t0 < 2500);
      // the jet
      if (shipEl.current.complete) { ctx.save(); ctx.translate(s.shipX * W, shipY); ctx.rotate(((s.shipX - 0.5) * 10 * Math.PI) / 180); ctx.drawImage(shipEl.current, -48, -48, 96, 96); ctx.restore(); }
    }
    return stop;
  });

  if (!b) return null;
  const task = fc.taskFor(b), subject = task?.categoryID ? categoryLabel(data, task.categoryID) : undefined;
  const pending = s0.hits + s0.flyHits;
  const people = (fc.fighters[b.id] ?? []).filter((x) => x.damage > 0).sort((a, c) => c.damage - a.damage);
  const total = Math.max(1, people.reduce((a, x) => a + x.damage, 0) + pending);
  const pool = prizeOf(b);
  return (
    <div className="modal-bg" onMouseDown={onClose}>
      <div className="modal" style={{ width: 800, padding: 0, background: "#070B1A", color: "white", overflow: "hidden" }} onMouseDown={(e) => e.stopPropagation()}>
        <div style={{ padding: 16 }}>
          <div className="row"><h2 style={{ margin: 0 }}>{b.title}</h2>{!isWorld(b) && <span className="badge" style={{ background: "#DC262660" }}>LV {b.monster}</span>}<span className="spacer" />
            <span className="small" style={{ opacity: 0.7 }}>{b.status === "defeated" ? "Defeated 🏆" : b.status === "escaped" ? "Escaped 💨" : `Escapes ${rel(new Date(b.deadline))}`}</span>
            <button className="btn small primary" onClick={onClose}>Done</button></div>
          <div className="row" style={{ marginTop: 8 }}>❤️<div className="progress" style={{ flex: 1 }}><div style={{ width: `${(left / b.hp) * 100}%`, background: "#DC2626" }} /></div><b>{left} / {b.hp}</b></div>
        </div>
        <div className="space" style={{ height: H, borderRadius: 0 }}><canvas ref={cv} style={{ width: W, height: H, display: "block", margin: "0 auto" }} />
          {b.status === "alive" && ammo === 0 && <div style={{ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%,-50%)", background: "rgba(0,0,0,.6)", padding: "6px 12px", borderRadius: 99, fontWeight: 600 }}>Out of bullets — study to reload 📚</div>}</div>
        <div className="row" style={{ padding: 16, alignItems: "flex-start", gap: 20 }}>
          <div style={{ flex: 1 }}>
            <div className="row" style={{ gap: 6 }}><span>⚡</span><b>{ammo} bullets</b><span className="small" style={{ opacity: 0.6 }}>· 1 per minute {subject ? `of ${subject}` : "studied"} since it appeared</span></div>
            <div style={{ display: "flex", gap: 2, margin: "6px 0" }}>{Array.from({ length: 30 }, (_, i) => <span key={i} style={{ width: 5, height: 16, borderRadius: 3, background: i < Math.min(30, ammo) ? "#FACC15" : "rgba(255,255,255,.1)" }} />)}
              {ammo > 30 && <span className="small" style={{ opacity: 0.6 }}>+{ammo - 30}</span>}</div>
            <div className="small" style={{ opacity: 0.6 }}>{b.status === "alive" ? "Hold ← → (or A D) to fly · Space to fire (hold for rapid fire) · only hits count" : "This fight is over."}</div>
            {fc.error && <div className="small" style={{ color: "#ef4444" }}>{fc.error}</div>}
          </div>
          <div style={{ width: 240 }}>
            <div className="small" style={{ fontWeight: 700, opacity: 0.7 }}>Damage · prize {pool} <RocketIcon size={13} /></div>
            {!people.length && !pending && <div className="small" style={{ opacity: 0.5 }}>No hits yet</div>}
            {people.slice(0, 5).map((x) => { const isMe = x.user_id === fc.me, dmg = x.damage + (isMe ? pending : 0);
              return <div key={x.user_id} className="row small"><span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{isMe ? "You" : f.people[x.user_id]?.profile.name ?? fc.names[x.user_id] ?? "Member"}</span><span className="spacer" /><span style={{ opacity: 0.7 }}>{dmg} · ~{Math.floor(pool * dmg / total)} 🚀</span></div>; })}
          </div>
        </div>
      </div>
    </div>
  );
}
