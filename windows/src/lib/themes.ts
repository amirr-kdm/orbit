// Design templates and fonts — the same choices as the Mac app (Theme.swift), saved under the same names
// (settings.template, settings.font, settings.scheduleFontSize) so they follow you between Mac and Windows.
import { isLight } from "./model";

/** How filled schedule cells are painted */
export type CellFill = "gradient" | "tint" | "neon" | "card" | "glass" | "grid" | "paper" | "outline";
export type TemplateID = "aurora" | "glass" | "pastel" | "neon" | "paper" | "sunset" | "forest" | "classic"
  | "latte" | "notebook" | "midnight" | "matcha" | "lavender" | "ocean" | "ember" | "sakura";

export interface Template {
  id: TemplateID; title: string; subtitle: string; accent: string; fill: CellFill; corner: number; spacing: number; shadow: boolean;
  /** Soft colour blobs behind the pages; empty = plain background */
  blobs: string[];
  /** Base tint of the page (Paper: warm in light mode; Neon: deep navy in dark mode) */
  baseTint?: string;
  /** Colour of a cell that has none picked */
  cell: string;
  /** How strongly `baseTint` covers the page in light and dark mode (missing: the original rule) */
  base?: [number, number];
}

export const TEMPLATES: Template[] = [
  { id: "aurora", title: "Aurora", subtitle: "Vivid gradient cells, soft northern-lights glow", accent: "#5B7CFA", fill: "gradient", corner: 12, spacing: 8, shadow: true, blobs: ["#5B7CFA", "#A855F7", "#22D3EE"], cell: "#5B7CFA" },
  { id: "glass", title: "Frosted Glass", subtitle: "Frosted translucent cells over colour", accent: "#0EA5E9", fill: "glass", corner: 14, spacing: 8, shadow: true, blobs: ["#F472B6", "#60A5FA", "#34D399"], cell: "#0EA5E9" },
  { id: "pastel", title: "Pastel", subtitle: "Gentle tints, big rounded corners", accent: "#E879F9", fill: "tint", corner: 16, spacing: 10, shadow: false, blobs: ["#FBCFE8", "#BFDBFE", "#FDE68A"], cell: "#C084FC" },
  { id: "neon", title: "Neon", subtitle: "Glowing outlines — best in dark mode", accent: "#22D3EE", fill: "neon", corner: 10, spacing: 8, shadow: false, blobs: ["#22D3EE", "#F0ABFC"], baseTint: "#0B1020", cell: "#22D3EE" },
  { id: "paper", title: "Paper", subtitle: "Clean cards with a colour edge", accent: "#C2410C", fill: "card", corner: 8, spacing: 6, shadow: true, blobs: [], baseTint: "#F5EFE6", cell: "#C2410C" },
  { id: "sunset", title: "Sunset", subtitle: "Warm oranges and pinks", accent: "#F97316", fill: "gradient", corner: 12, spacing: 8, shadow: true, blobs: ["#F97316", "#EC4899", "#FACC15"], cell: "#F97316" },
  { id: "forest", title: "Forest", subtitle: "Calm greens, earthy tones", accent: "#16A34A", fill: "tint", corner: 10, spacing: 8, shadow: false, blobs: ["#16A34A", "#84CC16", "#0D9488"], cell: "#16A34A" },
  { id: "classic", title: "Classic Grid", subtitle: "The simple timetable grid", accent: "#5B7CFA", fill: "grid", corner: 0, spacing: 0, shadow: false, blobs: [], cell: "#8E8E93" },
  { id: "latte", title: "Latte", subtitle: "Warm cream and coffee, cosy and calm", accent: "#A0522D", fill: "tint", corner: 14, spacing: 9, shadow: false, blobs: ["#D4A373", "#E9C46A", "#F4A261"], baseTint: "#F3E9DC", base: [1, 0.07], cell: "#A0522D" },
  { id: "notebook", title: "Notebook", subtitle: "Ruled paper with a coloured margin line", accent: "#2563EB", fill: "paper", corner: 4, spacing: 7, shadow: true, blobs: [], baseTint: "#FBF8F1", base: [1, 0.04], cell: "#2563EB" },
  { id: "midnight", title: "Midnight Black", subtitle: "Pure black, thin glowing frames", accent: "#71717A", fill: "outline", corner: 10, spacing: 8, shadow: false, blobs: [], baseTint: "#000000", base: [0, 1], cell: "#A1A1AA" },
  { id: "matcha", title: "Matcha", subtitle: "Soft sage greens, quiet and calm", accent: "#6B8F4E", fill: "tint", corner: 12, spacing: 9, shadow: false, blobs: ["#A3B18A", "#DAD7CD", "#588157"], baseTint: "#F1F3EC", base: [1, 0.05], cell: "#6B8F4E" },
  { id: "lavender", title: "Lavender Dusk", subtitle: "Dusky purples over frosted glass", accent: "#8B5CF6", fill: "glass", corner: 16, spacing: 9, shadow: true, blobs: ["#C4B5FD", "#F9A8D4", "#A5B4FC"], cell: "#8B5CF6" },
  { id: "ocean", title: "Deep Ocean", subtitle: "Deep blues, calm like the sea at night", accent: "#0284C7", fill: "gradient", corner: 12, spacing: 8, shadow: true, blobs: ["#0EA5E9", "#1E3A8A", "#14B8A6"], baseTint: "#06142B", base: [0.04, 1], cell: "#0284C7" },
  { id: "ember", title: "Ember", subtitle: "Glowing coals on a warm dark page", accent: "#DC2626", fill: "gradient", corner: 12, spacing: 8, shadow: true, blobs: ["#B91C1C", "#F59E0B", "#7C2D12"], baseTint: "#1A0F0A", base: [0.03, 1], cell: "#DC2626" },
  { id: "sakura", title: "Sakura", subtitle: "Cherry-blossom pinks, light and gentle", accent: "#EC4899", fill: "tint", corner: 16, spacing: 10, shadow: false, blobs: ["#FBCFE8", "#FECDD3", "#FDE68A"], baseTint: "#FFF5F7", base: [1, 0.05], cell: "#EC4899" },
];
export const templateOf = (id?: string) => TEMPLATES.find((t) => t.id === id) ?? TEMPLATES[0];

