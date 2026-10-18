# Orbit 🪐

**A study planner for macOS that turns focus time into a galaxy.**

Orbit brings your weekly timetable, daily to-do list, study timer and progress reports into one native Mac app, with Persian (Jalali) and Gregorian calendars side by side. Every week you study helps you level up, unlock new planets and grow your own galaxy, and you can follow your friends' progress online.

<p align="center">
  <img src="docs/screenshots/schedule.png" alt="Orbit weekly schedule" width="900">
</p>

- 📅 **Weekly schedule** with even/odd weeks, colours, categories and a live "Now / Next" card
- ✅ **Daily to-do list and a week board** with drag and drop
- ⏱ **Study timer** (stopwatch or Pomodoro), also shown in the menu bar
- 📊 **Weekly and monthly reports**, plus a **month calendar**
- 🌌 **My Galaxy**: 50 hand-drawn planets, levels, solar systems and a zoomable spiral galaxy
- 👥 **Friends**: leaderboard, live "studying now", and visits to each other's galaxies (optional, needs a free Supabase project)
- 🎨 8 design templates, Light/Dark mode and font choices
- 🔒 Your schedule and tasks stay on your Mac; only daily summaries are shared with friends

---

## ⬇️ Download

**[Download the latest Orbit.zip](https://github.com/amirr-kdm/orbit/releases/latest/download/Orbit.zip)** — a ready-to-use app for macOS 14+ (Apple Silicon and Intel).

1. Unzip it and drag **Orbit.app** into your **Applications** folder.
2. The first time, **right-click** Orbit.app → **Open** → **Open**. macOS asks because the app isn't notarized by Apple. You only need to do this once.
3. Want to study with friends? Open **Friends**, create your profile and add each other's friend codes. The download is already connected to the shared Orbit server, so there's nothing to set up.

All releases: [github.com/amirr-kdm/orbit/releases](https://github.com/amirr-kdm/orbit/releases)

---

## Contents

1. [Installation](#installation)
2. [Quick start](#quick-start)
3. [User guide](#user-guide)
   - [Weekly Schedule](#-weekly-schedule)
   - [Today](#-today)
   - [Tasks](#-tasks)
   - [Timer](#-timer)
   - [Calendar](#-calendar)
   - [Reports](#-reports)
   - [My Galaxy](#-my-galaxy)
   - [Friends](#-friends)
   - [Settings](#-settings)
4. [Setting up Friends (Supabase)](#setting-up-friends-supabase)
5. [Your data & privacy](#your-data--privacy)
6. [For developers](#for-developers)
7. [Roadmap](#roadmap) · [License](#license)

---

## Installation

> Just want to use the app? Grab it from **[Download](#️-download)** above. This section is for building from source.

### Requirements
- A Mac running **macOS 14 Sonoma or later** (Apple Silicon or Intel)
- **Xcode 15+**, or just the Command Line Tools. If you don't have them, run:
  ```bash
  xcode-select --install
  ```

### Build and install

```bash
# 1. Download the code
git clone https://github.com/amirr-kdm/orbit.git
cd orbit

# 2. Build the app → build/Orbit.app
./build.sh

# 3. Open it
open build/Orbit.app

# Optional: install into ~/Applications so it shows up in Launchpad and Spotlight
./build.sh install

# Universal (Apple Silicon + Intel) build, zipped for sharing → build/Orbit.zip
./build.sh release
```

The first build takes about a minute. Later builds are faster.

### First launch

Orbit is not signed with a paid Apple Developer certificate, so macOS may block it the first time:

- **"Orbit can't be opened because Apple cannot check it…"**: right-click (or Control-click) `Orbit.app`, choose **Open**, then click **Open** again. You only need to do this once.
- If you sent the app to a friend as a zip, they can also run:
  ```bash
  xattr -cr /path/to/Orbit.app
  ```
- **Keychain prompt** (only when using Friends): macOS may ask for your Mac login password so Orbit can read its saved sign-in. Enter it and choose **Always Allow**. Because the app isn't signed with a fixed certificate, this can come back after you rebuild.

### Updating

```bash
cd orbit
git pull
./build.sh install
```

Your data is kept between updates.

---

## Quick start

1. **Set up your week**: open **Weekly Schedule**, click a cell and type a class or a study block. Press **Enter** to save.
2. **Mark what to study**: choose **To-do** in the toolbar (or right-click a cell → Type → To-do). To-do cells appear in **Today** and **Tasks** on their day.
3. **Study**: in **Today**, press **Study** next to a to-do, then **Start** in the Timer. Press **Finish & Save** when you're done.
4. **Watch your progress** in **Reports**. Each week of study helps you level up in **My Galaxy**.
5. *(Optional)* Set up **Friends** to compare progress with your friends.

---

## User guide

### 📅 Weekly Schedule

![Weekly Schedule](docs/screenshots/schedule.png)

Your fixed week: days (Saturday → Friday) down the side, time slots across the top.

| What | How |
|---|---|
| Add or edit a cell | Click it and type. **Enter** saves, **Shift+Enter** adds a new line, **Esc** cancels. |
| Clear a cell | Delete all its text and press Enter, or right-click → **Clear Cell**. |
| Colour | Pick a swatch in the bottom toolbar. The sparkle swatch uses the template's colour. |
| **Type** | **Fixed** = classes, shifts, appointments (only shown in the grid). **To-do** = something to study (also listed in Today and Tasks). |
| **Category** | Toolbar → *Category*, or right-click a cell. The category is shown in the cell, used by filters, and saved with timer sessions. |
| **Repeat** | Toolbar → *Repeat*, or right-click: **Every week**, **Even weeks**, **Odd weeks** or **This week only**. A small EVEN / ODD / ONCE tag appears on the cell. |
| Other weeks | ◀ ▶ next to the week title. The **EVEN WEEK / ODD WEEK** badge shows the week's parity. Right-click it to swap even and odd if your school counts differently. |
| Text size | The slider in the toolbar (10–28 pt). |
| Tick off a to-do | Click the small circle in the corner of a To-do cell. |
| Study now | Right-click a To-do cell → **Study This Now**. |

The top-right card shows what's on **now** (with a progress bar) or what's **next** today. Change the time slots in **Settings**.

### ☀️ Today

![Today](docs/screenshots/today.png)

Your to-do list for today:
- **From your weekly schedule**: today's To-do cells, in time order.
- **Other tasks today**: one-off tasks. Type in the field and press Enter to add one.
- **Overdue**: unfinished tasks from earlier days, with **Move to Today**.
- **Today's sessions**: everything you've timed today.

Tick the circle to complete an item. Press **Study** to open it in the Timer, ready to start. The top cards show your study time against your daily goal, how many to-dos are done, and your total for the week.

### ✅ Tasks

![Tasks – week board](docs/screenshots/tasks-week.png)

Three views, switched at the top left:

- **Week**: one column per day, holding that day's schedule to-dos and tasks.
  - Click **+ Add** at the bottom of a day to add a task to it.
  - **Drag** a task to another day. Dragging a schedule to-do moves *only that day's session*: it becomes a task on the new day, and your weekly schedule doesn't change.
  - Undated tasks wait in the **No date** tray at the bottom. Drag them onto a day.
  - Right-click any card → **Move to** → any day of the week, the same day next week, or No Date.
  - Hover a card to show **✏️ Edit** and **▶ Study**.
- **Day**: one day in detail, with progress, that day's classes, schedule to-dos, tasks, and undated tasks you can **Move Here**.
- **List**: classic filters (Today, Upcoming, No Date, All Open, Done) and search.

Use ◀ **Today** ▶ to move between days or weeks, and **Category** (top right) to filter.

### ⏱ Timer

![Timer](docs/screenshots/timer.png)

1. Choose **Stopwatch** (counts up) or **Pomodoro** (25 min focus + 5 min break by default; change the lengths in Settings).
2. Pick what you're **Studying** from today's to-dos, or leave it on *Free study* and pick a category.
3. Add an optional note (for example, "chapter 3") and press **Start** (⌘↩).
4. **Pause**, **Resume**, then **Finish & Save**. The 🗑 button discards the session.

The running timer also shows in the **macOS menu bar**, so you can pause or finish it from any app. Forgot to time something? Use **Log Manually**. Sessions under 30 seconds aren't saved.

### 📆 Calendar

![Calendar](docs/screenshots/calendar.png)

A month view in the Persian or Gregorian calendar (the other calendar's dates are shown in each cell):
- Each day shows its to-dos and tasks (✓ / struck through when done), 📌 the number of fixed classes, done/total, and ⏱ the time studied.
- Fridays are in red, and today is highlighted.
- **Click** a day to see its classes, to-dos and study sessions on the right. **Double-click** a day (or press **Open in Tasks**) to plan it in Tasks.

### 📊 Reports

![Reports](docs/screenshots/reports.png)

Switch between **Weekly** and **Monthly** and step through periods with ◀ ▶:
- Total time studied, daily average, best day, to-dos completed, and the change compared with the previous period.
- A daily bar chart broken down by subject.
- Time by subject (a donut chart) and the items you spent the most time on.
- The tasks you completed in the period.

### 🌌 My Galaxy

![My Galaxy](docs/screenshots/galaxy.png)

Studying grows your own galaxy.

**Levels.** Everyone starts at **level 1**. When a week (Saturday → Friday) ends:
- **10+ hours** of study → **+1 level**
- **20+ hours** → **+2 levels**

The card at the top shows this week's progress towards the next level. The maximum level is 50.

**Planets.** You get **one new planet per level**. The 50 planets come in 10 groups of 5, and a new group unlocks every 5 levels (levels 1, 6, 11, 16 … 46).

![All 50 planets](docs/planets.png)

**Adding planets.** Scroll down to **Planet Collection**, click an unlocked planet, choose which solar system to add it to (**Add to**) and press **Add Planet**. Other buttons:
- **Use as Profile Picture**: your friends see this planet next to your name.
- **Remove One**: takes the planet back out of your galaxy, and you get its credit back.

**Solar systems.** Each solar system holds up to **8 planets**. Press **New Solar System** and choose its star: Yellow Sun, Red Giant, Blue Star, White Dwarf, Twin Stars or Pulsar. Stars unlock as you level up.

**The galaxy map.** Drag to move around, use the zoom slider, and **click a solar system to fly in**. Inside a system, **Customize** lets you rename it or change its star.

![A solar system up close](docs/screenshots/solar-system.png)

### 👥 Friends

![Friends](docs/screenshots/friends.png)

*(Needs a Supabase project, see [Setting up Friends](#setting-up-friends-supabase).)*

1. Type your name and press **Create My Profile**. No email or password is needed.
2. You get a **6-character friend code**. Press **Copy** and send it to a friend.
3. Type a friend's code under **Add a friend** and press **Add**. You both see each other right away.

What you'll see:
- **Studying right now**: friends whose timer is running, what they're studying, and for how long.
- **This week's leaderboard**: ranking by study time, with level, profile planet, 🔥 day streak and a green dot when someone is studying. **Click a row** to open the full breakdown: every subject studied this week (time and share), today's subjects, a day-by-day row, and a **Galaxy** button to explore their solar systems.
- **Friend cards**: today, this week, to-dos done, a 7-day chart and top subjects.

The ⋯ menu lets you change your name or **Delete My Profile** (this removes your shared data from the server). Right-click a friend card to remove a friend.

### ⚙️ Settings

![Settings](docs/screenshots/settings.png)

- **Appearance**: Light, Dark or System.
- **Template**: 8 designs (Aurora, Frosted Glass, Pastel, Neon, Paper, Sunset, Forest, Classic Grid). Each changes the weekly schedule's style and the app's accent colour.
- **Font**: SF Pro / Rounded / Serif / Mono change the whole app. Avenir Next, Futura, Helvetica Neue, Gill Sans, Optima, Georgia, Baskerville, American Typewriter and Chalkboard style the weekly schedule. Also sets the cell text size.
- **Calendar**: Persian or Gregorian as the primary calendar.
- **Weekly schedule time slots**: edit, add or delete columns, or reset to the defaults.
- **Timer & goal**: Pomodoro focus and break lengths, and your daily study goal.
- **Task categories**: names and colours.
- **Data**: where your data file lives, with **Show in Finder**.

---

## Setting up Friends (Supabase)

The Friends feature needs a free [Supabase](https://supabase.com) project, which acts as the online database. Without one, everything else works normally and the Friends page explains what to do.

1. Create a free account and a new project at [supabase.com](https://supabase.com). Choose a region close to you and keep the database password somewhere safe.
2. In the project, open **SQL Editor** → **New query**, paste the whole of [`supabase/schema.sql`](supabase/schema.sql) and press **Run**. This creates the tables, the friend-code functions and the security rules.
3. Open **Authentication → Sign In / Providers**, turn on **Allow anonymous sign-ins** and press **Save**.
4. Open **Project Settings → API Keys** and copy the **Project URL** and the **Publishable key** (it starts with `sb_publishable_`).
5. In the `orbit` folder:
   ```bash
   cp Resources/Supabase.example.plist Resources/Supabase.plist
   ```
   Open `Resources/Supabase.plist` and replace the placeholder `URL` and `PublishableKey` values with yours.
6. Rebuild: `./build.sh install`.

To use Friends together, everyone has to run a build that points to **the same** Supabase project. The app on the [Releases page](https://github.com/amirr-kdm/orbit/releases) is connected to the shared Orbit server. If you build from source with your own project, share your build (`./build.sh release`) with your friends.

> ⚠️ Only ever use the **publishable** key. Never put the **secret / service_role** key in the app or in the repository.
>
> `Resources/Supabase.plist` is git-ignored, so your project details never end up on GitHub.

**How it's secured:** the publishable key is designed to be public. Postgres **Row Level Security** lets each user read only their own data and their friends' data, and write only their own. Friendships are created through a server function that takes a friend code.

> **Note:** a free Supabase project is paused after a week without any activity. Open the Supabase dashboard and press *Restore* if that happens. No data is lost.

---

## Your data & privacy

- Everything you create (schedule, tasks, sessions, galaxy, settings) is stored **locally** in
  `~/Library/Application Support/Orbit/data.json`.
  It's plain JSON. To back it up, copy the file. **Settings → Data → Show in Finder** opens its folder.
- With Friends turned on, only **daily summaries** are uploaded: minutes studied, subjects with their time, to-dos done/total, what you're studying right now, your level, profile planet and galaxy layout. Your schedule, tasks and notes are **never** uploaded.
- **Delete My Profile** (Friends → ⋯) removes everything you shared from the server.

---

## For developers

Pure **SwiftUI + Swift Charts + Foundation**, with no third-party dependencies. It's built with Swift Package Manager and packaged into an `.app` by `build.sh`.

```
Sources/ClaudeSchedule/
├── ClaudeScheduleApp.swift     App entry, menu bar timer
├── Models.swift                Tasks, schedule entries, sessions, settings
├── Store.swift                 Local JSON storage and app logic
├── TimerEngine.swift           Stopwatch / Pomodoro
├── DateHelpers.swift           Persian & Gregorian calendars, formatting
├── Theme.swift                 Appearance, fonts, design templates
├── SupabaseConfig.swift        Reads Supabase.plist from the app bundle
├── Friends/                    Minimal Supabase client (REST + anonymous auth) and sync
├── Galaxy/                     Planet catalogue + renderer, levels, solar systems
└── Views/                      Today, Weekly Schedule, Tasks, Timer, Calendar,
                                Reports, Galaxy, Friends, Settings
supabase/schema.sql             Database schema and Row Level Security rules
scripts/make_icon.swift         Generates the app icon from Resources/icon-source.jpeg
build.sh                        Builds and packages Orbit.app
```

Developer environment variables:

| Variable | Effect |
|---|---|
| `CS_DATA_DIR=/path` | Use a separate data folder (and a separate Friends sign-in) |
| `CS_START_TAB=galaxy` | Open on a screen: `today`, `schedule`, `timer`, `tasks`, `calendar`, `reports`, `galaxy`, `friends`, `settings` |
| `CS_RENDER_PLANETS=/path.png` | Render all 50 planets to an image and quit |
| `CS_RENDER_SYSTEM=/path.png` | Render a sample solar system to an image and quit |

Example: `CS_DATA_DIR=/tmp/orbit-test build/Orbit.app/Contents/MacOS/Orbit`

---

## Roadmap

- Notifications for Pomodoro end and schedule slots
- Repeating one-off tasks and sub-task checklists
- Iranian public holidays in the calendar
- Instant level-ups with a celebration animation
- Export reports to PDF / CSV
- A Windows / web version that shares the same Supabase backend

## License

[MIT](LICENSE) © 2026 amirr-kdm
