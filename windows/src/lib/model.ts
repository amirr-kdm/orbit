// Data model — mirrors the Mac app so both share the same Friends server format.

export type Priority = 0 | 1 | 2;
export type EntryKind = "fixed" | "todo";
export type Recurrence = "weekly" | "even" | "odd" | "once";
export type SunType = "yellow" | "red" | "blue" | "white" | "binary" | "pulsar";
export type Appearance = "system" | "light" | "dark";

export interface Category { id: string; name: string; colorHex: string }

export interface TaskItem {
  id: string;
  title: string;
  notes: string;
  categoryID?: string;
  priority: Priority;
  dueDate?: string; // ISO
  hasTime: boolean;
  estimatedMinutes: number;
  isDone: boolean;
  /** Given up: won't be done */
  isSkipped?: boolean;
  createdAt: string;
  completedAt?: string;
}

export interface TimeSlot { id: string; startMinute: number; endMinute: number }

export interface ScheduleEntry {
  id: string;
  weekday: number; // 0 = Saturday
  slotID: string;
  text: string;
  colorHex?: string;
  kind: EntryKind;
  categoryID?: string;
  recurrence: Recurrence;
  weekStart?: string; // ISO, for "once"
  /** Free notes (edited in the Tasks graph) */
  notes?: string;
}

/** A store planet bought with rockets */
export interface Purchase { id: string; planetID: string; price: number; date: string }

export interface StudySession {
  id: string;
  categoryID?: string;
  taskID?: string;
  scheduleEntryID?: string;
  subject: string;
  colorHex: string;
  start: string; // ISO
  duration: number; // seconds
  note: string;
}

export interface PlacedPlanet { id: string; planetID: string; addedAt: string; systemID?: string }
export interface SolarSystem { id: string; name: string; sun: SunType }

export interface Settings {
  primaryCalendar: "persian" | "gregorian";
  pomodoroMinutes: number;
  breakMinutes: number;
  dailyGoalMinutes: number;
  timeSlots: TimeSlot[];
  appearance: Appearance;
  accent: string;
  /** ISO start of a week that counts as "even" */
  evenWeekAnchor: string;
  /** Colours offered for schedule and planner cells (add your own, delete any) */
  cellPalette: string[];
}

/** A rich-text note inside a planner (HTML) */
export interface PlannerNote { id: string; title: string; html: string; updatedAt: string }

/** A draft week with brainstorm notes that can be copied into the weekly schedule */
export interface Planner {
  id: string;
  name: string;
  createdAt: string;
  /** To-do cells of the planned week (same weekday / slot layout as the schedule) */
  entries: ScheduleEntry[];
  notes: PlannerNote[];
  /** The folder it's filed in (missing = not in a folder) */
  folderID?: string;
}

/** A folder in the Notes & Brainstorm sidebar (same shape as the Mac app) */
export interface PlannerFolder { id: string; name: string; expanded: boolean }

export interface AppData {
  tasks: TaskItem[];
  categories: Category[];
  sessions: StudySession[];
  settings: Settings;
  schedule: ScheduleEntry[];
  scheduleDone: string[];
  scheduleMoved: string[];
  galaxy: PlacedPlanet[];
  avatarPlanet?: string;
  solarSystems: SolarSystem[];
  planners: Planner[];
  /** Schedule to-dos given up on a day, keyed "entryID|yyyy-MM-dd" */
  scheduleSkipped: string[];
  purchases: Purchase[];
  refundsUsed: number;
  /** Extra rockets given outside of studying */
  rocketGrant: number;
  /** Weeks you studied the most in a group, keyed "groupID|yyyy-MM-dd" */
  groupWins: string[];
  /** Rocket gifts from the owner already added to rocketGrant (gift ids) */
  claimedGifts?: string[];
  plannerFolders?: PlannerFolder[];
}

export const uid = () =>
  (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2) + Date.now().toString(36)).toUpperCase();

export const defaultSlots = (): TimeSlot[] =>
  Array.from({ length: 9 }, (_, i) => ({ id: uid(), startMinute: 360 + i * 120, endMinute: 450 + i * 120 }));

export const SYSTEM_NAMES = ["Home System", "Nova Reach", "Amber Drift", "Cobalt Veil", "Starfall", "Moonwake",
  "Echo Nebula", "Solace", "Crimson Arc", "Halcyon", "Lumen Gate", "Zephyr Belt"];

export function defaultData(): AppData {
  // The week of Oct 17–23, 2026 counts as "even" (same as the Mac app)
  const anchor = new Date(2026, 9, 17).toISOString();
  return {
    tasks: [],
    categories: [
      { id: uid(), name: "Study", colorHex: "#4F7CF7" },
      { id: uid(), name: "Work", colorHex: "#F28C38" },
      { id: uid(), name: "Reading", colorHex: "#2BB673" },
      { id: uid(), name: "Exercise", colorHex: "#E5484D" },
      { id: uid(), name: "Personal", colorHex: "#9B6BDF" },
    ],
    sessions: [],
    settings: {
      primaryCalendar: "persian",
      pomodoroMinutes: 25,
      breakMinutes: 5,
      dailyGoalMinutes: 240,
      timeSlots: defaultSlots(),
      appearance: "system",
      accent: "#5B7CFA",
      evenWeekAnchor: anchor,
      cellPalette: [...PALETTE],
    },
    schedule: [],
    scheduleDone: [],
    scheduleMoved: [],
    galaxy: [],
    solarSystems: [{ id: uid(), name: SYSTEM_NAMES[0], sun: "yellow" }],
    planners: [],
    scheduleSkipped: [],
    purchases: [],
    refundsUsed: 0,
    rocketGrant: 0,
    groupWins: [],
  };
}

export const PALETTE = ["#FFFFFF", "#FF6B6B", "#FFA94D", "#FFD43B", "#69DB7C", "#4DABF7", "#7C6CF2", "#F783AC", "#94A3B8"];

export function isLight(hex: string): boolean {
  const v = parseInt(hex.replace("#", ""), 16);
  const r = ((v >> 16) & 255) / 255, g = ((v >> 8) & 255) / 255, b = (v & 255) / 255;
  return 0.299 * r + 0.587 * g + 0.114 * b > 0.62;
}

export const RECURRENCE_TITLE: Record<Recurrence, string> = {
  weekly: "Every week", even: "Even weeks", odd: "Odd weeks", once: "This week only",
};
export const RECURRENCE_BADGE: Record<Recurrence, string | undefined> = {
  weekly: undefined, even: "EVEN", odd: "ODD", once: "ONCE",
};
const PRIORITY: Record<Recurrence, number> = { weekly: 0, even: 1, odd: 1, once: 2 };
export const recurrencePriority = (r: Recurrence) => PRIORITY[r];
