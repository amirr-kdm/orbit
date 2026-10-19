// Friends: talks to the same Supabase project as the Mac app (same tables and data format).
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { AppData } from "./model";
import { addDays, dayKey, startOfDay, weekDays } from "./dates";
import { GROUP_WIN_ROCKETS, progress, sessionsIn, subjectOf, todosOn, useStore, wallet } from "./store";
import { weekStart } from "./dates";

const URL_ = (import.meta.env.VITE_SUPABASE_URL as string | undefined) ?? "";
const KEY_ = (import.meta.env.VITE_SUPABASE_KEY as string | undefined) ?? "";
export const supabaseConfigured = !!URL_ && !!KEY_ && !URL_.includes("YOUR-PROJECT");

interface Session { accessToken: string; refreshToken: string; expiresAt: number; userID: string }
const SESSION_KEY = "orbit-session-v1";

export interface SubjectStat { name: string; minutes: number; color: string }
export interface DailyStat { user_id: string; day: string; minutes: number; todos_done: number; todos_total: number; subjects: SubjectStat[] }
export interface LiveStatus { user_id: string; studying?: string | null; started_at?: string | null; updated_at?: string | null }
export interface GalaxyData { systems: { id: string; name: string; sun: string; planets: string[] }[] }
export interface Profile { id: string; name: string; friend_code: string; level?: number; avatar?: string | null; galaxy?: GalaxyData | null; rockets?: number }
/** A study group: everyone in it sees each other's progress */
export interface StudyGroup { id: string; name: string; code: string; owner: string; members: string[] }

export interface FriendCard { profile: Profile; stats: Record<string, DailyStat>; live?: LiveStatus; isMe: boolean }

export const minutesOn = (f: FriendCard, d: Date) => f.stats[dayKey(d)]?.minutes ?? 0;
export const weekMinutes = (f: FriendCard) => weekDays(new Date()).reduce((a, d) => a + minutesOn(f, d), 0);
export function streak(f: FriendCard): number {
  let d = new Date(); if (minutesOn(f, d) === 0) d = addDays(d, -1);
  let n = 0; while (minutesOn(f, d) > 0) { n++; d = addDays(d, -1); }
  return n;
}
export function studyingNow(f: FriendCard): string | undefined {
  const l = f.live;
  if (!l?.studying || !l.updated_at) return undefined;
  return Date.now() - new Date(l.updated_at).getTime() < 15 * 60_000 ? l.studying : undefined;
}
export function weekSubjects(f: FriendCard): SubjectStat[] {
  const tot = new Map<string, SubjectStat>();
  for (const d of weekDays(new Date())) for (const s of f.stats[dayKey(d)]?.subjects ?? []) {
    const cur = tot.get(s.name) ?? { ...s, minutes: 0 };
    cur.minutes += s.minutes; tot.set(s.name, cur);
  }
  return [...tot.values()].sort((a, b) => b.minutes - a.minutes);
}

// ---------- tiny REST client ----------

class Client {
  session: Session | null = JSON.parse(localStorage.getItem(SESSION_KEY) ?? "null");

  private save(s: Session | null) {
    this.session = s;
    if (s) localStorage.setItem(SESSION_KEY, JSON.stringify(s)); else localStorage.removeItem(SESSION_KEY);
  }

