// Rockets live on the server (supabase/wallet.sql), same as the Mac app: the balance, owned planets, refunds and
// claimed Level Pass levels come from there, and buying / refunds / rewards are server calls — so editing the
// data can't change rockets and two devices can't spend the same rockets twice.
// Until a member's wallet exists (the first time an app runs online it's moved over once), the local reckoning counts.
import { AppData } from "./model";
import { accountData, isOfflineError, OFFLINE_MESSAGE, sharedClient as client } from "./friends";
import { addDays, dayKey, weekStart } from "./dates";
import { canClaim, progress, serverWallet, wallet } from "./store";

type Update = (fn: (d: AppData) => void) => void;
interface WalletState {
  started: boolean; balance: number | null; refunds_left: number; levels: number[] | null;
  planets: { id: string; planet: string; price: number; at: string }[];
}

const cacheKey = () => `orbit-wallet-${client.session?.userID ?? ""}`;
export const walletLive = () => serverWallet.balance !== null;

async function fetchWallet(): Promise<WalletState | null> {
  try { return await client.rpc("my_wallet", {}); } catch { return null; }
}

function apply(s: WalletState, update: Update) {
  if (!s.started || s.balance === null) return;
  serverWallet.balance = s.balance;
  serverWallet.refundsLeft = s.refunds_left;
  try { localStorage.setItem(cacheKey(), String(s.balance)); } catch { /* ignore */ }
  const levels = [...new Set(s.levels ?? [])].sort((a, b) => a - b);
  // always a new data object, so every page shows the new balance
  update((d) => {
    const owned = s.planets.map((p) => ({ id: p.id.toUpperCase(), planetID: p.planet, price: p.price, date: p.at }));
    if (owned.map((p) => p.id).join() !== d.purchases.map((p) => p.id.toUpperCase()).join()) d.purchases = owned;
    if (levels.join() !== [...(d.claimedLevels ?? [])].sort((a, b) => a - b).join()) d.claimedLevels = levels;
  });
}

/** Fetch the wallet (moving the local balance over the first time) and take in what it says */
export async function walletRefresh(get: () => AppData, update: Update) {
  if (!client.session || !accountData.ready) return;
  if (serverWallet.balance === null) {
    const cached = Number(localStorage.getItem(cacheKey()) ?? "NaN");
    if (!Number.isNaN(cached)) serverWallet.balance = cached;
  }
  let state = await fetchWallet();
  if (!state) return;
  if (!state.started) {
    const d = get();
    const body = {
      balance: wallet(d).balance,
      planets: d.purchases.map((p) => ({ planetID: p.planetID, price: p.price, date: p.date })),
      levels: d.claimedLevels ?? [], refunds_used: d.refundsUsed,
    };
    try { await client.rpc("wallet_start", body); } catch { return; }
    state = await fetchWallet();
    if (!state) return;
  }
  apply(state, update);
  // finished weeks' bonuses (the server works them out from your study and pays each once)
  let paid = false;
  for (let back = 1; back <= 3; back++) {
    try { const n = await client.rpc("claim_week_bonus", { week_start: dayKey(addDays(weekStart(new Date()), -7 * back)) }); if (n > 0) paid = true; }
    catch { /* offline */ }
  }
  if (paid) { const s = await fetchWallet(); if (s) apply(s, update); }
}

/** Buy a store planet. Returns an error message, or null when it worked. */
export async function walletBuy(id: string, get: () => AppData, update: Update, localBuy: () => void): Promise<string | null> {
  if (!walletLive()) { localBuy(); return null; }
  try { await client.rpc("buy_planet", { planet: id }); await walletRefresh(get, update); return null; }
  catch (e) { return e instanceof Error && !e.message.includes("fetch") ? e.message : "Connect to the internet to buy planets."; }
}

/** Give one bought copy back for its full price (uses a refund ticket) */
export async function walletRefund(id: string, get: () => AppData, update: Update, localRefund: () => void): Promise<string | null> {
  if (!walletLive()) { localRefund(); return null; }
  const p = [...get().purchases].reverse().find((x) => x.planetID === id && x.price > 0);
  if (!p) return "Nothing to refund.";
  try {
    await client.rpc("refund_planet", { purchase: p.id.toLowerCase() });
    update((d) => {
      const owned = d.purchases.filter((x) => x.planetID === id).length - 1;
      if (d.galaxy.filter((g) => g.planetID === id).length > owned) {
        const j = d.galaxy.map((g) => g.planetID).lastIndexOf(id); if (j >= 0) d.galaxy.splice(j, 1);
      }
      if (d.avatarPlanet === id && owned === 0) d.avatarPlanet = undefined;
    });
    await walletRefresh(get, update);
    return null;
  } catch (e) { return e instanceof Error && !e.message.includes("fetch") ? e.message : "Connect to the internet to refund."; }
}

/** Take a Level Pass level's rewards. Returns a message when it didn't work (offline, or the server said no); null when taken.
 *  Nothing is lost when it fails: the level stays claimable until the server has paid it. */
export async function walletClaim(level: number, get: () => AppData, update: Update, localClaim: () => void): Promise<string | null> {
  if (!walletLive()) { localClaim(); return null; }
  if (!canClaim(get(), level)) return null;
  try {
    // the server checks your level: make sure it has the latest
    await client.patch(`profiles?id=eq.${client.session!.userID.toLowerCase()}`, { level: progress(get()).level });
    await client.rpc("claim_level", { lvl: level });
  } catch (e) {
    return isOfflineError(e) ? `${OFFLINE_MESSAGE} Your reward is safe: open the Level Pass again once you're online and press Claim.` : e instanceof Error ? e.message : "Couldn't take the reward. Try again in a moment.";
  }
  await walletRefresh(get, update);
  return canClaim(get(), level) ? "The server didn't confirm the reward yet. Try again in a moment." : null;
}

/** Last week's group prize, worked out by the server. True when it was paid now. */
export async function walletGroupWin(group: string, week: Date, get: () => AppData, update: Update): Promise<boolean> {
  try {
    const ok = await client.rpc("claim_group_win", { g: group.toLowerCase(), week_start: dayKey(week) });
    if (ok === true) { await walletRefresh(get, update); return true; }
  } catch { /* offline */ }
  return false;
}
