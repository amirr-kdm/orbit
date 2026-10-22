import { useEffect, useState } from "react";
import { Modal } from "../components";
import { Challenge, hm, RULES, useChallenges } from "../lib/challenges";
import { FriendCard, useFriends } from "../lib/friends";
import { useStore, wallet } from "../lib/store";
import { RocketIcon } from "./Store";
import { OrbiterProfile } from "./Orbiters";

const rel = (d: Date) => {
  const m = Math.round((d.getTime() - Date.now()) / 60000), a = Math.abs(m);
  const t = a < 60 ? `${a}m` : a < 1440 ? `${Math.round(a / 60)}h` : `${Math.round(a / 1440)}d`;
  return m >= 0 ? `in ${t}` : `${t} ago`;
};
const when = (s: string) => new Date(s).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

/** Every challenge, open to all Orbit members: upcoming (join until it starts), running, and recently finished */
export default function ChallengesPage() {
  const ch = useChallenges();
  const [creating, setCreating] = useState(false);
  const [showing, setShowing] = useState<string | null>(null);
  const [, tick] = useState(0);
  useEffect(() => { const t = setInterval(() => tick((n) => n + 1), 30_000); return () => clearInterval(t); }, []);
  const now = Date.now();
  const all = ch.list.filter((c) => c.kind !== "promise");
  const started = (c: Challenge) => now >= new Date(c.starts_at).getTime(), ended = (c: Challenge) => now >= new Date(c.ends_at).getTime();
  const upcoming = all.filter((c) => c.status === "open" && !started(c));
  const live = all.filter((c) => c.status === "open" && started(c) && !ended(c));
  const done = all.filter((c) => c.status !== "open" || ended(c));
  const rule = (icon: string, text: string) => <span className="small" style={{ padding: "3px 8px", borderRadius: 99, background: "color-mix(in srgb, var(--text) 7%, transparent)" }}>{icon} {text}</span>;
  const section = (title: string, icon: string, tint: string, list: Challenge[]) => list.length > 0 && (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <b style={{ color: tint }}>{icon} {title} · {list.length}</b>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(380px, 1fr))", gap: 14 }}>
        {list.map((c) => <ChallengeCard key={c.id} c={c} onOpen={setShowing} />)}
      </div>
    </div>
  );
  return (
    <div className="page">
      <div className="row" style={{ alignItems: "flex-start", gap: 16 }}>
        <div style={{ width: 56, height: 56, borderRadius: 16, display: "grid", placeItems: "center", fontSize: 26, background: "linear-gradient(135deg, #F97316, #EC4899)", flexShrink: 0 }}>🏁</div>
        <div style={{ flex: 1 }}>
          <h1 style={{ margin: 0 }}>Challenges</h1>
          <div className="muted">Study together with every Orbit member for rockets. Everyone pays the entry fee and anyone can join until it starts.</div>
          <div className="row" style={{ gap: 6, flexWrap: "wrap", marginTop: 6 }}>
            {rule("🕐", `at least ${RULES.minHours}h of study`)}{rule("👥", `${RULES.minPeople}+ people, or everyone is refunded`)}
            {rule("🎁", "all finish → fee back + bonus up to 100 🚀/h")}{rule("⇄", "some miss → their fees go to those who finished")}
          </div>
        </div>
        <button className="btn primary" onClick={() => { ch.setError(null); setCreating(true); }}>＋ New Challenge</button>
      </div>
      {!all.length && <div className="card muted">No challenges yet — start one with New Challenge.</div>}
      {section("Upcoming · join until it starts", "📅", "#3B82F6", upcoming)}
      {section("Running now", "🔥", "#F97316", live)}
      {section("Finished", "✅", "#22C55E", done)}
      {ch.error && <div className="small" style={{ color: "#ef4444" }}>{ch.error}</div>}
      {creating && <NewChallenge onClose={() => setCreating(false)} />}
      {showing && <OrbiterProfile userID={showing} onClose={() => setShowing(null)} />}
    </div>
  );
}

