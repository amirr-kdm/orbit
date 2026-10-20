import { STORE, type Craft } from "./storePlanets";
// The 50 planets — same catalogue and look as the Mac app, drawn on an HTML canvas.

type Shape = "circle" | "heart" | "star" | "cube" | "donut" | "diamond" | "hexagon" | "egg" | "cloud" | "flower"
  | "ghost" | "mushroom" | "crescent" | "gear" | "pyramid" | "burst";
type Pattern = "plain" | "bands" | "spots" | "craters" | "swirl" | "cracks" | "checker" | "stripes" | "dots" | "waves"
  | "clouds" | "polarCaps" | "hexgrid" | "snowflakes" | "rainbow" | "mountains" | "pepperoni" | "sprinkles";
type Feature = "catEars" | "whiskers" | "face" | "spikes" | "crown" | "leaf" | "eye" | "horns" | "wings" | "antenna"
  | "tentacles" | "bow" | "tree" | "flag" | "sunglasses" | "unicornHorn" | "volcanoes" | "halo" | "stem" | "fireWings";

export interface Ring { color: string; tilt?: number; width?: number; double?: boolean }
export interface PlanetDef {
  id: string; name: string; group: number; blurb: string;
  shape?: Shape; colors: [string, string, string]; pattern?: Pattern; accent?: string;
  ring?: Ring; moons?: number; emoji?: string; features?: Feature[]; glow?: boolean;
  /** Store planets: price in rockets, spacecraft in orbit, creatures walking on top, things standing on it, or a picture */
  price?: number; crafts?: Craft[]; walkers?: string[]; landmarks?: string[]; image?: string;
}

/** Group 1 → level 1, group 2 → level 6, … group 10 → level 46 */
export const unlockLevel = (group: number) => 1 + (group - 1) * 5;
export const GROUP_TITLES = ["Starter Worlds", "Explorer", "Wild Worlds", "Shapes & Snacks", "Deep Space",
  "Creatures", "Spooky & Bright", "Cosmic Wonders", "Royal Orbit", "Legendary"];

const P = (id: string, name: string, group: number, blurb: string, o: Omit<PlanetDef, "id" | "name" | "group" | "blurb">): PlanetDef =>
  ({ id, name, group, blurb, ...o });

