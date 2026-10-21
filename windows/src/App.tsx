import React, { createContext, useContext, useEffect, useState } from "react";
import { useStore } from "./lib/store";
import { APP_VERSION, RELEASES_PAGE, useUpdateCheck } from "./lib/updates";
import { useTimer } from "./lib/timer";
import { clock } from "./lib/dates";
import Today from "./pages/Today";
import Schedule from "./pages/Schedule";
import PlannerPage from "./pages/Planner";
import TimerPage from "./pages/Timer";
import Tasks from "./pages/Tasks";
import Calendar from "./pages/Calendar";
import Reports from "./pages/Reports";
import Galaxy from "./pages/Galaxy";
import StorePage from "./pages/Store";
import Friends from "./pages/Friends";
import Settings from "./pages/Settings";
import iconUrl from "./icon.png";
import { useAccount } from "./lib/account";
import LevelPass from "./pages/LevelPass";
import { myStreak } from "./lib/friends";
import { FREEZES_PER_MONTH } from "./lib/streak";
import { AdminPanel, LoginPage, PendingPage, ProfileModal } from "./pages/Account";
import { Avatar, StreakIcon } from "./components";

export type Tab = "today" | "schedule" | "planner" | "timer" | "tasks" | "calendar" | "reports" | "galaxy" | "store" | "friends" | "settings";
const TABS: { id: Tab; title: string; icon: string; section: string }[] = [
  { id: "today", title: "Today", icon: "☀️", section: "Plan" },
  { id: "schedule", title: "Weekly Schedule", icon: "🗓️", section: "Plan" },
  { id: "tasks", title: "Tasks", icon: "✅", section: "Plan" },
  { id: "calendar", title: "Calendar", icon: "📆", section: "Plan" },
  { id: "planner", title: "Notes & Brainstorm", icon: "🧠", section: "Plan" },
  { id: "timer", title: "Timer", icon: "⏱️", section: "Focus" },
  { id: "reports", title: "Reports", icon: "📊", section: "Focus" },
  { id: "galaxy", title: "My Galaxy", icon: "✨", section: "Rewards" },
  { id: "store", title: "Store", icon: "🛍️", section: "Rewards" },
  { id: "friends", title: "Friends", icon: "👥", section: "Social" },
  { id: "settings", title: "Settings", icon: "⚙️", section: "App" },
];

interface Nav { tab: Tab; go: (t: Tab, focusDay?: Date) => void; focusDay?: Date; clearFocus: () => void }
const NavCtx = createContext<Nav>(null!);
export const useNav = () => useContext(NavCtx);

