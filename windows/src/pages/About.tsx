// About Orbit: who made it, how to reach them, the news channel, the challenges group and the project — same design as the Mac app
import { useState } from "react";
import { Modal } from "../components";
import { APP_VERSION } from "../lib/updates";
import iconUrl from "../icon.png";
import telegram from "../assets/telegram.png";
import github from "../assets/github.png";
import linkedin from "../assets/linkedin.png";
import channel from "../assets/channel.png";
import flag from "../assets/flag.png";

export default function About({ onClose }: { onClose: () => void }) {
  const [copied, setCopied] = useState<string | null>(null);
  // The app can't open a browser itself: a click copies the link to paste in the browser
  const open = async (url: string) => {
    try { await navigator.clipboard.writeText(url); setCopied(url); setTimeout(() => setCopied((c) => (c === url ? null : c)), 2000); }
    catch { prompt("Open this link in your browser:", url); }
  };
  const link = (img: string, title: string, handle: string, url: string) => (
    <button key={url} onClick={() => open(url)} title={url}
      style={{ display: "flex", alignItems: "center", width: "100%", gap: 12, padding: 10, borderRadius: 12, border: "none", textAlign: "left", cursor: "pointer", color: "inherit",
        background: "color-mix(in srgb, var(--text) 4%, transparent)", font: "inherit" }}>
      <img src={img} alt="" style={{ width: 34, height: 34, borderRadius: 9, objectFit: "cover", flexShrink: 0 }} />
      <span style={{ flex: 1, minWidth: 0 }}><b>{title}</b>
        <div className="small muted" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{copied === url ? "Link copied — paste it in your browser" : handle}</div></span>
      <span className="muted">↗</span>
    </button>
  );
  const card = (title: string, text: string, children: React.ReactNode, name?: string) => (
    <div style={{ padding: 14, borderRadius: 16, background: "var(--card2)", border: "1px solid var(--line)", display: "flex", flexDirection: "column", gap: 6 }}>
      <div className="small muted" style={{ fontWeight: 900, letterSpacing: 1.5 }}>{title}</div>
      {name && <div style={{ fontSize: 20, fontWeight: 700 }}>{name}</div>}
      <div className="muted">{text}</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 4 }}>{children}</div>
    </div>
  );
  return (
    <Modal onClose={onClose} width={460}>
      <div style={{ display: "flex", flexDirection: "column", gap: 14, maxHeight: "78vh", overflowY: "auto", margin: -4, padding: 4 }}>
        <div style={{ textAlign: "center", display: "flex", flexDirection: "column", alignItems: "center", gap: 8, paddingTop: 8 }}>
          <img src={iconUrl} alt="" style={{ width: 84, height: 84, borderRadius: 18, boxShadow: "0 5px 14px rgba(168,85,247,.4)" }} />
          <div style={{ fontSize: 28, fontWeight: 900 }}>Orbit</div>
          <div className="muted">Plan your week, study with focus, and watch your galaxy grow.</div>
          <div className="small" style={{ opacity: 0.5 }}>Version {APP_VERSION}</div>
        </div>
        {card("DESIGNED & BUILT BY", "Ideas, feedback or a bug? Message me — I read everything.", <>
          {link(telegram, "Telegram", "@amirr_kdm", "https://t.me/amirr_kdm")}
          {link(github, "GitHub", "amirr-kdm", "https://github.com/amirr-kdm")}
          {link(linkedin, "LinkedIn", "www.linkedin.com/in/amirreza-khadempir/", "https://www.linkedin.com/in/amirreza-khadempir/")}
        </>, "Amirreza Khadempir")}
        {card("NEWS & UPDATES", "Join the Orbit channel on Telegram for new features, updates and tips. (The app also tells you when a new version is out.)",
          link(channel, "Orbit channel", "@orbitstudyplanner", "https://t.me/orbitstudyplanner"))}
        {card("ORBIT CHALLENGES 🚩", "The Orbiters' Telegram group: make friends with other Orbiters and plan challenges together.",
          link(flag, "Orbit Challenges", "Join the group on Telegram", "https://t.me/+mgr1bVSj1xwxMmFk"))}
        {card("OPEN SOURCE", "Orbit is free and open source (MIT). Downloads for Mac and Windows, the code and release notes are on GitHub.",
          link(github, "Orbit on GitHub", "github.com/amirr-kdm/orbit", "https://github.com/amirr-kdm/orbit"))}
        <div className="row"><span className="small" style={{ opacity: 0.5 }}>Made with ☕️ and a lot of study hours.</span><span className="spacer" /><button className="btn primary" onClick={onClose}>Done</button></div>
      </div>
    </Modal>
  );
}
