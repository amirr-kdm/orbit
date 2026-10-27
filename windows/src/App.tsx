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
import FightClubPage from "./pages/FightClub";
import ChallengesPage from "./pages/Challenges";
import About from "./pages/About";
import { ambient, fontOf, templateOf } from "./lib/themes";
import Settings from "./pages/Settings";
import iconUrl from "./icon.png";
import { useAccount } from "./lib/account";
import LevelPass from "./pages/LevelPass";
import { myStreak } from "./lib/friends";
import { FREEZES_PER_MONTH } from "./lib/streak";
import { AdminPanel, LoginPage, PendingPage, ProfileModal } from "./pages/Account";
import { Avatar, StreakIcon } from "./components";
import { Bell, Toast, Notice, useInbox } from "./lib/inbox";
import { useChallenges } from "./lib/challenges";
import { useFightClub } from "./lib/fightclub";
import { studyingNow, useFriends } from "./lib/friends";
import { QuickTaskModal } from "./lib/anytime";
import { progress, wallet } from "./lib/store";

export type Tab = "today" | "schedule" | "planner" | "timer" | "tasks" | "calendar" | "reports" | "galaxy" | "store" | "friends" | "groups" | "fightClub" | "challenges" | "settings";
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
  { id: "groups", title: "Groups", icon: "🫂", section: "Social" },
  { id: "challenges", title: "Challenges", icon: "🏁", section: "Social" },
  { id: "fightClub", title: "Fight Club", icon: "💥", section: "Social" },
  { id: "settings", title: "Settings", icon: "⚙️", section: "App" },
];

interface Nav { tab: Tab; go: (t: Tab, focusDay?: Date) => void; focusDay?: Date; clearFocus: () => void }
const NavCtx = createContext<Nav>(null!);
export const useNav = () => useContext(NavCtx);

const GroupsPage = () => <Friends only="groups" />;

