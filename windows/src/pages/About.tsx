// About Orbit: who made it, how to reach them, the news channel and the project — a small window like the Mac app's
import { useState } from "react";
import { Modal } from "../components";
import { APP_VERSION } from "../lib/updates";
import iconUrl from "../icon.png";
import linkedinUrl from "../assets/linkedin.png";

const LINKS = {
  telegram: "https://t.me/amirr_kdm", github: "https://github.com/amirr-kdm",
  linkedin: "https://www.linkedin.com/in/amirreza-khadempir/", channel: "https://t.me/orbitstudyplanner", group: "https://t.me/+mgr1bVSj1xwxMmFk", project: "https://github.com/amirr-kdm/orbit",
};

export default function About({ onClose }: { onClose: () => void }) {
  const [copied, setCopied] = useState<string | null>(null);
  // The app can't open a browser itself: a click copies the link to paste in the browser
  const open = async (url: string) => {
    try { await navigator.clipboard.writeText(url); setCopied(url); setTimeout(() => setCopied((c) => (c === url ? null : c)), 2000); }
    catch { prompt("Open this link in your browser:", url); }
  };
  const link = (icon: string, title: string, handle: string, url: string, tint: string) => (
    <button key={url} className="row" onClick={() => open(url)} title={url}
      style={{ width: "100%", gap: 12, padding: 10, borderRadius: 12, border: "none", textAlign: "left", cursor: "pointer", color: "inherit", background: "color-mix(in srgb, var(--text) 4%, transparent)" }}>
      {icon === "in" ? <img src={linkedinUrl} alt="" style={{ width: 34, height: 34, borderRadius: 9, objectFit: "cover", flexShrink: 0 }} />
        : <span style={{ width: 34, height: 34, borderRadius: 9, display: "grid", placeItems: "center", background: tint, color: "white", flexShrink: 0 }}>{icon}</span>}
      <span style={{ flex: 1 }}><b>{title}</b><div className="small muted">{copied === url ? "Link copied — paste it in your browser" : handle}</div></span>
      <span className="muted">↗</span>
    </button>
  );
  const card = (children: React.ReactNode) => (
    <div style={{ padding: 14, borderRadius: 16, background: "var(--card2)", border: "1px solid var(--line)", display: "flex", flexDirection: "column", gap: 6 }}>{children}</div>
  );
  const label = (t: string) => <div className="small muted" style={{ fontWeight: 900, letterSpacing: 1.5 }}>{t}</div>;
  return (
    <Modal onClose={onClose} width={460}>
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        <div className="row" style={{ gap: 14 }}>
          <img src={iconUrl} alt="" style={{ width: 64, height: 64, borderRadius: 14 }} />
          <div><div style={{ fontSize: 28, fontWeight: 900 }}>Orbit</div>
            <div className="muted">Plan your week, study with focus, and watch your galaxy grow.</div>
            <div className="small muted">Version {APP_VERSION}</div></div>
        </div>
        {card(<>{label("DESIGNED & BUILT BY")}<div style={{ fontSize: 20, fontWeight: 700 }}>Amirreza Khadempir</div>
          <div className="muted">Ideas, feedback or a bug? Message me — I read everything.</div>
          {link("✈️", "Telegram", "@amirr_kdm", LINKS.telegram, "#2AABEE")}
          {link("</>", "GitHub", "amirr-kdm", LINKS.github, "#6B7280")}
          {link("in", "LinkedIn", "linkedin.com/in/amirreza-khadempir", LINKS.linkedin, "#0A66C2")}</>)}
        {card(<>{label("NEWS & UPDATES")}<div className="muted">Join the Orbit channel on Telegram for new features, updates and tips. (The app also tells you when a new version is out.)</div>
          {link("📣", "Orbit channel", "@orbitstudyplanner", LINKS.channel, "#F97316")}</>)}
        {card(<>{label("ORBIT CHALLENGES 🚩")}<div className="muted">The Orbiters' Telegram group: make friends with other Orbiters and plan challenges together.</div>
          {link("🚩", "Orbit Challenges", "Join the group on Telegram", LINKS.group, "#EF4444")}</>)}
        {card(<>{label("OPEN SOURCE")}<div className="muted">Orbit is free and open source (MIT). Downloads for Mac and Windows, the code and release notes are on GitHub.</div>
          {link("⬇", "Orbit on GitHub", "github.com/amirr-kdm/orbit", LINKS.project, "#A855F7")}</>)}
        <div className="row"><span className="small muted">Made with ☕️ and a lot of study hours.</span><span className="spacer" /><button className="btn primary" onClick={onClose}>Done</button></div>
      </div>
    </Modal>
  );
}
