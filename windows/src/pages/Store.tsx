import { useState } from "react";
import { useNav } from "../App";
import { Modal, PlanetCanvas } from "../components";
import { PlanetDef } from "../lib/planets";
import { RARITY_COLOR, Rarity, rarityOf, STORE } from "../lib/storePlanets";
import {
  BONUS_TIERS, GROUP_WIN_ROCKETS, ownedCount, placedCount, progress, REFUND_TICKETS, ROCKETS_PER_HOUR, unplacedCount,
  useStore, wallet, weekBonuses, weeklyBonus,
} from "../lib/store";
import rocketIcon from "../assets/rocket.png";

export const RocketIcon = ({ size = 18 }: { size?: number }) => (
  <img src={rocketIcon} alt="rockets" style={{ width: size, height: size, borderRadius: size * 0.22, imageRendering: "pixelated", verticalAlign: "middle" }} />
);

const RARITIES: Rarity[] = ["common", "rare", "epic", "legendary"];
const cap = (s: string) => s[0].toUpperCase() + s.slice(1);

function RarityChip({ p }: { p: PlanetDef }) {
  const r = rarityOf(p.price!);
  return <span className="chip" style={{ background: `${RARITY_COLOR[r]}40`, color: RARITY_COLOR[r], fontWeight: 800, letterSpacing: 1, fontSize: 9 }}>{r.toUpperCase()}</span>;
}

/** The planet store: spend rockets earned by studying */
export default function StorePage() {
  const { data } = useStore();
  const [rarity, setRarity] = useState<Rarity | "">("");
  const [opened, setOpened] = useState<PlanetDef | null>(null);
  const w = wallet(data);
  const week = progress(data).weekHours;
  const next = [10, 15, 20, 25, 30, 30.01].find((h) => week < h);
  const last = weekBonuses(data).slice(-1)[0];
  const items = STORE.filter((p) => !rarity || rarityOf(p.price!) === rarity);

  return (
    <div className="page">
      <div className="card row" style={{ background: "linear-gradient(135deg,#1E1B4B,#0F172A)", color: "white", gap: 20, alignItems: "flex-start", padding: 20 }}>
        <RocketIcon size={64} />
        <div style={{ flex: 1 }}>
          <div className="small" style={{ opacity: 0.7, fontWeight: 600 }}>Your rockets</div>
          <div className="row" style={{ gap: 6 }}><span style={{ fontSize: 38, fontWeight: 900 }}>{w.balance.toLocaleString()}</span><RocketIcon size={22} /></div>
          <div className="small" style={{ opacity: 0.7 }}>{w.study} from study · {w.bonuses} weekly bonuses · {w.groups} group wins · {w.spent} spent</div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
          <b>🕐 {ROCKETS_PER_HOUR} rockets for every hour you study</b>
          <div className="small" style={{ opacity: 0.7 }}>Weekly bonus when Friday ends:</div>
          <div className="row" style={{ gap: 5 }}>
            {BONUS_TIERS.map(([h, r]) => <div key={h} style={{ background: "rgba(255,255,255,.08)", borderRadius: 7, padding: "3px 7px", textAlign: "center", fontSize: 11 }}><b>{h}</b><br />+{r}</div>)}
          </div>
          <div className="small" style={{ opacity: 0.7 }}>
            This week: {week.toFixed(1)}h{next ? (next > 30 ? " · study past 30h for +200" : ` · ${(next - week).toFixed(1)}h more for +${weeklyBonus(next)}`) : " · top bonus reached 🎉"}{last ? ` · last week +${last.rockets}` : ""}
            <br />+{GROUP_WIN_ROCKETS} for every group where you studied the most that week
          </div>
        </div>
      </div>

      <div className="row">
        <h2 style={{ margin: 0 }}>Planet Store</h2><span className="spacer" />
        <div className="seg">
          <button className={!rarity ? "on" : ""} onClick={() => setRarity("")}>All</button>
          {RARITIES.map((r) => <button key={r} className={rarity === r ? "on" : ""} onClick={() => setRarity(r)}>{cap(r)}</button>)}
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))", gap: 14 }}>
        {items.map((p) => {
          const r = rarityOf(p.price!), owned = ownedCount(data, p.id);
          return (
            <div key={p.id} className="store-card" style={{ borderColor: `${RARITY_COLOR[r]}66`, background: `radial-gradient(circle at top, ${RARITY_COLOR[r]}38, #0B1020 70%)` }} onClick={() => setOpened(p)}>
              {owned > 0 && <span className="count" style={{ background: "#22C55E" }}>Owned ×{owned}</span>}
              <PlanetCanvas planet={p} size={150} animate />
              <b>{p.name}</b>
              <div className="row" style={{ width: "100%" }}><RarityChip p={p} /><span className="spacer" />
                <span style={{ opacity: w.balance >= p.price! || owned ? 1 : 0.55 }}><RocketIcon size={15} /> <b>{p.price}</b></span></div>
            </div>
          );
        })}
      </div>
      {opened && <StoreDetail planet={opened} onClose={() => setOpened(null)} />}
    </div>
  );
}

