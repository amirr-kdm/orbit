import { useState } from "react";
import { GalaxyLookButton, GalaxyMap, LevelBadge, PlanetCanvas } from "../components";
import { galaxyData, useFriends } from "../lib/friends";
import { SunType, SYSTEM_NAMES } from "../lib/model";
import { GROUP_TITLES, PLANETS, planetByID, SUNS, unlockLevel } from "../lib/planets";
import { canClaim, HOURS_PER_LEVEL, MAX_LEVEL, progress, useStore } from "../lib/store";
import LevelPass from "./LevelPass";
import { StoreShelf } from "./Store";

export default function Galaxy() {
  const { data, actions, update } = useStore();
  const friends = useFriends();
  const p = progress(data);
  const gd = galaxyData(data);
  const [focused, setFocused] = useState<string | null>(null);
  const back = () => setFocused(null);
  const [pass, setPass] = useState(false);
  const ready = Array.from({ length: p.level }, (_, i) => i + 1).filter((l) => canClaim(data, l)).length;
  const [selected, setSelected] = useState<string | null>(null);
  const [target, setTarget] = useState<string>();
  const [toast, setToast] = useState<string | null>(null);
  const sys = gd.systems.find((s) => s.id === focused);
  const avatar = planetByID(data.avatarPlanet);
  const unlockedCount = PLANETS.filter((x) => unlockLevel(x.group) <= p.level).length;
  const show = (t: string) => { setToast(t); setTimeout(() => setToast(null), 2500); };

  return (
    <div className="page">
      <div className="card row" style={{ gap: 18 }}>
        {/* same as the Mac app: a dark disc with the planet drawn on it at the same size (pictures may spill a little past the edge) */}
        <div style={{ position: "relative", width: 96, height: 96, flexShrink: 0, borderRadius: "50%", background: "rgba(0,0,0,.85)", display: "grid", placeItems: "center" }}>
          {avatar ? <div style={{ position: "absolute", inset: 0 }}><PlanetCanvas planet={avatar} size={96} animate /></div> : <span style={{ fontSize: 34 }}>🪐</span>}
        </div>
        <div style={{ flex: 1 }}>
          <div className="row"><h2 style={{ margin: 0 }}>{friends.me?.name ?? "You"}</h2><LevelBadge level={p.level} /><span className="spacer" />
            <button className="btn primary" style={{ background: ready ? "#F97316" : undefined }} onClick={() => setPass(true)}>🏁 Level Pass{ready ? ` · ${ready} to claim` : ""}</button></div>
          {p.level >= MAX_LEVEL ? <div className="muted">Max level reached — every planet is yours 🏆</div> : <>
            <div className="small muted" style={{ margin: "4px 0" }}>{Math.max(0, p.level * HOURS_PER_LEVEL - p.totalHours).toFixed(1)}h of study to level {p.level + 1} · every {HOURS_PER_LEVEL}h studied = +1 level</div>
            <div className="progress" style={{ maxWidth: 420 }}><div style={{ width: `${((p.totalHours - (p.level - 1) * HOURS_PER_LEVEL) / HOURS_PER_LEVEL) * 100}%` }} /></div></>}
          <div className="row small muted" style={{ marginTop: 6, gap: 16 }}>
            <span>🕐 {p.totalHours.toFixed(1)}h studied</span><span>🔓 {unlockedCount} of {PLANETS.length} planets unlocked</span>
            <span>☀️ {data.solarSystems.length} solar systems</span>
            <span style={{ color: p.credits ? "var(--accent)" : undefined }}>✨ {p.credits ? `${p.credits} planet${p.credits > 1 ? "s" : ""} ready to add` : `Next planet at level ${p.level + 1}`}</span>
          </div>
        </div>
      </div>

      <div style={{ position: "relative" }}>
        {/* One continuous map: opening a system is the camera zooming in on it */}
        <GalaxyMap data={gd} height={600} focused={focused} onSelect={setFocused} onMove={(id, x, y) => actions.moveSystem(id, x, y)} />
        <div style={{ position: "absolute", top: 16, left: 18, right: 18, display: "flex", alignItems: "flex-start", color: "white", pointerEvents: "none" }}>
          <div style={{ pointerEvents: "auto" }}>
            {sys ? <>
              <button className="btn small" onClick={back}>‹ Galaxy</button>
              <h2 style={{ margin: "6px 0 0" }}>{sys.name}</h2><div style={{ opacity: 0.75 }}>{SUNS[sys.sun].name} · {sys.planets.length}/8 planets</div>
            </> : <>
              <div className="small" style={{ fontWeight: 800, letterSpacing: 2, opacity: 0.7 }}>MY GALAXY</div>
              <h2 style={{ margin: 0 }}>{gd.systems.length} solar system{gd.systems.length > 1 ? "s" : ""} · {data.galaxy.length} planets</h2>
              <div style={{ opacity: 0.7 }}>Drag to explore · drag a system to move it · click one to fly in</div>
            </>}
          </div>
          <span className="spacer" />
          <div style={{ pointerEvents: "auto" }} className="row">
            <GalaxyLookButton />
            {sys ? <>
              <select value={sys.sun} onChange={(e) => actions.updateSystem(sys.id, (s) => { s.sun = e.target.value as SunType; })}>
                {Object.entries(SUNS).map(([k, v]) => <option key={k} value={k} disabled={v.level > p.level}>{v.name}{v.level > p.level ? ` — level ${v.level}` : ""}</option>)}
              </select>
              <select value={sys.name} onChange={(e) => actions.updateSystem(sys.id, (s) => { s.name = e.target.value; })}>{SYSTEM_NAMES.map((n) => <option key={n}>{n}</option>)}</select>
              {data.solarSystems.length > 1 && <button className="btn small danger" title="Delete this solar system" onClick={() => {
                const n = data.galaxy.filter((g) => g.systemID === sys.id).length;
                if (confirm(`Delete ${sys.name}?${n ? ` Its ${n} planet${n > 1 ? "s" : ""} move to your other systems.` : ""}`)) { actions.deleteSystem(sys.id); setFocused(null); }
              }}>🗑</button>}
            </> : (
              <select value="" onChange={(e) => { if (!e.target.value) return; const id = actions.createSystem(e.target.value as SunType); setTarget(id); setFocused(id); show("✨ A new solar system was born!"); }}>
                <option value="">＋ New solar system…</option>
                {Object.entries(SUNS).map(([k, v]) => <option key={k} value={k} disabled={v.level > p.level}>{v.name}{v.level > p.level ? ` — level ${v.level}` : ""}</option>)}
              </select>
            )}
          </div>
        </div>
        {toast && <div style={{ position: "absolute", bottom: 16, left: "50%", transform: "translateX(-50%)", background: "rgba(0,0,0,.6)", color: "white", padding: "8px 16px", borderRadius: 99, fontWeight: 600 }}>{toast}</div>}
      </div>

      {pass && <LevelPass onClose={() => setPass(false)} />}
      <StoreShelf onToast={show} />

      <div className="row"><h2 style={{ margin: 0 }}>Planet Collection</h2><span className="muted">{unlockedCount}/{PLANETS.length}</span></div>

      {selected && (() => {
        const pl = planetByID(selected)!; const unlocked = unlockLevel(pl.group) <= p.level;
        const count = (sid: string) => data.galaxy.filter((g) => g.systemID === sid).length;
        const tgt = data.solarSystems.find((s) => s.id === (target ?? focused)) ?? data.solarSystems.find((s) => count(s.id) < 8);
        const full = !tgt || count(tgt.id) >= 8;
        const last = [...data.galaxy].reverse().find((g) => g.planetID === pl.id);
        return (
          <div className="card row" style={{ gap: 18, borderColor: "var(--accent)" }}>
            <div style={{ background: "#0b0d16", borderRadius: 16, padding: 6 }}><PlanetCanvas planet={pl} size={140} animate locked={!unlocked} /></div>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 8 }}>
              <div className="row"><h2 style={{ margin: 0 }}>{pl.name}</h2><LevelBadge level={unlockLevel(pl.group)} dim={!unlocked} /></div>
              <div className="muted">{pl.blurb}</div>
              {unlocked ? <>
                <div className="row">
                  <select value={tgt?.id ?? ""} onChange={(e) => setTarget(e.target.value)}>{data.solarSystems.map((s) => <option key={s.id} value={s.id}>{s.name} ({count(s.id)}/8)</option>)}</select>
                  <button className="btn primary" disabled={!p.credits || full} onClick={() => { actions.addPlanet(pl.id, tgt?.id); show(`🎉 ${pl.name} joined ${tgt?.name}!`); }}>
                    {!p.credits ? `Reach level ${p.level + 1} for a new planet` : full ? "System is full" : "＋ Add planet"}</button>
                </div>
                <div className="row">
                  <button className="btn" disabled={data.avatarPlanet === pl.id} onClick={() => update((d) => { d.avatarPlanet = pl.id; })}>{data.avatarPlanet === pl.id ? "✓ Your profile picture" : "Use as profile picture"}</button>
                  {last && <button className="btn danger" onClick={() => actions.removePlanet(last.id)}>Remove one</button>}
                </div>
              </> : <div className="muted">🔒 Reach level {unlockLevel(pl.group)} to unlock — every {HOURS_PER_LEVEL}h of study is +1 level</div>}
            </div>
            <button className="icon-btn" onClick={() => setSelected(null)}>✕</button>
          </div>
        );
      })()}

      {GROUP_TITLES.map((title, gi) => {
        const lvl = unlockLevel(gi + 1), unlocked = lvl <= p.level;
        return (
          <div key={title}>
            <div className="row" style={{ marginBottom: 8 }}><LevelBadge level={lvl} dim={!unlocked} /><b className={unlocked ? "" : "muted"}>{title}{unlocked ? "" : ` — unlocks at level ${lvl}`}</b></div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(124px, 1fr))", gap: 12 }}>
              {PLANETS.filter((x) => x.group === gi + 1).map((pl) => {
                const count = data.galaxy.filter((g) => g.planetID === pl.id).length;
                return (
                  <div key={pl.id} className={`planet-tile ${selected === pl.id ? "sel" : ""}`} onClick={() => setSelected(pl.id)}>
                    {count > 0 && <span className="count">×{count}</span>}
                    <PlanetCanvas planet={pl} size={84} locked={!unlocked} />
                    <div className="small" style={{ fontWeight: 600 }}>{pl.name}</div>
                    {data.avatarPlanet === pl.id && <div className="small" style={{ color: "var(--accent)" }}>Profile</div>}
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
