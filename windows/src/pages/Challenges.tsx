import { useEffect, useState } from "react";
import { Modal } from "../components";
import { Challenge, hm, useChallenges } from "../lib/challenges";
import { FriendCard, StudyGroup, useFriends } from "../lib/friends";
import { useStore, wallet } from "../lib/store";
import { RocketIcon } from "./Store";

const rel = (d: Date) => {
  const m = Math.round((d.getTime() - Date.now()) / 60000), a = Math.abs(m);
  const t = a < 60 ? `${a}m` : a < 1440 ? `${Math.round(a / 60)}h` : `${Math.round(a / 1440)}d`;
  return m >= 0 ? `in ${t}` : `${t} ago`;
};
const when = (s: string) => new Date(s).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

/** Challenges of one study group: create, join, leave, cancel, live progress */
export function GroupChallenges({ group }: { group: StudyGroup }) {
  const ch = useChallenges();
  const f = useFriends();
  const me = f.me?.id;
  const [creating, setCreating] = useState(false);
  const [, tick] = useState(0);
  useEffect(() => { const t = setInterval(() => tick((n) => n + 1), 30_000); return () => clearInterval(t); }, []);
  const list = ch.list.filter((c) => c.group_id === group.id);
  const name = (id: string) => (id === me ? "You" : f.people[id]?.profile.name ?? "Member");

  const row = (c: Challenge) => {
    const now = Date.now(), start = new Date(c.starts_at).getTime(), end = new Date(c.ends_at).getTime();
    const people = [...(ch.members[c.id] ?? [])].sort((a, b) => b.minutes - a.minutes);
    const mine = people.some((m) => m.user_id === me);
    const [label, color] = c.status === "cancelled" ? ["Cancelled", "#94A3B8"] : c.status === "settled" ? ["Finished", "#22C55E"]
      : now < start ? [`Starts ${rel(new Date(start))}`, "#3B82F6"] : now < end ? [`Live · ends ${rel(new Date(end))}`, "#F97316"] : ["Paying out soon", "#A855F7"];
    return (
      <div key={c.id} className="card" style={{ padding: 12, display: "flex", flexDirection: "column", gap: 8 }}>
        <div className="row"><b>{c.title}</b><span className="small" style={{ color, background: color + "26", padding: "1px 7px", borderRadius: 99, fontWeight: 600 }}>{label}</span>
          <span className="spacer" /><b className="row" style={{ gap: 4 }}><RocketIcon size={15} />{c.fee}</b></div>
        <div className="small muted">Study {hm(c.target_minutes)} between {when(c.starts_at)} and {when(c.ends_at)}</div>
        {people.map((m) => (
          <div key={m.user_id} className="row small">
            <span style={{ width: 110, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{name(m.user_id)}</span>
            <div className="progress" style={{ flex: 1 }}><div style={{ width: `${Math.min(100, (m.minutes / c.target_minutes) * 100)}%`, background: m.minutes >= c.target_minutes ? "#22C55E" : undefined }} /></div>
            <span className="muted" style={{ width: 96, textAlign: "right" }}>{hm(m.minutes)} / {hm(c.target_minutes)}</span>
          </div>
        ))}
        {c.status === "open" && (
          <div className="row">
            {now < start ? (mine ? (c.creator !== me && <button className="btn small" disabled={ch.busy} onClick={() => ch.leave(c)}>Leave (refund)</button>)
              : <button className="btn small primary" disabled={ch.busy} onClick={() => ch.join(c)}>Join for {c.fee} 🚀</button>)
              : !mine && <span className="small muted">Started — joining is closed</span>}
            <span className="spacer" />
            {c.creator === me && <button className="btn small danger" disabled={ch.busy} onClick={() => confirm(`Cancel “${c.title}”? Everyone gets their entry fee back.`) && ch.cancel(c)}>Cancel…</button>}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="card">
      <div className="row"><h3 style={{ margin: 0 }}>🏁 Challenges</h3><span className="spacer" />
        <button className="btn primary" onClick={() => { ch.setError(null); setCreating(true); }}>＋ New challenge</button></div>
      <div className="small muted" style={{ margin: "4px 0 10px" }}>Everyone pays the entry fee. All finish → fees doubled. Missed → that fee is shared by those who finished.</div>
      {!list.length && <div className="muted">No challenges yet — start one!</div>}
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>{list.map(row)}</div>
      {ch.error && <div className="small" style={{ color: "#ef4444", marginTop: 6 }}>{ch.error}</div>}
      {creating && <NewChallenge group={group} onClose={() => setCreating(false)} />}
    </div>
  );
}

function NewChallenge({ group, onClose }: { group: StudyGroup; onClose: () => void }) {
  const ch = useChallenges();
  const { data } = useStore();
  const [title, setTitle] = useState("");
  const [hours, setHours] = useState(6);
  const [length, setLength] = useState(24);
  const [fee, setFee] = useState(50);
  const [mode, setMode] = useState(0);
  const [at, setAt] = useState(() => new Date(Date.now() + 3600_000).toISOString().slice(0, 16));
  const start = () => (mode === 0 ? new Date() : mode === 1 ? new Date(Date.now() + 3600_000) : new Date(at));
  return (
    <Modal onClose={onClose} width={460}>
      <h3 style={{ marginTop: 0 }}>🏁 New challenge in {group.name}</h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <input placeholder="Name, e.g. Weekend sprint" value={title} onChange={(e) => setTitle(e.target.value)} />
        <div className="row">Study <input type="number" min={0.5} max={72} step={0.5} value={hours} onChange={(e) => setHours(+e.target.value)} style={{ width: 70 }} /> h
          within <input type="number" min={1} max={168} value={length} onChange={(e) => setLength(+e.target.value)} style={{ width: 70 }} /> h</div>
        <div className="seg">{["Now", "In 1 hour", "At…"].map((t, i) => <button key={t} className={mode === i ? "on" : ""} onClick={() => setMode(i)}>{t}</button>)}</div>
        {mode === 2 && <input type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} />}
        <div className="row">Entry fee <input type="number" min={0} value={fee} onChange={(e) => setFee(+e.target.value)} style={{ width: 90 }} /> <RocketIcon size={16} />
          <span className="small muted">· you have {wallet(data).balance}</span></div>
        <div className="small muted">You join too and pay the fee. Others can join or leave for a refund until it starts. Only you can cancel it (everyone is refunded).</div>
        {ch.error && <div className="small" style={{ color: "#ef4444" }}>{ch.error}</div>}
        <div className="row"><span className="spacer" /><button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={ch.busy || fee < 0 || hours > length}
            onClick={async () => { const s = start(); if (await ch.create(group.id, title || "Challenge", Math.round(hours * 60), Math.max(0, fee), s, new Date(s.getTime() + length * 3600_000))) onClose(); }}>
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
