// Fight Club — a weekly World Boss for every Orbiter, same rules as the Mac app; the server runs them
// (supabase/bosses.sql + supabase/world_boss.sql). The monster is random, the prize 1000 rockets split by damage.
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { notify, useAccount } from "./account";
import { accountData, sharedClient as client } from "./friends";
import { isInside, useStore } from "./store";
import { dayKey, weekStart } from "./dates";
import { uid } from "./model";

export interface Boss { id: string; creator: string; title: string; hp: number; deadline: string; monster: number; status: "alive" | "defeated" | "escaped"; created_at: string;
  /** Set for the weekly World Boss (the Saturday its week starts) */ world_week?: string | null }
export interface BossFighter { boss_id: string; user_id: string; minutes: number; damage: number; spent?: number }
export interface BossInvite { boss_id: string; user_id: string; from_user: string }

/** Same as the server: 45 rockets per hour of the goal, +15% per monster level above 1 */
export const isWorld = (b: Boss) => !!b.world_week;
/** World Boss: 1000 in all. Older monsters: 45 rockets per hour of the goal, +15% per level */
export const prizeOf = (b: Boss) => (isWorld(b) ? 1000 : bossPool(b.hp));
export const bossPool = (hp: number) => Math.floor((hp / 60) * 45 * (1 + 0.15 * (bossLevel(hp) - 1)));
export const bossLevel = (hp: number) => (hp <= 300 ? 1 : hp <= 600 ? 2 : hp <= 1200 ? 3 : hp <= 2400 ? 4 : 5);

interface FightClub {
  bosses: Boss[]; fighters: Record<string, BossFighter[]>; invites: BossInvite[]; error: string | null; busy: boolean;
  me: string | null;
  /** This week's World Boss */
  worldBoss: Boss | undefined;
  /** Usernames of World Boss fighters (they may not be friends) */
  names: Record<string, string>;
  /** Admin setting: hours of health per member for the next World Bosses */
  hoursPerMember: number; setHoursPerMember: (h: number) => Promise<void>;
  healthLeft: (b: Boss) => number; ammo: (b: Boss) => number;
  create: (title: string, minutes: number, deadline: Date) => Promise<string | null>;
  sendInvites: (b: Boss, friends: string[], groups: string[]) => Promise<void>;
  /** true when the server accepted it */
  answer: (boss: string, accept: boolean) => Promise<boolean>;
  fire: (b: Boss, shots: number, hits: number) => Promise<void>;
  /** `light`: only the monsters and fighters (right after firing — keeps the fight smooth) */
  remove: (b: Boss) => Promise<void>;
  load: (light?: boolean) => Promise<unknown>;
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
  const [names, setNames] = useState<Record<string, string>>({});
  const [hoursPerMember, setHours] = useState(5);
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
    const d = dataRef.current;
    for (const s of d.sessions) {
      if (s.isManual) continue;   // manual logs earn no bullets
      // the fight's subject, its subcategories included
      if (task && (task.categoryID ? !isInside(d, s.categoryID, task.categoryID) : !!s.categoryID)) continue;
      const a = new Date(s.start).getTime();
      ms += Math.max(0, Math.min(a + s.duration * 1000, end) - Math.max(a, start));
    }
    return Math.floor(ms / 60_000);
  };

  const load = useCallback(async (light = false): Promise<{ list: Boss[]; by: Record<string, BossFighter[]> } | undefined> => {
    if (!client.session) return;
    if (!light) {
      // make sure this week's World Boss exists (the first app to ask creates it)
      try { await client.rpc("world_boss", { week_start: dayKey(weekStart(new Date())) }); } catch { /* not approved yet / offline */ }
      try { const r: { hours_per_member: number }[] = await client.get("boss_settings?select=hours_per_member"); if (r[0]) setHours(r[0].hours_per_member); } catch { /* ignore */ }
    }
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
      const w = list.find(isWorld);
      if (w && !light) {
        const ids = [...new Set((by[w.id] ?? []).map((x) => x.user_id))];
        if (ids.length) {
          try { const rows: { id: string; name: string }[] = await client.rpc("boss_names", { ids }); setNames(Object.fromEntries(rows.map((x) => [x.id, x.name]))); } catch { /* ignore */ }
        }
      }
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
        // a World Boss: everyone fights it by studying; older monsters: only the ones I joined
        else if (accountData.ready && (isWorld(b) || (got.by[b.id] ?? []).some((f) => f.user_id === mine))) await client.rpc("report_boss", { b: b.id, mins: earned(b) });
      } catch { /* later */ }
    }
    await load(true);
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

  const week = dayKey(weekStart(new Date()));
  const worldBoss = bosses.find((b) => b.world_week === week) ?? bosses.find(isWorld);
  const value: FightClub = {
    bosses, fighters, invites, error, busy, me, healthLeft, ammo, load, setError, taskFor, worldBoss, names, hoursPerMember,
    setHoursPerMember: async (h) => { const ok = await perform(async () => { await client.rpc("admin_set_boss_hours", { hours: h }); return true; }); if (ok) setHours(h); },
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
        await load(true);
        if (before > 0 && left === 0) await account.claimGifts();
      } catch (e: any) { setError(e?.message?.includes("fetch") ? "Can't reach the server." : e?.message ?? String(e)); await load(); }
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
