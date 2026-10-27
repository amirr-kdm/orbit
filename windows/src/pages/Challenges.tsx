import { useEffect, useState } from "react";
import { Avatar, LevelBadge, Modal } from "../components";
import { Challenge, ChallengeMember, hm, isLive, RULES, typeOf, useChallenges } from "../lib/challenges";
import { FriendCard, studyingNow, useFriends } from "../lib/friends";
import { dayKey } from "../lib/dates";
import { subjectOf, useStore, wallet } from "../lib/store";
import { RocketIcon } from "./Store";
import { OrbiterProfile } from "./Orbiters";

const rel = (d: Date) => {
  const m = Math.round((d.getTime() - Date.now()) / 60000), a = Math.abs(m);
  const t = a < 60 ? `${a}m` : a < 1440 ? `${Math.round(a / 60)}h` : `${Math.round(a / 1440)}d`;
  return m >= 0 ? `in ${t}` : `${t} ago`;
};
const when = (s: string) => new Date(s).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

const TYPE_INFO = { public: ["🌍", "Public", "#3B82F6"], private: ["🔒", "Private", "#A855F7"], group: ["👥", "Group", "#22C55E"] } as const;
const TypePill = ({ c }: { c: Challenge }) => { const [i, n, col] = TYPE_INFO[typeOf(c)]; return <span className="small" style={{ color: col, background: col + "26", padding: "2px 8px", borderRadius: 99, fontWeight: 700 }}>{i} {n}</span>; };

/** Every challenge you can see: public ones, private ones you joined with a code, and your groups' — join any time until it ends */
export default function ChallengesPage() {
  const ch = useChallenges();
  const f = useFriends();
  const [creating, setCreating] = useState(false);
  const [showing, setShowing] = useState<string | null>(null);
  const [detail, setDetail] = useState<string | null>(null);
  const [filter, setFilter] = useState<"all" | "mine" | "public" | "private" | "group">("all");
  const [code, setCode] = useState("");
  const [, tick] = useState(0);
  useEffect(() => { const t = setInterval(() => tick((n) => n + 1), 30_000); return () => clearInterval(t); }, []);
  // a notification can open one directly
  useEffect(() => {
    const open = () => { const id = sessionStorage.getItem("orbit-open-challenge"); if (id) { setDetail(id); sessionStorage.removeItem("orbit-open-challenge"); } };
    open(); window.addEventListener("orbit-open-challenge", open); return () => window.removeEventListener("orbit-open-challenge", open);
  }, []);
  const now = Date.now();
  const me = f.me?.id;
  const all = ch.list.filter((c) => c.kind !== "promise")
    .filter((c) => filter === "all" ? true : filter === "mine" ? (ch.members[c.id] ?? []).some((m) => m.user_id === me) : typeOf(c) === filter);
  const started = (c: Challenge) => now >= new Date(c.starts_at).getTime(), ended = (c: Challenge) => now >= new Date(c.ends_at).getTime();
  const upcoming = all.filter((c) => c.status === "open" && !started(c));
  const live = all.filter((c) => c.status === "open" && started(c) && !ended(c));
  const done = all.filter((c) => c.status !== "open" || ended(c));
  const rule = (icon: string, text: string) => <span className="small" style={{ padding: "3px 8px", borderRadius: 99, background: "color-mix(in srgb, var(--text) 7%, transparent)" }}>{icon} {text}</span>;
  const section = (title: string, icon: string, tint: string, list: Challenge[]) => list.length > 0 && (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <b style={{ color: tint }}>{icon} {title} · {list.length}</b>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(380px, 1fr))", gap: 14, alignItems: "start" }}>
        {list.map((c) => <ChallengeCard key={c.id} c={c} onOpen={setDetail} />)}
      </div>
    </div>
  );
  const joinCode = async () => { const id = await ch.joinByCode(code); if (id) { setCode(""); setDetail(id); } };
  const dc = detail ? ch.list.find((c) => c.id === detail) : undefined;
  return (
    <div className="page">
      <div className="row" style={{ alignItems: "flex-start", gap: 16 }}>
        <div style={{ width: 56, height: 56, borderRadius: 16, display: "grid", placeItems: "center", fontSize: 26, background: "linear-gradient(135deg, #F97316, #EC4899)", flexShrink: 0 }}>🏁</div>
        <div style={{ flex: 1 }}>
          <h1 style={{ margin: 0 }}>Challenges</h1>
          <div className="muted">Study together for rockets. Join any time until it ends — study counts from the moment you join.</div>
          <div className="row" style={{ gap: 6, flexWrap: "wrap", marginTop: 6 }}>
            {rule("🕐", `at least ${RULES.minHours}h of study`)}{rule("👥", `${RULES.minPeople}+ people, or everyone is refunded`)}
            {rule("🎁", "all finish → fee back + bonus up to 100 🚀/h")}{rule("⇄", "some miss → their fees go to those who finished")}
          </div>
        </div>
        <button className="btn primary" onClick={() => { ch.setError(null); setCreating(true); }}>＋ New Challenge</button>
      </div>
      <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
        <div className="seg">{(["all", "mine", "public", "private", "group"] as const).map((k) => <button key={k} className={filter === k ? "on" : ""} onClick={() => setFilter(k)}>{k === "all" ? "All" : k === "mine" ? "Joined" : TYPE_INFO[k][1]}</button>)}</div>
        <span className="spacer" />
        <input placeholder="🔑 Invite code" value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && code.trim()) joinCode(); }} style={{ width: 150, fontFamily: "monospace" }} />
        <button className="btn" disabled={code.trim().length < 4 || ch.busy} onClick={joinCode}>Join</button>
      </div>
      {!all.length && <div className="card muted">No challenges here yet — start one with New Challenge.</div>}
      {section("Running now", "🔥", "#F97316", live)}
      {section("Starting soon", "📅", "#3B82F6", upcoming)}
      {section("Finished", "✅", "#22C55E", done)}
      {ch.error && <div className="small" style={{ color: "#ef4444" }}>{ch.error}</div>}
      {creating && <NewChallenge onClose={() => setCreating(false)} onCreated={setDetail} />}
      {dc && <ChallengeDetail c={dc} onClose={() => setDetail(null)} onProfile={setShowing} />}
      {showing && <OrbiterProfile userID={showing} onClose={() => setShowing(null)} />}
    </div>
  );
}

