// Accounts (email + username + password), owner approval, cloud backup of the data and the owner's admin tools.
// Same server and rules as the Mac app. The app keeps working offline on the local copy.
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { AppData } from "./model";
import { sharedClient as client, supabaseConfigured, useFriends } from "./friends";
import { useStore } from "./store";

export type AccountState = "noServer" | "loading" | "signedOut" | "needsUpgrade" | "pending" | "approved";
export interface Profile { id: string; name: string; username?: string | null; approved?: boolean; is_admin?: boolean }
export interface AdminUser {
  id: string; name: string; username?: string | null; email?: string | null; approved: boolean; is_admin: boolean;
  requested_at?: string | null; last_backup?: string | null; last_studied?: string | null;
}

interface Account {
  state: AccountState; profile: Profile | null; email: string | null; message: string | null; busy: boolean;
  lastSync: Date | null; syncing: boolean; syncError: string | null;
  users: AdminUser[]; isAdmin: boolean; pendingCount: number;
  setMessage: (m: string | null) => void;
  signUp: (email: string, username: string, password: string) => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  upgrade: (email: string, username: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  refreshStatus: () => Promise<void>;
  changeUsername: (u: string) => Promise<boolean>;
  changePassword: (current: string, next: string) => Promise<boolean>;
  changeEmail: (next: string, password: string) => Promise<boolean>;
  upload: () => Promise<void>;
  loadUsers: () => Promise<void>;
  approve: (id: string) => Promise<void>;
  reject: (id: string) => Promise<void>;
  resetPassword: (id: string) => Promise<string | null>;
  /** Give (or take back, if negative) rockets; their app adds them on its next check */
  giftRockets: (id: string, amount: number) => Promise<boolean>;
  /** Rockets just received as a gift (banner until dismissed) */
  giftNotice: number | null; clearGiftNotice: () => void;
}

const Ctx = createContext<Account | null>(null);
const SYNC_KEY = "orbit-sync-v1";
interface SyncMeta { account?: string; at?: string; dirty?: boolean }
const meta = (): SyncMeta => { try { return JSON.parse(localStorage.getItem(SYNC_KEY) ?? "{}"); } catch { return {}; } };
const setMeta = (m: SyncMeta) => { try { localStorage.setItem(SYNC_KEY, JSON.stringify({ ...meta(), ...m })); } catch { /* ignore */ } };
const approvedKey = (id: string) => `orbit-approved-${id}`;

export function validate(email: string, username: string, password: string): string | null {
  if (!email.includes("@") || !email.includes(".")) return "Enter a valid email.";
  if (username.length < 3 || username.length > 24) return "Usernames are 3–24 characters.";
  if (/\s/.test(username)) return "Usernames can't have spaces.";
  if (password.length < 6) return "Passwords are at least 6 characters.";
  return null;
}

function friendly(m: string): string {
  const l = m.toLowerCase();
  if (l.includes("invalid login")) return "Wrong email or password.";
  if (l.includes("already registered") || l.includes("already been registered")) return "There's already an account with this email. Log in instead.";
  if (l.includes("profiles_username_key") || l.includes("duplicate key")) return "That username is taken.";
  if (l.includes("fetch")) return "Can't reach the server. Check your internet or VPN.";
  return m;
}

export function AccountProvider({ children }: { children: React.ReactNode }) {
  const { data, replaceAll, update } = useStore();
  const friends = useFriends();
  const [state, setState] = useState<AccountState>(supabaseConfigured ? "loading" : "noServer");
  const [profile, setProfile] = useState<Profile | null>(null);
  const [email, setEmail] = useState<string | null>(client.session?.email ?? null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [lastSync, setLastSync] = useState<Date | null>(null);
  const [syncing, setSyncing] = useState(false);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const dataRef = useRef<AppData>(data); dataRef.current = data;
  const stateRef = useRef(state); stateRef.current = state;
  const restoring = useRef(false);
  const [giftNotice, setGiftNotice] = useState<number | null>(null);
  const timer = useRef<number>();
  const notified = useRef<Set<string>>(new Set());

  const perform = useCallback(async (work: () => Promise<void>) => {
    setBusy(true); setMessage(null);
    try { await work(); } catch (e: any) { setMessage(friendly(e?.message ?? String(e))); }
    finally { setBusy(false); }
  }, []);

  // ---------- cloud backup ----------

  const upload = useCallback(async () => {
    const s = client.session;
    if (stateRef.current !== "approved" || !s) return;
    setSyncing(true);
    const now = new Date().toISOString();
    const body = `{"user_id":"${s.userID.toLowerCase()}","updated_at":"${now}","device":"Windows","data":${JSON.stringify(dataRef.current)}}`;
    try {
      await client.raw("POST", "user_data", body, "resolution=merge-duplicates,return=minimal");
      setMeta({ account: s.userID, at: now, dirty: false });
      setLastSync(new Date()); setSyncError(null);
    } catch (e: any) {
      setSyncError(e?.message?.includes("fetch") ? "Offline — your changes are saved here and will sync later." : e?.message ?? "Sync failed");
    } finally { setSyncing(false); }
  }, []);

  const download = useCallback(async (uid: string) => {
    const rows = await client.raw("GET", `user_data?user_id=eq.${uid.toLowerCase()}&select=data,updated_at`, undefined);
    const row = rows?.[0];
    if (!row?.data) return;
    // Keep the old local copy aside, just in case
    try { localStorage.setItem(`orbit-data-before-${Date.now()}`, JSON.stringify(dataRef.current)); } catch { /* ignore */ }
    restoring.current = true;
    replaceAll(row.data as AppData);
    setMeta({ account: uid, at: row.updated_at, dirty: false });
    setLastSync(new Date());
    setTimeout(() => { restoring.current = false; }, 500);
  }, [replaceAll]);

  /** First sync after signing in: bring the server copy down, or send ours up */
  const syncOnStart = useCallback(async () => {
    const s = client.session;
    if (!s) return;
    setSyncing(true);
    try {
      const rows: { updated_at: string }[] = await client.get(`user_data?user_id=eq.${s.userID.toLowerCase()}&select=updated_at`);
      const m = meta();
      if (!rows.length) { setMeta({ account: s.userID }); await upload(); return; }
      const server = new Date(rows[0].updated_at).getTime();
      if (m.account !== s.userID) await download(s.userID);
      else if (server > new Date(m.at ?? 0).getTime()) { if (m.dirty) await upload(); else await download(s.userID); }
      else if (m.dirty) await upload();
      setSyncError(null);
    } catch (e: any) {
      setSyncError("Offline — your changes are saved here and will sync later.");
    } finally { setSyncing(false); }
  }, [upload, download]);

  // Local changes: mark dirty and upload a few seconds later
  const first = useRef(true);
  useEffect(() => {
    if (first.current) { first.current = false; return; }
    if (restoring.current) return;
    setMeta({ dirty: true });
    if (stateRef.current !== "approved") return;
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(upload, 4000);
  }, [data, upload]);

  // Add rocket gifts from the owner that this account hasn't counted yet
  const claimGifts = useCallback(async () => {
    if (stateRef.current !== "approved" || restoring.current) return;
    try {
      const gifts: { id: string; amount: number }[] = await client.get("rocket_gifts?select=id,amount");
      const known = dataRef.current.claimedGifts ?? [];
      if (!gifts.some((g) => !known.includes(g.id))) return;
      const total = gifts.filter((g) => !known.includes(g.id)).reduce((a, g) => a + g.amount, 0);
      if (total > 0) {
        setGiftNotice(total);
        notify(`You got ${total} 🚀 rockets!`, "A gift from the Orbit admin. Spend them in the Store.");
      }
      update((d) => {
        const claimed = d.claimedGifts ?? (d.claimedGifts = []);
        for (const g of gifts) if (!claimed.includes(g.id)) { claimed.push(g.id); d.rocketGrant += g.amount; }
      });
    } catch { /* offline — try again later */ }
  }, [update]);

  // ---------- profile / state ----------

  const loadProfile = useCallback(async () => {
    const s = client.session;
    if (!s) { setState("signedOut"); return; }
    setEmail(s.email ?? null);
    try {
      const rows: Profile[] = await client.get(`profiles?id=eq.${s.userID.toLowerCase()}&select=id,name,username,approved,is_admin`);
      const p = rows[0];
      if (!p) {
        client.signOut(); friends.clearLocal(); setProfile(null); setState("signedOut");
        setMessage("This account no longer exists. Sign up again, or ask the owner.");
        return;
      }
      setProfile(p);
      if (!s.email) { setState("needsUpgrade"); return; }
      localStorage.setItem(approvedKey(s.userID), p.approved ? "1" : "0");
      if (p.approved) { setState("approved"); stateRef.current = "approved"; await friends.reload(); await syncOnStart(); setTimeout(claimGifts, 1000); }
      else setState("pending");
    } catch {
      setState((cur) => (cur === "loading" ? (localStorage.getItem(approvedKey(s.userID)) === "1" ? "approved" : "pending") : cur));
    }
  }, [friends, syncOnStart, claimGifts]);

  useEffect(() => {
    if (!supabaseConfigured) return;
    const s = client.session;
    if (!s) { setState("signedOut"); return; }
    if (s.email && localStorage.getItem(approvedKey(s.userID)) === "1") setState("approved");
    loadProfile();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Waiting for approval: check every 30 seconds
  useEffect(() => {
    if (state !== "pending") return;
    const t = setInterval(loadProfile, 30_000);
    return () => clearInterval(t);
  }, [state, loadProfile]);

  // Retry the backup every minute (after being offline)
  useEffect(() => {
    if (state !== "approved") return;
    const t = setInterval(() => { claimGifts(); if (meta().dirty) upload(); }, 60_000);
    return () => clearInterval(t);
  }, [state, upload, claimGifts]);

  // ---------- admin (owner only — the server refuses everyone else) ----------

  const isAdmin = !!profile?.is_admin;
  const loadUsers = useCallback(async () => {
    if (!isAdmin) return;
    try {
      const list: AdminUser[] = await client.rpc("admin_users", {});
      const fresh = list.filter((u) => !u.approved && !notified.current.has(u.id));
      const firstLoad = notified.current.size === 0 && users.length === 0;
      list.filter((u) => !u.approved).forEach((u) => notified.current.add(u.id));
      if (fresh.length && !firstLoad && "Notification" in window) {
        const show = () => fresh.forEach((u) => new Notification("New Orbit sign-up", { body: `${u.username ?? u.name} (${u.email ?? "no email"}) is waiting for your approval.` }));
        if (Notification.permission === "granted") show();
        else if (Notification.permission !== "denied") Notification.requestPermission().then((p) => p === "granted" && show());
      }
      setUsers(list);
    } catch (e: any) { setMessage(e?.message ?? String(e)); }
  }, [isAdmin, users.length]);

  useEffect(() => {
    if (state !== "approved" || !isAdmin) return;
    loadUsers();
    const t = setInterval(loadUsers, 45_000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state, isAdmin]);

  const usernameFree = async (name: string) => (await client.rpcAnon("username_available", { wanted: name })) !== false;

  const value: Account = {
    state, profile, email, message, busy, lastSync, syncing, syncError, users, isAdmin,
    pendingCount: users.filter((u) => !u.approved).length,
    setMessage,
    signUp: async (em, username, password) => {
      em = em.trim().toLowerCase(); username = username.trim();
      const problem = validate(em, username, password);
      if (problem) { setMessage(problem); return; }
      await perform(async () => {
        if (!(await usernameFree(username))) throw new Error("That username is taken.");
        await client.signUp(em, password);
        await client.insert("profiles", { id: client.session!.userID.toLowerCase(), name: username, username });
        await loadProfile();
      });
    },
    signIn: async (em, password) => {
      em = em.trim().toLowerCase();
      if (!em || !password) { setMessage("Enter your email and password."); return; }
      await perform(async () => { await client.signInPassword(em, password); await loadProfile(); });
    },
    upgrade: async (em, username, password) => {
      em = em.trim().toLowerCase(); username = username.trim();
      const problem = validate(em, username, password);
      if (problem) { setMessage(problem); return; }
      await perform(async () => {
        if (username.toLowerCase() !== (profile?.username ?? "").toLowerCase() && !(await usernameFree(username))) throw new Error("That username is taken.");
        await client.updateUser({ email: em, password });
        await client.patch(`profiles?id=eq.${client.session!.userID.toLowerCase()}`, { username, name: username });
        await loadProfile();
      });
    },
    signOut: async () => {
      window.clearTimeout(timer.current);
      if (meta().dirty) await upload();
      client.signOut(); friends.clearLocal();
      setProfile(null); setEmail(null); setUsers([]); setState("signedOut");
    },
    refreshStatus: loadProfile,
    changeUsername: async (u) => {
      u = u.trim();
      if (u.length < 3 || u.length > 24) { setMessage("Usernames are 3–24 characters."); return false; }
      let ok = false;
      await perform(async () => {
        if (!(await usernameFree(u))) throw new Error("That username is taken.");
        await client.patch(`profiles?id=eq.${client.session!.userID.toLowerCase()}`, { username: u, name: u });
        setProfile((p) => (p ? { ...p, username: u, name: u } : p));
        await friends.reload();
        ok = true;
      });
      return ok;
    },
    changePassword: async (current, next) => {
      if (next.length < 6) { setMessage("Passwords are at least 6 characters."); return false; }
      let ok = false;
      await perform(async () => {
        try { await client.signInPassword(email ?? "", current); } catch { throw new Error("Your current password isn't right."); }
        await client.updateUser({ password: next });
        ok = true;
      });
      return ok;
    },
    changeEmail: async (next, password) => {
      next = next.trim().toLowerCase();
      if (!next.includes("@")) { setMessage("That doesn't look like an email."); return false; }
      let ok = false;
      await perform(async () => {
        try { await client.signInPassword(email ?? "", password); } catch { throw new Error("Your password isn't right."); }
        await client.updateUser({ email: next });
        setEmail(client.session?.email ?? next);
        ok = true;
      });
      return ok;
    },
    upload,
    loadUsers,
    approve: async (id) => { await perform(() => client.rpc("approve_user", { uid: id })); await loadUsers(); },
    reject: async (id) => { await perform(() => client.rpc("reject_user", { uid: id })); await loadUsers(); },
    resetPassword: async (id) => {
      const temp = "Orbit-" + Math.floor(100000 + Math.random() * 900000);
      let ok = false;
      await perform(async () => { await client.rpc("admin_reset_password", { uid: id, new_password: temp }); ok = true; });
      return ok ? temp : null;
    },
    giftNotice, clearGiftNotice: () => setGiftNotice(null),
    giftRockets: async (id, amount) => {
      let ok = false;
      await perform(async () => { await client.rpc("admin_gift_rockets", { uid: id, amount }); ok = true; });
      if (ok && id.toLowerCase() === client.session?.userID.toLowerCase()) await claimGifts();
      return ok;
    },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAccount(): Account {
  const a = useContext(Ctx);
  if (!a) throw new Error("AccountProvider missing");
  return a;
}

/** A system notification when allowed (falls back silently; the in-app banner always shows) */
export function notify(title: string, body: string) {
  try {
    if (!("Notification" in window)) return;
    if (Notification.permission === "granted") new Notification(title, { body });
    else if (Notification.permission !== "denied") Notification.requestPermission().then((p) => { if (p === "granted") new Notification(title, { body }); });
  } catch { /* not supported in this webview */ }
}
