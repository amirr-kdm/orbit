// The notification bell (top right): everything the app wants to tell you, with an unread count and a small card that slides in.
// Same idea as the Mac app's Inbox. Notices are kept on this computer.
import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { notify } from "./account";

export type NoticeKind = "gift" | "challenge" | "group" | "boss" | "update" | "info";
export interface Notice { id: string; title: string; body: string; date: number; kind: NoticeKind; read: boolean; route?: string; target?: string }
export const KIND_ICON: Record<NoticeKind, string> = { gift: "🎁", challenge: "🏁", group: "👥", boss: "💥", update: "⬇️", info: "🔔" };
export const KIND_COLOR: Record<NoticeKind, string> = { gift: "#F97316", challenge: "#EC4899", group: "#A855F7", boss: "#EF4444", update: "#3B82F6", info: "#6B7280" };

interface Inbox {
  items: Notice[]; unread: number; toast: Notice | null;
  post: (n: { id: string; title: string; body: string; kind?: NoticeKind; route?: string; target?: string; system?: boolean }) => void;
  markRead: (id: string) => void; markAllRead: () => void; clear: () => void; dismissToast: () => void;
}
const Ctx = createContext<Inbox | null>(null);
const KEY = "orbit-inbox";

export function InboxProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<Notice[]>(() => { try { return JSON.parse(localStorage.getItem(KEY) ?? "[]"); } catch { return []; } });
  const [toast, setToast] = useState<Notice | null>(null);
  const ref = useRef(items); ref.current = items;
  // ids already shown once: clearing the bell (or old ones dropping off) must never bring the same thing back
  const seen = useRef<Set<string>>(new Set([...(() => { try { return JSON.parse(localStorage.getItem("orbit-inbox-seen") ?? "[]") as string[]; } catch { return []; } })(), ...items.map((x) => x.id)]));
  const timer = useRef<number>();
  const save = (l: Notice[]) => { setItems(l); ref.current = l; try { localStorage.setItem(KEY, JSON.stringify(l)); } catch { /* full */ } };

  const post: Inbox["post"] = useCallback((n) => {
    if (seen.current.has(n.id) || ref.current.some((x) => x.id === n.id)) return;
    seen.current.add(n.id);
    try { localStorage.setItem("orbit-inbox-seen", JSON.stringify([...seen.current].slice(-600))); } catch { /* full */ }
    const item: Notice = { id: n.id, title: n.title, body: n.body, kind: n.kind ?? "info", date: Date.now(), read: false, route: n.route, target: n.target };
    save([item, ...ref.current].slice(0, 60));
    setToast(item);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast((t) => (t?.id === item.id ? null : t)), 6000);
    if (n.system !== false) notify(n.title, n.body);
  }, []);

  const value = useMemo<Inbox>(() => ({
    items, unread: items.filter((x) => !x.read).length, toast, post,
    markRead: (id) => { if (ref.current.some((x) => x.id === id && !x.read)) save(ref.current.map((x) => (x.id === id ? { ...x, read: true } : x))); },
    markAllRead: () => save(ref.current.map((x) => ({ ...x, read: true }))),
    clear: () => { save([]); setToast(null); },
    dismissToast: () => setToast(null),
  }), [items, toast, post]);
  useEffect(() => () => window.clearTimeout(timer.current), []);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useInbox(): Inbox {
  const c = useContext(Ctx);
  if (!c) throw new Error("InboxProvider missing");
  return c;
}

const ago = (t: number) => { const m = Math.max(0, Math.round((Date.now() - t) / 60000)); return m < 1 ? "now" : m < 60 ? `${m}m` : m < 1440 ? `${Math.round(m / 60)}h` : `${Math.round(m / 1440)}d`; };