export default function App() {
  const { data, passMoment, setPassMoment } = useStore();
  const timer = useTimer();
  const [tab, setTab] = useState<Tab>((new URLSearchParams(location.search).get("tab") as Tab) || "today");
  const [focusDay, setFocusDay] = useState<Date>();
  const account = useAccount();
  const [showAdmin, setShowAdmin] = useState(false);
  const [showProfile, setShowProfile] = useState(false);
  const update = useUpdateCheck();
  const [updateHidden, setUpdateHidden] = useState(false);
  const [copied, setCopied] = useState(false);

  // Theme + accent
  useEffect(() => {
    const apply = () => {
      const dark = data.settings.appearance === "dark" || (data.settings.appearance === "system" && matchMedia("(prefers-color-scheme: dark)").matches);
      document.documentElement.dataset.theme = dark ? "dark" : "light";
      document.documentElement.style.setProperty("--accent", data.settings.accent);
    };
    apply();
    const mq = matchMedia("(prefers-color-scheme: dark)"); mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, [data.settings.appearance, data.settings.accent]);

  useEffect(() => { document.title = timer.active ? `⏱ ${clock(timer.display)} · Orbit` : "Orbit"; }, [timer.active, timer.display]);

  const nav: Nav = { tab, go: (t, d) => { setTab(t); setFocusDay(d); }, focusDay, clearFocus: () => setFocusDay(undefined) };
  const Page = { today: Today, schedule: Schedule, planner: PlannerPage, timer: TimerPage, tasks: Tasks, calendar: Calendar, reports: Reports, galaxy: Galaxy, store: StorePage, friends: Friends, settings: Settings }[tab];

  // Accounts: log in, upgrade an old profile, or wait for the owner's approval
  if (account.state === "loading") return <div className="space-login" />;
  if (account.state === "signedOut") return <LoginPage />;
  if (account.state === "needsUpgrade") return <LoginPage upgrade />;
  if (account.state === "pending") return <PendingPage />;

  return (
    <NavCtx.Provider value={nav}>
      <div className="app">
        <aside className="sidebar">
          <div className="brand"><img src={iconUrl} alt="" />Orbit</div>
          {TABS.map((t, i) => (<React.Fragment key={t.id}>
            {t.section !== TABS[i - 1]?.section && <div className="nav-section">{t.section}</div>}
            <button className={`nav ${tab === t.id ? "active" : ""}`} onClick={() => nav.go(t.id)}>
              <span className="ico">{t.icon}</span>{t.title}
            </button>
          </React.Fragment>))}
          <div style={{ marginTop: "auto", display: "flex", flexDirection: "column", gap: 8 }}>
            {timer.active && (
              <div className="mini-timer" onClick={() => nav.go("timer")}>
                <b>{clock(timer.display)}</b>
                <div className="small muted">{timer.phase === "rest" ? "Break" : timer.targetTitle ?? "Free study"} {timer.running ? "" : "· paused"}</div>
              </div>
            )}
            {account.isAdmin && (
              <button className="nav" onClick={() => setShowAdmin((v) => !v)} title="Sign-ups and members (only you see this)">
                <span className="ico">👑</span>Admin{account.pendingCount > 0 && <span className="badge" style={{ background: "#ef4444", marginLeft: "auto" }}>{account.pendingCount}</span>}
              </button>
            )}
            {account.state === "approved" && (
              <button className="account-chip" onClick={() => setShowProfile(true)}>
                <Avatar name={account.profile?.name ?? "?"} planet={data.avatarPlanet} size={26} color="var(--accent)" />
                <div style={{ flex: 1, minWidth: 0 }}><b className="small">@{account.profile?.username ?? account.profile?.name}</b>
                  <div className="small muted">{account.syncError ? "Offline" : "Synced"}</div></div>
                <StreakChip />
              </button>
            )}
          </div>
        </aside>
        <main className="main">
          {account.giftNotice != null && (
            <div className="banner" style={{ background: "color-mix(in srgb, #F97316 18%, transparent)" }}>
              🎁 <b>{account.giftNotice}</b><span className="spacer" />
              <button className="btn small primary" onClick={() => { nav.go("store"); account.clearGiftNotice(); }}>Open Store</button>
              <button className="icon-btn" onClick={account.clearGiftNotice}>✕</button>
            </div>
          )}
          {update && !updateHidden && (
            <div className="banner" style={{ background: "color-mix(in srgb, var(--accent) 18%, transparent)" }}>
              ⬇️ <b>Orbit {update} is out</b> <span className="muted">— you have {APP_VERSION}.</span><span className="spacer" />
              <button className="btn small primary" onClick={async () => {
                try { await navigator.clipboard.writeText(RELEASES_PAGE); setCopied(true); } catch { prompt("Open this link in your browser:", RELEASES_PAGE); }
              }}>{copied ? "Link copied — paste it in your browser" : "Copy download link"}</button>
              <button className="icon-btn" onClick={() => setUpdateHidden(true)}>✕</button>
            </div>
          )}
          <Page />
        </main>
        {showAdmin && account.isAdmin && <AdminPanel onClose={() => setShowAdmin(false)} />}
        {showProfile && <ProfileModal onClose={() => setShowProfile(false)} />}
        {passMoment && <LevelPass key={passMoment.id} fromHours={passMoment.from} onClose={() => setPassMoment(null)} />}
      </div>
    </NavCtx.Provider>
  );
}

/** Streak days next to the account; hover to see the freezes left this month */
function StreakChip() {
  const { data } = useStore();
  const info = myStreak(data);
  return (
    <span className="streak-chip" onClick={(e) => e.stopPropagation()}>
      <StreakIcon size={15} /><b>{info.days}</b>
      <span className="streak-pop">
        <b><StreakIcon size={18} /> {info.days}-day streak</b>
        <span>{Array.from({ length: FREEZES_PER_MONTH }, (_, i) => <span key={i} style={{ opacity: i < info.freezesLeft ? 1 : 0.3 }}>❄️</span>)} {info.freezesLeft} of {FREEZES_PER_MONTH} freezes left this month</span>
        <span className="small muted">Miss a day and a freeze is used automatically, so your streak survives. You get 3 new ones every month.</span>
        {info.frozen.length > 0 && <span className="small" style={{ color: "#22D3EE" }}>Frozen: {info.frozen.slice(0, 5).map((d) => d.toLocaleDateString()).join(", ")}</span>}
      </span>
    </span>
  );
}
