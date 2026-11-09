import { PlanetCanvas } from "../components";
import { inTauri } from "../lib/notify";
import { PLANETS, planetByID, unlockLevel } from "../lib/planets";
import { STORE } from "../lib/storePlanets";
import { progress, useStore } from "../lib/store";

/** The Notchbit page (the Mac app's, for the Windows island): turn it on, pick the planet and set how it behaves */
export default function Notchbit() {
  const { data, update } = useStore();
  const s = data.settings;
  const set = (fn: (x: typeof s) => void) => update((d) => fn(d.settings));
  const on = !!s.islandOn;
  const level = progress(data).level;
  const owned = new Set(data.purchases.map((p) => p.planetID));
  // planets unlocked by level, then the ones bought in the Store (each once)
  const planets = [...PLANETS.filter((p) => unlockLevel(p.group) <= level), ...[...owned].map((id) => STORE.find((p) => p.id === id) ?? planetByID(id)).filter((p): p is NonNullable<typeof p> => !!p)]
    .filter((p, i, a) => a.findIndex((q) => q.id === p.id) === i);
  const chosen = s.islandPlanet || data.avatarPlanet || "terra";
  const planet = planetByID(chosen) ?? PLANETS[0];

  const toggle = (title: string, hint: string, value: boolean, onChange: (v: boolean) => void, disabled = false) => (
    <label className="list-row" style={{ opacity: disabled ? 0.5 : 1 }}>
      <span style={{ flex: 1 }}>{title}<br /><span className="small muted">{hint}</span></span>
      <input type="checkbox" checked={value} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
  const slider = (title: string, hint: string, value: number, min: number, max: number, step: number, fmt: (v: number) => string, onChange: (v: number) => void) => (
    <div className="list-row" style={{ flexDirection: "column", alignItems: "stretch", gap: 2 }}>
      <div className="row"><span style={{ flex: 1 }}>{title}</span><span className="muted" style={{ fontVariantNumeric: "tabular-nums" }}>{fmt(value)}</span></div>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(+e.target.value)} />
      <span className="small muted">{hint}</span>
    </div>
  );
  const soon = (title: string, hint: string) => toggle(title, hint + " (Not on Windows yet)", false, () => {}, true);

  return (
    <div className="page" style={{ maxWidth: 760, margin: "0 auto" }}>
      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        <div style={{ background: "#000", padding: "18px 20px 22px", backgroundImage: "linear-gradient(45deg, rgba(99,102,241,.35), rgba(236,72,153,.18), transparent)" }}>
          <div style={{ margin: "0 auto", width: 274, height: 32, background: "#000", borderRadius: "0 0 12px 12px", display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 14px", border: "1px solid rgba(255,255,255,.08)", borderTop: "none" }}>
            <PlanetCanvas planet={planet} size={26} />
            <span style={{ color: "#fff", fontSize: 12, fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>24:10</span>
          </div>
        </div>
        <div className="row" style={{ padding: "14px 18px", gap: 14 }}>
          <div style={{ flex: 1 }}><h2 style={{ margin: 0 }}>Notchbit</h2>
            <div className="muted">Your planet, the timer, your tasks and your music, hanging from the top of the screen.</div></div>
          <input type="checkbox" style={{ width: 22, height: 22 }} checked={on} onChange={(e) => set((x) => { x.islandOn = e.target.checked; })} />
        </div>
      </div>
      <div className="small muted" style={{ margin: "6px 4px 12px" }}>Windows has no notch, so Orbit draws one at the top centre of the main screen. It works in the installed Windows app, not in a browser.</div>

      {!inTauri() && (
        <div className="card row" style={{ gap: 12 }}>
          <div style={{ flex: 1 }}><b>Try it in a browser window</b><div className="small muted">Opens the island in a small window with your real data and buttons. The real island (always on top, top of the screen) only exists in the installed Windows app.</div></div>
          <button className="btn" onClick={() => window.open(`${location.origin}/?island=1`, "orbit-island", "popup=yes,width=440,height=260,left=200,top=120")}>Open preview</button>
        </div>
      )}

      {on && <>
        <div className="card"><h3><span className="t2-ico">🪐</span>Planet</h3>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(64px, 1fr))", gap: 10 }}>
            {planets.map((p) => (
              <button key={p.id} title={p.name} onClick={() => set((x) => { x.islandPlanet = p.id; })}
                style={{ padding: 6, borderRadius: 12, cursor: "pointer", display: "grid", placeItems: "center", background: "var(--card2)", color: "inherit",
                  border: `2px solid ${chosen === p.id ? "var(--accent)" : "transparent"}` }}>
                <PlanetCanvas planet={p} size={44} />
              </button>))}
          </div>
        </div>

        <div className="card"><h3><span className="t2-ico">🎛</span>What it shows</h3>
          {toggle("Planet moves", "A gentle float. Turn off for a still planet.", s.islandMotion !== false, (v) => set((x) => { x.islandMotion = v; }))}
          {toggle("Words to review", "An orange number beside the planet with today's Leitner words.", s.islandDue !== false, (v) => set((x) => { x.islandDue = v; }))}
        </div>

        <div className="card"><h3><span className="t2-ico">🔊</span>Volume &amp; brightness</h3>
          {soon("Show them in the island", "A level meter when you change the volume or brightness.")}
          {soon("Battery", "Plugging the charger in or out, 20% and 80%.")}
          {soon("Lock sign", "A small lock when you lock the PC.")}
          {soon("Keyboard language", "Shows EN or FA when you switch the keyboard.")}
        </div>

        <div className="card"><h3><span className="t2-ico">⏰</span>Next up</h3>
          {toggle("Remind me before a weekly to-do starts", "A few minutes before an item of your weekly schedule starts, the island opens with its name and a Start button.", s.islandNextUp !== false, (v) => set((x) => { x.islandNextUp = v; }))}
          {s.islandNextUp !== false && <div className="list-row"><span style={{ flex: 1 }}>Remind me</span>
            <select value={s.islandLead ?? 10} onChange={(e) => set((x) => { x.islandLead = +e.target.value; })}>{[5, 10, 15, 30].map((m) => <option key={m} value={m}>{m} min before</option>)}</select></div>}
        </div>

        <div className="card"><h3><span className="t2-ico">👆</span>Opening</h3>
          <div className="seg" style={{ marginBottom: 8 }}>
            <button className={!s.islandClickOnly ? "on" : ""} onClick={() => set((x) => { x.islandClickOnly = false; })}>Pointer or click</button>
            <button className={s.islandClickOnly ? "on" : ""} onClick={() => set((x) => { x.islandClickOnly = true; })}>Click only</button>
          </div>
          <div className="small muted">{s.islandClickOnly ? "The pointer can rest on the island without opening it. Click it to open." : "The island peeks when the pointer rests on it; click to open the big view."}</div>
        </div>

        <div className="card"><h3><span className="t2-ico">🌊</span>Feel</h3>
          {slider("Animation speed", "Slower or faster opening and closing.", s.islandSpeed ?? 1, 0.5, 2, 0.1, (v) => `${v.toFixed(1)}×`, (v) => set((x) => { x.islandSpeed = v; }))}
          {slider("Opens after", "How long the pointer rests on the island before it opens.", s.islandOpenDelay ?? 0.12, 0, 0.6, 0.01, (v) => `${v.toFixed(2)} s`, (v) => set((x) => { x.islandOpenDelay = v; }))}
          {slider("Closes after", "How long it waits once the pointer has left.", s.islandCloseDelay ?? 0.35, 0.1, 1.5, 0.05, (v) => `${v.toFixed(2)} s`, (v) => set((x) => { x.islandCloseDelay = v; }))}
          {slider("Planet size", "The planet (or the cover) beside the notch.", s.islandPlanetSize ?? 30, 20, 36, 1, (v) => `${v} px`, (v) => set((x) => { x.islandPlanetSize = v; }))}
          <button className="btn small" onClick={() => set((x) => { x.islandSpeed = 1; x.islandOpenDelay = 0.12; x.islandCloseDelay = 0.35; x.islandPlanetSize = 30; })}>Reset to defaults</button>
        </div>

        <div className="card"><h3><span className="t2-ico">🎵</span>Music</h3>
          {toggle("Show music", "Cover and controls for whatever plays (Spotify, a browser, any app using the Windows media controls).", s.islandMusic !== false, (v) => set((x) => { x.islandMusic = v; }))}
          {slider("Keep the song after pausing", "After you pause, the music view stays this long in case you play again.", s.islandMusicHold ?? 30, 5, 120, 5, (v) => `${v} s`, (v) => set((x) => { x.islandMusicHold = v; }))}
        </div>
      </>}
    </div>
  );
}