export const PLANETS: PlanetDef[] = [
  P("terra", "Terra Nova", 1, "Blue oceans, green lands, fluffy clouds.", { colors: ["#7DD3FC", "#2563EB", "#1E3A8A"], pattern: "clouds", accent: "#22C55E", moons: 1 }),
  P("ember", "Ember", 1, "Rivers of lava and two smoking volcanoes.", { colors: ["#78350F", "#451A03", "#1C0A00"], pattern: "cracks", accent: "#FB923C", features: ["volcanoes"], glow: true }),
  P("frost", "Frostbite", 1, "Snowflakes fall forever here.", { colors: ["#F0F9FF", "#BAE6FD", "#38BDF8"], pattern: "snowflakes", accent: "#FFFFFF" }),
  P("saturnella", "Saturnella", 1, "Sandy bands and an elegant ring.", { colors: ["#FDE68A", "#D97706", "#92400E"], pattern: "bands", accent: "#FEF3C7", ring: { color: "#FCD34D" } }),
  P("lunaris", "Lunaris", 1, "A sleepy grey crescent full of craters.", { shape: "crescent", colors: ["#F1F5F9", "#9CA3AF", "#4B5563"], pattern: "craters", accent: "#374151" }),

  P("bubblegum", "Bubblegum", 2, "A fluffy pink cloud with a bow on top.", { shape: "cloud", colors: ["#FBCFE8", "#F472B6", "#9D174D"], pattern: "swirl", accent: "#FDF2F8", features: ["bow"] }),
  P("jade", "Jade Jungle", 2, "One giant tree holds the whole world together.", { colors: ["#86EFAC", "#16A34A", "#14532D"], pattern: "mountains", accent: "#052E16", features: ["tree"] }),
  P("neptuno", "Neptuno", 2, "Wild blue storms and two loyal moons.", { colors: ["#93C5FD", "#1D4ED8", "#172554"], pattern: "bands", accent: "#BFDBFE", moons: 2 }),
  P("rust", "Rust Rover", 2, "Red dust, dry valleys — someone planted a flag.", { colors: ["#FDBA74", "#C2410C", "#7C2D12"], pattern: "craters", accent: "#431407", moons: 1, features: ["flag"] }),
  P("citrus", "Citrus", 2, "Smells like oranges. Probably.", { colors: ["#FED7AA", "#F97316", "#C2410C"], pattern: "dots", accent: "#FFEDD5", features: ["leaf"] }),

  P("dino", "Dino Prime", 3, "A dinosaur egg the size of a planet. It's hatching!", { shape: "egg", colors: ["#ECFCCB", "#A3E635", "#4D7C0F"], pattern: "spots", accent: "#3F6212", emoji: "🦖" }),
  P("donut", "Donut World", 3, "A planet with a hole. Sprinkles included.", { shape: "donut", colors: ["#FBCFE8", "#F472B6", "#BE185D"], pattern: "sprinkles", accent: "#FDE047" }),
  P("choco", "Choco Moon", 3, "A chocolate mushroom with candy spots.", { shape: "mushroom", colors: ["#D6A06B", "#78350F", "#3B1A08"], pattern: "spots", accent: "#FDE68A" }),
  P("aurora", "Aurora", 3, "Northern lights dance under a golden halo.", { colors: ["#A78BFA", "#6D28D9", "#2E1065"], pattern: "waves", accent: "#6EE7B7", features: ["halo"], glow: true }),
  P("honey", "Honeycomb", 3, "A hexagon hive, buzzing and golden.", { shape: "hexagon", colors: ["#FEF08A", "#EAB308", "#854D0E"], pattern: "hexgrid", accent: "#713F12", emoji: "🐝" }),

  P("kitty", "Kitty Planet", 4, "Purrs when you study.", { colors: ["#FED7AA", "#FB923C", "#9A3412"], pattern: "stripes", accent: "#7C2D12", features: ["catEars", "face", "whiskers"] }),
  P("pizza", "Pizza Planet", 4, "Extra cheese, extra gravity.", { colors: ["#FEF08A", "#FBBF24", "#B45309"], pattern: "pepperoni", accent: "#DC2626", ring: { color: "#D97706", tilt: -8, width: 0.2 } }),
  P("cube9", "Cube-9", 4, "Scientists still argue about this one.", { shape: "cube", colors: ["#A5F3FC", "#0891B2", "#164E63"], pattern: "checker", accent: "#CFFAFE", moons: 1 }),
  P("heartbeat", "Heartbeat", 4, "A flying heart. Made of pure motivation.", { shape: "heart", colors: ["#FDA4AF", "#E11D48", "#881337"], accent: "#FFE4E6", features: ["wings"], glow: true }),
  P("starforge", "Starforge", 4, "A star that decided to be a planet.", { shape: "star", colors: ["#FEF9C3", "#FACC15", "#A16207"], accent: "#FDE047", features: ["face"], glow: true }),

  P("melon", "Watermelon", 5, "Juicy stripes from pole to pole.", { colors: ["#86EFAC", "#15803D", "#14532D"], pattern: "stripes", accent: "#052E16", moons: 1, features: ["stem"] }),
  P("disco", "Disco Ball", 5, "Every night is party night. Shades on.", { colors: ["#F8FAFC", "#94A3B8", "#334155"], pattern: "checker", accent: "#E0E7FF", features: ["sunglasses"], glow: true }),
  P("oceaneye", "Ocean Eye", 5, "It's watching you study. Good.", { colors: ["#99F6E4", "#0D9488", "#134E4A"], pattern: "waves", accent: "#CCFBF1", features: ["eye"] }),
  P("spiral", "Spiral", 5, "A tiny galaxy wrapped in a planet.", { colors: ["#C4B5FD", "#7C3AED", "#1E1B4B"], pattern: "swirl", accent: "#F0ABFC", ring: { color: "#E9D5FF", tilt: 30, width: 0.1, double: true } }),
  P("coral", "Coral Bloom", 5, "A flower world where fish swim in the petals.", { shape: "flower", colors: ["#FECDD3", "#FB7185", "#BE123C"], pattern: "dots", accent: "#FEF3C7", emoji: "🐠" }),

  P("trex", "Stego Rock", 6, "Rocky, spiky, and very old.", { colors: ["#D6D3D1", "#78716C", "#292524"], pattern: "craters", accent: "#1C1917", emoji: "🦕", features: ["spikes"] }),
  P("octo", "Octo World", 6, "Eight arms, one ocean, many hugs.", { colors: ["#C4B5FD", "#8B5CF6", "#4C1D95"], pattern: "spots", accent: "#DDD6FE", features: ["tentacles", "face"] }),
  P("mushroom", "Mushroom Kingdom", 6, "Red cap, white spots, good vibes.", { shape: "mushroom", colors: ["#FCA5A5", "#DC2626", "#7F1D1D"], pattern: "spots", accent: "#FFFFFF", features: ["face"] }),
  P("candycane", "Candy Cane", 6, "Peppermint fresh, all year long.", { colors: ["#FFFFFF", "#FECACA", "#F87171"], pattern: "stripes", accent: "#DC2626", ring: { color: "#86EFAC", tilt: -25, width: 0.1 }, features: ["bow"] }),
  P("crystal", "Crystal Shard", 6, "Shines in every colour of light.", { shape: "diamond", colors: ["#CFFAFE", "#22D3EE", "#0E7490"], pattern: "rainbow", accent: "#FFFFFF", glow: true }),

  P("robo", "Robo Core", 7, "Beep boop. Fully automated.", { shape: "cube", colors: ["#E2E8F0", "#64748B", "#1E293B"], pattern: "checker", accent: "#38BDF8", emoji: "🤖", features: ["antenna"] }),
  P("ghost", "Ghostly", 7, "Boo! (It's friendly.)", { shape: "ghost", colors: ["#FFFFFF", "#E0E7FF", "#A5B4FC"], accent: "#C7D2FE", features: ["face"], glow: true }),
  P("pumpkin", "Pumpkin", 7, "Spooky season, forever.", { colors: ["#FDBA74", "#EA580C", "#7C2D12"], pattern: "bands", accent: "#9A3412", features: ["face", "stem"] }),
  P("twinvolcano", "Twin Volcano", 7, "A lava pyramid with two moons and zero chill.", { shape: "pyramid", colors: ["#57534E", "#292524", "#0C0A09"], pattern: "cracks", accent: "#EF4444", moons: 2, glow: true }),
  P("rainbow", "Rainbow", 7, "All the colours, all the time.", { colors: ["#FFFFFF", "#E0F2FE", "#BAE6FD"], pattern: "rainbow", accent: "#FFFFFF", ring: { color: "#FFFFFF", tilt: 12, width: 0.08 }, features: ["face"] }),

  P("blackhole", "Black Hole", 8, "Swallows distractions whole.", { colors: ["#1F2937", "#030712", "#000000"], accent: "#F59E0B", ring: { color: "#FB923C", tilt: -10, width: 0.24, double: true }, glow: true }),
  P("snowglobe", "Snow Globe", 8, "A snowman lives inside. He's very happy.", { colors: ["#F0F9FF", "#BAE6FD", "#38BDF8"], pattern: "polarCaps", accent: "#FFFFFF", emoji: "⛄️" }),
  P("dragonegg", "Dragon Egg", 8, "Something with wings is about to hatch…", { shape: "egg", colors: ["#6EE7B7", "#059669", "#064E3B"], pattern: "hexgrid", accent: "#FDE047", features: ["spikes", "wings"], glow: true }),
  P("whale", "Cosmic Whale", 8, "Swims through space, singing.", { colors: ["#BFDBFE", "#3B82F6", "#1E3A8A"], pattern: "waves", accent: "#DBEAFE", moons: 1, emoji: "🐳" }),
  P("goldchild", "Golden Gear", 8, "The clockwork that keeps time moving.", { shape: "gear", colors: ["#FEF3C7", "#F59E0B", "#78350F"], pattern: "swirl", accent: "#FFFBEB", glow: true }),

  P("royale", "Saturn Royale", 9, "Rings fit for a king.", { colors: ["#E9D5FF", "#A855F7", "#581C87"], pattern: "bands", accent: "#F3E8FF", ring: { color: "#FDE047", tilt: -16, width: 0.14, double: true }, features: ["crown"] }),
  P("neongrid", "Neon Pyramid", 9, "Straight out of a synthwave song.", { shape: "pyramid", colors: ["#312E81", "#1E1B4B", "#020617"], pattern: "checker", accent: "#F0ABFC", glow: true }),
  P("cheese", "Moon Cheese", 9, "The rumours were true.", { shape: "crescent", colors: ["#FEF08A", "#FACC15", "#CA8A04"], pattern: "craters", accent: "#A16207", features: ["face"] }),
  P("alien", "Alien Hive", 9, "We come in peace. Mostly.", { colors: ["#BBF7D0", "#22C55E", "#14532D"], pattern: "dots", accent: "#DCFCE7", emoji: "👽", features: ["antenna"] }),
  P("ufo", "UFO Station", 9, "Parking spot for flying saucers.", { colors: ["#E2E8F0", "#94A3B8", "#475569"], pattern: "bands", accent: "#22D3EE", ring: { color: "#67E8F9", tilt: 0, width: 0.1 }, emoji: "🛸" }),

  P("phoenix", "Phoenix", 10, "Reborn from fire every week.", { colors: ["#FDE047", "#F97316", "#991B1B"], pattern: "swirl", accent: "#FEF08A", emoji: "🔥", features: ["fireWings"], glow: true }),
  P("unicorn", "Unicorn Dream", 10, "A pastel cloud with a magic horn.", { shape: "cloud", colors: ["#FBCFE8", "#C4B5FD", "#93C5FD"], pattern: "rainbow", accent: "#FFFFFF", features: ["unicornHorn", "face"], glow: true }),
  P("diamondheart", "Diamond Heart", 10, "Unbreakable, like your focus.", { shape: "heart", colors: ["#E0F2FE", "#7DD3FC", "#0369A1"], pattern: "checker", accent: "#FFFFFF", features: ["crown"], glow: true }),
  P("infinity", "Infinity Loop", 10, "Study, sleep, repeat.", { shape: "donut", colors: ["#F0ABFC", "#A855F7", "#3B0764"], pattern: "swirl", accent: "#FDF4FF", moons: 2, features: ["halo"], glow: true }),
  P("claude", "Claude's Cosmos", 10, "The final reward. ✨", { shape: "burst", colors: ["#FED7AA", "#D97757", "#7C2D12"], pattern: "swirl", accent: "#FFEDD5", ring: { color: "#FED7AA", tilt: -20, width: 0.12, double: true }, moons: 3, features: ["face"], glow: true }),
];

export const planetByID = (id?: string | null) => PLANETS.find((p) => p.id === id) ?? STORE.find((p) => p.id === id);
export const isStorePlanet = (id?: string | null) => STORE.some((p) => p.id === id);

// ---------- Painter ----------

function rng(seed: string) {
  let s = BigInt(1469598103934665603n);
  for (const ch of seed) s = ((s ^ BigInt(ch.codePointAt(0)!)) * 1099511628211n) & 0xFFFFFFFFFFFFFFFFn;
  return () => {
    s = (s * 6364136223846793005n + 1442695040888963407n) & 0xFFFFFFFFFFFFFFFFn;
    return Number(s >> 33n) / 2 ** 31;
  };
}

function rgba(hex: string, a = 1) {
  const v = parseInt(hex.replace("#", ""), 16);
  return `rgba(${(v >> 16) & 255},${(v >> 8) & 255},${v & 255},${a})`;
}

type Ctx = CanvasRenderingContext2D;
const TAU = Math.PI * 2;

function poly(ctx: Ctx, cx: number, cy: number, pts: [number, number][]) {
  ctx.beginPath();
  pts.forEach(([rad, a], i) => {
    const x = cx + Math.cos(a) * rad, y = cy + Math.sin(a) * rad;
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  });
  ctx.closePath();
}
function regular(ctx: Ctx, cx: number, cy: number, n: number, outer: number, inner: number, start = 0) {
  poly(ctx, cx, cy, Array.from({ length: n }, (_, i) => [i % 2 === 0 ? outer : inner, (i / n) * TAU + start] as [number, number]));
}
function ellipse(ctx: Ctx, x: number, y: number, rx: number, ry: number) {
  ctx.beginPath(); ctx.ellipse(x, y, rx, ry, 0, 0, TAU);
}

