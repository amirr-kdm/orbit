// All Orbiters board and member profiles — same as the Mac app (supabase/orbiters.sql).
// Every member sees only names, planets, levels and hours; what someone studies stays for friends.
import { useEffect, useState } from "react";
import { Avatar, LevelBadge, Modal, StreakIcon } from "../components";
import { dayKey, duration, shortDuration, weekStart } from "../lib/dates";
import { sharedClient as client, studyingNow, useFriends, weekMinutes, weekSubjects } from "../lib/friends";
import slayer from "../assets/badge-slayer.png";

interface Orbiter { id: string; name: string; avatar?: string | null; level?: number | null; minutes: number }
interface OrbiterInfo { id: string; name: string; avatar?: string | null; level?: number | null; streak?: number | null; slain: number; joined?: string | null }

/** Add / accept / cancel buttons for someone who isn't a friend yet */
export function FriendButton({ id }: { id: string }) {
  const f = useFriends();
  if (id === f.me?.id) return null;
  if (f.isFriend(id)) return <span className="small" style={{ color: "#22C55E" }}>✓ Friend</span>;
  if (f.incoming.includes(id)) return <span className="row" style={{ gap: 4 }}><button className="btn primary small" onClick={() => f.respond(id, true)}>Accept</button><button className="btn small" onClick={() => f.respond(id, false)}>Decline</button></span>;
  if (f.outgoing.includes(id)) return <button className="btn small" title="Cancel the request" onClick={() => f.cancelRequest(id)}>Requested ✕</button>;
  return <button className="btn small" onClick={() => f.sendRequest(id)}>＋ Add Friend</button>;
}

