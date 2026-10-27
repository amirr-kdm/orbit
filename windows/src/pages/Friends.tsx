import { useEffect, useState } from "react";
import { NewChallenge, PromiseModal, Promises } from "./Challenges";
import { hm, typeOf, useChallenges } from "../lib/challenges";
import { StreakIcon, Avatar, GalaxyMap, LevelBadge, Modal, SystemCanvas } from "../components";
import { dayKey, duration, isToday, shortDuration, WEEKDAYS_SHORT, weekDays, weekdayIndex } from "../lib/dates";
import { FriendCard, minutesOn, streak, studyingNow, supabaseConfigured, useFriends, weekMinutes, weekSubjects } from "../lib/friends";
import { SUNS } from "../lib/planets";
import { GROUP_WIN_ROCKETS } from "../lib/store";
import { RocketIcon } from "./Store";
import { AllOrbiters } from "./Orbiters";
import { useStore } from "../lib/store";

export default function Friends({ only }: { only?: "groups" } = {}) {
  const f = useFriends();
  const { data } = useStore();
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [added, setAdded] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [galaxy, setGalaxy] = useState<FriendCard | null>(null);
  const [promising, setPromising] = useState<FriendCard | null>(null);
  const [copied, setCopied] = useState(false);
  const [tab0, setTab] = useState<number>(() => Number(localStorage.getItem("friends-tab") ?? 0));
  const tab = only === "groups" ? 1 : tab0 === 1 ? 0 : tab0;
  useEffect(() => { localStorage.setItem("friends-tab", String(tab)); }, [tab]);

  useEffect(() => { const t = setInterval(f.refresh, 45_000); return () => clearInterval(t); }, [f.refresh]);

  if (!supabaseConfigured) return (
    <div className="page"><div className="card" style={{ textAlign: "center", padding: 40 }}>
      <div style={{ fontSize: 40 }}>👥</div><h2>Friends isn't set up</h2>
      <div className="muted">This build has no Supabase project. See the README to connect one.</div></div></div>
  );

  if (!f.me) return (
    <div className="page" style={{ alignItems: "center", textAlign: "center", paddingTop: 80, gap: 14 }}>
      <div style={{ fontSize: 44 }}>👥</div>
      <h2 style={{ margin: 0 }}>Connecting to your account…</h2>
      {f.error && <div style={{ color: "#ef4444" }}>⚠️ {f.error}</div>}
      <button className="btn" onClick={f.refresh}>↻ Try again</button>
    </div>
  );

  const mine = f.myCard();
  const everyone = [...(mine ? [mine] : []), ...f.friends].sort((a, b) => weekMinutes(b) - weekMinutes(a));
  const top = Math.max(1, ...everyone.map(weekMinutes));
  const live = f.friends.filter((x) => studyingNow(x));

  return (
    <div className="page">
      <div className="grid2">
        <div className="card row" style={{ gap: 14, borderColor: "var(--accent)" }}>
          <Avatar name={f.me.name} planet={data.avatarPlanet} size={56} color="var(--accent)" />
          <div style={{ flex: 1 }}>
            <div className="row"><b style={{ fontSize: 18 }}>{f.me.name}</b>
              <button className="icon-btn" title="Change name" onClick={() => { const n = prompt("Your name", f.me!.name); if (n?.trim()) f.rename(n.trim()); }}>✏️</button></div>
            <div className="small muted">Your friend code</div>
            <div className="row"><span style={{ fontFamily: "ui-monospace, Consolas, monospace", fontSize: 26, fontWeight: 800, letterSpacing: 4 }}>{f.me.friend_code}</span>
              <button className="btn small" onClick={() => { navigator.clipboard.writeText(f.me!.friend_code); setCopied(true); setTimeout(() => setCopied(false), 1500); }}>{copied ? "✓ Copied" : "Copy"}</button></div>
          </div>
        </div>
        <div className="card">
          <h3><span className="t2-ico">➕</span>Add a friend</h3>
          <div className="row"><input style={{ flex: 1, fontFamily: "monospace" }} placeholder="Friend's code, e.g. 4F9A2C" value={code} onChange={(e) => setCode(e.target.value)}
            onKeyDown={async (e) => { if (e.key === "Enter" && code.trim().length >= 4) { const n = await f.addFriend(code); setAdded(n); if (n) setCode(""); } }} />
            <button className="btn primary" disabled={code.trim().length < 4} onClick={async () => { const n = await f.addFriend(code); setAdded(n); if (n) setCode(""); }}>Add</button></div>
          <div className="small" style={{ marginTop: 6, color: added ? "#22C55E" : "var(--muted)" }}>{added ? `You and ${added} are now friends 🎉` : "Ask your friend for their code from this page in their app."}</div>
        </div>
      </div>

      {f.error && <div style={{ color: "#ef4444" }}>⚠️ {f.error}</div>}

      {f.incoming.length > 0 && (
        <div className="card"><h3><span className="t2-ico">🙋</span>Friend requests</h3>
          {f.incoming.map((id) => { const c = f.people[id]; const g = f.groups.find((x) => x.members.includes(id)); return (
            <div key={id} className="list-row"><Avatar name={c?.profile.name ?? "?"} planet={c?.profile.avatar} size={30} color="#F97316" />
              <div style={{ flex: 1 }}><b>{c?.profile.name ?? "Someone"}</b>{g && <div className="small muted">From your group {g.name}</div>}</div>
              <button className="btn primary small" onClick={() => f.respond(id, true)}>Accept</button>
              <button className="btn small" onClick={() => f.respond(id, false)}>Decline</button></div>); })}
        </div>
      )}

      {!only && <div className="seg" style={{ alignSelf: "flex-start" }}>
        <button className={tab === 2 ? "on" : ""} onClick={() => setTab(2)}>All Orbiters</button>
        <button className={tab === 0 ? "on" : ""} onClick={() => setTab(0)}>Friends ({f.friends.length})</button>
      </div>}

      {tab === 2 ? <AllOrbiters /> : tab === 1 ? <Groups mine={mine} onGalaxy={setGalaxy} /> : <>
      {live.length > 0 && (
        <div className="card"><h3><span className="t2-ico">📡</span>Studying right now</h3>
          {live.map((x) => <div key={x.profile.id} className="row" style={{ padding: "4px 0" }}><Avatar name={x.profile.name} planet={x.profile.avatar} size={28} color="#22C55E" />
            <b>{x.profile.name}</b><span className="muted">is studying</span><b style={{ color: "#22C55E" }}>{studyingNow(x)}</b><span className="spacer" />
            {x.live?.started_at && <span className="muted">for {duration((Date.now() - new Date(x.live.started_at).getTime()) / 1000)}</span>}</div>)}
        </div>
      )}

      <Promises />
      <div className="card">
        <h3><span className="t2-ico">🏆</span>This week's leaderboard</h3>
        {!f.friends.length && <div className="muted">Add a friend with their code to start comparing. Share yours: <b>{f.me.friend_code}</b></div>}
        {everyone.map((x, i) => {
          const open = expanded === x.profile.id;
          return (
            <div key={x.profile.id} style={{ borderBottom: i < everyone.length - 1 ? "1px solid var(--line)" : undefined, padding: "8px 0" }}>
              <div className="row" style={{ cursor: "pointer" }} onClick={() => setExpanded(open ? null : x.profile.id)} title="Show what they studied">
                <span className="muted" style={{ transform: open ? "rotate(90deg)" : undefined, transition: ".2s" }}>›</span>
                <span style={{ width: 28, textAlign: "center", fontSize: i < 3 ? 20 : 14 }}>{i < 3 ? ["🥇", "🥈", "🥉"][i] : i + 1}</span>
                <Avatar name={x.profile.name} planet={x.profile.avatar} size={34} color={x.isMe ? "var(--accent)" : undefined} />
                <div style={{ flex: 1 }}>
                  <div className="row"><b>{x.profile.name}{x.isMe ? " (you)" : ""}</b><LevelBadge level={x.profile.level ?? 1} />{studyingNow(x) && <span className="dot" style={{ background: "#22C55E" }} />}
                    <span className="spacer" />{streak(x) > 0 && <span><StreakIcon size={15} /> {streak(x)}</span>}
                    {x.profile.rockets !== undefined && <span title="Rockets"><RocketIcon size={15} /> {x.profile.rockets}</span>}<b style={{ width: 80, textAlign: "right" }}>{duration(weekMinutes(x) * 60)}</b>
                    {!x.isMe && <button className="icon-btn" title={`Promise ${x.profile.name} you'll study — with rockets at stake`} onClick={(e) => { e.stopPropagation(); setPromising(x); }}>🤞</button>}</div>
                  <div className="progress" style={{ marginTop: 5 }}><div style={{ width: `${(weekMinutes(x) / top) * 100}%`, background: x.isMe ? undefined : "#94A3B8" }} /></div>
                </div>
              </div>
              {open && <Breakdown card={x} onGalaxy={() => setGalaxy(x)} />}
            </div>
          );
        })}
      </div>

      </>}

      <div className="row small muted"><span>🔒 Every Orbiter sees only your name, planet, level and hours this week. Friends and groups also see to-dos done, top subjects and what you're studying right now. Your schedule, tasks and notes stay on this computer.</span><span className="spacer" />
        {f.lastSync && <span>Synced {f.lastSync.toTimeString().slice(0, 5)}</span>}
        <button className="btn small" onClick={f.refresh}>↻ Refresh</button>
        <button className="btn small danger" onClick={() => confirm("Delete your Friends profile? Your shared stats and friendships are removed from the server.") && f.deleteProfile()}>Delete my profile</button>
      </div>

      {galaxy && <FriendGalaxy card={galaxy} onClose={() => setGalaxy(null)} />}
      {promising && <PromiseModal friend={promising} onClose={() => setPromising(null)} />}
    </div>
  );
}

