import { useEffect, useRef, useState } from "react";
import { PlanetCanvas } from "../components";
import { RocketIcon } from "./Store";
import { planetByID } from "../lib/planets";
import { canClaim, HOURS_PER_LEVEL, levelPlanet, MAX_LEVEL, progress, rocketsForLevel, useStore, wallet } from "../lib/store";
import ship1 from "../assets/pass_ship1.png";
import ship2 from "../assets/pass_ship2.png";
import ship3 from "../assets/pass_ship3.png";

const SHIPS = [ship1, ship2, ship3];
const SPACING = 132;
const position = (hours: number) => Math.min(MAX_LEVEL, 1 + hours / HOURS_PER_LEVEL);

/** The Level Pass: a line of levels with a ship showing where you are; click a reward to take it.
 *  `fromHours` = study hours before the session that opened it (the ship flies from there). */
export default function LevelPass({ fromHours, onClose }: { fromHours?: number; onClose: () => void }) {
  const { data, actions } = useStore();
  const p = progress(data);
  const target = position(p.totalHours);
  const start = fromHours !== undefined ? position(fromHours) : target;
  const [shipAt, setShipAt] = useState(start);
  // The view holds between start and finish (so you see the ship fly), then follows on long flights
  const [cameraAt, setCameraAt] = useState(Math.abs(target - start) <= 5 ? (start + target) / 2 : start);
  const [look, setLook] = useState(0);
  const [ship, setShip] = useState(() => Number(localStorage.getItem("pass-ship") ?? 1));
  const [preview, setPreview] = useState<number | null>(null);
  const box = useRef<HTMLDivElement>(null);
  const drag = useRef<{ x: number; look: number } | null>(null);

  useEffect(() => {
    if (start === target) return;
    const cam0 = cameraAt, longFlight = Math.abs(target - start) > 5;
    let raf = 0; const t0 = performance.now() + 900, dur = 2400;
    const step = (now: number) => {
      const t = Math.max(0, Math.min(1, (now - t0) / dur)), e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      setShipAt(start + (target - start) * e);
      if (longFlight) setCameraAt(cam0 + (target - cam0) * e);
      if (t < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const claimable = Array.from({ length: p.level }, (_, i) => i + 1).filter((l) => canClaim(data, l));
  const width = box.current?.clientWidth ?? 860;
  const offset = width / 2 - SPACING * (cameraAt - 1) + look;
  const clampLook = (x: number) => Math.min(SPACING * (cameraAt - 1) + 300, Math.max(SPACING * (cameraAt - 1) - SPACING * (MAX_LEVEL - 1) - 300, x));

  return (
    <div className="modal-bg" onMouseDown={onClose}>
      <div className="modal pass" style={{ width: 900, padding: 0, overflow: "hidden" }} onMouseDown={(e) => e.stopPropagation()}>
        <div className="row" style={{ padding: 20, gap: 14 }}>
          <div style={{ flex: 1 }}>
            <div className="small" style={{ fontWeight: 800, letterSpacing: 2, color: "#F97316" }}>LEVEL PASS</div>
            <div className="row" style={{ gap: 8 }}><h2 style={{ margin: 0 }}>Level {p.level}</h2>
              {p.level < MAX_LEVEL && <span className="muted">· {Math.max(0, p.level * HOURS_PER_LEVEL - p.totalHours).toFixed(1)}h to level {p.level + 1}</span>}</div>
            <div className="small muted">Every 3 hours of study is a level. Click a reward to take it.</div>
          </div>
          <div className="row" style={{ gap: 4 }}>
            {SHIPS.map((src, i) => (
              <button key={i} title={`Fly ship ${i + 1}`} onClick={() => { setShip(i + 1); localStorage.setItem("pass-ship", String(i + 1)); }}
                style={{ padding: 3, borderRadius: 8, border: `1.5px solid ${ship === i + 1 ? "#F97316" : "transparent"}`, background: ship === i + 1 ? "rgba(249,115,22,.25)" : "rgba(255,255,255,.05)" }}>
                <img src={src} alt="" style={{ width: 34, height: 34, display: "block" }} /></button>
            ))}
          </div>
          <span className="row" style={{ gap: 6, fontWeight: 700 }}><RocketIcon size={18} /> {wallet(data).balance.toLocaleString()}</span>
          {claimable.length > 0 && <button className="btn primary" style={{ background: "#F97316" }} onClick={async () => { for (const lv of claimable) await actions.claimLevel(lv); }}>Claim All ({claimable.length})</button>}
          <button className="btn" onClick={onClose}>Done</button>
        </div>
        <div ref={box} className="space" style={{ height: 330, borderRadius: 0, cursor: "grab", userSelect: "none" }}
          onWheel={(e) => setLook((l) => clampLook(l - (Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY)))}
          onMouseDown={(e) => { drag.current = { x: e.clientX, look }; }}
          onMouseMove={(e) => { if (drag.current) setLook(clampLook(drag.current.look + e.clientX - drag.current.x)); }}
          onMouseUp={() => (drag.current = null)} onMouseLeave={() => (drag.current = null)}>
          <div style={{ position: "absolute", left: offset, top: 0, width: SPACING * (MAX_LEVEL - 1), height: 330 }}>
            <div style={{ position: "absolute", top: 118, left: 0, right: 0, height: 6, borderRadius: 3, background: "var(--pl-line)" }} />
            <div style={{ position: "absolute", top: 118, left: 0, height: 6, borderRadius: 3, width: Math.max(6, SPACING * (shipAt - 1)), background: "linear-gradient(90deg,#F97316,#EC4899)", boxShadow: "0 0 8px rgba(249,115,22,.6)" }} />
            {Array.from({ length: MAX_LEVEL }, (_, i) => i + 1).map((lv) => {
              const reached = lv <= p.level, claimed = (data.claimedLevels ?? []).includes(lv), take = reached && !claimed;
              const planet = planetByID(levelPlanet(lv));
              return (
                <div key={lv} style={{ position: "absolute", left: SPACING * (lv - 1) - SPACING / 2, top: 104, width: SPACING, display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
                  <div style={{ width: 30, height: 30, borderRadius: "50%", display: "grid", placeItems: "center", fontWeight: 800, fontSize: 13,
                    background: reached ? "#F97316" : "var(--pl-line)", border: `1.5px solid ${reached ? "var(--pl-edge-on)" : "var(--pl-edge-off)"}` }}>{lv}</div>
                  <button disabled={!take && !planet}
                    onClick={() => { if (take) actions.claimLevel(lv); else if (planet) setPreview(lv); }}
                    title={planet ? `Level ${lv}: ${rocketsForLevel(lv)} rockets + ${planet.name}` : `Level ${lv}: ${rocketsForLevel(lv)} rockets`}
                    style={{ width: 104, height: planet ? 136 : 64, borderRadius: 12, color: "var(--pl-fg)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 4,
                      background: take ? "rgba(249,115,22,.18)" : "var(--pl-tile)", border: `${take ? 2 : 1}px solid ${take ? "#F97316" : planet ? "rgba(168,85,247,.6)" : "var(--pl-tile-edge)"}`,
                      boxShadow: take ? "0 0 10px rgba(249,115,22,.5)" : undefined, opacity: reached || planet ? 1 : 0.55, cursor: take || planet ? "pointer" : "default" }}>
                    {planet && <PlanetCanvas planet={planet} size={70} animate />}
                    <span className="row small" style={{ gap: 3, fontWeight: 700 }}><RocketIcon size={14} />+{rocketsForLevel(lv)}</span>
                    <span className="small" style={{ fontWeight: 600, color: claimed ? "#22C55E" : take ? "#F97316" : "var(--pl-dim)" }}>{claimed ? "Taken ✓" : take ? "Claim" : "Locked"}</span>
                  </button>
                </div>
              );
            })}
            {/* the ship hovers above where you are */}
            <div className="pass-ship" style={{ position: "absolute", left: SPACING * (shipAt - 1) - 39, top: 4, display: "flex", flexDirection: "column", alignItems: "center", gap: 2, pointerEvents: "none" }}>
              <img src={SHIPS[ship - 1] ?? ship1} alt="" style={{ width: 78, height: 78 }} />
              <span className="small" style={{ fontWeight: 800, padding: "0 6px", borderRadius: 99, background: "#F97316" }}>You</span>
            </div>
          </div>
        </div>
        {preview !== null && (() => {
          const planet = planetByID(levelPlanet(preview))!; const reached = preview <= p.level, claimed = (data.claimedLevels ?? []).includes(preview);
          return (
            <div className="modal-bg" onMouseDown={() => setPreview(null)}>
              <div className="modal" style={{ width: 300, textAlign: "center", display: "flex", flexDirection: "column", alignItems: "center", gap: 8, background: "#0B1020", color: "white" }} onMouseDown={(e) => e.stopPropagation()}>
                <PlanetCanvas planet={planet} size={200} animate />
                <h3 style={{ margin: 0 }}>{planet.name}</h3>
                <div className="small" style={{ opacity: 0.75 }}>{planet.blurb}</div>
                <b style={{ color: claimed ? "#22C55E" : reached ? "#F97316" : "rgba(255,255,255,.6)" }}>{claimed ? "Yours ✓" : reached ? "🎁 Ready to claim" : `🔒 Unlocks at level ${preview}`}</b>
                <button className="btn" onClick={() => setPreview(null)}>Close</button>
              </div>
            </div>
          );
        })()}
      </div>
    </div>
  );
}