/** What someone studied inside the challenge window: mine from my sessions, others' from their shared daily stats */
function useStudied() {
  const { data } = useStore();
  const f = useFriends();
  return (m: ChallengeMember, c: Challenge, me?: string) => {
    const from = Math.max(new Date(c.starts_at).getTime(), m.joined_at ? new Date(m.joined_at).getTime() : 0), to = Math.min(Date.now(), new Date(c.ends_at).getTime());
    if (to <= from) return [];
    const tot = new Map<string, { name: string; color: string; minutes: number }>();
    if (m.user_id === me) {
      for (const s of data.sessions) {
        const t = new Date(s.start).getTime();
        if (s.isManual || t < from || t > to) continue;
        const sub = subjectOf(data, s), cur = tot.get(sub.name) ?? { ...sub, minutes: 0 };
        cur.minutes += Math.round(s.duration / 60); tot.set(sub.name, cur);
      }
    } else {
      const card = f.people[m.user_id];
      if (card) for (let t = new Date(new Date(from).setHours(0, 0, 0, 0)); t.getTime() <= to; t.setDate(t.getDate() + 1)) {
        for (const x of card.stats[dayKey(t)]?.subjects ?? []) { const cur = tot.get(x.name) ?? { ...x, minutes: 0 }; cur.minutes += x.minutes; tot.set(x.name, cur); }
      }
    }
    return [...tot.values()].filter((x) => x.minutes > 0).sort((a, b) => b.minutes - a.minutes);
  };
}