/** A circle with a bite taken out: outer arc of the planet + inner arc of the bite circle */
function crescentPath(ctx: Ctx, c: number, r: number) {
  const bx = c + r * 0.7, by = c - r * 0.25, R = r * 0.95;
  const dx = bx - c, dy = by - c, d = Math.hypot(dx, dy);
  const a = (r * r - R * R + d * d) / (2 * d), h = Math.sqrt(Math.max(0, r * r - a * a));
  const mx = c + (a * dx) / d, my = c + (a * dy) / d;
  const p1 = [mx + (h * -dy) / d, my + (h * dx) / d], p2 = [mx - (h * -dy) / d, my - (h * dx) / d];
  const towardB = Math.atan2(dy, dx);
  const arcAvoiding = (cx: number, cy: number, rad: number, from: number[], to: number[], avoid: number) => {
    const a1 = Math.atan2(from[1] - cy, from[0] - cx), a2 = Math.atan2(to[1] - cy, to[0] - cx);
    const mid = a1 + (((a2 - a1) % TAU) + TAU) % TAU / 2;
    ctx.arc(cx, cy, rad, a1, a2, Math.cos(mid - avoid) > 0);
  };
  ctx.beginPath();
  ctx.moveTo(p1[0], p1[1]);
  arcAvoiding(c, c, r, p1, p2, towardB);            // the planet's outer edge, away from the bite
  arcAvoiding(bx, by, R, p2, p1, towardB);           // the bite's edge, inside the planet
  ctx.closePath();
}

function shapePath(ctx: Ctx, shape: Shape, c: number, r: number) {
  switch (shape) {
    case "circle": ellipse(ctx, c, c, r, r); break;
    case "donut":
      ctx.beginPath(); ctx.arc(c, c, r * 1.05, 0, TAU); ctx.moveTo(c + r * 0.4, c); ctx.arc(c, c, r * 0.4, 0, TAU, true); break;
    case "cube": ctx.beginPath(); ctx.roundRect(c - r * 0.88, c - r * 0.88, r * 1.76, r * 1.76, r * 0.3); break;
    case "diamond": poly(ctx, c, c, [[r * 1.15, -Math.PI / 2], [r * 0.92, -0.2], [r * 1.15, Math.PI / 2], [r * 0.92, Math.PI + 0.2]]); break;
    case "hexagon": regular(ctx, c, c, 6, r * 1.05, r * 1.05); break;
    case "pyramid": poly(ctx, c, c, [[r * 1.2, -Math.PI / 2], [r * 1.15, Math.PI / 6], [r * 1.15, (Math.PI * 5) / 6]]); break;
    case "star": regular(ctx, c, c, 10, r * 1.2, r * 0.62, -Math.PI / 2); break;
    case "burst": regular(ctx, c, c, 24, r * 1.15, r * 0.82); break;
    case "gear": {
      const pts: [number, number][] = [];
      for (let i = 0; i < 10; i++) { const a = (i / 10) * TAU; pts.push([r * 0.88, a - 0.2], [r * 1.12, a - 0.12], [r * 1.12, a + 0.12], [r * 0.88, a + 0.2]); }
      poly(ctx, c, c, pts); break;
    }
    case "egg":
      ctx.beginPath(); ctx.moveTo(c, c - r * 1.2);
      ctx.bezierCurveTo(c + r * 1.15, c - r * 1.2, c + r * 1.15, c + r * 0.95, c, c + r * 0.95);
      ctx.bezierCurveTo(c - r * 1.15, c + r * 0.95, c - r * 1.15, c - r * 1.2, c, c - r * 1.2); break;
    case "cloud":
      ctx.beginPath();
      for (const [dx, dy, rr] of [[-0.55, 0.15, 0.6], [0, -0.25, 0.75], [0.55, 0.1, 0.62], [-0.1, 0.35, 0.62], [0.35, 0.38, 0.5]]) {
        ctx.moveTo(c + r * (dx + rr), c + r * dy); ctx.arc(c + r * dx, c + r * dy, r * rr, 0, TAU);
      }
      break;
    case "flower":
      ctx.beginPath();
      for (let i = 0; i < 6; i++) { const a = (i / 6) * TAU; const x = c + Math.cos(a) * r * 0.6, y = c + Math.sin(a) * r * 0.6; ctx.moveTo(x + r * 0.52, y); ctx.arc(x, y, r * 0.52, 0, TAU); }
      ctx.moveTo(c + r * 0.6, c); ctx.arc(c, c, r * 0.6, 0, TAU); break;
    case "ghost":
      ctx.beginPath(); ctx.moveTo(c - r * 0.9, c + r * 1.05); ctx.lineTo(c - r * 0.9, c - r * 0.1);
      ctx.arc(c, c - r * 0.1, r * 0.9, Math.PI, 0); ctx.lineTo(c + r * 0.9, c + r * 1.05);
      for (let k = 0; k < 4; k++) { const x0 = c + r * 0.9 - k * r * 0.45; ctx.quadraticCurveTo(x0 - r * 0.225, c + r * 0.7, x0 - r * 0.45, c + r * 1.05); }
      ctx.closePath(); break;
    case "mushroom":
      ctx.beginPath(); ctx.moveTo(c - r * 1.15, c + r * 0.15);
      ctx.bezierCurveTo(c - r * 1.15, c - r * 1.35, c + r * 1.15, c - r * 1.35, c + r * 1.15, c + r * 0.15);
      ctx.quadraticCurveTo(c, c + r * 0.4, c - r * 1.15, c + r * 0.15); break;
    case "crescent": crescentPath(ctx, c, r); break;
    case "heart":
      ctx.beginPath(); ctx.moveTo(c, c + r);
      ctx.bezierCurveTo(c - r * 0.55, c + r * 0.55, c - r * 1.15, c + r * 0.15, c - r * 1.1, c - r * 0.35);
      ctx.arc(c - r * 0.55, c - r * 0.4, r * 0.56, (185 * Math.PI) / 180, 0);
      ctx.arc(c + r * 0.55, c - r * 0.4, r * 0.56, Math.PI, (355 * Math.PI) / 180);
      ctx.bezierCurveTo(c + r * 1.15, c + r * 0.15, c + r * 0.55, c + r * 0.55, c, c + r); break;
  }
}

function drawRing(ctx: Ctx, ring: Ring, c: number, r: number, front: boolean, phase: number) {
  ctx.save();
  ctx.translate(c, c); ctx.rotate(((ring.tilt ?? -18) * Math.PI) / 180);
  ctx.beginPath(); ctx.rect(-r * 3, front ? 0 : -r * 3, r * 6, r * 3); ctx.clip();
  const ks = ring.double ? [1.55, 1.85] : [1.65];
  ks.forEach((k, i) => {
    const w = r * (ring.width ?? 0.16) * (ring.double ? 0.7 : 1);
    const dir = i % 2 === 0 ? 1 : -0.7;
    ctx.lineWidth = w;
    ellipse(ctx, 0, 0, r * k, r * k * 0.28); ctx.strokeStyle = rgba(ring.color, 0.45); ctx.stroke();
    ctx.setLineDash([r * 0.5, r * 0.22]); ctx.lineDashOffset = phase * Math.PI * r * k * 1.3 * dir; ctx.lineCap = "round";
    ellipse(ctx, 0, 0, r * k, r * k * 0.28); ctx.strokeStyle = rgba(ring.color, 0.95); ctx.lineWidth = w * 0.8; ctx.stroke();
    ctx.setLineDash([]);
    for (let j = 0; j < 6; j++) {
      const a = (j / 6 + phase * dir) * TAU;
      ellipse(ctx, Math.cos(a) * r * k, Math.sin(a) * r * k * 0.28, w * 0.28, w * 0.28); ctx.fillStyle = "rgba(255,255,255,0.9)"; ctx.fill();
    }
  });
  ctx.restore();
}

