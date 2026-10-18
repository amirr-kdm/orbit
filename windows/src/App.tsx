import { createContext, useContext, useEffect, useState } from "react";
import { useStore } from "./lib/store";
import { useTimer } from "./lib/timer";
import { clock } from "./lib/dates";
import Today from "./pages/Today";
import Schedule from "./pages/Schedule";
import TimerPage from "./pages/Timer";
import Tasks from "./pages/Tasks";
import Calendar from "./pages/Calendar";
import Reports from "./pages/Reports";
import Galaxy from "./pages/Galaxy";
import Friends from "./pages/Friends";
import Settings from "./pages/Settings";
import iconUrl from "./icon.png";

export type Tab = "today" | "schedule" | "timer" | "tasks" | "calendar" | "reports" | "galaxy" | "friends" | "settings";
const TABS: { id: Tab; title: string; icon: string }[] = [
  { id: "today", title: "Today", icon: "☀️" },
  { id: "schedule", title: "Weekly Schedule", icon: "🗓️" },
  { id: "timer", title: "Timer", icon: "⏱️" },
  { id: "tasks", title: "Tasks", icon: "✅" },
  { id: "calendar", title: "Calendar", icon: "📆" },
  { id: "reports", title: "Reports", icon: "📊" },
  { id: "galaxy", title: "My Galaxy", icon: "✨" },
  { id: "friends", title: "Friends", icon: "👥" },
  { id: "settings", title: "Settings", icon: "⚙️" },
];

interface Nav { tab: Tab; go: (t: Tab, focusDay?: Date) => void; focusDay?: Date; clearFocus: () => void }
const NavCtx = createContext<Nav>(null!);
export const useNav = () => useContext(NavCtx);

export default function App() {
  const { data } = useStore();
  const timer = useTimer();
  const [tab, setTab] = useState<Tab>((new URLSearchParams(location.search).get("tab") as Tab) || "today");
  const [focusDay, setFocusDay] = useState<Date>();

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
  const Page = { today: Today, schedule: Schedule, timer: TimerPage, tasks: Tasks, calendar: Calendar, reports: Reports, galaxy: Galaxy, friends: Friends, settings: Settings }[tab];

  return (
    <NavCtx.Provider value={nav}>
      <div className="app">
        <aside className="sidebar">
          <div className="brand"><img src={iconUrl} alt="" />Orbit</div>
          {TABS.map((t) => (
            <button key={t.id} className={`nav ${tab === t.id ? "active" : ""}`} onClick={() => nav.go(t.id)}>
              <span className="ico">{t.icon}</span>{t.title}
            </button>
          ))}
          {timer.active && (
            <div className="mini-timer" onClick={() => nav.go("timer")}>
              <b>{clock(timer.display)}</b>
              <div className="small muted">{timer.phase === "rest" ? "Break" : timer.targetTitle ?? "Free study"} {timer.running ? "" : "· paused"}</div>
            </div>
          )}
        </aside>
        <main className="main"><Page /></main>
      </div>
    </NavCtx.Provider>
  );
}
