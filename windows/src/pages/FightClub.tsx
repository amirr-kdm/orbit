import { useEffect, useMemo, useRef, useState } from "react";
import { Avatar, Modal } from "../components";
import { dayNum, monthNum, yearNum } from "../lib/dates";
import { Boss, bossLevel, bossPool, useFightClub } from "../lib/fightclub";
import { useFriends } from "../lib/friends";
import { RocketIcon } from "./Store";
import m1 from "../assets/boss1.png";
import m2 from "../assets/boss2.png";
import m3 from "../assets/boss3.png";
import m4 from "../assets/boss4.png";
import m5 from "../assets/boss5.png";
import fighter from "../assets/fighter.png";

const MONSTERS = [m1, m2, m3, m4, m5];
export const monsterImg = (n: number) => MONSTERS[Math.min(5, Math.max(1, n)) - 1];
const hm = (m: number) => { const h = Math.floor(m / 60), r = m % 60; return h === 0 ? `${r}m` : r === 0 ? `${h}h` : `${h}h ${r}m`; };
const rel = (d: Date) => {
  const m = Math.round((d.getTime() - Date.now()) / 60000), a = Math.abs(m);
  const t = a < 60 ? `${a}m` : a < 1440 ? `${Math.round(a / 60)}h` : `${Math.round(a / 1440)}d`;
  return m >= 0 ? `in ${t}` : `${t} ago`;
};
const persianDate = (d: Date) => d.toLocaleDateString("en-US-u-ca-persian", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
const persianShort = (d: Date) => `${d.toLocaleDateString("en-US-u-ca-persian", { weekday: "long", day: "numeric", month: "long" })} · ${d.toTimeString().slice(0, 5)}`;

export default function FightClubPage() {
  const fc = useFightClub();
  const f = useFriends();
  const [summoning, setSummoning] = useState(false);
  const [battle, setBattle] = useState<string | null>(null);
  useEffect(() => { fc.load(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const mine = fc.bosses.filter((b) => (fc.fighters[b.id] ?? []).some((x) => x.user_id === fc.me));
  const invites = fc.invites.filter((i) => i.user_id === fc.me);

  return (
    <div className="page">
      <div className="row" style={{ gap: 14 }}>
        <img src={m5} alt="" style={{ width: 76 }} />
        <div style={{ flex: 1 }}><h1 style={{ margin: 0 }}>Fight Club</h1>
          <div className="muted">Summon a monster for a study goal. Study to earn bullets, fire them from your ship, and share the rockets when it falls.</div></div>
        <img src={fighter} alt="" style={{ width: 70 }} />
      </div>

      {invites.length > 0 && (
        <div className="card">
          <h3>✉️ Invitations</h3>
          {invites.map((i) => {
            const b = fc.bosses.find((x) => x.id === i.boss_id); if (!b) return null;
            return (
              <div key={i.boss_id} className="row" style={{ gap: 12, padding: "6px 0" }}>
                <img src={monsterImg(b.monster)} alt="" style={{ width: 44 }} />
                <div style={{ flex: 1 }}>
                  <b>{f.people[i.from_user]?.profile.name ?? "A friend"} invites you to fight “{b.title}”</b>
                  <div className="small muted">LV {b.monster} · {hm(b.hp)} of health · {bossPool(b.hp)} 🚀 prize · due {rel(new Date(b.deadline))}</div>
                </div>
                <button className="btn" disabled={fc.busy} onClick={() => fc.answer(b.id, false)}>Decline</button>
                <button className="btn primary" style={{ background: "#DC2626" }} disabled={fc.busy} onClick={() => fc.answer(b.id, true)}>Join the Fight</button>
              </div>
            );
          })}
        </div>
      )}

      <div className="card">
        <div className="row"><h3 style={{ margin: 0 }}>💥 Your fights</h3><span className="spacer" />
          <button className="btn primary" style={{ background: "#DC2626" }} onClick={() => { fc.setError(null); setSummoning(true); }}>＋ Summon monster</button></div>
        <div className="small muted" style={{ margin: "4px 0 10px" }}>Set a goal and a monster appears. Fight alone or invite friends or a whole group. Every minute you study is a bullet.</div>
        {!mine.length && <div className="muted">No monsters yet — summon one!</div>}
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {mine.map((b) => {
            const left = fc.healthLeft(b);
            return (
              <div key={b.id} className="row" style={{ gap: 12, padding: 10, borderRadius: 12, cursor: "pointer", background: "color-mix(in srgb, var(--text) 5%, transparent)" }}
                onClick={() => setBattle(b.id)}
                onContextMenu={(e) => { e.preventDefault(); if (b.creator === fc.me && confirm(`Delete “${b.title}”? It disappears for everyone fighting it.`)) fc.remove(b); }}>
                <img src={monsterImg(b.monster)} alt="" style={{ width: 54, filter: b.status === "alive" ? undefined : "grayscale(1)" }} />
                <div style={{ flex: 1 }}>
                  <div className="row"><b>{b.title}</b><span className="badge" style={{ background: "#DC262640", color: "inherit" }}>LV {b.monster}</span>
                    <span className="small muted">{b.status === "defeated" ? "Defeated 🏆" : b.status === "escaped" ? "Escaped 💨" : `Due ${rel(new Date(b.deadline))}`}</span>
                    <span className="spacer" /><span className="small muted">👥 {(fc.fighters[b.id] ?? []).length}</span></div>
                  <div className="progress" style={{ margin: "6px 0" }}><div style={{ width: `${(left / b.hp) * 100}%`, background: "#DC2626" }} /></div>
                  <div className="small muted">{hm(left)} of {hm(b.hp)} health left · {bossPool(b.hp)} 🚀 prize</div>
                </div>
                <span className="muted">›</span>
              </div>
            );
          })}
        </div>
        {fc.error && <div className="small" style={{ color: "#ef4444", marginTop: 6 }}>{fc.error}</div>}
      </div>

      {summoning && <SummonModal onClose={() => setSummoning(false)} onCreated={(id) => { setSummoning(false); setBattle(id); }} />}
      {battle && <Battle bossID={battle} onClose={() => setBattle(null)} />}
    </div>
  );
}

/** Tap friends' avatars and whole groups */
function InvitePicker({ friends, groups, setFriends, setGroups, taken = [] }: {
  friends: string[]; groups: string[]; setFriends: (v: string[]) => void; setGroups: (v: string[]) => void; taken?: string[];
}) {
  const f = useFriends();
  const toggle = (list: string[], id: string) => (list.includes(id) ? list.filter((x) => x !== id) : [...list, id]);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      {!f.friends.length && !f.groups.length && <div className="small muted">Add friends or join a group to fight together — or just fight alone.</div>}
      {f.friends.length > 0 && <><div className="small muted" style={{ fontWeight: 700 }}>FRIENDS</div>
        <div className="row" style={{ flexWrap: "wrap", gap: 8 }}>
          {f.friends.map((x) => {
            const on = friends.includes(x.profile.id), done = taken.includes(x.profile.id);
            return (
              <button key={x.profile.id} disabled={done} onClick={() => setFriends(toggle(friends, x.profile.id))}
                style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4, padding: 6, borderRadius: 10, border: "none", width: 76,
                  background: on ? "rgba(220,38,38,.18)" : "transparent", opacity: done ? 0.5 : 1, color: "inherit" }}>
                <span style={{ position: "relative" }}><Avatar name={x.profile.name} planet={x.profile.avatar} size={40} />
                  {(on || done) && <span style={{ position: "absolute", right: -4, bottom: -4 }}>✅</span>}</span>
                <span className="small" style={{ maxWidth: 70, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{x.profile.name}</span>
                {done && <span className="small muted">already in</span>}
              </button>
            );
          })}
        </div></>}
      {f.groups.length > 0 && <><div className="small muted" style={{ fontWeight: 700 }}>WHOLE GROUP</div>
        <div className="row" style={{ flexWrap: "wrap", gap: 8 }}>
          {f.groups.map((g) => {
            const on = groups.includes(g.id);
            return <button key={g.id} className="btn" onClick={() => setGroups(toggle(groups, g.id))}
              style={{ borderRadius: 99, background: on ? "rgba(220,38,38,.25)" : undefined }}>{on ? "✓" : "👥"} {g.name} · {g.members.length}</button>;
          })}
        </div></>}
    </div>
  );
}

type Due = "tonight" | "tomorrow" | "days3" | "week" | "custom";
const TIMES: [string, number, number][] = [["Noon", 12, 0], ["6 PM", 18, 0], ["9 PM", 21, 0], ["Midnight", 23, 59]];

/** Next ~420 days with their Persian date — year → month → day pickers come from this */
function usePersianDays() {
  return useMemo(() => {
    const out: { date: Date; y: number; m: number; d: number }[] = [];
    const t = new Date(); t.setHours(0, 0, 0, 0);
    for (let i = 0; i < 420; i++) { const d = new Date(t); d.setDate(t.getDate() + i); out.push({ date: d, y: yearNum(d, "persian"), m: monthNum(d, "persian"), d: dayNum(d, "persian") }); }
    return out;
  }, []);
}
const MONTHS = ["Farvardin", "Ordibehesht", "Khordad", "Tir", "Mordad", "Shahrivar", "Mehr", "Aban", "Azar", "Dey", "Bahman", "Esfand"];

function SummonModal({ onClose, onCreated }: { onClose: () => void; onCreated: (id: string) => void }) {
  const fc = useFightClub();
  const days = usePersianDays();
  const [title, setTitle] = useState("");
  const [hours, setHours] = useState(5);
  const [due, setDue] = useState<Due>("days3");
  const [pick, setPick] = useState(() => days[5]);
  const [time, setTime] = useState<[number, number]>([23, 59]);
  const [customTime, setCustomTime] = useState(false);
  const [friends, setFriends] = useState<string[]>([]);
  const [groups, setGroups] = useState<string[]>([]);

  const deadline = useMemo(() => {
    const now = new Date(), tonight = new Date(); tonight.setHours(23, 59, 0, 0);
    const plus = (n: number) => new Date(tonight.getTime() + n * 86400_000);
    if (due === "tonight") return now.getTime() + 7200_000 > tonight.getTime() ? plus(1) : tonight;
    if (due === "tomorrow") return plus(1);
    if (due === "days3") return plus(3);
    if (due === "week") return plus(7);
    const d = new Date(pick.date); d.setHours(time[0], time[1], 0, 0); return d;
  }, [due, pick, time]);
  const tooSoon = deadline.getTime() < Date.now() + 1800_000;
  const level = bossLevel(hours * 60), pool = bossPool(hours * 60);
  const years = [...new Set(days.map((x) => x.y))];
  const months = [...new Set(days.filter((x) => x.y === pick.y).map((x) => x.m))];
  const dayList = days.filter((x) => x.y === pick.y && x.m === pick.m);
  const choose = (y: number, m: number, d: number) => setPick(days.find((x) => x.y === y && x.m === m && x.d === d) ?? days.find((x) => x.y === y && x.m === m) ?? days.find((x) => x.y === y) ?? days[0]);
  const preset = TIMES.find((t) => t[1] === time[0] && t[2] === time[1]);

  return (
    <Modal onClose={onClose} width={620}>
      <h3 style={{ marginTop: 0 }}>💥 Summon a monster</h3>
      <div className="row" style={{ alignItems: "flex-start", gap: 18 }}>
        <div style={{ width: 150, textAlign: "center" }}>
          <img src={monsterImg(level)} alt="" style={{ width: 70 + level * 14 }} />
          <div><span className="badge" style={{ background: "#DC262640", color: "inherit" }}>Level {level}</span></div>
          <div className="small" style={{ fontWeight: 600, marginTop: 4 }}>{pool} 🚀 prize</div>
        </div>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 10 }}>
          <input placeholder="Goal, e.g. Finish chapter 5" value={title} onChange={(e) => setTitle(e.target.value)} />
          <div className="small muted" style={{ fontWeight: 700 }}>HOW MUCH STUDY</div>
          <div className="row" style={{ gap: 6 }}>
            {[2, 5, 10, 20].map((h) => <button key={h} className="btn small" style={{ background: hours === h ? "#DC2626" : undefined, color: hours === h ? "white" : undefined }} onClick={() => setHours(h)}>{h}h</button>)}
            <b style={{ width: 70, textAlign: "right" }}>{hm(Math.round(hours * 60))}</b>
            <input type="number" min={0.5} max={100} step={0.5} value={hours} onChange={(e) => setHours(Math.max(0.5, +e.target.value))} style={{ width: 64 }} />
          </div>
          <div className="small muted" style={{ fontWeight: 700 }}>DEADLINE</div>
          <div className="seg">{([["tonight", "Tonight"], ["tomorrow", "Tomorrow"], ["days3", "3 days"], ["week", "A week"], ["custom", "Pick…"]] as [Due, string][]).map(([k, t]) =>
            <button key={k} className={due === k ? "on" : ""} onClick={() => setDue(k)}>{t}</button>)}</div>
          {due === "custom" && <>
            <div className="small muted">📅 Today is {persianDate(new Date())}</div>
            <div className="row" style={{ gap: 6 }}>
              <select value={pick.y} onChange={(e) => choose(+e.target.value, pick.m, pick.d)}>{years.map((y) => <option key={y} value={y}>{y}</option>)}</select>
              <select value={pick.m} onChange={(e) => choose(pick.y, +e.target.value, pick.d)}>{months.map((m) => <option key={m} value={m}>{m} · {MONTHS[m - 1]}</option>)}</select>
              <select value={pick.d} onChange={(e) => choose(pick.y, pick.m, +e.target.value)}>{dayList.map((x) => <option key={x.d} value={x.d}>{x.d}</option>)}</select>
            </div>
            <div className="row" style={{ gap: 6 }}>
              {TIMES.map(([t, h, m]) => { const on = !customTime && preset?.[0] === t;
                return <button key={t} className="btn small" style={{ background: on ? "#DC2626" : undefined, color: on ? "white" : undefined }} onClick={() => { setCustomTime(false); setTime([h, m]); }}>{t}</button>; })}
              <button className="btn small" style={{ background: customTime || !preset ? "#DC2626" : undefined, color: customTime || !preset ? "white" : undefined }} onClick={() => setCustomTime(true)}>Custom</button>
            </div>
            {(customTime || !preset) && <div className="row" style={{ gap: 6 }}>Time
              <select value={time[0]} onChange={(e) => setTime([+e.target.value, time[1]])}>{Array.from({ length: 24 }, (_, i) => <option key={i} value={i}>{String(i).padStart(2, "0")}</option>)}</select>:
              <select value={time[1]} onChange={(e) => setTime([time[0], +e.target.value])}>{Array.from({ length: 12 }, (_, i) => i * 5).concat(time[1] % 5 ? [time[1]] : []).map((m) => <option key={m} value={m}>{String(m).padStart(2, "0")}</option>)}</select></div>}
          </>}
          <div className="small muted">Escapes {persianShort(deadline)} · {rel(deadline)}</div>
          {tooSoon && <div className="small" style={{ color: "#ef4444" }}>That's too soon — pick a time at least 30 minutes from now.</div>}
        </div>
      </div>
      <hr style={{ border: "none", borderTop: "1px solid var(--line)", margin: "14px 0" }} />
      <b>{friends.length || groups.length ? "Invites go out when you summon" : "Fight alone, or tap friends and groups to invite them"}</b>
      <div style={{ marginTop: 8 }}><InvitePicker friends={friends} groups={groups} setFriends={setFriends} setGroups={setGroups} /></div>
      <div className="small muted" style={{ marginTop: 10 }}>Each minute studied after it appears is one bullet. Only hits count. If the deadline comes first, it escapes and nobody wins.</div>
      {fc.error && <div className="small" style={{ color: "#ef4444" }}>{fc.error}</div>}
      <div className="row" style={{ marginTop: 12 }}><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" style={{ background: "#DC2626" }} disabled={fc.busy || tooSoon} onClick={async () => {
          const id = await fc.create(title || "Study goal", Math.round(hours * 60), deadline);
          if (!id) return;
          await fc.load();
          if (friends.length || groups.length) await fc.sendInvites({ id } as Boss, friends, groups);
          onCreated(id);
        }}>{friends.length || groups.length ? "Summon & Invite" : "Summon & Fight Alone"}</button></div>
    </Modal>
  );
}