function pattern(ctx: Ctx, p: Pattern, c: number, r: number, accent: string, rnd: () => number) {
  const bx = c - r * 1.3, by = c - r * 1.3, bw = r * 2.6;
  switch (p) {
    case "plain": break;
    case "bands":
      for (let k = 0; k < 7; k += 2) { ctx.fillStyle = rgba(accent, 0.32); ctx.fillRect(bx, by + (bw * k) / 7, bw, bw / 7); }
      break;
    case "spots":
      for (let i = 0; i < 7; i++) { const w = r * (0.25 + rnd() * 0.5); ellipse(ctx, c - r + rnd() * r * 1.6 + w / 2, c - r + rnd() * r * 1.6 + w / 2, w / 2, (w * (0.6 + rnd() * 0.5)) / 2); ctx.fillStyle = rgba(accent, 0.7); ctx.fill(); }
      break;
    case "craters":
      for (let i = 0; i < 8; i++) { const w = r * (0.15 + rnd() * 0.35); const x = c - r + rnd() * r * 1.7, y = c - r + rnd() * r * 1.7; ellipse(ctx, x + w / 2, y + w / 2, w / 2, w / 2); ctx.fillStyle = rgba(accent, 0.35); ctx.fill(); ctx.strokeStyle = "rgba(255,255,255,0.18)"; ctx.lineWidth = Math.max(0.5, w * 0.08); ctx.stroke(); }
      break;
    case "swirl":
      for (let k = 0; k < 4; k++) { ctx.beginPath(); ctx.arc(c + r * 0.2, c + r * 0.1, r * (0.35 + k * 0.28), (k * 50 * Math.PI) / 180, ((k * 50 + 200) * Math.PI) / 180); ctx.strokeStyle = rgba(accent, 0.45); ctx.lineWidth = r * 0.13; ctx.lineCap = "round"; ctx.stroke(); }
      break;
    case "cracks":
      ctx.save(); ctx.shadowColor = accent; ctx.shadowBlur = r * 0.25;
      for (let i = 0; i < 5; i++) {
        ctx.beginPath(); let x = c - r + rnd() * r * 2, y = c - r + rnd() * r * 0.4; ctx.moveTo(x, y);
        for (let j = 0; j < 5; j++) { x += (rnd() - 0.5) * r * 0.6; y += r * (0.2 + rnd() * 0.25); ctx.lineTo(x, y); }
        ctx.strokeStyle = accent; ctx.lineWidth = Math.max(1, r * 0.07); ctx.lineCap = "round"; ctx.stroke();
      }
      ctx.restore(); break;
    case "checker": {
      const s = r * 0.42;
      for (let i = 0; i * s < bw; i++) for (let j = 0; j * s < bw; j++) { ctx.fillStyle = (i + j) % 2 === 0 ? rgba(accent, 0.3) : "rgba(0,0,0,0.12)"; ctx.fillRect(bx + j * s, by + i * s, s, s); }
      break;
    }
    case "stripes":
      ctx.save(); ctx.translate(c, c); ctx.rotate(-Math.PI / 6);
      for (let k = -6; k <= 6; k += 2) { ctx.fillStyle = rgba(accent, 0.4); ctx.fillRect(k * r * 0.22, -r * 2, r * 0.22, r * 4); }
      ctx.restore(); break;
    case "dots": {
      const s = r * 0.32;
      for (let y = by; y < by + bw; y += s) for (let x = bx; x < bx + bw; x += s) { ellipse(ctx, x + rnd() * s * 0.4, y + rnd() * s * 0.4, r * 0.045, r * 0.045); ctx.fillStyle = rgba(accent, 0.75); ctx.fill(); }
      break;
    }
    case "waves":
      for (let k = 0; k < 6; k++) {
        const y0 = by + (bw * (k + 1)) / 7; ctx.beginPath(); ctx.moveTo(bx, y0);
        for (let x = bx; x <= bx + bw; x += r * 0.1) ctx.lineTo(x, y0 + Math.sin(x / r * 4 + k) * r * 0.12);
        ctx.strokeStyle = rgba(accent, 0.4); ctx.lineWidth = r * 0.07; ctx.stroke();
      }
      break;
    case "clouds":
      for (let i = 0; i < 5; i++) { const w = r * (0.35 + rnd() * 0.45); ellipse(ctx, c - r + rnd() * r * 1.5 + w / 2, c - r + rnd() * r * 1.5 + w * 0.35, w / 2, w * 0.35); ctx.fillStyle = rgba(accent, 0.8); ctx.fill(); }
      for (let i = 0; i < 6; i++) { const w = r * (0.3 + rnd() * 0.5); ctx.beginPath(); ctx.roundRect(c - r * 1.1 + rnd() * r * 1.8, c - r + rnd() * r * 1.8, w, w * 0.25, w * 0.12); ctx.fillStyle = "rgba(255,255,255,0.6)"; ctx.fill(); }
      break;
    case "polarCaps":
      ellipse(ctx, c, c - r * 0.9, r * 0.9, r * 0.35); ctx.fillStyle = "rgba(255,255,255,0.9)"; ctx.fill();
      ellipse(ctx, c, c + r * 0.95, r * 0.8, r * 0.3); ctx.fill(); break;
    case "hexgrid": {
      const s = r * 0.26; let row = 0;
      for (let y = by; y < by + bw; y += s * 1.5, row++) for (let x = bx + (row % 2 ? s * 0.87 : 0); x < bx + bw; x += s * 1.73) {
        regular(ctx, x, y, 6, s, s, Math.PI / 6); ctx.strokeStyle = rgba(accent, 0.5); ctx.lineWidth = Math.max(0.6, r * 0.04); ctx.stroke();
      }
      break;
    }
    case "snowflakes":
      for (let i = 0; i < 9; i++) {
        const x = c - r + rnd() * r * 2, y = c - r + rnd() * r * 2, s = r * (0.08 + rnd() * 0.1);
        for (let k = 0; k < 3; k++) { const a = (k / 3) * Math.PI; ctx.beginPath(); ctx.moveTo(x - Math.cos(a) * s, y - Math.sin(a) * s); ctx.lineTo(x + Math.cos(a) * s, y + Math.sin(a) * s); ctx.strokeStyle = rgba(accent, 0.9); ctx.lineWidth = Math.max(0.6, r * 0.03); ctx.stroke(); }
      }
      break;
    case "rainbow":
      ["#EF4444", "#F97316", "#FACC15", "#22C55E", "#3B82F6", "#8B5CF6"].forEach((h, i) => {
        ctx.beginPath(); ctx.arc(c, c + r * 0.9, r * (1.5 - i * 0.16), Math.PI, TAU); ctx.strokeStyle = rgba(h, 0.75); ctx.lineWidth = r * 0.16; ctx.stroke();
      });
      break;
    case "mountains": {
      ctx.beginPath(); ctx.moveTo(bx, c + r * 1.2); let x = bx;
      while (x < bx + bw) { ctx.lineTo(x + r * 0.2, c + r * (0.05 + rnd() * 0.35)); x += r * 0.4; ctx.lineTo(x, c + r * 0.6); }
      ctx.lineTo(bx + bw, c + r * 1.2); ctx.closePath(); ctx.fillStyle = rgba(accent, 0.55); ctx.fill(); break;
    }
    case "pepperoni":
      for (let i = 0; i < 8; i++) { const w = r * 0.32; const x = c - r * 0.85 + rnd() * r * 1.4 + w / 2, y = c - r * 0.85 + rnd() * r * 1.4 + w / 2; ellipse(ctx, x, y, w / 2, w / 2); ctx.fillStyle = accent; ctx.fill(); ellipse(ctx, x - w * 0.08, y - w * 0.08, w * 0.2, w * 0.2); ctx.fillStyle = "rgba(255,255,255,0.25)"; ctx.fill(); }
      break;
    case "sprinkles": {
      const cols = ["#FDE047", "#60A5FA", "#34D399", "#FFFFFF", "#A78BFA"];
      for (let i = 0; i < 26; i++) { const x = c - r + rnd() * r * 2, y = c - r + rnd() * r * 2, a = rnd() * Math.PI; ctx.beginPath(); ctx.moveTo(x - Math.cos(a) * r * 0.07, y - Math.sin(a) * r * 0.07); ctx.lineTo(x + Math.cos(a) * r * 0.07, y + Math.sin(a) * r * 0.07); ctx.strokeStyle = cols[i % 5]; ctx.lineWidth = r * 0.05; ctx.lineCap = "round"; ctx.stroke(); }
      break;
    }
  }
}

