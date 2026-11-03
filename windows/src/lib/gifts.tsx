// Gifts from friends and from the admin: a planet or rockets in a gift box. The server keeps them (supabase/planet_gifts.sql,
// rocket_gifts_box.sql, admin_gift_boxes.sql); nothing reaches the receiver's balance or shelf until they open the box.
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { useAccount } from "./account";
import { sharedClient as client } from "./friends";
import { useStore } from "./store";

export interface PlanetGift { id: string; from_name: string; planet_id: string | null; rockets?: number | null; box: string; note?: string | null; created_at: string }
export interface GiftOpened { result: "planet" | "rockets" | "rocketbox"; planet: string | null; amount: number }

export type BoxStyle = "starry" | "royal" | "rose" | "balloon" | "treasure";
export const BOX_STYLES: { id: BoxStyle; name: string }[] = [
  { id: "starry", name: "Starry" }, { id: "royal", name: "Royal" }, { id: "rose", name: "Rosy" }, { id: "balloon", name: "Balloons" }, { id: "treasure", name: "Treasure" },
];
export const boxStyle = (id: string): BoxStyle => (BOX_STYLES.some((b) => b.id === id) ? (id as BoxStyle) : "starry");

interface Gifts {
  /** The box to show now: it stays until it has been opened */
  next: PlanetGift | undefined;
  finish: (g: PlanetGift) => void;
  open: (g: PlanetGift) => Promise<GiftOpened | null>;
  sendPlanet: (to: string, planet: string, box: BoxStyle, note: string) => Promise<string | null>;
  sendRockets: (to: string, amount: number, box: BoxStyle, note: string) => Promise<string | null>;
}
const Ctx = createContext<Gifts | null>(null);

/** Developer tool: open the app with ?testGift=royal (and &rockets=500 for a box of rockets) to see a pretend gift box; nothing is sent or received */
const TEST = new URLSearchParams(location.search);
const testGift = (): PlanetGift | null => {
  const box = TEST.get("testGift"); if (box == null) return null;
  const rockets = Number(TEST.get("rockets")) || null;
  return { id: "test-gift", from_name: "sara", planet_id: rockets ? null : "s6_rocketkitty", rockets, box: box || "starry", note: "Good luck with the exams!", created_at: new Date().toISOString() };
};

const messageOf = (e: unknown) => (e instanceof Error ? e.message : String(e));

export function GiftsProvider({ children }: { children: React.ReactNode }) {
  const account = useAccount();
  const { actions } = useStore();
  const [pending, setPending] = useState<PlanetGift[]>([]);
  const refreshing = useRef(false);

  const refresh = useCallback(async () => {
    const t = testGift();
    if (t) { setPending((cur) => (cur.length ? cur : [t])); return; }
    if (account.state !== "approved" || refreshing.current) return;
    refreshing.current = true;
    try {
      const rows: PlanetGift[] = await client.rpc("my_planet_gifts", {});
      setPending((cur) => (cur.map((g) => g.id).join() === rows.map((g) => g.id).join() ? cur : rows));
    } catch { /* offline — try again later */ } finally { refreshing.current = false; }
  }, [account.state]);

  // boxes are checked every 25 seconds
  useEffect(() => {
    refresh();
    const t = window.setInterval(refresh, 25_000);
    return () => window.clearInterval(t);
  }, [refresh]);

  const value: Gifts = {
    next: pending[0],
    finish: (g) => setPending((p) => p.filter((x) => x.id !== g.id)),
    open: async (g) => {
      if (g.id === "test-gift") return g.planet_id ? { result: "planet", planet: g.planet_id, amount: 0 } : { result: "rocketbox", planet: null, amount: g.rockets ?? 0 };
      try {
        const r: GiftOpened = await client.rpc("open_planet_gift", { gift: g.id });
        await actions.walletRefresh();
        return r;
      } catch (e) {
        // already opened somewhere else, or taken back: it is gone, don't keep it on screen
        if (/Already opened|Gift not found/.test(messageOf(e))) setPending((p) => p.filter((x) => x.id !== g.id));
        return null;
      }
    },
    sendPlanet: async (to, planet, box, note) => {
      try { await client.rpc("send_planet_gift", { recipient: to, planet, box, note: note.trim() || null }); await actions.walletRefresh(); return null; }
      catch (e) { return messageOf(e); }
    },
    sendRockets: async (to, amount, box, note) => {
      try { await client.rpc("send_rocket_gift", { recipient: to, amount, box, note: note.trim() || null }); await actions.walletRefresh(); return null; }
      catch (e) { return messageOf(e); }
    },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useGifts(): Gifts {
  const c = useContext(Ctx);
  if (!c) throw new Error("GiftsProvider missing");
  return c;
}

/** Tell the admin panel (and anyone else) which members already hold a gift-only planet */
export async function planetHolders(planet: string): Promise<string[]> {
  try { return ((await client.rpc("admin_planet_holders", { planet })) as string[]).map((x) => x.toLowerCase()); } catch { return []; }
}
