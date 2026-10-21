// Fight Club — same rules as the Mac app; the server runs them (supabase/bosses.sql)
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { notify, useAccount } from "./account";
import { accountData, sharedClient as client } from "./friends";
import { useStore } from "./store";
import { uid } from "./model";

export interface Boss { id: string; creator: string; title: string; hp: number; deadline: string; monster: number; status: "alive" | "defeated" | "escaped"; created_at: string }
export interface BossFighter { boss_id: string; user_id: string; minutes: number; damage: number; spent?: number }
export interface BossInvite { boss_id: string; user_id: string; from_user: string }

/** Same as the server: 45 rockets per hour of the goal, +15% per monster level above 1 */
export const bossPool = (hp: number) => Math.floor((hp / 60) * 45 * (1 + 0.15 * (bossLevel(hp) - 1)));
export const bossLevel = (hp: number) => (hp <= 300 ? 1 : hp <= 600 ? 2 : hp <= 1200 ? 3 : hp <= 2400 ? 4 : 5);

interface FightClub {
  bosses: Boss[]; fighters: Record<string, BossFighter[]>; invites: BossInvite[]; error: string | null; busy: boolean;
  me: string | null;
  healthLeft: (b: Boss) => number; ammo: (b: Boss) => number;
  create: (title: string, minutes: number, deadline: Date) => Promise<string | null>;
  sendInvites: (b: Boss, friends: string[], groups: string[]) => Promise<void>;
  /** true when the server accepted it */
  answer: (boss: string, accept: boolean) => Promise<boolean>;
  fire: (b: Boss, shots: number, hits: number) => Promise<void>;
  remove: (b: Boss) => Promise<void>;
  load: () => Promise<unknown>;
  taskFor: (b: { id: string }) => import("./model").TaskItem | undefined;
  /** Pick (or change) the subject that shoots at this monster: makes or updates its task */
  setSubject: (category: string, b: { id: string; title: string; deadline: string; hp: number }) => void;
  setError: (e: string | null) => void;
}
const Ctx = createContext<FightClub | null>(null);