function behind(ctx: Ctx, f: Feature, c: number, r: number, c1: string, accent: string) {
  switch (f) {
    case "catEars":
      for (const d of [-1, 1]) { ctx.beginPath(); ctx.moveTo(c + d * r * 0.25, c - r * 0.85); ctx.lineTo(c + d * r * 0.85, c - r * 1.35); ctx.lineTo(c + d * r * 0.9, c - r * 0.45); ctx.closePath(); ctx.fillStyle = c1; ctx.fill(); }
      break;
    case "spikes":
      for (let i = 0; i < 12; i++) { const a = (i / 12) * TAU; poly(ctx, c, c, [[r * 0.9, a - 0.18], [r * 1.32, a], [r * 0.9, a + 0.18]]); ctx.fillStyle = rgba(accent, 0.9); ctx.fill(); }
      break;
    case "horns": case "antenna":
      for (const d of [-1, 1]) {
        ctx.beginPath(); ctx.moveTo(c + d * r * 0.35, c - r * 0.8); ctx.quadraticCurveTo(c + d * r * 0.2, c - r * 1.35, c + d * r * 0.7, c - r * 1.45);
        ctx.strokeStyle = f === "antenna" ? "#94A3B8" : c1; ctx.lineWidth = r * 0.09; ctx.lineCap = "round"; ctx.stroke();
        ellipse(ctx, c + d * r * 0.7, c - r * 1.45, r * 0.12, r * 0.12); ctx.fillStyle = f === "antenna" ? "#F43F5E" : accent; ctx.fill();
      }
      break;
    case "wings": case "fireWings":
      for (const d of [-1, 1]) {
        ctx.beginPath(); ctx.moveTo(c + d * r * 0.6, c - r * 0.1);
        ctx.bezierCurveTo(c + d * r, c - r * 0.9, c + d * r * 1.4, c - r * 1.2, c + d * r * 1.75, c - r * 0.9);
        ctx.bezierCurveTo(c + d * r * 1.7, c - r * 0.1, c + d * r * 1.3, c + r * 0.5, c + d * r * 0.7, c + r * 0.4); ctx.closePath();
        const g = ctx.createLinearGradient(c, c, c + d * r * 1.7, c - r * 0.9);
        const cols = f === "fireWings" ? ["#FDE047", "#EF4444"] : ["#FFFFFF", "#E0E7FF"];
        g.addColorStop(0, cols[0]); g.addColorStop(1, cols[1]); ctx.fillStyle = g; ctx.fill();
      }
      break;
    case "tentacles":
      for (let i = 0; i < 6; i++) {
        const x = c - r * 0.75 + i * r * 0.3; ctx.beginPath(); ctx.moveTo(x, c + r * 0.6);
        ctx.bezierCurveTo(x + r * 0.3, c + r * 0.95, x - r * 0.3, c + r * 1.15, x + (i % 2 ? 1 : -1) * r * 0.25, c + r * 1.45);
        ctx.strokeStyle = c1; ctx.lineWidth = r * 0.17; ctx.lineCap = "round"; ctx.stroke();
      }
      break;
    case "tree":
      ctx.fillStyle = "#78350F"; ctx.fillRect(c - r * 0.1, c - r * 1.45, r * 0.2, r * 0.6);
      for (const [dx, dy, rr] of [[0, -1.55, 0.38], [-0.28, -1.38, 0.28], [0.28, -1.38, 0.28]]) { ellipse(ctx, c + r * dx, c + r * dy, r * rr, r * rr); ctx.fillStyle = "#22C55E"; ctx.fill(); }
      break;
    case "volcanoes":
      for (const [dx, h] of [[-0.45, 0.45], [0.35, 0.6]]) {
        const x = c + dx * r, y = c - r * 0.8;
        poly(ctx, x, y, [[r * 0.35, Math.PI], [r * h, -Math.PI / 2], [r * 0.35, 0]]); ctx.fillStyle = "#44403C"; ctx.fill();
        ellipse(ctx, x, y - r * h - r * 0.04, r * 0.1, r * 0.08); ctx.fillStyle = "#F97316"; ctx.fill();
      }
      break;
    case "halo":
      ellipse(ctx, c, c - r * 1.24, r * 0.65, r * 0.18); ctx.strokeStyle = "#FDE047"; ctx.lineWidth = r * 0.1; ctx.stroke(); break;
    case "unicornHorn": {
      ctx.beginPath(); ctx.moveTo(c - r * 0.18, c - r * 0.75); ctx.lineTo(c + r * 0.05, c - r * 1.7); ctx.lineTo(c + r * 0.22, c - r * 0.75); ctx.closePath();
      const g = ctx.createLinearGradient(c, c - r * 1.7, c, c - r * 0.75); g.addColorStop(0, "#FDE68A"); g.addColorStop(1, "#F472B6"); ctx.fillStyle = g; ctx.fill(); break;
    }
    case "stem": ctx.fillStyle = "#65A30D"; ctx.fillRect(c - r * 0.08, c - r * 1.3, r * 0.16, r * 0.45); break;
    default: break;
  }
}

function front(ctx: Ctx, f: Feature, c: number, r: number, accent: string, shape: Shape) {
  const fy = shape === "mushroom" ? c - r * 0.3 : c;
  switch (f) {
    case "face":
      for (const d of [-1, 1]) {
        ellipse(ctx, c + d * r * 0.32, fy - r * 0.12, r * 0.09, r * 0.13); ctx.fillStyle = "rgba(0,0,0,0.75)"; ctx.fill();
        ellipse(ctx, c + d * r * 0.55, fy + r * 0.12, r * 0.12, r * 0.07); ctx.fillStyle = "rgba(244,114,182,0.45)"; ctx.fill();
      }
      ctx.beginPath(); ctx.arc(c, fy + r * 0.05, r * 0.26, (25 * Math.PI) / 180, (155 * Math.PI) / 180);
      ctx.strokeStyle = "rgba(0,0,0,0.7)"; ctx.lineWidth = r * 0.07; ctx.lineCap = "round"; ctx.stroke(); break;
    case "whiskers":
      for (const d of [-1, 1]) for (const k of [-1, 0, 1]) { ctx.beginPath(); ctx.moveTo(c + d * r * 0.4, c + r * 0.12); ctx.lineTo(c + d * r * 1.05, c + r * (0.12 + 0.13 * k)); ctx.strokeStyle = "rgba(0,0,0,0.5)"; ctx.lineWidth = r * 0.035; ctx.stroke(); }
      break;
    case "eye":
      ellipse(ctx, c, c, r * 0.5, r * 0.3); ctx.fillStyle = "#fff"; ctx.fill();
      ellipse(ctx, c, c, r * 0.22, r * 0.22); ctx.fillStyle = accent; ctx.fill();
      ellipse(ctx, c, c, r * 0.1, r * 0.1); ctx.fillStyle = "#000"; ctx.fill(); break;
    case "crown": {
      const y = c - r * 0.85, w = r * 0.9; ctx.beginPath(); ctx.moveTo(c - w / 2, y);
      for (const [dx, dy] of [[-0.5, -0.4], [-0.25, -0.18], [0, -0.5], [0.25, -0.18], [0.5, -0.4], [0.5, 0]]) ctx.lineTo(c + w * dx, y + r * dy);
      ctx.closePath(); const g = ctx.createLinearGradient(c, y - r * 0.5, c, y); g.addColorStop(0, "#FDE047"); g.addColorStop(1, "#CA8A04"); ctx.fillStyle = g; ctx.fill(); break;
    }
    case "leaf":
      ctx.beginPath(); ctx.moveTo(c + r * 0.15, c - r * 0.95); ctx.quadraticCurveTo(c + r * 0.35, c - r * 1.45, c + r * 0.75, c - r * 1.35);
      ctx.quadraticCurveTo(c + r * 0.7, c - r * 0.95, c + r * 0.15, c - r * 0.95); ctx.fillStyle = "#22C55E"; ctx.fill(); break;
    case "bow":
      poly(ctx, c, c - r * 0.92, [[0, 0], [r * 0.5, Math.PI + 0.45], [r * 0.5, Math.PI - 0.45]]); ctx.fillStyle = "#F43F5E"; ctx.fill();
      poly(ctx, c, c - r * 0.92, [[0, 0], [r * 0.5, -0.45], [r * 0.5, 0.45]]); ctx.fill();
      ellipse(ctx, c, c - r * 0.92, r * 0.1, r * 0.1); ctx.fillStyle = "#BE123C"; ctx.fill(); break;
    case "flag": {
      const px = c + r * 0.35, py = c - r * 0.9;
      ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(px, py - r * 0.75); ctx.strokeStyle = "#E5E7EB"; ctx.lineWidth = r * 0.05; ctx.stroke();
      ctx.beginPath(); ctx.moveTo(px, py - r * 0.75); ctx.lineTo(px + r * 0.5, py - r * 0.62); ctx.lineTo(px, py - r * 0.48); ctx.closePath(); ctx.fillStyle = "#FACC15"; ctx.fill(); break;
    }
    case "sunglasses":
      for (const d of [-1, 1]) { ctx.beginPath(); ctx.roundRect(c + d * r * 0.36 - r * 0.28, c - r * 0.28, r * 0.56, r * 0.34, r * 0.1); ctx.fillStyle = "rgba(0,0,0,0.88)"; ctx.fill(); }
      ctx.beginPath(); ctx.moveTo(c - r * 0.1, c - r * 0.16); ctx.lineTo(c + r * 0.1, c - r * 0.16); ctx.strokeStyle = "#000"; ctx.lineWidth = r * 0.06; ctx.stroke(); break;
    default: break;
  }
}

