<div align="center">

<img src="docs/icon.png" alt="Orbit icon" width="140">

# Orbit

**A study planner that turns your focus time into a galaxy.**

Weekly timetable · to-do lists · study timer · reports · Persian & Gregorian calendars · study with friends

[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://github.com/amirr-kdm/orbit/releases/latest/download/Orbit.zip)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](https://github.com/amirr-kdm/orbit/releases/latest/download/Orbit-Setup.exe)
[![Release](https://img.shields.io/github/v/release/amirr-kdm/orbit)](https://github.com/amirr-kdm/orbit/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## ⬇️ Download

<table>
<tr>
<td width="50%" valign="top">

### 🍎 macOS
**[Download Orbit.zip](https://github.com/amirr-kdm/orbit/releases/latest/download/Orbit.zip)**
macOS 14+ · Apple Silicon & Intel

1. Unzip and drag **Orbit.app** into **Applications**.
2. First time only: **right-click → Open → Open** (the app isn't notarized by Apple).

</td>
<td width="50%" valign="top">

### 🪟 Windows
**[Download Orbit-Setup.exe](https://github.com/amirr-kdm/orbit/releases/latest/download/Orbit-Setup.exe)**
Windows 10 / 11 · 64-bit

1. Run **Orbit-Setup.exe**.
2. If SmartScreen appears: **More info → Run anyway** (the app isn't code-signed).

</td>
</tr>
</table>

👥 **Friends works across platforms.** Both downloads connect to the same server, so Mac and Windows users can add each other with a friend code. There's nothing to set up.

---

## ✨ Features

| | |
|---|---|
| 📅 **Weekly schedule** | Even/odd weeks, custom colours, categories, repeat rules and a live "Now / Next" card |
| 📝 **Planner** | Draft weeks with brainstorm notes (rich text, checklists, tables), then add them to your schedule |
| ✅ **Tasks** | Daily to-do list plus Day, Week and List views with drag and drop |
| ⏱ **Study timer** | Stopwatch or Pomodoro; every session is saved |
| 📊 **Reports & calendar** | Weekly and monthly charts, a month calendar in Persian or Gregorian |
| 🌌 **My Galaxy** | Level up by studying, collect 50 planets and build solar systems |
| 👥 **Friends** | Leaderboard, who's studying now, subject breakdowns and visits to each other's galaxies |
| 🔒 **Private** | Your schedule and tasks stay on your computer; only daily totals are shared |

---

## 📖 Contents

[Quick start](#-quick-start) · [User guide](#-user-guide) · [Data & privacy](#-your-data--privacy) · [Build from source](#-build-from-source) · [Self-hosting Friends](#-self-hosting-friends-supabase)

---

## 🚀 Quick start

1. **Set up your week.** Open **Weekly Schedule**, click a cell and type a class or study block. **Enter** saves.
2. **Mark what to study.** Set the cell's type to **To-do**. To-do cells appear in **Today** and **Tasks**.
3. **Study.** In **Today**, press **Study** next to a to-do, then **Start**. Press **Finish & Save** when done.
4. **Track progress** in **Reports**. Every week of study helps you level up in **My Galaxy**.
5. **Study together.** Open **Friends**, create a profile and share your code.

---

## 📘 User guide

### 📅 Weekly Schedule

<img src="docs/screenshots/schedule.png" alt="Weekly Schedule" width="100%">

Days run down the side (Saturday → Friday) and time slots across the top.

| Action | How |
|---|---|
| Add / edit a cell | Click and type. **Enter** saves, **Shift+Enter** adds a line, **Esc** cancels. |
| Clear a cell | Delete its text and press Enter, or right-click → **Clear Cell**. |
| Colour | Pick a swatch in the bottom toolbar. **+** creates your own colour; right-click a swatch to delete it. |
| Type | **Fixed** = classes and appointments. **To-do** = something to study (also listed in Today and Tasks). |
| Category | Toolbar or right-click. Saved with timer sessions and used by filters. |
| Repeat | **Every week**, **Even weeks**, **Odd weeks** or **This week only**. |
| Other weeks | ◀ ▶ next to the title. Right-click the **EVEN / ODD WEEK** badge to swap parity. |
| Tick off / study | Click the circle in a To-do cell, or right-click → **Study This Now**. |

### 📝 Planner

Create as many planners as you like (for example "Midterm week" or "Summer plan"). Each one has:

- **A weekly plan** with the same days and time slots as your schedule. Class times from the weekly schedule are **locked**, so you can only plan around them. Use **This week / Next week** to choose which week's classes are locked.
- **Notes & brainstorm**: any number of notes with titles, headings, bold / italic / underline, colours and highlights, bulleted, numbered and **checklists** (click a box to tick it), divider lines and **tables** (use *Table Options…* to add rows and columns or merge cells).

Press **Add to Weekly Schedule…**, then choose the week and how it repeats. If some planned to-dos land on cells that already have a to-do, Orbit lists the clashes and asks what to do:
- **Replace the old to-dos** with the planner's,
- **Keep the old to-dos**, skipping only the clashing planner to-dos and adding the rest, or
- **Cancel**.

### ☀️ Today & ✅ Tasks

<table>
<tr>
<td width="50%"><img src="docs/screenshots/today.png" alt="Today"></td>
<td width="50%"><img src="docs/screenshots/tasks-week.png" alt="Tasks week board"></td>
</tr>
</table>

**Today** lists today's schedule to-dos, other tasks, overdue items and today's sessions. Press **Study** to send an item to the timer.

**Tasks** has three views:
- **Week**: a column per day. **Drag** cards between days; moving a schedule to-do moves only that day's session. Undated tasks wait in the **No date** tray.
- **Day**: one day in detail.
- **List**: filters (Today, Upcoming, No Date, All Open, Done) and search.
- **Graph**: an Obsidian-style map where every category is a hub with its tasks and weekly to-dos around it. Drag nodes, pinch to zoom, hover to highlight connections, and click an item to tick it off or study it.

### ⏱ Timer

<img src="docs/screenshots/timer.png" alt="Timer" width="100%">

Choose **Stopwatch** or **Pomodoro**, pick what you're studying, then **Start → Pause → Finish & Save**. On Mac the timer also lives in the menu bar. Missed one? Use **Log Manually**. Sessions under 30 seconds aren't saved.

### 📆 Calendar & 📊 Reports

<table>
<tr>
<td width="50%"><img src="docs/screenshots/calendar.png" alt="Calendar"></td>
<td width="50%"><img src="docs/screenshots/reports.png" alt="Reports"></td>
</tr>
</table>

**Calendar** shows each day's to-dos, classes and study time; click a day for details, double-click to plan it in Tasks.
**Reports** shows totals, daily average, best day, a per-subject bar chart, a subject donut and the to-dos **left undone** in the period, weekly or monthly.

### 🌌 My Galaxy

<table>
<tr>
<td width="50%"><img src="docs/screenshots/galaxy.png" alt="Galaxy map"></td>
<td width="50%"><img src="docs/screenshots/solar-system.png" alt="A solar system"></td>
</tr>
</table>

- **Levels:** everyone starts at level 1. At the end of each week (Sat → Fri), **10 h** of study = **+1 level** and **20 h** = **+2 levels**. Max level 50.
- **Planets:** one new planet per level. 50 planets in 10 groups; a new group unlocks every 5 levels (1, 6, 11 … 46).
- **Solar systems:** up to 8 planets each, with stars that unlock as you level up (Yellow Sun, Red Giant, Blue Star, White Dwarf, Twin Stars, Pulsar).
- **Map:** drag to explore, zoom, and click a system to fly in. Any planet can be your **profile picture**.

<details>
<summary><b>See all 50 planets</b></summary>
<br>
<img src="docs/planets.png" alt="All 50 planets" width="100%">
</details>

### 👥 Friends

<img src="docs/screenshots/friends.png" alt="Friends" width="100%">

1. Type your name and press **Create My Profile**. No email or password needed.
2. Share your **6-character friend code**; add theirs under **Add a friend**.

You'll see who's **studying right now**, a weekly **leaderboard** with levels and 🔥 streaks (click a row for a subject-by-subject breakdown and their **Galaxy**), and friend cards with 7-day charts.

### ⚙️ Settings

<img src="docs/screenshots/settings.png" alt="Settings" width="100%">

Appearance (Light / Dark / System), design templates and fonts (Mac), primary calendar, time slots, Pomodoro and daily goal, task categories, and your data location / backup.

---

## 🔒 Your data & privacy

- Everything you create is stored **locally**:
  - **Mac:** `~/Library/Application Support/Orbit/data.json`
  - **Windows:** inside the app's local storage. Use **Settings → Export backup** to save a copy.
- With Friends, only **daily summaries** are uploaded: minutes studied, subjects and their time, to-dos done, what you're studying now, level, profile planet and galaxy layout. Schedules, tasks and notes are **never** uploaded.
- **Delete My Profile** removes everything you shared from the server.

---

## 🛠 Build from source

<details>
<summary><b>macOS (SwiftUI)</b></summary>

Requires macOS 14+ and Xcode 15+ (or `xcode-select --install`).

```bash
git clone https://github.com/amirr-kdm/orbit.git
cd orbit
./build.sh            # → build/Orbit.app
./build.sh install    # install into ~/Applications
./build.sh release    # universal build → build/Orbit.zip
```

Update later with `git pull && ./build.sh install`. Your data is kept.

If you share a zip and macOS blocks it, run `xattr -cr /path/to/Orbit.app`. With Friends, macOS may ask for your login password to read the saved sign-in. Choose **Always Allow**.

</details>

<details>
<summary><b>Windows (Tauri + React)</b></summary>

The source is in [`windows/`](windows). Requires Node 20+ and Rust.

```bash
cd windows
npm install
npm run tauri dev     # run in development
npm run tauri build   # build the installer
```

Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_KEY` to enable Friends. Releases are built automatically by [GitHub Actions](.github/workflows/windows.yml).

</details>

<details>
<summary><b>Project layout & developer flags</b></summary>

```
Sources/ClaudeSchedule/   macOS app (SwiftUI): models, store, timer, galaxy, friends, views
windows/                  Windows app (Tauri + React + TypeScript)
supabase/schema.sql       Database schema and Row Level Security rules
scripts/make_icon.swift   Generates the Mac icon from Resources/icon-source.jpeg
build.sh                  Builds and packages Orbit.app
```

| Variable (Mac) | Effect |
|---|---|
| `CS_DATA_DIR=/path` | Use a separate data folder and Friends sign-in |
| `CS_START_TAB=galaxy` | Open on a screen (`today`, `schedule`, `planner`, `timer`, `tasks`, `calendar`, `reports`, `galaxy`, `friends`, `settings`) |
| `CS_TASKS_MODE=graph` | Open Tasks in a view (`day`, `week`, `list`, `graph`) |
| `CS_RENDER_PLANETS=/path.png` | Render all 50 planets and quit |
| `CS_RENDER_SYSTEM=/path.png` | Render a sample solar system and quit |

</details>

---

## ☁️ Self-hosting Friends (Supabase)

The downloads already use the shared Orbit server. You only need this if you build from source with **your own** server.

<details>
<summary><b>Setup steps</b></summary>

1. Create a free project at [supabase.com](https://supabase.com).
2. **SQL Editor → New query**, paste [`supabase/schema.sql`](supabase/schema.sql) and press **Run**. Then do the same with [`supabase/groups.sql`](supabase/groups.sql) (groups and friend requests).
3. **Authentication → Sign In / Providers**: turn on **Allow anonymous sign-ins**.
4. **Project Settings → API Keys**: copy the **Project URL** and **Publishable key** (`sb_publishable_…`).
5. Mac: `cp Resources/Supabase.example.plist Resources/Supabase.plist`, fill in `URL` and `PublishableKey`, then `./build.sh install`.
   Windows: set `VITE_SUPABASE_URL` / `VITE_SUPABASE_KEY` before building.

Everyone who wants to be friends must use builds pointing to **the same** project.

> ⚠️ Only use the **publishable** key, never the secret / service_role key. `Resources/Supabase.plist` is git-ignored.

Row Level Security lets each user read only their own and their friends' data, and write only their own. A free project pauses after a week of inactivity; press *Restore* in the dashboard (no data is lost).

</details>

---

## 📄 License

[MIT](LICENSE) © 2026 amirr-kdm