/** One challenge: who, how far, and what you can do */
function ChallengeCard({ c, onOpen }: { c: Challenge; onOpen: (id: string) => void }) {
  const ch = useChallenges();
  const f = useFriends();
  const me = f.me?.id;
  const now = Date.now(), start = new Date(c.starts_at).getTime(), end = new Date(c.ends_at).getTime();
  const people = [...(ch.members[c.id] ?? [])].sort((a, b) => b.minutes - a.minutes);
  const mine = people.some((m) => m.user_id === me);
  const group = c.group_id ? f.groups.find((g) => g.id === c.group_id)?.name ?? "A study group" : "Open to all Orbit members";
  const [label, color] = c.status === "cancelled" ? ["Cancelled", "#94A3B8"] : c.status === "settled" ? ["Finished", "#22C55E"]
    : now < start ? [`Starts ${rel(new Date(start))}`, "#3B82F6"] : now < end ? [`Live · ends ${rel(new Date(end))}`, "#F97316"] : ["Paying out soon", "#A855F7"];
  const name = (id: string) => (id === me ? "You" : f.people[id]?.profile.name ?? ch.names[id] ?? "Member");
  const fact = (icon: string, value: string, label: string) => <div><b>{icon} {value}</b><div className="small muted">{label}</div></div>;
  return (
    <div className="card" style={{ padding: 16, display: "flex", flexDirection: "column", gap: 10, borderColor: color + "40" }}>
      <div className="row" style={{ alignItems: "flex-start" }}>
        <div style={{ flex: 1, minWidth: 0 }}><b>{c.title}</b><div className="small muted">{c.group_id ? "👥" : "🌍"} {group}</div></div>
        <span className="small" style={{ color, background: color + "26", padding: "2px 8px", borderRadius: 99, fontWeight: 600, whiteSpace: "nowrap" }}>{label}</span>
      </div>
      <div className="row" style={{ gap: 14, flexWrap: "wrap" }}>
        {fact("🕐", hm(c.target_minutes), "goal")}{fact("📅", `${Math.round((end - start) / 3600_000)}h`, "window")}
        {fact("🎟", `${c.fee} 🚀`, "entry")}{fact("🎁", `+${RULES.bonus(c.fee, c.target_minutes)} 🚀`, "if all finish")}
      </div>
      <div className="small muted">{when(c.starts_at)} → {when(c.ends_at)}</div>
      {people.length < RULES.minPeople && c.status === "open" && <div className="small" style={{ color: "#F97316" }}>⏳ Needs at least {RULES.minPeople} people — otherwise everyone is refunded</div>}
      {people.map((m) => (
        <div key={m.user_id} className="row small">
          <span style={{ width: 100, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", cursor: m.user_id !== me ? "pointer" : undefined }}
            onClick={() => m.user_id !== me && onOpen(m.user_id)}>{name(m.user_id)}</span>
          <div className="progress" style={{ flex: 1 }}><div style={{ width: `${Math.min(100, (m.minutes / Math.max(1, c.target_minutes)) * 100)}%`, background: m.minutes >= c.target_minutes ? "#22C55E" : undefined }} /></div>
          <span className="muted" style={{ width: 96, textAlign: "right" }}>{hm(m.minutes)} / {hm(c.target_minutes)}</span>
        </div>
      ))}
      {c.status === "open" && (
        <div className="row">
          {now < start ? (mine ? (c.creator !== me ? <button className="btn small" disabled={ch.busy} onClick={() => ch.leave(c)}>Leave (refund)</button>
              : <span className="small" style={{ color: "#22C55E" }}>✓ You're in</span>)
            : <button className="btn small primary" disabled={ch.busy} onClick={() => ch.join(c)}>Join for {c.fee} 🚀</button>)
            : !mine && <span className="small muted">Started — joining is closed</span>}
          <span className="spacer" />
          {c.creator === me && <button className="btn small danger" disabled={ch.busy} onClick={() => confirm(`Cancel “${c.title}”? Everyone gets their entry fee back.`) && ch.cancel(c)}>Cancel…</button>}
        </div>
      )}
    </div>
  );
}

function NewChallenge({ onClose }: { onClose: () => void }) {
  const ch = useChallenges();
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
      <h3 style={{ marginTop: 0 }}>🏁 New challenge · open to every Orbit member</h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
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
          <span>• Others can join or leave (refund) until it starts. Only you can cancel it — everyone is refunded.</span>
        </div>
        {fee < minFee && <div className="small" style={{ color: "#F97316" }}>The entry fee must be at least {minFee} 🚀 for {hours} hours.</div>}
        {fee > have && <div className="small" style={{ color: "#F97316" }}>You don't have enough rockets.</div>}
        {ch.error && <div className="small" style={{ color: "#ef4444" }}>{ch.error}</div>}
        <div className="row"><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={ch.busy || fee < minFee || fee > have || hours > length}
            onClick={async () => { const s = start(); if (await ch.create(title.trim() || "Challenge", hours * 60, fee, s, new Date(s.getTime() + length * 3600_000))) onClose(); }}>
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