/** Paint a planet into a square of `size` px starting at (0,0). `phase` animates moons and rings. */
export function paintPlanet(ctx: Ctx, p: PlanetDef, size: number, phase = 0) {
  const c = size / 2, r = size * 0.3;
  if (p.image) { paintPicture(ctx, p, c, r, phase); return; }
  const rnd = rng(p.id);
  const [c0, c1, c2] = p.colors;
  const accent = p.accent ?? "#FFFFFF";
  const shape = p.shape ?? "circle";
  const eo: CanvasFillRule = shape === "donut" ? "evenodd" : "nonzero";

  if (p.glow) {
    const g = ctx.createRadialGradient(c, c, r * 0.8, c, c, r * 1.6);
    g.addColorStop(0, rgba(accent, 0.45)); g.addColorStop(1, rgba(accent, 0));
    ctx.fillStyle = g; ellipse(ctx, c, c, r * 1.6, r * 1.6); ctx.fill();
  }
  if (p.ring) drawRing(ctx, p.ring, c, r, false, phase);
  for (const f of p.features ?? []) behind(ctx, f, c, r, c1, accent);

  if (shape === "mushroom") {
    const g = ctx.createLinearGradient(c - r * 0.3, c, c + r * 0.3, c); g.addColorStop(0, "#FEF3C7"); g.addColorStop(1, "#D6D3D1");
    ctx.beginPath(); ctx.roundRect(c - r * 0.32, c + r * 0.05, r * 0.64, r * 0.85, r * 0.2); ctx.fillStyle = g; ctx.fill();
  }
  const body = ctx.createRadialGradient(c - r * 0.35, c - r * 0.4, 0, c - r * 0.35, c - r * 0.4, r * 1.5);
  body.addColorStop(0, c0); body.addColorStop(0.5, c1); body.addColorStop(1, c2);
  shapePath(ctx, shape, c, r); ctx.fillStyle = body; ctx.fill(eo);

  ctx.save();
  shapePath(ctx, shape, c, r); ctx.clip(eo);
  pattern(ctx, p.pattern ?? "plain", c, r, accent, rnd);
  const shade = ctx.createRadialGradient(c - r * 0.3, c - r * 0.35, r * 0.5, c - r * 0.3, c - r * 0.35, r * 1.6);
  shade.addColorStop(0, "rgba(0,0,0,0)"); shade.addColorStop(1, "rgba(0,0,0,0.5)");
  ctx.fillStyle = shade; ctx.fillRect(0, 0, size, size);
  ellipse(ctx, c - r * 0.35, c - r * 0.55, r * 0.27, r * 0.17); ctx.fillStyle = "rgba(255,255,255,0.28)"; ctx.fill();
  ctx.restore();

  if (p.emoji) {
    const g = ctx.createRadialGradient(c, c, 0, c, c, r * 0.65); g.addColorStop(0, "rgba(255,255,255,0.45)"); g.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = g; ellipse(ctx, c, c, r * 0.62, r * 0.62); ctx.fill();
    ctx.save(); ctx.font = `${r * 1.1}px "Segoe UI Emoji","Apple Color Emoji",sans-serif`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.shadowColor = "rgba(0,0,0,0.45)"; ctx.shadowBlur = r * 0.1; ctx.fillText(p.emoji, c, c + r * 0.08); ctx.restore();
  }
  for (const f of p.features ?? []) front(ctx, f, c, r, accent, shape);
  if (p.landmarks?.length || p.walkers?.length) paintSurface(ctx, p, c, r, phase);
  if (p.ring) drawRing(ctx, p.ring, c, r, true, phase);
  if (p.crafts?.length) paintCrafts(ctx, p.crafts, c, r, phase);

  for (let i = 0; i < (p.moons ?? 0); i++) {
    const a = (i / Math.max(1, p.moons!) + phase) * TAU + 0.6;
    const mx = c + Math.cos(a) * r * 1.45, my = c + Math.sin(a) * r * 0.55 - r * 0.2, mr = r * (0.16 + 0.04 * (i % 2));
    const g = ctx.createRadialGradient(mx - mr * 0.4, my - mr * 0.4, 0, mx - mr * 0.4, my - mr * 0.4, mr * 1.6);
    g.addColorStop(0, "#F1F5F9"); g.addColorStop(1, "#64748B"); ctx.fillStyle = g; ellipse(ctx, mx, my, mr, mr); ctx.fill();
  }
}

// ---------- Store planets: surface, spacecraft, pictures ----------

const EMOJI_FONT = '"Segoe UI Emoji","Apple Color Emoji","Noto Color Emoji",sans-serif';

/** Landmarks stand on the upper rim; walkers stroll back and forth across the top */
function paintSurface(ctx: Ctx, p: PlanetDef, c: number, r: number, phase: number) {
  const size = r * 0.6;
  const standing = (e: string, angle: number, scale = 1, flip = false, lift = 0) => {
    const edge = r + size * scale * 0.38 + lift;
    ctx.save();
    ctx.translate(c + Math.cos(angle) * edge, c + Math.sin(angle) * edge);
    ctx.rotate(angle + Math.PI / 2);
    if (flip) ctx.scale(-1, 1);
    ctx.font = `${size * scale}px ${EMOJI_FONT}`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(e, 0, 0);
    ctx.restore();
  };
  const n = p.landmarks?.length ?? 0;
  (p.landmarks ?? []).forEach((e, i) => { const t = n === 1 ? 0.5 : i / (n - 1); standing(e, -Math.PI / 2 + (t - 0.5) * 2.1, 1.05); });
  (p.walkers ?? []).forEach((e, i) => {
    const off = i * 2.1, wave = Math.sin(phase * TAU + off);
    const right = Math.cos(phase * TAU + off) > 0;
    const bounce = Math.abs(Math.sin(phase * TAU * 12 + off)) * size * 0.08;
    standing(e, -Math.PI / 2 + wave * 0.75, 0.85, right, bounce);
  });
}

function paintCrafts(ctx: Ctx, all: Craft[], c: number, r: number, phase: number) {
  if (all.includes("stars")) twinkles(ctx, c, r, phase);
  if (all.includes("asteroids")) asteroidBelt(ctx, c, r, phase);
  const crafts = all.filter((x) => x !== "stars" && x !== "asteroids");
  crafts.forEach((craft, i) => {
    const a = (i / Math.max(1, crafts.length) + phase * (craft === "comet" ? 0.6 : 1)) * TAU + 2.2;
    const ox = r * (craft === "comet" ? 1.55 : 1.42), oy = r * 0.62;
    const x = c + Math.cos(a) * ox, y = c + Math.sin(a) * oy - r * 0.1;
    const heading = Math.atan2(Math.cos(a) * oy, -Math.sin(a) * ox);
    const u = r * (craft === "comet" ? 0.26 : 0.33);
    ctx.save(); ctx.translate(x, y);
    if (!["ufo", "station", "satellite"].includes(craft)) ctx.rotate(heading);
    if (craft === "rocket") rocket(ctx, u);
    else if (craft === "ufo") ufo(ctx, u);
    else if (craft === "station") station(ctx, u, phase);
    else if (craft === "satellite") satellite(ctx, u * 0.85);
    else if (craft === "shuttle") shuttle(ctx, u);
    else if (craft === "comet") comet(ctx, u);
    else if (craft === "astronaut") { ctx.rotate(-heading); ctx.font = `${u * 2}px ${EMOJI_FONT}`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText("🧑‍🚀", 0, 0); }
    ctx.restore();
  });
}

