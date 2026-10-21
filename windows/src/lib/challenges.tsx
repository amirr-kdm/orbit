// Group challenges and promises to a friend — same rules as the Mac app; payouts run on the server (supabase/challenges.sql)
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { useAccount } from "./account";
import { accountData, sharedClient as client } from "./friends";
import { studyTime, useStore, wallet } from "./store";

export interface Challenge {
  id: string; kind: "group" | "promise"; group_id: string | null; creator: string; friend: string | null;
  title: string; target_minutes: number; fee: number; starts_at: string; ends_at: string; status: "open" | "settled" | "cancelled";
}
export interface ChallengeMember { challenge_id: string; user_id: string; minutes: number }
/** Apps can still report minutes for this long after the end; then it pays out */
const GRACE = 3600_000;

interface Challenges {
  list: Challenge[]; members: Record<string, ChallengeMember[]>; error: string | null; busy: boolean;
  create: (group: string, title: string, minutes: number, fee: number, start: Date, end: Date) => Promise<boolean>;
  promise: (friend: string, minutes: number, stake: number, end: Date) => Promise<boolean>;
  join: (c: Challenge) => Promise<void>; leave: (c: Challenge) => Promise<void>; cancel: (c: Challenge) => Promise<void>;
  setError: (e: string | null) => void;
}
const Ctx = createContext<Challenges | null>(null);

export function ChallengesProvider({ children }: { children: React.ReactNode }) {
  const { data } = useStore();
  const account = useAccount();
  const [list, setList] = useState<Challenge[]>([]);
  const [members, setMembers] = useState<Record<string, ChallengeMember[]>>({});
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const dataRef = useRef(data); dataRef.current = data;

  /** Open ones, plus anything finished in the last week */
  const load = useCallback(async () => {
    if (!client.session) return;
    try {
      const since = new Date(Date.now() - 7 * 86400_000).toISOString();
      const l: Challenge[] = await client.get(`challenges?or=(status.eq.open,ends_at.gt.${since})&order=starts_at.desc`);
      const by: Record<string, ChallengeMember[]> = {};
      if (l.length) {
        const rows: ChallengeMember[] = await client.get(`challenge_members?challenge_id=in.(${l.map((c) => c.id).join(",")})&select=challenge_id,user_id,minutes`);
        for (const r of rows) (by[r.challenge_id] ??= []).push(r);
      }
      setList(l); setMembers(by);
      return { l, by };
    } catch { return undefined; }
  }, []);

  /** Every minute: report my study minutes in running challenges, and pay out finished ones */
  const tick = useCallback(async () => {
    const me = client.session?.userID.toLowerCase(); if (!me) return;
    const got = await load(); if (!got) return;
    const now = Date.now(); let settled = false;
    for (const c of got.l) {
      const start = new Date(c.starts_at).getTime(), end = new Date(c.ends_at).getTime();
      const mine = (got.by[c.id] ?? []).some((m) => m.user_id.toLowerCase() === me);
      if (c.status === "open" && mine && accountData.ready && now >= start && now <= end + GRACE) {
        const minutes = Math.floor(studyTime(dataRef.current, new Date(start), new Date(Math.min(now, end))) / 60);
        try { await client.rpc("report_challenge", { c: c.id, minutes }); } catch { /* offline */ }
      }
      if (c.status === "open" && now >= end + GRACE) { try { await client.rpc("settle_challenge", { c: c.id }); settled = true; } catch { /* later */ } }
    }
    if (settled) { await load(); await account.claimGifts(); }
  }, [load, account]);

  useEffect(() => {
    if (account.state !== "approved") return;
    tick();
    const t = setInterval(tick, 60_000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account.state]);

  const perform = async (cost: number, work: () => Promise<unknown>) => {
    const have = wallet(dataRef.current).balance;
    if (cost > have) { setError(`Not enough rockets — you have ${have}.`); return false; }
    setBusy(true);
    try { await work(); setError(null); await load(); await account.claimGifts(); return true; }
    catch (e: any) { setError(e?.message?.includes("fetch") ? "Can't reach the server. Check your internet or VPN." : e?.message ?? String(e)); return false; }
    finally { setBusy(false); }
  };

  const value: Challenges = {
    list, members, error, busy, setError,
    create: (g, title, minutes, fee, start, end) => perform(fee, () => client.rpc("create_challenge", { g, title, target_minutes: minutes, fee, starts_at: start.toISOString(), ends_at: end.toISOString() })),
    promise: (friend, minutes, stake, end) => perform(stake, () => client.rpc("create_promise", { to_friend: friend, target_minutes: minutes, stake, ends_at: end.toISOString() })),
    join: async (c) => { await perform(c.fee, () => client.rpc("join_challenge", { c: c.id })); },
    leave: async (c) => { await perform(0, () => client.rpc("leave_challenge", { c: c.id })); },
    cancel: async (c) => { await perform(0, () => client.rpc("cancel_challenge", { c: c.id })); },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useChallenges(): Challenges {
  const c = useContext(Ctx);
  if (!c) throw new Error("ChallengesProvider missing");
  return c;
}

/** "6h", "1h 30m" */
export const hm = (m: number) => { const h = Math.floor(m / 60), r = m % 60; return h === 0 ? `${r}m` : r === 0 ? `${h}h` : `${h}h ${r}m`; };