export function FightClubProvider({ children }: { children: React.ReactNode }) {
  const { data, update } = useStore();
  const account = useAccount();
  const [bosses, setBosses] = useState<Boss[]>([]);
  const [fighters, setFighters] = useState<Record<string, BossFighter[]>>({});
  const [invites, setInvites] = useState<BossInvite[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const dataRef = useRef(data); dataRef.current = data;
  const notified = useRef(new Set<string>());
  const me = client.session?.userID.toLowerCase() ?? null;

  /** The task made for this fight (it holds the subject that counts) */
  const taskFor = (b: { id: string }) => dataRef.current.tasks.find((t) => t.bossID === b.id);

  /** Bullets I've earned so far from my own study (what the server accepts after the next report).
   *  Only the part of each session after the monster appeared counts — a timer already running when it was
   *  summoned counts from that moment. With a subject picked, only study in that subject counts. */
  const earned = (b: Boss) => {
    const start = new Date(b.created_at).getTime(), end = Math.min(Date.now(), new Date(b.deadline).getTime());
    if (end <= start) return 0;
    const task = taskFor(b);
    let ms = 0;
    for (const s of dataRef.current.sessions) {
      if (task && (s.categoryID ?? undefined) !== (task.categoryID ?? undefined)) continue;
      const a = new Date(s.start).getTime();
      ms += Math.max(0, Math.min(a + s.duration * 1000, end) - Math.max(a, start));
    }
    return Math.floor(ms / 60_000);
  };

  const load = useCallback(async (): Promise<{ list: Boss[]; by: Record<string, BossFighter[]> } | undefined> => {
    if (!client.session) return;
    try {
      const since = new Date(Date.now() - 7 * 86400_000).toISOString();
      const list: Boss[] = await client.get(`bosses?or=(status.eq.alive,deadline.gt.${since})&order=created_at.desc`);
      const by: Record<string, BossFighter[]> = {};
      if (list.length) {
        const rows: BossFighter[] = await client.get(`boss_fighters?boss_id=in.(${list.map((b) => b.id).join(",")})`);
        for (const r of rows) (by[r.boss_id] ??= []).push(r);
      }
      const inv: BossInvite[] = await client.get("boss_invites?select=boss_id,user_id,from_user");
      setBosses(list); setFighters(by); setInvites(inv);
      const mine = client.session.userID.toLowerCase();
      for (const i of inv.filter((x) => x.user_id === mine && !notified.current.has(x.boss_id))) {
        notified.current.add(i.boss_id);
        const b = list.find((x) => x.id === i.boss_id);
        if (b) notify(`👾 You're invited to fight “${b.title}”`, "Open Fight Club to join — study to earn bullets and share the prize.");
      }
      return { list, by };
    } catch { return undefined; }
  }, []);

  /** Every minute: report my bullets for living monsters, let late ones escape */
  const tick = useCallback(async () => {
    const got = await load(); if (!got || !client.session) return;
    const mine = client.session.userID.toLowerCase();
    for (const b of got.list.filter((x) => x.status === "alive")) {
      try {
        if (Date.now() > new Date(b.deadline).getTime()) await client.rpc("expire_boss", { b: b.id });
        else if (accountData.ready && (got.by[b.id] ?? []).some((f) => f.user_id === mine)) await client.rpc("report_boss", { b: b.id, mins: earned(b) });
      } catch { /* later */ }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [load]);

  useEffect(() => {
    if (account.state !== "approved") return;
    tick();
    const t = setInterval(tick, 60_000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account.state]);

  const perform = async (work: () => Promise<unknown>) => {
    setBusy(true);
    try { const r = await work(); setError(null); return r; }
    catch (e: any) { setError(e?.message?.includes("fetch") ? "Can't reach the server." : e?.message ?? String(e)); return undefined; }
    finally { setBusy(false); await load(); }
  };

  const healthLeft = (b: Boss) => Math.max(0, b.hp - (fighters[b.id] ?? []).reduce((a, f) => a + f.damage, 0));
  const ammo = (b: Boss) => {
    const f = (fighters[b.id] ?? []).find((x) => x.user_id === me);
    return Math.max(0, Math.max(earned(b), f?.minutes ?? 0) - (f?.spent ?? f?.damage ?? 0));
  };

  const value: FightClub = {
    bosses, fighters, invites, error, busy, me, healthLeft, ammo, load, setError, taskFor,
    setSubject: (category, b) => update((d) => {
      const t = d.tasks.find((x) => x.bossID === b.id);
      if (t) { t.categoryID = category; return; }
      d.tasks.push({ id: uid(), title: `💥 ${b.title}`, notes: "Fight Club: study this subject to earn bullets.", categoryID: category,
        priority: 1, dueDate: b.deadline, hasTime: true, estimatedMinutes: b.hp, isDone: false, createdAt: new Date().toISOString(), bossID: b.id });
    }),
    create: async (title, minutes, deadline) => {
      const id = await perform(() => client.rpc("create_boss", { title, goal: minutes, ends: deadline.toISOString() }));
      return typeof id === "string" ? id : null;
    },
    sendInvites: async (b, friends, groups) => {
      await perform(async () => {
        for (const f of friends) await client.rpc("invite_boss", { b: b.id, who: f });
        for (const g of groups) await client.rpc("invite_boss_group", { b: b.id, g });
      });
    },
    answer: async (boss, accept) => {
      let ok = false;
      await perform(async () => { await client.rpc("answer_boss_invite", { b: boss, accept }); ok = true; });
      return ok;
    },
    fire: async (b, shots, hits) => {
      const before = healthLeft(b);
      try {
        if (accountData.ready) await client.rpc("report_boss", { b: b.id, mins: earned(b) });
        const left = await client.rpc("fire_boss", { b: b.id, shots, hits });
        setError(null);
        if (before > 0 && left === 0) await account.claimGifts();
      } catch (e: any) { setError(e?.message ?? String(e)); }
      await load();
    },
    remove: async (b) => { await perform(() => client.rpc("delete_boss", { b: b.id })); },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useFightClub(): FightClub {
  const c = useContext(Ctx);
  if (!c) throw new Error("FightClubProvider missing");
  return c;
}