export interface FontDef { id: string; title: string; css: string; whole: boolean }
/** "Whole app" fonts change everything; the others style the weekly schedule (like the Mac app) */
export const FONTS: FontDef[] = [
  { id: "system", title: "System (Segoe UI)", css: `"Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif`, whole: true },
  { id: "rounded", title: "Rounded", css: `"SF Pro Rounded", "Nunito", "Varela Round", "Segoe UI Variable Display", "Segoe UI", sans-serif`, whole: true },
  { id: "serif", title: "Serif", css: `"New York", "Cambria", Georgia, serif`, whole: true },
  { id: "mono", title: "Mono", css: `"SF Mono", "Cascadia Code", Consolas, monospace`, whole: true },
  { id: "avenir", title: "Avenir Next", css: `"Avenir Next", "Century Gothic", "Segoe UI", sans-serif`, whole: false },
  { id: "futura", title: "Futura", css: `Futura, "Century Gothic", sans-serif`, whole: false },
  { id: "helvetica", title: "Helvetica Neue", css: `"Helvetica Neue", Arial, sans-serif`, whole: false },
  { id: "gillSans", title: "Gill Sans", css: `"Gill Sans", "Gill Sans MT", Calibri, sans-serif`, whole: false },
  { id: "optima", title: "Optima", css: `Optima, Candara, "Segoe UI", sans-serif`, whole: false },
  { id: "georgia", title: "Georgia", css: `Georgia, serif`, whole: false },
  { id: "baskerville", title: "Baskerville", css: `Baskerville, "Baskerville Old Face", "Book Antiqua", serif`, whole: false },
  { id: "typewriter", title: "American Typewriter", css: `"American Typewriter", "Courier New", monospace`, whole: false },
  { id: "chalkboard", title: "Chalkboard", css: `"Chalkboard SE", "Comic Sans MS", cursive`, whole: false },
];
export const fontOf = (id?: string) => FONTS.find((f) => f.id === id) ?? FONTS[0];

