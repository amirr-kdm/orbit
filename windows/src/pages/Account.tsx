import { useEffect, useRef, useState } from "react";
import { Avatar, Modal } from "../components";
import { useAccount } from "../lib/account";
import { useStore } from "../lib/store";
import abduction from "../assets/login-abduction.png";
import cat from "../assets/login-cat.png";
import satellite from "../assets/login-satellite.png";
import iconUrl from "../icon.png";
import { frameLoop } from "../components";

/** Deep space with twinkling stars and soft nebulas */
function Space({ children }: { children: React.ReactNode }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const stars = Array.from({ length: 170 }, () => ({ x: Math.random(), y: Math.random(), s: 0.6 + Math.random() * 1.8, sp: 0.6 + Math.random() * 1.6, ph: Math.random() * 6 }));
    const draw = (t: number) => {
      const c = canvas.current;
      if (c) {
        const w = c.clientWidth, h = c.clientHeight, dpr = devicePixelRatio || 1;
        if (c.width !== w * dpr) { c.width = w * dpr; c.height = h * dpr; }
        const ctx = c.getContext("2d")!;
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
        for (const s of stars) {
          ctx.globalAlpha = 0.85 * (0.35 + 0.65 * (0.5 + 0.5 * Math.sin((t / 1000) * s.sp + s.ph)));
          ctx.fillStyle = "white"; ctx.beginPath(); ctx.arc(s.x * w, s.y * h, s.s / 2, 0, Math.PI * 2); ctx.fill();
        }
      }
    };
    return frameLoop(draw, 24);
  }, []);
  return (
    <div className="space-login">
      <canvas ref={canvas} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
      {children}
    </div>
  );
}

export function LoginPage({ upgrade = false }: { upgrade?: boolean }) {
  const a = useAccount();
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const showExtra = upgrade || mode === "signup";
  useEffect(() => { if (upgrade && !username) setUsername(a.profile?.username ?? (a.profile?.name ?? "").replace(/\s/g, "")); }, [upgrade, a.profile]); // eslint-disable-line react-hooks/exhaustive-deps

  const submit = () => {
    if (showExtra && password !== confirm) { a.setMessage("The two passwords don't match."); return; }
    if (upgrade) a.upgrade(email, username, password);
    else if (mode === "signup") a.signUp(email, username, password);
    else a.signIn(email, password);
  };
  const subtitle = upgrade ? `Welcome back, ${a.profile?.name ?? "explorer"}` : mode === "login" ? "Welcome back, explorer" : "Create your account";

  return (
    <Space>
      <img src={satellite} alt="" className="login-satellite" />
      <img src={cat} alt="" className="login-cat" />
      <div className="login-row">
        <div className="login-hero">
          <div className="login-frame"><img src={abduction} alt="A UFO beaming up a cow" /><div className="beam-glow" /></div>
          <div className="login-tag">Study. Level up. Get abducted by good habits.</div>
          <div className="small" style={{ opacity: 0.5 }}>Your planner, timer and galaxy — synced to your account</div>
        </div>
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); submit(); }}>
          <div className="row" style={{ gap: 12 }}>
            <img src={iconUrl} alt="" style={{ width: 52, height: 52, borderRadius: 12 }} />
            <div><div className="login-title">ORBIT</div><div className="small" style={{ opacity: 0.7 }}>{subtitle}</div></div>
          </div>
          {upgrade ? (
            <div className="small" style={{ opacity: 0.8, lineHeight: 1.5 }}>Orbit now uses accounts. Add an email and a password to keep your friends, groups, galaxy and data — and to get it all back on any computer.</div>
          ) : (
            <div className="login-tabs">
              <button type="button" className={mode === "login" ? "on" : ""} onClick={() => { setMode("login"); a.setMessage(null); }}>Log in</button>
              <button type="button" className={mode === "signup" ? "on" : ""} onClick={() => { setMode("signup"); a.setMessage(null); }}>Sign up</button>
            </div>
          )}
          <input className="login-field" type="email" placeholder="✉  Email" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus />
          {showExtra && <input className="login-field" placeholder="@  Username" value={username} onChange={(e) => setUsername(e.target.value)} />}
          <input className="login-field" type="password" placeholder="🔒  Password" value={password} onChange={(e) => setPassword(e.target.value)} />
          {showExtra && <input className="login-field" type="password" placeholder="🔒  Repeat password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />}
          {a.message && <div style={{ color: "#FCA5A5" }}>⚠ {a.message}</div>}
          <button type="submit" className="login-button" disabled={a.busy}>{a.busy ? "…" : upgrade ? "Create my account →" : mode === "login" ? "Log in →" : "Create account →"}</button>
          <div className="small" style={{ opacity: 0.5 }}>
            {mode === "signup" && !upgrade ? "New accounts are checked by the owner before they can use Orbit. You'll get in as soon as you're approved."
              : upgrade ? "Your friends, groups and stats stay exactly as they are." : "Forgot your password? Ask the Orbit owner to reset it."}
          </div>
        </form>
      </div>
    </Space>
  );
}