export function AllOrbiters() {
  const f = useFriends();
  const [list, setList] = useState<Orbiter[] | null>(null);
  const [showing, setShowing] = useState<string | null>(null);
  useEffect(() => {
    client.rpc("orbiters_board", { week_start: dayKey(weekStart(new Date())) }).then((r: Orbiter[]) => setList(r)).catch(() => setList([]));
  }, []);
  const me = f.me?.id;
  const top = Math.max(1, list?.[0]?.minutes ?? 1);
  return (
    <div className="card">
      <h3><span className="t2-ico">🌍</span>All Orbiters · this week</h3>
      <div className="small muted" style={{ marginBottom: 8 }}>Everyone using Orbit, ranked by study time this week. You see hours only — add someone as a friend to see what they study.</div>
      {!list && <div className="muted">Loading…</div>}
      {list?.map((o, i) => (
        <div key={o.id} className="row" style={{ gap: 12, padding: "6px 0", borderBottom: i < list.length - 1 ? "1px solid var(--line)" : undefined }}>
          <span style={{ width: 30, textAlign: "center", fontSize: i < 3 ? 20 : 14, fontWeight: 700 }}>{i < 3 ? ["🥇", "🥈", "🥉"][i] : i + 1}</span>
          <span style={{ cursor: "pointer" }} title={`Open ${o.name}'s profile`} onClick={() => setShowing(o.id)}><Avatar name={o.name} planet={o.avatar ?? undefined} size={34} color="var(--accent)" /></span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="row" style={{ gap: 6 }}><b style={{ cursor: "pointer", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} onClick={() => setShowing(o.id)}>{o.id === me ? `${o.name} (you)` : o.name}</b>
              {o.level != null && <LevelBadge level={o.level} />}</div>
            <div className="progress" style={{ marginTop: 5 }}><div style={{ width: `${(o.minutes / top) * 100}%`, background: o.id === me ? "#F97316" : undefined }} /></div>
          </div>
          <b style={{ width: 72, textAlign: "right" }}>{o.minutes > 0 ? duration(o.minutes * 60) : "—"}</b>
          <span style={{ width: 140, display: "flex", justifyContent: "flex-end" }}><FriendButton id={o.id} /></span>
        </div>
      ))}
      {showing && <OrbiterProfile userID={showing} onClose={() => setShowing(null)} />}
    </div>
  );
}

/** A member's profile: planet, name, level, streak and the World Bosses they helped beat — for anyone.
 *  Friends also see their study this week, subjects and what they're studying right now. */
export function OrbiterProfile({ userID, onClose }: { userID: string; onClose: () => void }) {
  const f = useFriends();
  const [info, setInfo] = useState<OrbiterInfo | null>(null);
  useEffect(() => { client.rpc("orbiter_profile", { uid: userID }).then((r: OrbiterInfo[]) => setInfo(r[0] ?? null)).catch(() => {}); }, [userID]);
  const isMe = userID === f.me?.id;
  const card = isMe ? f.myCard() : f.people[userID];
  const isFriend = f.isFriend(userID);
  const name = info?.name ?? card?.profile.name ?? "Orbiter";
  const subjects = card ? weekSubjects(card).slice(0, 5) : [];
  const top = Math.max(1, subjects[0]?.minutes ?? 1);
  const fact = (icon: React.ReactNode, value: string, label: string) => (
    <div style={{ flex: 1, textAlign: "center", padding: "12px 4px", borderRadius: 14, background: "color-mix(in srgb, var(--text) 5%, transparent)" }}>
      <div style={{ height: 26, display: "grid", placeItems: "center" }}>{icon}</div>
      <div style={{ fontSize: 18, fontWeight: 700 }}>{value}</div><div className="small muted">{label}</div>
    </div>
  );
  return (
    <Modal onClose={onClose} width={420}>
      <div style={{ textAlign: "center", margin: "-8px -8px 0", padding: "20px 0 16px", borderRadius: 14, background: "linear-gradient(color-mix(in srgb, var(--accent) 35%, transparent), transparent)" }}>
        <div style={{ display: "inline-block" }}><Avatar name={name} planet={info?.avatar ?? card?.profile.avatar ?? undefined} size={96} color="var(--accent)" /></div>
        <h2 style={{ margin: "8px 0 4px" }}>{name}</h2>
        <div className="row" style={{ justifyContent: "center", gap: 6 }}>
          {(info?.level ?? card?.profile.level) != null && <LevelBadge level={(info?.level ?? card?.profile.level)!} />}
          {isMe ? <span className="badge" style={{ background: "#F9731640" }}>You</span> : isFriend && <span className="badge" style={{ background: "#22C55E40" }}>Friend</span>}
        </div>
      </div>
      <div className="row" style={{ gap: 10, marginTop: 14 }}>
        {fact(<StreakIcon size={24} />, String(info?.streak ?? card?.profile.streak ?? 0), "day streak")}
        {fact(<img src={slayer} alt="" style={{ height: 24, filter: (info?.slain ?? 0) > 0 ? undefined : "grayscale(1)", opacity: (info?.slain ?? 0) > 0 ? 1 : 0.4 }} />, String(info?.slain ?? 0), "World Bosses beaten")}
        {fact(<span>📅</span>, info?.joined ? new Date(info.joined).toLocaleDateString("en-US-u-ca-persian", { month: "short", year: "numeric" }) : "—", "joined")}
      </div>
      {(isFriend || isMe) && card ? (
        <div style={{ marginTop: 14, display: "flex", flexDirection: "column", gap: 6 }}>
          <div className="row"><b>🕐 This week</b><span className="spacer" /><b>{duration(weekMinutes(card) * 60)}</b></div>
          {studyingNow(card) && <div className="small" style={{ color: "#22C55E" }}>📡 Studying {studyingNow(card)} right now</div>}
          {subjects.map((s) => (
            <div key={s.name} className="row small" style={{ gap: 8 }}><span className="dot" style={{ background: s.color }} />
              <span style={{ width: 120, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{s.name}</span>
              <div className="progress" style={{ flex: 1 }}><div style={{ width: `${(s.minutes / top) * 100}%`, background: s.color }} /></div>
              <span style={{ width: 46, textAlign: "right" }}>{shortDuration(s.minutes * 60)}</span></div>
          ))}
        </div>
      ) : !isMe && <div className="small muted" style={{ marginTop: 14 }}>🔒 Study time and subjects are shared with friends only.</div>}
      <div className="row" style={{ marginTop: 16 }}><FriendButton id={userID} /><span className="spacer" /><button className="btn primary" onClick={onClose}>Done</button></div>
    </Modal>
  );
}