/** How a schedule cell looks in a template: its background style and text colour */
export function cellLook(t: Template, hex: string | undefined, filled: boolean, dark: boolean): { style: React.CSSProperties; text?: string } {
  const r = t.corner;
  if (!filled) return { style: t.fill === "grid" ? { borderRadius: 0, border: "0.5px solid color-mix(in srgb, var(--muted) 35%, transparent)" } : { borderRadius: r } };
  const c = hex ?? t.cell;
  switch (t.fill) {
    case "gradient": return { style: { borderRadius: r, background: `linear-gradient(135deg, ${c}, ${c}b8)`, border: "1px solid rgba(255,255,255,.22)",
      boxShadow: t.shadow ? `0 3px 6px ${c}4d` : "none" }, text: isLight(c) ? "rgba(0,0,0,.8)" : "white" };
    case "tint": return { style: { borderRadius: r, background: `${c}38`, border: `1px solid ${c}66`, boxShadow: "none" } };
    case "neon": return { style: { borderRadius: r, background: `${c}14`, border: `1.5px solid ${c}`, boxShadow: `0 0 6px ${c}b3` }, text: c };
    case "card": return { style: { borderRadius: r, background: `linear-gradient(90deg, ${c} 5px, var(--card) 5px)`, border: "1px solid color-mix(in srgb, var(--text) 8%, transparent)",
      boxShadow: t.shadow ? `0 3px 6px ${c}4d` : "none" } };
    case "glass": return { style: { borderRadius: r, background: `linear-gradient(${c}47, ${c}47), ${dark ? "rgba(255,255,255,.06)" : "rgba(255,255,255,.55)"}`, backdropFilter: "blur(14px)",
      border: "1px solid rgba(255,255,255,.35)", boxShadow: t.shadow ? `0 3px 6px ${c}4d` : "none" } };
    case "paper": return { style: { borderRadius: r, border: "1px solid color-mix(in srgb, var(--text) 10%, transparent)", boxShadow: t.shadow ? "0 2px 5px rgba(0,0,0,.12)" : "none",
      // a sheet of ruled paper: faint blue lines, a coloured margin line on the left
      background: `linear-gradient(90deg, transparent 8px, ${c}d9 8px, ${c}d9 9.5px, transparent 9.5px), repeating-linear-gradient(transparent 0 13px, rgba(147,197,253,.45) 13px 14px), ${dark ? "#1E1E22" : "#FFFFFF"}` } };
    case "outline": return { style: { borderRadius: r, background: `${c}0f`, border: `1px solid ${c}e6`, boxShadow: `0 0 4px ${c}59` } };
    case "grid": return { style: { borderRadius: 0, background: `${c}4d`, border: "0.5px solid color-mix(in srgb, var(--muted) 35%, transparent)", boxShadow: "none" } };
  }
}

/** The soft colour blobs behind the pages, as a CSS background */
export function ambient(t: Template, dark: boolean): string {
  const pos = ["12% 8%", "92% 90%", "75% 10%"];
  const blobs = t.blobs.map((c, i) => `radial-gradient(circle at ${pos[i % 3]}, ${c}${dark ? "38" : "47"} 0, transparent 38%)`);
  const hex2 = (a: number) => Math.round(a * 255).toString(16).padStart(2, "0");
  if (t.base && t.baseTint) {
    const a = t.base[dark ? 1 : 0];
    return [...blobs, a > 0 ? `linear-gradient(${t.baseTint}${hex2(a)}, ${t.baseTint}${hex2(a)})` : ""].filter(Boolean).join(", ");
  }
  const base = t.baseTint ? (t.fill === "neon" ? (dark ? t.baseTint : `${t.baseTint}0a`) : (dark ? `${t.baseTint}0f` : t.baseTint)) : null;
  return [...blobs, base ? `linear-gradient(${base}, ${base})` : ""].filter(Boolean).join(", ");
}

/** Is the app showing dark mode (from the Appearance setting, or the system's when it's "system") */
export const isDarkMode = (appearance: string) =>
  appearance === "dark" || (appearance === "system" && matchMedia("(prefers-color-scheme: dark)").matches);