function asteroidBelt(ctx: Ctx, c: number, r: number, phase: number) {
  const rnd = rng("belt");
  for (let k = 0; k < 14; k++) {
    const a = (k / 14 + phase * 0.35) * TAU + rnd() * 0.3;
    const rx = r * (1.5 + rnd() * 0.18), ry = r * (0.5 + rnd() * 0.1);
    const x = c + Math.cos(a) * rx, y = c + Math.sin(a) * ry, s = r * (0.06 + rnd() * 0.07);
    const spin = phase * TAU * 2 + k;
    ctx.beginPath();
    for (let v = 0; v < 6; v++) {
      const va = (v / 6) * TAU + spin, vr = s * (0.75 + rnd() * 0.45);
      const px = x + Math.cos(va) * vr, py = y + Math.sin(va) * vr;
      if (v === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.closePath();
    const g = ctx.createLinearGradient(x - s, y - s, x + s, y + s); g.addColorStop(0, "#D6D3D1"); g.addColorStop(1, "#57534E");
    ctx.fillStyle = g; ctx.fill();
  }
}

function twinkles(ctx: Ctx, c: number, r: number, phase: number) {
  const rnd = rng("stars");
  for (let k = 0; k < 7; k++) {
    const a = rnd() * TAU, d = r * (1.35 + rnd() * 0.35);
    const x = c + Math.cos(a) * d, y = c + Math.sin(a) * d * 0.85;
    const tw = 0.5 + 0.5 * Math.sin(phase * TAU * 3 + k * 1.7), s = r * (0.05 + 0.07 * tw);
    ctx.beginPath();
    ctx.moveTo(x, y - s * 2); ctx.quadraticCurveTo(x, y, x + s * 2, y); ctx.quadraticCurveTo(x, y, x, y + s * 2);
    ctx.quadraticCurveTo(x, y, x - s * 2, y); ctx.quadraticCurveTo(x, y, x, y - s * 2);
    ctx.fillStyle = rgba("#FEF9C3", 0.55 + 0.45 * tw); ctx.fill();
  }
}

function rocket(ctx: Ctx, u: number) {
  let g = ctx.createLinearGradient(-u, 0, -u * 2.1, 0); g.addColorStop(0, "#FDE047"); g.addColorStop(0.5, "#22D3EE"); g.addColorStop(1, "rgba(37,99,235,0)");
  ctx.beginPath(); ctx.moveTo(-u, -u * 0.28); ctx.quadraticCurveTo(-u * 2.1, 0, -u, u * 0.28); ctx.fillStyle = g; ctx.fill();
  ctx.fillStyle = "#F05252";
  ctx.beginPath(); ctx.moveTo(-u * 0.5, -u * 0.3); ctx.lineTo(-u * 1.05, -u * 0.75); ctx.lineTo(-u * 0.95, -u * 0.2); ctx.fill();
  ctx.beginPath(); ctx.moveTo(-u * 0.5, u * 0.3); ctx.lineTo(-u * 1.05, u * 0.75); ctx.lineTo(-u * 0.95, u * 0.2); ctx.fill();
  g = ctx.createLinearGradient(0, -u * 0.4, 0, u * 0.4); g.addColorStop(0, "#F8FAFC"); g.addColorStop(1, "#CBD5E1");
  ctx.beginPath(); ctx.moveTo(u * 1.1, 0); ctx.quadraticCurveTo(u * 0.5, -u * 0.55, -u, -u * 0.36); ctx.lineTo(-u, u * 0.36);
  ctx.quadraticCurveTo(u * 0.5, u * 0.55, u * 1.1, 0); ctx.fillStyle = g; ctx.fill();
  ctx.beginPath(); ctx.moveTo(u * 1.1, 0); ctx.quadraticCurveTo(u * 0.9, -u * 0.25, u * 0.55, -u * 0.33); ctx.lineTo(u * 0.55, u * 0.33);
  ctx.quadraticCurveTo(u * 0.9, u * 0.25, u * 1.1, 0); ctx.fillStyle = "#F05252"; ctx.fill();
  ellipse(ctx, u * 0.22, 0, u * 0.22, u * 0.22); ctx.fillStyle = "#475569"; ctx.fill();
  ellipse(ctx, u * 0.22, 0, u * 0.17, u * 0.17); ctx.fillStyle = "#38BDF8"; ctx.fill();
}

function ufo(ctx: Ctx, u: number) {
  const beam = ctx.createLinearGradient(0, u * 0.2, 0, u * 1.3); beam.addColorStop(0, "rgba(190,242,100,0.45)"); beam.addColorStop(1, "rgba(190,242,100,0)");
  ellipse(ctx, 0, u * 0.7, u * 0.55, u * 0.55); ctx.fillStyle = beam; ctx.fill();
  ellipse(ctx, 0, -u * 0.25, u * 0.6, u * 0.5); ctx.fillStyle = "rgba(30,41,59,0.9)"; ctx.fill();
  for (const dx of [-0.25, 0.25]) {
    ellipse(ctx, u * dx, -u * 0.4, u * 0.13, u * 0.15); ctx.fillStyle = "#4ADE80"; ctx.fill();
    ctx.fillStyle = "#000"; ellipse(ctx, u * (dx - 0.05), -u * 0.41, u * 0.035, u * 0.04); ctx.fill(); ellipse(ctx, u * (dx + 0.05), -u * 0.41, u * 0.035, u * 0.04); ctx.fill();
  }
  const g = ctx.createLinearGradient(0, -u * 0.3, 0, u * 0.3); g.addColorStop(0, "#E5E7EB"); g.addColorStop(1, "#9CA3AF");
  ellipse(ctx, 0, 0, u * 1.15, u * 0.27); ctx.fillStyle = g; ctx.fill();
  ellipse(ctx, 0, u * 0.22, u * 0.75, u * 0.17); ctx.fillStyle = "#A78BFA"; ctx.fill();
  ctx.fillStyle = "#FBCFE8"; for (let k = -2; k <= 2; k++) { ellipse(ctx, k * u * 0.28, u * 0.22, u * 0.05, u * 0.05); ctx.fill(); }
}

function station(ctx: Ctx, u: number, spin: number) {
  ctx.rotate(spin * Math.PI);
  for (const side of [-1, 1]) {
    const x = side < 0 ? -u * 1.35 : u * 0.45;
    const g = ctx.createLinearGradient(x, -u * 0.28, x + u * 0.9, u * 0.28); g.addColorStop(0, "#60A5FA"); g.addColorStop(1, "#1D4ED8");
    ctx.fillStyle = g; ctx.fillRect(x, -u * 0.28, u * 0.9, u * 0.56);
  }
  ctx.fillStyle = "#CBD5E1"; ctx.fillRect(-u * 0.5, -u * 0.05, u, u * 0.1);
  ctx.lineWidth = Math.max(0.8, u * 0.12); ctx.strokeStyle = "#E2E8F0"; ellipse(ctx, 0, 0, u * 0.45, u * 0.45); ctx.stroke();
  ellipse(ctx, 0, 0, u * 0.22, u * 0.22); ctx.fillStyle = "#F8FAFC"; ctx.fill();
  ellipse(ctx, 0, 0, u * 0.08, u * 0.08); ctx.fillStyle = "#F43F5E"; ctx.fill();
}

function satellite(ctx: Ctx, u: number) {
  ctx.rotate(-0.44);
  ctx.fillStyle = "#3B82F6"; ctx.fillRect(-u * 1.2, -u * 0.22, u * 0.8, u * 0.44); ctx.fillRect(u * 0.4, -u * 0.22, u * 0.8, u * 0.44);
  ctx.fillStyle = "#FBBF24"; ctx.beginPath(); ctx.roundRect(-u * 0.35, -u * 0.3, u * 0.7, u * 0.6, u * 0.1); ctx.fill();
  ctx.beginPath(); ctx.arc(0, -u * 0.55, u * 0.3, Math.PI * 1.1, Math.PI * 1.9); ctx.strokeStyle = "#E5E7EB"; ctx.lineWidth = Math.max(0.8, u * 0.1); ctx.stroke();
}

function shuttle(ctx: Ctx, u: number) {
  ctx.beginPath(); ctx.moveTo(u * 0.2, 0); ctx.lineTo(-u * 0.8, -u * 0.8); ctx.lineTo(-u * 0.9, u * 0.8); ctx.closePath(); ctx.fillStyle = "#CBD5E1"; ctx.fill();
  ctx.beginPath(); ctx.roundRect(-u, -u * 0.24, u * 2, u * 0.48, u * 0.24); ctx.fillStyle = "#F8FAFC"; ctx.fill();
  ctx.beginPath(); ctx.roundRect(u * 0.55, -u * 0.24, u * 0.45, u * 0.48, u * 0.24); ctx.fillStyle = "#1F2937"; ctx.fill();
  ellipse(ctx, -u * 1.15, 0, u * 0.2, u * 0.15); ctx.fillStyle = "#FB923C"; ctx.fill();
}

function comet(ctx: Ctx, u: number) {
  const g = ctx.createLinearGradient(0, 0, -u * 3.2, 0); g.addColorStop(0, "rgba(165,243,252,0.85)"); g.addColorStop(1, "rgba(165,243,252,0)");
  ctx.beginPath(); ctx.moveTo(0, -u * 0.35); ctx.quadraticCurveTo(-u * 1.4, -u * 0.4, -u * 3.2, 0); ctx.quadraticCurveTo(-u * 1.4, u * 0.4, 0, u * 0.35); ctx.fillStyle = g; ctx.fill();
  const h = ctx.createRadialGradient(0, 0, 0, 0, 0, u * 0.6); h.addColorStop(0, "rgba(255,255,255,0.9)"); h.addColorStop(1, "rgba(103,232,249,0)");
  ellipse(ctx, 0, 0, u * 0.6, u * 0.6); ctx.fillStyle = h; ctx.fill();
  ellipse(ctx, 0, 0, u * 0.26, u * 0.26); ctx.fillStyle = "#FFFFFF"; ctx.fill();
}

/** Pixel-art pictures, loaded once */
const PICTURES: Record<string, HTMLImageElement> = {};
export function registerPicture(name: string, url: string) {
  const img = new Image(); img.src = url; PICTURES[name] = img;
}

function paintPicture(ctx: Ctx, p: PlanetDef, c: number, r: number, phase: number) {
  const accent = p.accent ?? "#FFFFFF";
  const g = ctx.createRadialGradient(c, c, r * 0.3, c, c, r * 1.6); g.addColorStop(0, rgba(accent, 0.45)); g.addColorStop(1, rgba(accent, 0));
  ctx.fillStyle = g; ellipse(ctx, c, c, r * 1.6, r * 1.6); ctx.fill();
  const bob = Math.sin(phase * TAU) * r * 0.08, side = r * 3.3;
  if (p.image === "ufo") {
    const b = ctx.createLinearGradient(c, c + r * 0.25, c, c + r * 1.3); b.addColorStop(0, rgba(accent, 0.5)); b.addColorStop(1, rgba(accent, 0));
    ctx.beginPath(); ctx.moveTo(c - r * 0.35, c + r * 0.25 + bob); ctx.lineTo(c + r * 0.35, c + r * 0.25 + bob); ctx.lineTo(c + r * 0.7, c + r * 1.3); ctx.lineTo(c - r * 0.7, c + r * 1.3); ctx.closePath();
    ctx.fillStyle = b; ctx.fill();
  }
  // Animated pictures (from a GIF) are registered as name_0, name_1, … and play at ~8 frames a second
  let n = 0; while (PICTURES[`${p.image}_${n}`]) n++;
  const img = n ? PICTURES[`${p.image}_${Math.floor(performance.now() / 125) % n}`] : PICTURES[p.image!];
  if (img?.complete && img.naturalWidth) {
    ctx.save(); ctx.imageSmoothingEnabled = false; ctx.drawImage(img, c - side / 2, c - side / 2 + bob, side, side); ctx.restore();
  }
}

// ---------- Stars ----------

export const SUNS: Record<string, { name: string; level: number; colors: [string, string, string]; scale: number }> = {
  yellow: { name: "Yellow Sun", level: 1, colors: ["#FFFBEB", "#FDE047", "#F97316"], scale: 1 },
  red: { name: "Red Giant", level: 6, colors: ["#FEE2E2", "#F87171", "#991B1B"], scale: 1.35 },
  blue: { name: "Blue Star", level: 16, colors: ["#EFF6FF", "#60A5FA", "#1D4ED8"], scale: 1.1 },
  white: { name: "White Dwarf", level: 21, colors: ["#FFFFFF", "#E0E7FF", "#818CF8"], scale: 0.7 },
  binary: { name: "Twin Stars", level: 31, colors: ["#FFFBEB", "#FDBA74", "#F43F5E"], scale: 1 },
  pulsar: { name: "Pulsar", level: 41, colors: ["#ECFEFF", "#22D3EE", "#7C3AED"], scale: 1 },
};

export function paintSun(ctx: Ctx, sun: string, cx: number, cy: number, r: number, t: number) {
  const s = SUNS[sun] ?? SUNS.yellow;
  const pulse = 1 + Math.sin(t * 2) * 0.05;
  /** A star that reads as a real sun: wide corona, slow rays, a limb-darkened disc and drifting granules */
  const star = (x: number, y: number, rad: number) => {
    let g = ctx.createRadialGradient(x, y, rad, x, y, rad * 3.4 * pulse);
    g.addColorStop(0, rgba(s.colors[2], 0.28)); g.addColorStop(1, rgba(s.colors[2], 0));
    ctx.fillStyle = g; ellipse(ctx, x, y, rad * 3.4, rad * 3.4); ctx.fill();
    g = ctx.createRadialGradient(x, y, rad * 0.9, x, y, rad * 1.8);
    g.addColorStop(0, rgba(s.colors[1], 0.75)); g.addColorStop(1, rgba(s.colors[2], 0));
    ctx.fillStyle = g; ellipse(ctx, x, y, rad * 1.8, rad * 1.8); ctx.fill();
    ctx.save(); ctx.globalAlpha = 0.22;
    for (let k = 0; k < 12; k++) {
      const a = (k / 12) * TAU + t * 0.05, len = rad * (1.9 + 0.35 * Math.sin(t * 0.9 + k * 1.7));
      ctx.beginPath(); ctx.moveTo(x + Math.cos(a - 0.09) * rad * 0.9, y + Math.sin(a - 0.09) * rad * 0.9);
      ctx.lineTo(x + Math.cos(a) * len, y + Math.sin(a) * len); ctx.lineTo(x + Math.cos(a + 0.09) * rad * 0.9, y + Math.sin(a + 0.09) * rad * 0.9); ctx.closePath();
      const rg = ctx.createLinearGradient(x, y, x + Math.cos(a) * len, y + Math.sin(a) * len);
      rg.addColorStop(0, s.colors[0]); rg.addColorStop(1, rgba(s.colors[1], 0)); ctx.fillStyle = rg; ctx.fill();
    }
    ctx.restore();
    g = ctx.createRadialGradient(x, y, 0, x, y, rad);
    g.addColorStop(0, s.colors[0]); g.addColorStop(0.62, s.colors[1]); g.addColorStop(1, s.colors[2]);
    ctx.fillStyle = g; ellipse(ctx, x, y, rad, rad); ctx.fill();
    ctx.save(); ellipse(ctx, x, y, rad, rad); ctx.clip(); ctx.globalAlpha = 0.25;
    for (let k = 0; k < 9; k++) {
      const a = k * 2.4 + t * 0.12, d = rad * (0.25 + 0.55 * (((k * 37) % 10) / 10)), gr = rad * (0.16 + 0.06 * Math.sin(t + k));
      const qx = x + Math.cos(a) * d, qy = y + Math.sin(a) * d * 0.9;
      const sg = ctx.createRadialGradient(qx, qy, 0, qx, qy, gr);
      sg.addColorStop(0, k % 3 === 0 ? s.colors[2] : "#FFFFFF"); sg.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = sg; ellipse(ctx, qx, qy, gr, gr); ctx.fill();
    }
    ctx.restore();
    ctx.strokeStyle = rgba(s.colors[0], 0.5); ctx.lineWidth = Math.max(1, rad * 0.04); ellipse(ctx, x, y, rad, rad); ctx.stroke();
  };
  if (sun === "binary") {
    const a = t * 0.8;
    star(cx + Math.cos(a) * r * 0.9, cy + Math.sin(a) * r * 0.45, r * 0.7);
    star(cx - Math.cos(a) * r * 0.9, cy - Math.sin(a) * r * 0.45, r * 0.55);
  } else if (sun === "pulsar") {
    for (const k of [0, Math.PI]) {
      const a = t * 1.6 + k;
      ctx.beginPath(); ctx.moveTo(cx, cy);
      ctx.lineTo(cx + Math.cos(a - 0.08) * r * 4, cy + Math.sin(a - 0.08) * r * 4);
      ctx.lineTo(cx + Math.cos(a + 0.08) * r * 4, cy + Math.sin(a + 0.08) * r * 4); ctx.closePath();
      const g = ctx.createLinearGradient(cx, cy, cx + Math.cos(a) * r * 4, cy + Math.sin(a) * r * 4);
      g.addColorStop(0, rgba(s.colors[1], 0.8)); g.addColorStop(1, rgba(s.colors[1], 0)); ctx.fillStyle = g; ctx.fill();
    }
    star(cx, cy, r * 0.65);
  } else star(cx, cy, r);
}