export default function App() {
  const { data, passMoment, setPassMoment } = useStore();
  const timer = useTimer();
  const [tab, setTab] = useState<Tab>((new URLSearchParams(location.search).get("tab") as Tab) || "today");
  const [focusDay, setFocusDay] = useState<Date>();
  const account = useAccount();
  const [showAdmin, setShowAdmin] = useState(false);
  const [showProfile, setShowProfile] = useState(false);
  const [showAbout, setShowAbout] = useState(false);
  const [quick, setQuick] = useState(false);
  const challenges = useChallenges();
  const fc = useFightClub();
  const fr = useFriends();
  const update = useUpdateCheck();
  const [updateHidden, setUpdateHidden] = useState(false);
  const [copied, setCopied] = useState(false);
  const inbox = useInbox();
  useEffect(() => { if (update) inbox.post({ id: `update-${update}`, kind: "update", route: undefined, title: `Orbit ${update} is out`, body: `You have ${APP_VERSION}. Open the banner at the top to get the new version.` }); }, [update]); // eslint-disable-line react-hooks/exhaustive-deps

  // Theme + accent
  useEffect(() => {
    const apply = () => {
      const dark = data.settings.appearance === "dark" || (data.settings.appearance === "system" && matchMedia("(prefers-color-scheme: dark)").matches);
      document.documentElement.dataset.theme = dark ? "dark" : "light";
      document.documentElement.style.setProperty("--accent", data.settings.accent);
      // the template's soft colour blobs behind every page, and a whole-app font
      // like the Mac app, the template's background shows behind the weekly schedule
      document.documentElement.style.setProperty("--ambient", (tab === "schedule" && ambient(templateOf(data.settings.template), dark)) || "none");
      // Midnight Black in dark mode: the whole app turns pure black
      document.documentElement.dataset.tpl = templateOf(data.settings.template).id;
      const f = fontOf(data.settings.font);
      document.body.style.fontFamily = f.whole ? f.css : "";
    };
    apply();
    const mq = matchMedia("(prefers-color-scheme: dark)"); mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, [data.settings.appearance, data.settings.accent, data.settings.template, data.settings.font, tab]);

  useEffect(() => { document.title = timer.active ? `⏱ ${clock(timer.display)} · Orbit` : "Orbit"; }, [timer.active, timer.display]);

  // Ctrl+N: new task from anywhere
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "n") { e.preventDefault(); setQuick(true); } };
    window.addEventListener("keydown", k); return () => window.removeEventListener("keydown", k);
  }, []);

  const nav: Nav = { tab, go: (t, d) => { setTab(t); setFocusDay(d); }, focusDay, clearFocus: () => setFocusDay(undefined) };
  const Page = { today: Today, schedule: Schedule, planner: PlannerPage, timer: TimerPage, tasks: Tasks, calendar: Calendar, reports: Reports, galaxy: Galaxy, store: StorePage, friends: Friends, groups: GroupsPage, fightClub: FightClubPage, challenges: ChallengesPage, settings: Settings }[tab];

  const openNotice = (n: Notice) => {
    if (n.route) {
      if (n.target) { sessionStorage.setItem("orbit-open-challenge", n.target); setTimeout(() => window.dispatchEvent(new Event("orbit-open-challenge")), 50); }
      nav.go(n.route as Tab);
    }
  };
  /** Little numbers on the sidebar: friends studying, challenges running, my Fight Club place */
  const badge = (id: Tab): { text: string; color: string } | null => {
    if (id === "friends") { const n = fr.friends.filter((x) => studyingNow(x)).length; return n ? { text: String(n), color: "#22C55E" } : null; }
    if (id === "challenges") { const n = challenges.liveCount(); return n ? { text: String(n), color: "#F97316" } : null; }
    if (id === "fightClub" && fc.worldBoss) {
      const ranked = (fc.fighters[fc.worldBoss.id] ?? []).filter((x) => x.damage > 0), mine = ranked.find((x) => x.user_id === fc.me);
      return mine ? { text: `#${ranked.filter((x) => x.damage > mine.damage).length + 1}`, color: "#EF4444" } : null;
    }
    return null;
  };

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
              <span className="ico">{t.icon}</span>
              {t.id === "galaxy" ? <span>{t.title}<span className="sub">🪐 {data.galaxy.length} · ☀️ {data.solarSystems.length}</span></span> : t.title}
              {(() => { const b = badge(t.id); return b && <span className="nbadge" style={{ background: b.color }}>{b.text}</span>; })()}
            </button>
          </React.Fragment>))}
          <button className="nav" onClick={() => setShowAbout(true)}><span className="ico">ℹ️</span>About</button>
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
                  <div className="small muted" title={account.syncError ? "Offline" : "Synced"} style={{ whiteSpace: "nowrap" }}>Lv {progress(data).level} · {wallet(data).balance} 🚀</div></div>
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
          <div className="topbar">
            <button className="icon-btn" style={{ fontSize: 18 }} title="New task (Ctrl+N)" onClick={() => setQuick(true)}>＋</button>
            <Bell onOpenNotice={openNotice} />
          </div>
          <div className="main-scroll"><Page /></div>
        </main>
        <Toast onOpenNotice={openNotice} />
        {quick && <QuickTaskModal onClose={() => setQuick(false)} onStudy={(id) => { timer.setTarget({ kind: "task", id }); nav.go("timer"); }} />}
        {showAdmin && account.isAdmin && <AdminPanel onClose={() => setShowAdmin(false)} />}
        {showAbout && <About onClose={() => setShowAbout(false)} />}
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
  // The popup is placed on the window (not inside the narrow sidebar), kept fully on screen
  const [pos, setPos] = useState<{ left: number; bottom: number } | null>(null);
  const show = (el: HTMLElement) => {
    const r = el.getBoundingClientRect(), w = 260;
    setPos({ left: Math.max(8, Math.min(r.left, window.innerWidth - w - 8)), bottom: window.innerHeight - r.top + 8 });
  };
  return (
    <span className="streak-chip" onClick={(e) => e.stopPropagation()}
      onMouseEnter={(e) => show(e.currentTarget)} onMouseLeave={() => setPos(null)}>
      <StreakIcon size={15} /><b>{info.days}</b>
      <span className="streak-pop" style={pos ? { display: "flex", left: pos.left, bottom: pos.bottom } : undefined}>
        <b><StreakIcon size={18} /> {info.days}-day streak</b>
        <span>{Array.from({ length: FREEZES_PER_MONTH }, (_, i) => <span key={i} style={{ opacity: i < info.freezesLeft ? 1 : 0.3 }}>❄️</span>)} {info.freezesLeft} of {FREEZES_PER_MONTH} freezes left this month</span>
        <span className="small muted">Miss a day and a freeze is used automatically, so your streak survives. You get 3 new ones every month.</span>
        {info.frozen.length > 0 && <span className="small" style={{ color: "#22D3EE" }}>Frozen: {info.frozen.slice(0, 5).map((d) => d.toLocaleDateString()).join(", ")}</span>}
      </span>
    </span>
  );
}