function Breakdown({ card, onGalaxy }: { card: FriendCard; onGalaxy: () => void }) {
  const week = weekSubjects(card);
  const tot = Math.max(1, week.reduce((a, s) => a + s.minutes, 0));
  const today = card.stats[dayKey(new Date())];
  return (
    <div style={{ margin: "10px 0 4px 42px", background: "var(--card2)", borderRadius: 12, padding: 12, display: "flex", flexDirection: "column", gap: 12 }}>
      <div className="row" style={{ alignItems: "flex-start", gap: 24 }}>
        <div style={{ flex: 1, minWidth: 0 }}><b className="small">This week</b>
          {!week.length && <div className="small muted">Nothing logged yet this week.</div>}
          {week.map((s) => <div key={s.name} className="row small" style={{ padding: "3px 0" }}><span className="dot" style={{ background: s.color }} /><span style={{ width: 150, flexShrink: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={s.name}>{s.name}</span>
            <div className="progress" style={{ flex: 1 }}><div style={{ width: `${(s.minutes / tot) * 100}%`, background: s.color }} /></div>
            <b style={{ width: 64, textAlign: "right" }}>{duration(s.minutes * 60)}</b><span className="muted" style={{ width: 36, textAlign: "right" }}>{Math.round((s.minutes / tot) * 100)}%</span></div>)}
        </div>
        <div style={{ width: 240, flexShrink: 0, minWidth: 0, overflow: "hidden" }}><b className="small">Today</b>
          {!today?.subjects.length && <div className="small muted">Nothing yet today.</div>}
          {today?.subjects.map((s) => <div key={s.name} className="row small"><span className="dot" style={{ background: s.color }} /><span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={s.name}>{s.name}</span><span className="spacer" />{duration(s.minutes * 60)}</div>)}
          {today && today.todos_total > 0 && <div className="small muted">☑ {today.todos_done}/{today.todos_total} to-dos done</div>}
          {studyingNow(card) && <div className="small" style={{ color: "#22C55E", overflowWrap: "anywhere" }}>● Studying {studyingNow(card)} now</div>}
        </div>
      </div>
      <div className="row" style={{ gap: 6 }}>
        {weekDays(new Date()).map((d) => { const m = minutesOn(card, d); return (
          <div key={d.toDateString()} title={(card.stats[dayKey(d)]?.subjects ?? []).map((s) => `${s.name} ${duration(s.minutes * 60)}`).join(", ")}
            style={{ flex: 1, textAlign: "center", padding: "6px 0", borderRadius: 8, background: isToday(d) ? "color-mix(in srgb, var(--accent) 18%, transparent)" : "color-mix(in srgb, var(--text) 5%, transparent)" }}>
            <div className="small muted">{WEEKDAYS_SHORT[weekdayIndex(d)]}</div><b className="small">{m ? shortDuration(m * 60) : "—"}</b></div>
        ); })}
        <button className="btn small" onClick={onGalaxy}>✨ Galaxy</button>
      </div>
    </div>
  );
}

function FriendGalaxy({ card, onClose }: { card: FriendCard; onClose: () => void }) {
  const data = card.profile.galaxy ?? { systems: [] };
  const [focus, setFocus] = useState<string | null>(null);
  const sys = data.systems.find((s) => s.id === focus);
  const count = data.systems.reduce((a, s) => a + s.planets.length, 0);
  return (
    <Modal onClose={onClose} width={940}>
      <div className="row" style={{ marginBottom: 12 }}>
        <Avatar name={card.profile.name} planet={card.profile.avatar} size={44} />
        <div><div className="row"><h2 style={{ margin: 0 }}>{card.isMe ? "Your galaxy" : `${card.profile.name}'s galaxy`}</h2><LevelBadge level={card.profile.level ?? 1} /></div>
          <div className="muted">{data.systems.length} solar systems · {count} planets · <StreakIcon size={14} /> {streak(card)}</div></div>
        <span className="spacer" />
        {sys && <button className="btn" onClick={() => setFocus(null)}>‹ Galaxy</button>}
        <button className="btn primary" onClick={onClose}>Done</button>
      </div>
      {count === 0 ? <div className="space" style={{ height: 520, display: "grid", placeItems: "center" }}>No planets yet ✨</div>
        : <div style={{ position: "relative" }}>
            <GalaxyMap data={data} height={520} focused={focus} onSelect={setFocus} />
            {sys && <div style={{ position: "absolute", top: 12, left: 14, fontWeight: 600, color: "white" }}>{sys.name} · {SUNS[sys.sun]?.name}</div>}
          </div>}
    </Modal>
  );
}

/** Study groups: create one, share its code, see everyone's progress, send friend requests */
function Groups({ mine, onGalaxy }: { mine: FriendCard | null; onGalaxy: (c: FriendCard) => void }) {
  const f = useFriends();
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [note, setNote] = useState<string | null>(null);
  const [sel, setSel] = useState<string | null>(localStorage.getItem("selected-group"));
  const g = f.groups.find((x) => x.id === sel) ?? f.groups[0];
  const ch = useChallenges();
  const [newCh, setNewCh] = useState(false);
  const myID = f.me?.id;
  const cards = g ? g.members.map((id) => (id === myID ? mine : f.people[id])).filter((c): c is FriendCard => !!c).sort((a, b) => weekMinutes(b) - weekMinutes(a)) : [];
  const top = Math.max(1, ...cards.map(weekMinutes));
  const pick = (id: string) => { setSel(id); localStorage.setItem("selected-group", id); };

  const friendButton = (id: string) => {
    if (f.isFriend(id)) return <span className="small" style={{ color: "#22C55E" }}>✓ Friend</span>;
    if (f.incoming.includes(id)) return <><button className="btn primary small" onClick={() => f.respond(id, true)}>Accept</button><button className="btn small" onClick={() => f.respond(id, false)}>Decline</button></>;
    if (f.outgoing.includes(id)) return <button className="btn small" title="Cancel the request" onClick={() => f.cancelRequest(id)}>Requested ✕</button>;
    return <button className="btn small" onClick={() => f.sendRequest(id)}>＋ Add friend</button>;
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
      {f.groupPrize && <div className="card row" style={{ background: "rgba(250,204,21,.18)" }}><b>{f.groupPrize}</b><span className="spacer" /><button className="btn small" onClick={f.clearPrize}>Nice!</button></div>}
      <div className="small muted">🏆 Each week, whoever studies the most in a group wins {GROUP_WIN_ROCKETS} rockets (paid after Friday).</div>
      <div className="grid2">
        <div className="card"><h3><span className="t2-ico">👥</span>New group</h3>
          <div className="row"><input style={{ flex: 1 }} placeholder="Group name, e.g. IELTS crew" value={name} onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && name.trim()) { f.createGroup(name); setName(""); } }} />
            <button className="btn primary" disabled={!name.trim()} onClick={() => { f.createGroup(name); setName(""); }}>Create</button></div>
          <div className="small muted" style={{ marginTop: 6 }}>You'll get a code to share. Everyone who joins sees each other's study time.</div>
        </div>
        <div className="card"><h3><span className="t2-ico">🔑</span>Join a group</h3>
          <div className="row"><input style={{ flex: 1, fontFamily: "monospace" }} placeholder="Group code" value={code} onChange={(e) => setCode(e.target.value)} />
            <button className="btn primary" disabled={code.trim().length < 4} onClick={async () => { const n = await f.joinGroup(code); if (n) { setCode(""); setNote(`You joined ${n} 🎉`); } }}>Join</button></div>
          <div className="small" style={{ marginTop: 6, color: note ? "var(--accent)" : "var(--muted)" }}>{note ?? "Ask a friend for their group's code."}</div>
        </div>
      </div>
      {!f.groups.length ? <div className="card muted" style={{ textAlign: "center", padding: 30 }}>No groups yet. Create one for your class or study buddies, or join one with a code.</div> : <>
        <div className="row" style={{ flexWrap: "wrap" }}>
          {f.groups.map((x) => <button key={x.id} className={`btn ${x.id === g?.id ? "primary" : ""}`} style={{ borderRadius: 99 }} onClick={() => pick(x.id)}>👥 {x.name} · {x.members.length}</button>)}
        </div>
        {g && <div className="card">
          <div className="row" style={{ marginBottom: 10 }}>
            <div><h2 style={{ margin: 0 }}>{g.name}</h2><div className="small muted">{g.members.length} member{g.members.length === 1 ? "" : "s"}{g.owner === myID ? " · you created it" : ""}</div></div>
            <span className="spacer" />
            <span style={{ fontFamily: "monospace", fontSize: 20, fontWeight: 800, letterSpacing: 3 }}>{g.code}</span>
            <button className="btn small" onClick={() => navigator.clipboard.writeText(g.code)}>Copy code</button>
            <button className="btn small danger" onClick={() => confirm(`Leave ${g.name}? You can join again with the code.`) && f.leaveGroup(g.id)}>Leave</button>
          </div>
          <div className="row" style={{ margin: "4px 0 10px" }}><h3 style={{ margin: 0 }}>🏁 Group challenges</h3><span className="spacer" /><button className="btn small primary" onClick={() => { ch.setError(null); setNewCh(true); }}>＋ New group challenge</button></div>
          {(() => { const list = ch.list.filter((c) => c.kind !== "promise" && c.group_id === g.id); return list.length ? list.map((c) => (
            <div key={c.id} className="list-row"><div style={{ flex: 1 }}><b>{c.title}</b><div className="small muted">{hm(c.target_minutes)} goal · {c.fee} 🚀 entry · {(ch.members[c.id] ?? []).length} joined · {c.status === "open" ? (Date.now() < new Date(c.ends_at).getTime() ? "open" : "paying out") : c.status}</div></div>
              <span className="small muted">{typeOf(c) === "group" ? "👥" : ""}</span></div>)) : <div className="small muted" style={{ marginBottom: 8 }}>No challenges in this group yet. Make one — only group members can join it.</div>; })()}
          {newCh && <NewChallenge presetGroup={g.id} onClose={() => setNewCh(false)} />}
          <h3>🏆 This week in {g.name}</h3>
          {cards.map((x, i) => (
            <div key={x.profile.id} className="list-row">
              <span style={{ width: 28, textAlign: "center", fontSize: i < 3 ? 20 : 14 }}>{i < 3 ? ["🥇", "🥈", "🥉"][i] : i + 1}</span>
              <Avatar name={x.profile.name} planet={x.profile.avatar} size={32} color={x.isMe ? "var(--accent)" : undefined} />
              <div style={{ flex: 1 }}>
                <div className="row"><b>{x.profile.name}{x.isMe ? " (you)" : ""}</b><LevelBadge level={x.profile.level ?? 1} />{studyingNow(x) && <span className="small" style={{ color: "#22C55E" }}>● {studyingNow(x)}</span>}
                  <span className="spacer" />{streak(x) > 0 && <span><StreakIcon size={15} /> {streak(x)}</span>}{x.profile.rockets !== undefined && <span><RocketIcon size={14} /> {x.profile.rockets}</span>}
                  <b style={{ width: 70, textAlign: "right" }}>{duration(weekMinutes(x) * 60)}</b></div>
                <div className="progress" style={{ marginTop: 4 }}><div style={{ width: `${(weekMinutes(x) / top) * 100}%` }} /></div>
              </div>
              <button className="btn small" onClick={() => onGalaxy(x)}>✨</button>
              {!x.isMe && friendButton(x.profile.id)}
            </div>
          ))}
        </div>}
      </>}
    </div>
  );
}