function Row({ n, onOpen }: { n: Notice; onOpen: (n: Notice) => void }) {
  const inbox = useInbox();
  const t = useRef<number>();
  return (
    <button className="notice-row" style={{ background: n.read ? undefined : "color-mix(in srgb, var(--accent) 10%, transparent)" }}
      onClick={() => onOpen(n)}
      // resting the mouse on a new one for a moment reads it
      onMouseEnter={() => { if (!n.read) t.current = window.setTimeout(() => inbox.markRead(n.id), 450); }}
      onMouseLeave={() => window.clearTimeout(t.current)}>
      <span className="notice-ico" style={{ background: KIND_COLOR[n.kind] }}>{KIND_ICON[n.kind]}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="row"><b style={{ fontWeight: n.read ? 500 : 800, flex: 1 }}>{n.title}</b><span className="small muted">{ago(n.date)}</span></div>
        <div className="small muted">{n.body}</div>
      </div>
      {!n.read && <span style={{ width: 8, height: 8, borderRadius: 99, background: "var(--accent)", marginTop: 6 }} />}
    </button>
  );
}

/** Bell with the unread count on its corner; opens a small list under it */
export function Bell({ onOpenNotice }: { onOpenNotice: (n: Notice) => void }) {
  const inbox = useInbox();
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const down = (e: MouseEvent) => { if (!box.current?.contains(e.target as Node)) setOpen(false); };
    window.addEventListener("mousedown", down); return () => window.removeEventListener("mousedown", down);
  }, [open]);
  return (
    <div ref={box} style={{ position: "relative" }}>
      <button className="icon-btn" style={{ position: "relative", fontSize: 17 }} title={inbox.unread ? `${inbox.unread} unread` : "Notifications"} onClick={() => setOpen((v) => !v)}>
        🔔{inbox.unread > 0 && <span className="bell-count">{inbox.unread > 99 ? "99+" : inbox.unread}</span>}
      </button>
      {open && (
        <div className="notice-pop">
          <div className="row" style={{ padding: "10px 14px", borderBottom: "1px solid var(--line)" }}>
            <b>Notifications</b>
            {inbox.unread > 0 && <span className="small" style={{ background: "#ef4444", color: "white", borderRadius: 99, padding: "1px 7px", fontWeight: 800 }}>{inbox.unread} new</span>}
            <span className="spacer" />
            {inbox.unread > 0 && <button className="btn small" onClick={inbox.markAllRead}>Mark all read</button>}
            {inbox.items.length > 0 && <button className="icon-btn" title="Clear all" onClick={inbox.clear}>🗑</button>}
          </div>
          {!inbox.items.length ? <div className="muted" style={{ textAlign: "center", padding: "34px 14px" }}>🔕<br /><b>You're all caught up</b><br /><span className="small">New challenges, gifts and news show up here.</span></div>
            : <div style={{ maxHeight: 380, overflowY: "auto" }}>{inbox.items.map((n) => <Row key={n.id} n={n} onOpen={(x) => { inbox.markRead(x.id); setOpen(false); onOpenNotice(x); }} />)}</div>}
        </div>
      )}
    </div>
  );
}

/** The card that slides in at the top right when something new arrives */
export function Toast({ onOpenNotice }: { onOpenNotice: (n: Notice) => void }) {
  const inbox = useInbox();
  const n = inbox.toast;
  if (!n) return null;
  return (
    <div className="notice-toast" key={n.id} style={{ borderColor: KIND_COLOR[n.kind] + "73" }} onClick={() => { inbox.markRead(n.id); inbox.dismissToast(); onOpenNotice(n); }}>
      <span className="notice-ico" style={{ background: KIND_COLOR[n.kind], width: 38, height: 38 }}>{KIND_ICON[n.kind]}</span>
      <div style={{ flex: 1, minWidth: 0 }}><b>{n.title}</b><div className="small muted">{n.body}</div></div>
      <button className="icon-btn" onClick={(e) => { e.stopPropagation(); inbox.dismissToast(); }}>✕</button>
    </div>
  );
}