/** The challenge page: facts, your actions, and what each participant studied or is studying */
function ChallengeDetail({ c, onClose, onProfile }: { c: Challenge; onClose: () => void; onProfile: (id: string) => void }) {
  const ch = useChallenges();
  const f = useFriends();
  const studied = useStudied();
  const me = f.me?.id;
  const now = Date.now(), start = new Date(c.starts_at).getTime(), end = new Date(c.ends_at).getTime();
  const people = [...(ch.members[c.id] ?? [])].sort((a, b) => b.minutes - a.minutes);
  const mine = people.some((m) => m.user_id === me);
  const myGroup = !!c.group_id && f.groups.some((g) => g.id === c.group_id);
  const canJoin = c.status === "open" && now < end && !mine && (typeOf(c) === "public" || (typeOf(c) === "group" && myGroup));
  const groupName = c.group_id ? f.groups.find((g) => g.id === c.group_id)?.name ?? "A study group" : null;
  const name = (id: string) => (id === me ? "You" : f.people[id]?.profile.name ?? ch.people[id]?.name ?? ch.names[id] ?? "Member");
  const [label, color] = c.status === "cancelled" ? ["Cancelled", "#94A3B8"] : c.status === "settled" ? ["Finished", "#22C55E"]
    : now < start ? [`Starts ${rel(new Date(start))}`, "#3B82F6"] : now < end ? [`Live · ends ${rel(new Date(end))}`, "#F97316"] : ["Paying out soon", "#A855F7"];
  const tile = (icon: string, v: string, l: string) => <div className="card" style={{ flex: 1, minWidth: 90, textAlign: "center", padding: 10 }}><b>{icon} {v}</b><div className="small muted">{l}</div></div>;
  return (
    <Modal onClose={onClose} width={640}>
      <div className="row" style={{ alignItems: "flex-start" }}>
        <div style={{ flex: 1 }}><h2 style={{ margin: 0 }}>{c.title}</h2>
          <div className="row small muted" style={{ gap: 8, marginTop: 4 }}><TypePill c={c} />{groupName && <span>👥 {groupName}</span>}<span>{when(c.starts_at)} → {when(c.ends_at)}</span></div></div>
        <span className="small" style={{ color, background: color + "26", padding: "3px 10px", borderRadius: 99, fontWeight: 700 }}>{label}</span>
      </div>
      <div className="row" style={{ gap: 8, margin: "12px 0", flexWrap: "wrap" }}>
        {tile("🕐", hm(c.target_minutes), "goal")}{tile("🎟", `${c.fee} 🚀`, "entry")}{tile("🎁", `+${RULES.bonus(c.fee, c.target_minutes)} 🚀`, "if all finish")}{tile("👥", String(people.length), "joined")}
      </div>
      {typeOf(c) === "private" && c.invite_code && mine && (
        <div className="card row" style={{ background: "rgba(168,85,247,.12)" }}>🔑 Invite code <b style={{ fontFamily: "monospace", letterSpacing: 3, fontSize: 18 }}>{c.invite_code}</b>
          <span className="spacer" /><button className="btn small" onClick={() => navigator.clipboard.writeText(c.invite_code!)}>Copy</button></div>
      )}
      <div className="row" style={{ margin: "8px 0" }}>
        {canJoin && <button className="btn primary" disabled={ch.busy} onClick={() => ch.join(c)}>Join for {c.fee} 🚀</button>}
        {mine && now < start && c.creator !== me && c.status === "open" && <button className="btn" disabled={ch.busy} onClick={() => ch.leave(c)}>Leave (refund)</button>}
        {mine && <span className="small" style={{ color: "#22C55E" }}>✓ You're in</span>}
        <span className="spacer" />
        {c.creator === me && c.status === "open" && <button className="btn small danger" disabled={ch.busy} onClick={() => confirm(`Cancel “${c.title}”? Everyone gets their entry fee back.`) && ch.cancel(c)}>Cancel…</button>}
      </div>
      {ch.error && <div className="small" style={{ color: "#ef4444" }}>{ch.error}</div>}
      <h3>Participants</h3>
      <div style={{ maxHeight: 340, overflowY: "auto" }}>
        {people.map((m, i) => {
          const isMe = m.user_id === me, sees = isMe || !!f.people[m.user_id];
          const subs = studied(m, c, me), liveNow = isMe ? undefined : f.people[m.user_id] ? studyingNow(f.people[m.user_id]) : undefined;
          const lv = ch.people[m.user_id]?.level ?? f.people[m.user_id]?.profile.level;
          const done = m.minutes >= c.target_minutes;
          return (
            <div key={m.user_id} className="list-row" style={{ alignItems: "flex-start" }}>
              <span style={{ width: 28, textAlign: "center", fontSize: i < 3 ? 20 : 14 }}>{i < 3 ? ["🥇", "🥈", "🥉"][i] : i + 1}</span>
              <span style={{ cursor: isMe ? undefined : "pointer" }} onClick={() => !isMe && onProfile(m.user_id)}><Avatar name={name(m.user_id)} planet={f.people[m.user_id]?.profile.avatar ?? ch.people[m.user_id]?.avatar} size={38} color={isMe ? "var(--accent)" : undefined} /></span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="row"><b>{name(m.user_id)}</b>{lv ? <LevelBadge level={lv} /> : null}{m.user_id === c.creator && <span className="small muted">creator</span>}
                  {liveNow && <span className="small" style={{ color: "#22C55E" }}>● Studying {liveNow} now</span>}<span className="spacer" />
                  <b style={{ color: done ? "#22C55E" : undefined }}>{hm(m.minutes)} / {hm(c.target_minutes)}{done ? " ✓" : ""}</b></div>
                <div className="progress" style={{ margin: "4px 0" }}><div style={{ width: `${Math.min(100, (m.minutes / Math.max(1, c.target_minutes)) * 100)}%`, background: done ? "#22C55E" : undefined }} /></div>
                {sees ? <div className="row" style={{ gap: 5, flexWrap: "wrap" }}>
                  {subs.map((x) => <span key={x.name} className="small" style={{ padding: "1px 8px", borderRadius: 99, background: x.color + "33" }}><span style={{ color: x.color }}>●</span> {x.name} {hm(x.minutes)}</span>)}
                  {!subs.length && <span className="small muted">Nothing yet</span>}</div>
                  : <div className="small muted">Hours only — add as a friend to see what they study.</div>}
              </div>
            </div>
          );
        })}
      </div>
    </Modal>
  );
}

/** One challenge: who, how far, and what you can do */
function ChallengeCard({ c, onOpen }: { c: Challenge; onOpen: (id: string) => void }) {
  const profile = (id: string) => onOpen(id);
  const ch = useChallenges();
  const f = useFriends();
  const me = f.me?.id;
  const now = Date.now(), start = new Date(c.starts_at).getTime(), end = new Date(c.ends_at).getTime();
  const people = [...(ch.members[c.id] ?? [])].sort((a, b) => b.minutes - a.minutes);
  const mine = people.some((m) => m.user_id === me);
  const group = c.group_id ? f.groups.find((g) => g.id === c.group_id)?.name ?? "A study group" : typeOf(c) === "private" ? "Private · invite code" : "Open to all Orbit members";
  const [label, color] = c.status === "cancelled" ? ["Cancelled", "#94A3B8"] : c.status === "settled" ? ["Finished", "#22C55E"]
    : now < start ? [`Starts ${rel(new Date(start))}`, "#3B82F6"] : now < end ? [`Live · ends ${rel(new Date(end))}`, "#F97316"] : ["Paying out soon", "#A855F7"];
  const fact = (icon: string, value: string, label: string) => <div><b>{icon} {value}</b><div className="small muted">{label}</div></div>;
  return (
    <div className="card" style={{ padding: 16, display: "flex", flexDirection: "column", gap: 10, borderColor: color + "40", cursor: "pointer" }} onClick={() => profile(c.id)}>
      <div className="row" style={{ alignItems: "flex-start" }}>
        <div style={{ flex: 1, minWidth: 0 }}><b>{c.title}</b><div className="small muted">{TYPE_INFO[typeOf(c)][0]} {group}</div></div>
        <span className="small" style={{ color, background: color + "26", padding: "2px 8px", borderRadius: 99, fontWeight: 600, whiteSpace: "nowrap" }}>{label}</span>
      </div>
      <div className="row" style={{ gap: 14, flexWrap: "wrap" }}>
        {fact("🕐", hm(c.target_minutes), "goal")}{fact("📅", `${Math.round((end - start) / 3600_000)}h`, "window")}
        {fact("🎟", `${c.fee} 🚀`, "entry")}{fact("🎁", `+${RULES.bonus(c.fee, c.target_minutes)} 🚀`, "if all finish")}
      </div>
      <div className="small muted">{when(c.starts_at)} → {when(c.ends_at)}</div>
      {people.length < RULES.minPeople && c.status === "open" && <div className="small" style={{ color: "#F97316" }}>⏳ Needs at least {RULES.minPeople} people — otherwise everyone is refunded</div>}
      <div className="row small muted"><AvatarsRow ids={people.map((m) => m.user_id)} /> {people.length} joined{mine ? " · ✓ you're in" : ""}</div>
      {c.status === "open" && now < end && !mine && typeOf(c) !== "private" && <div className="row"><button className="btn small primary" disabled={ch.busy} onClick={(e) => { e.stopPropagation(); ch.join(c); }}>Join for {c.fee} 🚀</button></div>}
    </div>
  );
}

function AvatarsRow({ ids }: { ids: string[] }) {
  const f = useFriends();
  const ch = useChallenges();
  return <span style={{ display: "inline-flex" }}>{ids.slice(0, 5).map((id, i) => <span key={id} style={{ marginLeft: i ? -8 : 0 }}><Avatar name={f.people[id]?.profile.name ?? ch.people[id]?.name ?? "?"} planet={f.people[id]?.profile.avatar ?? ch.people[id]?.avatar} size={24} /></span>)}</span>;
}

export function NewChallenge({ onClose, onCreated, presetGroup }: { onClose: () => void; onCreated?: (id: string) => void; presetGroup?: string }) {
  const ch = useChallenges();
  const f = useFriends();
  const [type, setType] = useState<"public" | "private" | "group">(presetGroup ? "group" : "public");
  const [group, setGroup] = useState<string>(presetGroup ?? f.groups[0]?.id ?? "");
  const { data } = useStore();
  const [title, setTitle] = useState("");
  const [hours, setHoursRaw] = useState(RULES.minHours);
  const [length, setLength] = useState(24);
  const [fee, setFee] = useState(RULES.minFee(RULES.minHours));
  const [mode, setMode] = useState(0);
  const [at, setAt] = useState(() => { const d = new Date(Date.now() + 3600_000), p = (n: number) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; });
  const setHours = (h: number) => { const v = Math.min(168, Math.max(RULES.minHours, Math.round(h) || RULES.minHours)); setHoursRaw(v); setFee((x) => Math.max(x, RULES.minFee(v))); setLength((l) => Math.max(l, v)); };
  const start = () => (mode === 0 ? new Date() : mode === 1 ? new Date(Date.now() + 3600_000) : new Date(at));
  const minFee = RULES.minFee(hours), have = wallet(data).balance;
  return (
    <Modal onClose={onClose} width={520}>
      <h3 style={{ marginTop: 0 }}>🏁 New challenge</h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <div className="seg" style={{ alignSelf: "flex-start" }}>{(["public", "private", "group"] as const).map((k) => <button key={k} disabled={k === "group" && !f.groups.length} className={type === k ? "on" : ""} onClick={() => setType(k)}>{TYPE_INFO[k][0]} {TYPE_INFO[k][1]}</button>)}</div>
        <div className="small muted">{type === "public" ? "Every Orbit member can see and join it." : type === "private" ? "Hidden: only people with the invite code can join." : "Only members of the group you pick."}</div>
        {type === "group" && <select value={group} onChange={(e) => setGroup(e.target.value)}>{f.groups.map((g) => <option key={g.id} value={g.id}>👥 {g.name}</option>)}</select>}
        <input placeholder="Name, e.g. Weekend sprint" value={title} onChange={(e) => setTitle(e.target.value)} />
        <div className="row">Study <input type="number" min={RULES.minHours} max={168} step={1} value={hours} onChange={(e) => setHours(+e.target.value)} style={{ width: 70 }} /> hours
          within <input type="number" min={Math.max(RULES.minHours, hours)} max={336} value={length} onChange={(e) => setLength(Math.min(336, Math.max(hours, Math.round(+e.target.value) || hours)))} style={{ width: 70 }} /> hours</div>
        <div className="seg" style={{ alignSelf: "flex-start" }}>{["Now", "In 1 hour", "At…"].map((t, i) => <button key={t} className={mode === i ? "on" : ""} onClick={() => setMode(i)}>{t}</button>)}</div>
        {mode === 2 && <input type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} />}
        <div className="row">Entry fee <input type="number" min={minFee} value={fee} onChange={(e) => setFee(Math.round(+e.target.value) || 0)} style={{ width: 90 }} /> <RocketIcon size={16} />
          <span className="small muted">· at least {minFee} · you have {have}</span></div>
        <div className="small muted" style={{ display: "flex", flexDirection: "column", gap: 3 }}>
          <span>• At least {RULES.minHours} hours, and the fee is at least 50 🚀 per hour ({hours}h → {minFee} 🚀).</span>
          <span>• Needs at least {RULES.minPeople} people by the end — otherwise everyone just gets their fee back.</span>
          <span>• Everyone finishes → fee back + {RULES.bonus(fee, hours * 60)} 🚀 bonus each (at most 100 🚀 per hour).</span>
          <span>• Some miss → their fees are shared by those who finished.</span>
          <span>• Others can join any time until it ends (study counts from when they join). Only you can cancel it — everyone is refunded.</span>
        </div>
        {fee < minFee && <div className="small" style={{ color: "#F97316" }}>The entry fee must be at least {minFee} 🚀 for {hours} hours.</div>}
        {fee > have && <div className="small" style={{ color: "#F97316" }}>You don't have enough rockets.</div>}
        {ch.error && <div className="small" style={{ color: "#ef4444" }}>{ch.error}</div>}
        <div className="row"><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={ch.busy || fee < minFee || fee > have || hours > length}
            onClick={async () => { const s = start(); const id = await ch.create(title.trim() || "Challenge", hours * 60, fee, s, new Date(s.getTime() + length * 3600_000), type, type === "group" ? group : undefined); if (id) { onClose(); onCreated?.(id); } }}>
            Create & pay {fee} 🚀</button></div>
      </div>
    </Modal>
  );
}

/** My promises and the ones made to me */
export function Promises() {
  const ch = useChallenges();
  const f = useFriends();
  const me = f.me?.id;
  const list = ch.list.filter((c) => c.kind === "promise");
  if (!list.length) return null;
  return (
    <div className="card">
      <h3>🤞 Promises</h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {list.map((c) => {
          const mine = c.creator === me;
          const other = f.people[mine ? c.friend ?? c.creator : c.creator]?.profile.name ?? "a friend";
          const done = ch.members[c.id]?.[0]?.minutes ?? 0;
          return (
            <div key={c.id} style={{ padding: 10, borderRadius: 10, background: "color-mix(in srgb, var(--text) 5%, transparent)" }}>
              <div className="row"><b>{mine ? `You promised ${other}` : `${other} promised you`}</b><span className="spacer" />
                <span className="small muted">{c.status === "settled" ? (done >= c.target_minutes ? "Kept ✅" : "Missed ❌") : c.status === "cancelled" ? "Cancelled" : `Due ${rel(new Date(c.ends_at))}`}</span></div>
              <div className="row small" style={{ marginTop: 6 }}><div className="progress" style={{ flex: 1 }}><div style={{ width: `${Math.min(100, (done / c.target_minutes) * 100)}%` }} /></div>
                <span className="muted">{hm(done)} / {hm(c.target_minutes)} · {c.fee} 🚀 at stake</span></div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function PromiseModal({ friend, onClose }: { friend: FriendCard; onClose: () => void }) {
  const ch = useChallenges();
  const { data } = useStore();
  const [hours, setHours] = useState(4);
  const [stake, setStake] = useState(50);
  const tonight = new Date(); tonight.setHours(23, 59, 0, 0);
  const [by, setBy] = useState(() => { const d = tonight; const p = (n: number) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T23:59`; });
  useEffect(() => ch.setError(null), []); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <Modal onClose={onClose} width={440}>
      <h3 style={{ marginTop: 0 }}>🤞 Make a promise to {friend.profile.name}</h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <div className="row">I'll study <input type="number" min={0.5} max={24} step={0.5} value={hours} onChange={(e) => setHours(+e.target.value)} style={{ width: 70 }} /> h</div>
        <div className="row">By <input type="datetime-local" value={by} onChange={(e) => setBy(e.target.value)} /></div>
        <div className="row">Stake <input type="number" min={1} value={stake} onChange={(e) => setStake(+e.target.value)} style={{ width: 90 }} /> <RocketIcon size={16} />
          <span className="small muted">· you have {wallet(data).balance}</span></div>
        <div className="small muted">Study counts from now until the deadline. Keep it → you get the stake back. Miss it → {friend.profile.name} gets it.</div>
        {ch.error && <div className="small" style={{ color: "#ef4444" }}>{ch.error}</div>}
        <div className="row"><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={ch.busy || stake < 1}
            onClick={async () => { if (await ch.promise(friend.profile.id, Math.round(hours * 60), stake, new Date(by))) onClose(); }}>Promise · stake {stake} 🚀</button></div>
      </div>
    </Modal>
  );
}