function StoreDetail({ planet, onClose }: { planet: PlanetDef; onClose: () => void }) {
  const { data, actions } = useStore();
  const nav = useNav();
  const [msg, setMsg] = useState<string | null>(null);
  const w = wallet(data), owned = ownedCount(data, planet.id), left = REFUND_TICKETS - data.refundsUsed;
  const r = rarityOf(planet.price!);
  return (
    <Modal onClose={onClose} width={760}>
      <div className="row" style={{ alignItems: "flex-start", gap: 24 }}>
        <div style={{ background: `radial-gradient(circle, ${RARITY_COLOR[r]}55, transparent 70%)`, borderRadius: "50%" }}><PlanetCanvas planet={planet} size={260} animate /></div>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 10 }}>
          <div style={{ color: RARITY_COLOR[r], fontWeight: 900, letterSpacing: 1.5, fontSize: 12 }}>{r.toUpperCase()}</div>
          <h1 style={{ margin: 0 }}>{planet.name}</h1>
          <div className="muted">{planet.blurb}</div>
          <div className="row" style={{ gap: 6 }}><RocketIcon size={24} /><b style={{ fontSize: 22 }}>{planet.price}</b><span className="muted">· you have {w.balance}</span></div>
          {owned > 0 && <div style={{ color: "#22C55E" }}>✓ You own {owned}{unplacedCount(data, planet.id) ? ` · ${unplacedCount(data, planet.id)} not in your galaxy` : ""}</div>}
          <div className="row">
            <button className="btn primary" disabled={w.balance < planet.price!} onClick={() => { actions.buyPlanet(planet.id); setMsg(`${planet.name} is yours! 🎉 Place it from My Galaxy → Your Store Planets.`); }}>
              {w.balance >= planet.price! ? (owned ? "🛒 Buy another" : "🛒 Buy") : `🔒 Need ${planet.price! - w.balance} more`}</button>
            {owned > 0 && <>
              <button className="btn" onClick={() => { nav.go("galaxy"); onClose(); }}>Go to My Galaxy</button>
              <button className="btn" disabled={left <= 0} onClick={() => {
                if (confirm(`Refund ${planet.name} for ${planet.price} rockets? This uses 1 of your ${left} refund tickets. If it's in your galaxy, it's taken out.`)) {
                  actions.refund(planet.id); setMsg(`Refunded ${planet.price} rockets.`);
                }
              }}>🎟 Refund</button>
            </>}
          </div>
          <div className="small muted">🎟 {left} of {REFUND_TICKETS} refund tickets left · a refund returns the full price</div>
          {msg && <div style={{ color: "var(--accent)", fontWeight: 600 }}>{msg}</div>}
          <div className="row"><span className="spacer" /><button className="btn primary" onClick={onClose}>Done</button></div>
        </div>
      </div>
    </Modal>
  );
}