export function PendingPage() {
  const a = useAccount();
  return (
    <Space>
      <div style={{ position: "relative", display: "flex", flexDirection: "column", alignItems: "center", gap: 18, color: "white", textAlign: "center", margin: "auto" }}>
        <img src={cat} alt="" className="float-cat" style={{ width: 190 }} />
        <div className="login-title" style={{ fontSize: 28 }}>Waiting for approval</div>
        <div style={{ opacity: 0.75, maxWidth: 480, lineHeight: 1.5 }}>Hi @{a.profile?.username ?? a.profile?.name}! The Orbit owner checks every new account. This screen opens the app by itself as soon as you're approved.</div>
        {a.email && <div className="small" style={{ opacity: 0.5 }}>✉ {a.email}</div>}
        <div className="row"><button className="btn" onClick={a.refreshStatus}>↻ Check again</button><button className="btn" onClick={a.signOut}>Log out</button></div>
      </div>
    </Space>
  );
}

export function ProfileModal({ onClose }: { onClose: () => void }) {
  const a = useAccount();
  const { data } = useStore();
  const [username, setUsername] = useState(a.profile?.username ?? "");
  const [newEmail, setNewEmail] = useState("");
  const [emailPw, setEmailPw] = useState("");
  const [cur, setCur] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [note, setNote] = useState<string | null>(null);
  useEffect(() => { a.setMessage(null); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Modal onClose={onClose} width={560}>
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        <div className="row" style={{ gap: 14 }}>
          <Avatar name={a.profile?.name ?? "?"} planet={data.avatarPlanet} size={56} color="var(--accent)" />
          <div style={{ flex: 1 }}><h2 style={{ margin: 0 }}>@{a.profile?.username ?? a.profile?.name}</h2><div className="muted">{a.email}</div></div>
          {a.isAdmin && <span style={{ color: "#F97316", fontWeight: 700 }}>👑 Owner</span>}
        </div>
        <div className="card"><h3>Username</h3>
          <div className="row"><input style={{ flex: 1 }} value={username} onChange={(e) => setUsername(e.target.value)} />
            <button className="btn" disabled={username === a.profile?.username || username.length < 3} onClick={async () => { if (await a.changeUsername(username)) setNote("Username updated."); }}>Save</button></div></div>
        <div className="card"><h3>Email</h3>
          <div className="row"><input style={{ flex: 1 }} placeholder="New email" value={newEmail} onChange={(e) => setNewEmail(e.target.value)} />
            <input type="password" placeholder="Password" value={emailPw} onChange={(e) => setEmailPw(e.target.value)} style={{ width: 140 }} />
            <button className="btn" disabled={!newEmail || !emailPw} onClick={async () => { if (await a.changeEmail(newEmail, emailPw)) { setNote("Email updated."); setNewEmail(""); setEmailPw(""); } }}>Change</button></div></div>
        <div className="card"><h3>Password</h3>
          <input type="password" placeholder="Current password" value={cur} onChange={(e) => setCur(e.target.value)} style={{ width: "100%", marginBottom: 8 }} />
          <div className="row"><input type="password" placeholder="New password" value={pw} onChange={(e) => setPw(e.target.value)} style={{ flex: 1 }} />
            <input type="password" placeholder="Repeat new password" value={pw2} onChange={(e) => setPw2(e.target.value)} style={{ flex: 1 }} />
            <button className="btn" disabled={!cur || !pw} onClick={async () => {
              if (pw !== pw2) { a.setMessage("The new passwords don't match."); return; }
              if (await a.changePassword(cur, pw)) { setNote("Password changed."); setCur(""); setPw(""); setPw2(""); }
            }}>Change</button></div></div>
        <div className="card row"><span>{a.syncError ? "⚠️" : "☁️"}</span>
          <div style={{ flex: 1 }}><div>{a.syncError ?? (a.lastSync ? `Synced at ${a.lastSync.toTimeString().slice(0, 5)}` : "Your data is backed up to your account")}</div>
            <div className="small muted">Everything is also kept on this computer, so Orbit works offline.</div></div>
          <button className="btn" disabled={a.syncing} onClick={a.upload}>{a.syncing ? "Syncing…" : "Sync now"}</button></div>
        {a.message && <div style={{ color: "#ef4444" }}>⚠ {a.message}</div>}
        {note && <div style={{ color: "#22C55E" }}>✓ {note}</div>}
        <div className="row"><button className="btn danger" onClick={async () => { await a.signOut(); onClose(); }}>Log out</button><span className="spacer" /><button className="btn primary" onClick={onClose}>Done</button></div>
      </div>
    </Modal>
  );
}

/** The owner's admin panel (right side). The server refuses these calls for anyone else. */
export function AdminPanel({ onClose }: { onClose: () => void }) {
  const a = useAccount();
  const [giftNote, setGiftNote] = useState<string | null>(null);
  const pending = a.users.filter((u) => !u.approved), members = a.users.filter((u) => u.approved);
  const ago = (s?: string | null) => (s ? new Date(s).toLocaleString() : "—");
  return (
    <aside className="admin-panel">
      <div className="row"><b style={{ color: "#F97316", fontSize: 18 }}>👑 Admin</b><span className="spacer" />
        <button className="icon-btn" title="Refresh" onClick={a.loadUsers}>↻</button><button className="icon-btn" onClick={onClose}>✕</button></div>
      <div className="small muted">Only you see this panel. {members.length} members · {pending.length} waiting</div>
      <div className="small" style={{ fontWeight: 800, letterSpacing: 1, color: "var(--faint)", marginTop: 8 }}>WAITING FOR APPROVAL</div>
      {!pending.length && <div className="small muted">No one is waiting.</div>}
      {pending.map((u) => (
        <div key={u.id} className="card" style={{ background: "rgba(249,115,22,.12)", padding: 12 }}>
          <b>@{u.username ?? u.name}</b><div className="small muted">{u.email ?? "—"}</div><div className="small muted">Signed up {ago(u.requested_at)}</div>
          <div className="row" style={{ marginTop: 6 }}>
            <button className="btn small primary" style={{ background: "#16A34A" }} onClick={() => a.approve(u.id)}>✓ Approve</button>
            <button className="btn small danger" onClick={() => confirm(`Reject @${u.username ?? u.name}? Their profile is removed.`) && a.reject(u.id)}>✕ Reject</button>
          </div>
        </div>
      ))}
      <div className="small" style={{ fontWeight: 800, letterSpacing: 1, color: "var(--faint)", marginTop: 8 }}>MEMBERS</div>
      {members.map((u) => (
        <div key={u.id} className="list-row" style={{ alignItems: "flex-start" }}>
          <div style={{ flex: 1 }}>
            <b>@{u.username ?? u.name}</b> {u.is_admin && <span style={{ color: "#F97316" }}>👑</span>}
            <div className="small muted">{u.email ?? "no email yet"}</div>
            <div className="small" style={{ color: "var(--faint)" }}>Backup: {ago(u.last_backup)} · Studied: {u.last_studied ?? "—"}</div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <button className="btn small" onClick={async () => {
              const v = prompt(`How many rockets for @${u.username ?? u.name}? (negative takes them back)`, "100");
              const n = Math.round(Number(v));
              if (v && n && await a.giftRockets(u.id, n)) setGiftNote(`Sent ${n} 🚀 to @${u.username ?? u.name}.`);
            }}>🚀 Give rockets</button>
            {!u.is_admin && <>
            <button className="btn small" onClick={async () => { const p = await a.resetPassword(u.id); if (p) prompt(`New password for @${u.username ?? u.name}. Send it to them privately — they can change it in their profile.`, p); }}>Reset password</button>
            <button className="btn small danger" onClick={() => confirm(`Remove @${u.username ?? u.name}? Their profile, friendships and backup are removed.`) && a.reject(u.id)}>Remove</button>
            </>}
          </div>
        </div>
      ))}
      {giftNote && <div className="small" style={{ color: "#22C55E" }}>{giftNote}</div>}
      {a.message && <div className="small" style={{ color: "#ef4444" }}>{a.message}</div>}
    </aside>
  );
}