  private async send(method: string, path: string, body?: unknown, auth = true, prefer?: string): Promise<any> {
    const headers: Record<string, string> = { apikey: KEY_, "Content-Type": "application/json" };
    if (auth && this.session) headers.Authorization = `Bearer ${this.session.accessToken}`;
    if (prefer) headers.Prefer = prefer;
    const res = await fetch(URL_ + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    const json = text ? JSON.parse(text) : null;
    if (!res.ok) throw new Error(json?.message ?? json?.msg ?? json?.error_description ?? `Server error (${res.status})`);
    return json;
  }

  private store(r: any) {
    this.save({ accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: Date.now() + r.expires_in * 1000, userID: r.user.id.toUpperCase() });
  }

  async signIn() { this.store(await this.send("POST", "/auth/v1/signup", {}, false)); }
  signOut() { this.save(null); }

  private async fresh() {
    if (!this.session) throw new Error("Not signed in");
    if (this.session.expiresAt - Date.now() > 60_000) return;
    this.store(await this.send("POST", "/auth/v1/token?grant_type=refresh_token", { refresh_token: this.session.refreshToken }, false));
  }
  async get(path: string) { await this.fresh(); return this.send("GET", "/rest/v1/" + path); }
  async insert(table: string, body: unknown) { await this.fresh(); return this.send("POST", "/rest/v1/" + table, body, true, "return=representation"); }
  async upsert(table: string, body: unknown) { await this.fresh(); return this.send("POST", "/rest/v1/" + table, body, true, "resolution=merge-duplicates,return=minimal"); }
  async patch(path: string, body: unknown) { await this.fresh(); return this.send("PATCH", "/rest/v1/" + path, body, true, "return=minimal"); }
  async del(path: string) { await this.fresh(); return this.send("DELETE", "/rest/v1/" + path, undefined, true, "return=minimal"); }
  async rpc(name: string, body: unknown) { await this.fresh(); return this.send("POST", "/rest/v1/rpc/" + name, body); }
}

// ---------- local summaries ----------

function localStat(d: AppData, day: Date, userID: string): DailyStat {
  const s0 = startOfDay(day);
  const sessions = sessionsIn(d, s0, addDays(s0, 1));
  const todos = todosOn(d, day);
  const subj = new Map<string, SubjectStat>();
  for (const s of sessions) {
    const { name, color } = subjectOf(d, s);
    const cur = subj.get(name) ?? { name, minutes: 0, color };
    cur.minutes += Math.floor(s.duration / 60); subj.set(name, cur);
  }
  return {
    user_id: userID.toLowerCase(), day: dayKey(day),
    minutes: Math.floor(sessions.reduce((a, s) => a + s.duration, 0) / 60),
    todos_done: todos.filter((t) => t.isDone).length, todos_total: todos.length,
    subjects: [...subj.values()].sort((a, b) => b.minutes - a.minutes).slice(0, 20),
  };
}

export function galaxyData(d: AppData): GalaxyData {
  return { systems: d.solarSystems.map((s) => ({ id: s.id, name: s.name, sun: s.sun, planets: d.galaxy.filter((g) => g.systemID === s.id).map((g) => g.planetID) })) };
}

// ---------- React context ----------

interface Friends {
  me: Profile | null; friends: FriendCard[]; loading: boolean; error: string | null; lastSync: Date | null;
  groups: StudyGroup[]; people: Record<string, FriendCard>; incoming: string[]; outgoing: string[];
  groupPrize: string | null; clearPrize: () => void;
  isFriend: (id: string) => boolean;
  createGroup: (name: string) => Promise<void>;
  joinGroup: (code: string) => Promise<string | null>;
  leaveGroup: (id: string) => Promise<void>;
  sendRequest: (id: string) => Promise<void>;
  respond: (id: string, accept: boolean) => Promise<void>;
  cancelRequest: (id: string) => Promise<void>;
  createProfile: (name: string) => Promise<void>;
  addFriend: (code: string) => Promise<string | null>;
  removeFriend: (id: string) => Promise<void>;
  rename: (name: string) => Promise<void>;
  deleteProfile: () => Promise<void>;
  refresh: () => Promise<void>;
  myCard: () => FriendCard | null;
  setLive: (title: string | null, startedAt: Date | null) => void;
}
const Ctx = createContext<Friends | null>(null);

export function FriendsProvider({ children }: { children: React.ReactNode }) {
  const { data, actions } = useStore();
  const client = useRef(new Client()).current;
  const [groups, setGroups] = useState<StudyGroup[]>([]);
  const [people, setPeople] = useState<Record<string, FriendCard>>({});
  const [incoming, setIncoming] = useState<string[]>([]);
  const [outgoing, setOutgoing] = useState<string[]>([]);
  const [groupPrize, setGroupPrize] = useState<string | null>(null);
  const [me, setMe] = useState<Profile | null>(null);
  const [friends, setFriends] = useState<FriendCard[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastSync, setLastSync] = useState<Date | null>(null);
  const live = useRef<{ title: string | null; startedAt: Date | null; sent?: string | null }>({ title: null, startedAt: null });
  const dataRef = useRef(data); dataRef.current = data;
  const lastSent = useRef<string>("");

  const run = useCallback(async (fn: () => Promise<void>) => {
    try { await fn(); setError(null); }
    catch (e: any) { setError(e?.message?.includes("fetch") ? "Can't reach the server. Check your internet or VPN." : e?.message ?? String(e)); }
  }, []);

  const refresh = useCallback(async () => {
    if (!supabaseConfigured || !client.session) return;
    setLoading(true);
    await run(async () => {
      const uid = client.session!.userID.toLowerCase();
      const mine: Profile[] = await client.get(`profiles?id=eq.${uid}`);
      setMe(mine[0] ?? null);
      const [links, gs, ms, rs]: [{ friend_id: string }[], { id: string; name: string; code: string; owner: string }[], { group_id: string; user_id: string }[], { from_user: string; to_user: string }[]] = await Promise.all([
        client.get(`friendships?select=friend_id&user_id=eq.${uid}`),
        client.get("groups?select=id,name,code,owner&order=created_at"),
        client.get("group_members?select=group_id,user_id&order=joined_at"),
        client.get("friend_requests?select=from_user,to_user"),
      ]);
      const friendIDs = links.map((l) => l.friend_id);
      const groupList = gs.map((g) => ({ ...g, members: ms.filter((m) => m.group_id === g.id).map((m) => m.user_id) }));
      setGroups(groupList);
      const inc = rs.filter((r) => r.to_user === uid).map((r) => r.from_user), out = rs.filter((r) => r.from_user === uid).map((r) => r.to_user);
      setIncoming(inc); setOutgoing(out);
      const ids = [...new Set([...friendIDs, ...ms.map((m) => m.user_id), ...inc, ...out])].filter((id) => id !== uid);
      if (!ids.length) { setFriends([]); setPeople({}); setLastSync(new Date()); return; }
      const list = `(${ids.join(",")})`;
      const since = dayKey(addDays(new Date(), -35));
      const [ps, ss, ls]: [Profile[], DailyStat[], LiveStatus[]] = await Promise.all([
        client.get(`profiles?id=in.${list}`), client.get(`daily_stats?user_id=in.${list}&day=gte.${since}`), client.get(`live_status?user_id=in.${list}`),
      ]);
      const cards: FriendCard[] = ps.map((p) => ({
        profile: p, isMe: false, live: ls.find((l) => l.user_id === p.id),
        stats: Object.fromEntries(ss.filter((s) => s.user_id === p.id).map((s) => [s.day, s])),
      }));
      setPeople(Object.fromEntries(cards.map((c) => [c.profile.id, c])));
      setFriends(cards.filter((c) => friendIDs.includes(c.profile.id)).sort((a, b) => weekMinutes(b) - weekMinutes(a)));

      // Last week's group prize: whoever studied the most (ties included) wins 100 rockets, once per group per week
      const last = addDays(weekStart(new Date()), -7);
      const days = Array.from({ length: 7 }, (_, i) => addDays(last, i));
      const myLastWeek = Math.floor(sessionsIn(dataRef.current, last, addDays(last, 7)).reduce((a, s) => a + s.duration, 0) / 60);
      if (myLastWeek > 0) {
        const keys: string[] = [], won: string[] = [];
        for (const g of groupList) {
          if (g.members.length < 2) continue;
          const best = Math.max(0, ...g.members.filter((m) => m !== uid).map((m) => {
            const c = cards.find((x) => x.profile.id === m);
            return c ? days.reduce((a, d) => a + minutesOn(c, d), 0) : 0;
          }));
          const key = `${g.id}|${dayKey(last)}`;
          if (myLastWeek >= best && !dataRef.current.groupWins.includes(key)) { keys.push(key); won.push(g.name); }
        }
        if (keys.length) { actions.recordGroupWins(keys); setGroupPrize(`🏆 You studied the most last week in ${won.join(", ")}: +${GROUP_WIN_ROCKETS * keys.length} rockets!`); }
      }
      setLastSync(new Date());
    });
    setLoading(false);
  }, [client, run, actions]);

  const sync = useCallback(async () => {
    if (!supabaseConfigured || !client.session || !me) return;
    const d = dataRef.current;
    const uid = client.session.userID;
    const rows = Array.from({ length: 7 }, (_, i) => localStat(d, addDays(new Date(), -i), uid));
    const extras = { level: progress(d).level, avatar: d.avatarPlanet ?? null, galaxy: galaxyData(d), rockets: wallet(d).balance };
    const sig = JSON.stringify([rows, extras]);
    if (sig === lastSent.current) return;
    await run(async () => {
      await client.patch(`profiles?id=eq.${uid.toLowerCase()}`, extras);
      await client.upsert("daily_stats", rows);
      lastSent.current = sig;
      setLastSync(new Date());
    });
  }, [client, me, run]);

  const pushLive = useCallback(async (force = false) => {
    if (!supabaseConfigured || !client.session || !me) return;
    const { title, startedAt, sent } = live.current;
    if (!force && sent === title) return;
    live.current.sent = title;
    await run(() => client.upsert("live_status", {
      user_id: client.session!.userID.toLowerCase(), studying: title,
      started_at: title ? startedAt?.toISOString() : null, updated_at: new Date().toISOString(),
    }));
  }, [client, me, run]);

  useEffect(() => { refresh(); }, [refresh]);
  useEffect(() => {
    const t = setInterval(() => { sync(); pushLive(!!live.current.title); }, 60_000);
    sync();
    return () => clearInterval(t);
  }, [sync, pushLive]);
  useEffect(() => { sync(); }, [data.sessions.length, sync]);

  const value: Friends = {
    me, friends, loading, error, lastSync, refresh,
    groups, people, incoming, outgoing, groupPrize, clearPrize: () => setGroupPrize(null),
    isFriend: (id) => friends.some((f) => f.profile.id === id),
    createGroup: async (name) => { if (!name.trim()) return; await run(() => client.rpc("create_group", { group_name: name.trim() })); await refresh(); },
    joinGroup: async (code) => {
      let name: string | null = null;
      await run(async () => { name = await client.rpc("join_group", { group_code: code }); });
      if (name) await refresh();
      return name;
    },
    leaveGroup: async (id) => { await run(() => client.rpc("leave_group", { g: id })); await refresh(); },
    sendRequest: async (id) => { await run(() => client.rpc("send_friend_request", { other: id })); await refresh(); },
    respond: async (id, accept) => { await run(() => client.rpc("respond_friend_request", { other: id, accept })); await refresh(); },
    cancelRequest: async (id) => { await run(() => client.rpc("cancel_friend_request", { other: id })); await refresh(); },
    createProfile: async (name) => {
      await run(async () => {
        if (!client.session) await client.signIn();
        const rows: Profile[] = await client.insert("profiles", { id: client.session!.userID.toLowerCase(), name: name.trim() });
        setMe(rows[0]);
      });
    },
    addFriend: async (code) => {
      let name: string | null = null;
      await run(async () => { name = await client.rpc("add_friend", { code }); });
      if (name) await refresh();
      return name;
    },
    removeFriend: async (id) => { await run(() => client.rpc("remove_friend", { friend: id })); setFriends((f) => f.filter((x) => x.profile.id !== id)); },
    rename: async (name) => { if (!me) return; await run(() => client.patch(`profiles?id=eq.${me.id}`, { name })); setMe({ ...me, name }); },
    deleteProfile: async () => {
      if (!me) return;
      await run(async () => { await client.del(`profiles?id=eq.${me.id}`); client.signOut(); setMe(null); setFriends([]); });
    },
    myCard: () => {
      if (!me || !client.session) return null;
      const d = dataRef.current;
      const stats = Object.fromEntries(Array.from({ length: 35 }, (_, i) => { const s = localStat(d, addDays(new Date(), -i), client.session!.userID); return [s.day, s]; }));
      return {
        isMe: true, stats,
        profile: { ...me, level: progress(d).level, avatar: d.avatarPlanet, galaxy: galaxyData(d), rockets: wallet(d).balance },
        live: { user_id: me.id, studying: live.current.title, started_at: live.current.startedAt?.toISOString(), updated_at: new Date().toISOString() },
      };
    },
    setLive: (title, startedAt) => { live.current.title = title; live.current.startedAt = startedAt; pushLive(); },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useFriends(): Friends {
  const f = useContext(Ctx);
  if (!f) throw new Error("FriendsProvider missing");
  return f;
}