function InviteModal({ boss, onClose }: { boss: Boss; onClose: () => void }) {
  const fc = useFightClub();
  const [friends, setFriends] = useState<string[]>([]);
  const [groups, setGroups] = useState<string[]>([]);
  const taken = [...(fc.fighters[boss.id] ?? []).map((x) => x.user_id), ...fc.invites.filter((i) => i.boss_id === boss.id).map((i) => i.user_id)];
  return (
    <Modal onClose={onClose} width={480}>
      <h3 style={{ marginTop: 0 }}>Invite to fight “{boss.title}”</h3>
      <InvitePicker friends={friends} groups={groups} setFriends={setFriends} setGroups={setGroups} taken={taken} />
      <div className="row" style={{ marginTop: 12 }}><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" style={{ background: "#DC2626" }} disabled={fc.busy || (!friends.length && !groups.length)} onClick={async () => { await fc.sendInvites(boss, friends, groups); onClose(); }}>Send invites</button></div>
    </Modal>
  );
}

const FLIGHT = 550; // ms from ship to monster height

/** The fight: a living monster drifts and dodges; hold ← → (or A D) to fly, Space to fire. Only hits count. */
function Battle({ bossID, onClose }: { bossID: string; onClose: () => void }) {
  const fc = useFightClub();
  const f = useFriends();
  const b = fc.bosses.find((x) => x.id === bossID);
  const cv = useRef<HTMLCanvasElement>(null);
  const state = useRef({ shipX: 0.5, left: false, right: false, bullets: [] as { x: number; t0: number; hit: boolean }[], shots: 0, hits: 0, last: 0 });
  const [, force] = useState(0);
  const [inviting, setInviting] = useState(false);
  const start = useRef(performance.now());
  const monsterEl = useRef(new Image());
  const shipEl = useRef(new Image());
  useEffect(() => { shipEl.current.src = fighter; }, []);
  useEffect(() => { if (b) monsterEl.current.src = monsterImg(b.monster); }, [b?.monster]); // eslint-disable-line react-hooks/exhaustive-deps

  const W = 760, H = 420;
  const left = b ? Math.max(0, fc.healthLeft(b) - state.current.hits) : 0;
  const ammo = b ? Math.max(0, fc.ammo(b) - state.current.shots) : 0;
  const size = b ? Math.min(H * 0.5, 120 + b.monster * 18) : 120;
  const pace = () => (b ? 0.55 + 0.12 * b.monster + 0.9 * (1 - left / Math.max(1, b.hp)) : 1);
  const monsterX = (t: number) => { const p = pace(); return 0.5 + (Math.sin(t * p) * 0.7 + Math.sin(t * p * 2.3 + 1.1) * 0.25 + Math.sin(t * p * 0.37 + 2) * 0.2) * 0.33; };

  // keyboard
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      const s = state.current;
      if (e.key === "ArrowLeft" || e.key === "a") s.left = true;
      if (e.key === "ArrowRight" || e.key === "d") s.right = true;
      if (e.key === " ") { e.preventDefault(); shoot(); }
    };
    const up = (e: KeyboardEvent) => { if (e.key === "ArrowLeft" || e.key === "a") state.current.left = false; if (e.key === "ArrowRight" || e.key === "d") state.current.right = false; };
    window.addEventListener("keydown", down); window.addEventListener("keyup", up);
    return () => { window.removeEventListener("keydown", down); window.removeEventListener("keyup", up); };
  });

  const shoot = () => {
    if (!b || b.status !== "alive" || ammo <= 0 || left <= 0) return;
    const s = state.current, now = performance.now();
    if (now - s.last < 120) return;
    s.last = now;
    const t = (now - start.current) / 1000;
    const target = monsterX(t + FLIGHT / 1000) * W;
    const hit = Math.abs(s.shipX * W - target) < size * 0.32;
    s.bullets.push({ x: s.shipX, t0: now, hit });
    s.shots++; if (hit) s.hits++;
    force((n) => n + 1);
  };

  // send what was fired every 1.2 s (and when closing)
  useEffect(() => {
    const flush = async () => {
      const s = state.current; if (!b || !s.shots) return;
      const shots = s.shots, hits = s.hits; s.shots = 0; s.hits = 0;
      await fc.fire(b, shots, hits); force((n) => n + 1);
    };
    const t = setInterval(flush, 1200);
    return () => { clearInterval(t); flush(); };
  }, [b?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // draw loop
  useEffect(() => {
    let raf = 0;
    const draw = (now: number) => {
      raf = requestAnimationFrame(draw);
      const c = cv.current; if (!c || !b) return;
      const s = state.current, ctx = c.getContext("2d")!, dpr = devicePixelRatio || 1;
      if (c.width !== W * dpr) { c.width = W * dpr; c.height = H * dpr; }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
      const dir = (s.right ? 1 : 0) - (s.left ? 1 : 0);
      if (dir) s.shipX = Math.min(0.96, Math.max(0.04, s.shipX + dir * 0.011));
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
      if (monsterEl.current.complete) ctx.drawImage(monsterEl.current, -size / 2, -size, size, size);
      if (hitNow) { ctx.globalCompositeOperation = "source-atop"; ctx.fillStyle = "rgba(255,60,60,.45)"; ctx.fillRect(-size / 2, -size, size, size); }
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
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  });

  if (!b) return null;
  const people = (fc.fighters[b.id] ?? []).filter((x) => x.damage > 0).sort((a, c) => c.damage - a.damage);
  const total = Math.max(1, people.reduce((a, x) => a + x.damage, 0) + state.current.hits);
  const pool = bossPool(b.hp);
  return (
    <div className="modal-bg" onMouseDown={onClose}>
      <div className="modal" style={{ width: 800, padding: 0, background: "#070B1A", color: "white", overflow: "hidden" }} onMouseDown={(e) => e.stopPropagation()}>
        <div style={{ padding: 16 }}>
          <div className="row"><h2 style={{ margin: 0 }}>{b.title}</h2><span className="badge" style={{ background: "#DC262660" }}>LV {b.monster}</span><span className="spacer" />
            <span className="small" style={{ opacity: 0.7 }}>{b.status === "defeated" ? "Defeated 🏆" : b.status === "escaped" ? "Escaped 💨" : `Escapes ${rel(new Date(b.deadline))}`}</span>
            {b.status === "alive" && <button className="btn small" onClick={() => setInviting(true)}>👤＋ Invite</button>}
            {b.creator === fc.me && <button className="btn small danger" title="Delete this monster" onClick={() => { if (confirm(`Delete “${b.title}”? It disappears for everyone fighting it.`)) { fc.remove(b); onClose(); } }}>🗑</button>}
            <button className="btn small primary" onClick={onClose}>Done</button></div>
          <div className="row" style={{ marginTop: 8 }}>❤️<div className="progress" style={{ flex: 1 }}><div style={{ width: `${(left / b.hp) * 100}%`, background: "#DC2626" }} /></div><b>{left} / {b.hp}</b></div>
        </div>
        <div className="space" style={{ height: H, borderRadius: 0 }}><canvas ref={cv} style={{ width: W, height: H, display: "block", margin: "0 auto" }} />
          {b.status === "alive" && ammo === 0 && <div style={{ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%,-50%)", background: "rgba(0,0,0,.6)", padding: "6px 12px", borderRadius: 99, fontWeight: 600 }}>Out of bullets — study to reload 📚</div>}</div>
        <div className="row" style={{ padding: 16, alignItems: "flex-start", gap: 20 }}>
          <div style={{ flex: 1 }}>
            <div className="row" style={{ gap: 6 }}><span>⚡</span><b>{ammo} bullets</b><span className="small" style={{ opacity: 0.6 }}>· 1 per minute studied since it appeared</span></div>
            <div style={{ display: "flex", gap: 2, margin: "6px 0" }}>{Array.from({ length: 30 }, (_, i) => <span key={i} style={{ width: 5, height: 16, borderRadius: 3, background: i < Math.min(30, ammo) ? "#FACC15" : "rgba(255,255,255,.1)" }} />)}
              {ammo > 30 && <span className="small" style={{ opacity: 0.6 }}>+{ammo - 30}</span>}</div>
            <div className="small" style={{ opacity: 0.6 }}>{b.status === "alive" ? "Hold ← → (or A D) to fly · Space to fire (hold for rapid fire) · only hits count" : "This fight is over."}</div>
            {fc.error && <div className="small" style={{ color: "#ef4444" }}>{fc.error}</div>}
          </div>
          <div style={{ width: 240 }}>
            <div className="small" style={{ fontWeight: 700, opacity: 0.7 }}>Damage · prize {pool} <RocketIcon size={13} /></div>
            {!people.length && !state.current.hits && <div className="small" style={{ opacity: 0.5 }}>No hits yet</div>}
            {people.slice(0, 5).map((x) => { const isMe = x.user_id === fc.me, dmg = x.damage + (isMe ? state.current.hits : 0);
              return <div key={x.user_id} className="row small"><span>{isMe ? "You" : f.people[x.user_id]?.profile.name ?? "Member"}</span><span className="spacer" /><span style={{ opacity: 0.7 }}>{dmg} · ~{Math.floor(pool * dmg / total)} 🚀</span></div>; })}
          </div>
        </div>
        {inviting && <InviteModal boss={b} onClose={() => setInviting(false)} />}
      </div>
    </div>
  );
}
