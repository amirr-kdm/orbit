import { useEffect, useState } from "react";
import pkg from "../../package.json";

export const APP_VERSION: string = pkg.version;
export const RELEASES_PAGE = "https://github.com/amirr-kdm/orbit/releases/latest";

const newer = (a: string, b: string) => {
  const x = a.split(".").map(Number), y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) { const p = x[i] || 0, q = y[i] || 0; if (p !== q) return p > q; }
  return false;
};

/** Checks GitHub for a newer Orbit (now and every 6 hours); notifies once per version */
export function useUpdateCheck() {
  const [available, setAvailable] = useState<string | null>(null);
  useEffect(() => {
    const check = async () => {
      try {
        const r = await fetch("https://api.github.com/repos/amirr-kdm/orbit/releases/latest");
        if (!r.ok) return;
        const latest = String((await r.json()).tag_name ?? "").replace(/^v/i, "");
        if (!latest || !newer(latest, APP_VERSION)) return;
        setAvailable(latest);
      } catch { /* offline */ }
    };
    check();
    const t = setInterval(check, 6 * 3600_000);
    return () => clearInterval(t);
  }, []);
  return available;
}