/** My Galaxy: planets bought in the Store wait here to be placed, moved or removed */
export function StoreShelf({ onToast }: { onToast: (t: string) => void }) {
  const { data, actions } = useStore();
  const [sel, setSel] = useState<string | null>(null);
  const [target, setTarget] = useState("");
  const owned = STORE.filter((p) => ownedCount(data, p.id) > 0);
  if (!owned.length) return null;
  const credits = progress(data).credits;
  const count = (sid: string) => data.galaxy.filter((g) => g.systemID === sid).length;
  const p = owned.find((x) => x.id === sel);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div className="row"><h2 style={{ margin: 0 }}>Your Store Planets</h2><RocketIcon size={20} /></div>
      <div className="row" style={{ gap: 12, flexWrap: "wrap" }}>
        {owned.map((x) => {
          const waiting = unplacedCount(data, x.id), placed = placedCount(data, x.id);
          return (
            <div key={x.id} className="planet-tile" style={{ width: 140, outline: sel === x.id ? "2.5px solid var(--accent)" : undefined, borderColor: `${RARITY_COLOR[rarityOf(x.price!)]}88` }}
              onClick={() => setSel(sel === x.id ? null : x.id)}>
              <PlanetCanvas planet={x} size={96} />
              <b className="small">{x.name}</b>
              <span className="small" style={{ opacity: 0.7 }}>{waiting ? `${waiting} waiting · ${placed} placed` : `All ${placed} placed`}</span>
              {data.avatarPlanet === x.id && <span className="small" style={{ color: "var(--accent)" }}>Profile</span>}
            </div>
          );
        })}
      </div>

      {p && (
        <div className="card row" style={{ alignItems: "flex-start", gap: 18, borderColor: "var(--accent)" }}>
          <div style={{ background: "#0b0d16", borderRadius: 16, padding: 6 }}><PlanetCanvas planet={p} size={130} animate /></div>
          <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 10 }}>
            <div className="row"><h2 style={{ margin: 0 }}>{p.name}</h2><RarityChip p={p} /></div>
            <div className="muted">{p.blurb}</div>
            {unplacedCount(data, p.id) > 0 && (
              <div className="row">
                <select value={target} onChange={(e) => setTarget(e.target.value)}>
                  <option value="">First system with room</option>
                  {data.solarSystems.map((s) => <option key={s.id} value={s.id}>{s.name} ({count(s.id)}/8)</option>)}
                </select>
                <button className="btn primary" disabled={!credits} onClick={() => { actions.placeOwned(p.id, target || undefined); onToast(`🎉 ${p.name} joined your galaxy!`); }}>
                  {credits ? `＋ Place (${unplacedCount(data, p.id)} waiting)` : `Reach level ${progress(data).level + 1} for a free spot`}</button>
              </div>
            )}
            {data.galaxy.filter((g) => g.planetID === p.id).map((copy) => (
              <div key={copy.id} className="row small">
                <span>☀️ In {data.solarSystems.find((s) => s.id === copy.systemID)?.name ?? "your galaxy"}</span>
                <select value="" disabled={data.solarSystems.length < 2} onChange={(e) => { if (e.target.value) { actions.movePlaced(copy.id, e.target.value); onToast(`${p.name} moved`); } }}>
                  <option value="">Move to…</option>
                  {data.solarSystems.filter((s) => s.id !== copy.systemID).map((s) => <option key={s.id} value={s.id} disabled={count(s.id) >= 8}>{s.name} ({count(s.id)}/8)</option>)}
                </select>
                <button className="btn small danger" onClick={() => { actions.removePlanet(copy.id); onToast(`${p.name} is back on your shelf`); }}>Remove</button>
              </div>
            ))}
            <button className="btn" style={{ alignSelf: "flex-start" }} disabled={data.avatarPlanet === p.id} onClick={() => actions.setAvatar(p.id)}>
              {data.avatarPlanet === p.id ? "✓ Your profile picture" : "Use as profile picture"}</button>
          </div>
          <button className="icon-btn" onClick={() => setSel(null)}>✕</button>
        </div>
      )}
      <div className="small muted">Click a planet to place, move or remove it. Placing uses one of your planet spots (one per level — {credits} free now).</div>
    </div>
  );
}
