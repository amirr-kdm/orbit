import React from "react";
import ReactDOM from "react-dom/client";
import "./styles.css";
import App from "./App";
import { StoreProvider } from "./lib/store";
import { FriendsProvider } from "./lib/friends";
import { TimerProvider } from "./lib/timer";
import { AccountProvider } from "./lib/account";
import { ChallengesProvider } from "./lib/challenges";
import { FightClubProvider } from "./lib/fightclub";
import { InboxProvider } from "./lib/inbox";
import { GiftsProvider } from "./lib/gifts";
import { registerPicture } from "./lib/planets";
import ufo from "./assets/ufo.png";
import satellite from "./assets/satellite.png";
import meteor from "./assets/meteor.png";

registerPicture("ufo", ufo);
registerPicture("satellite", satellite);
registerPicture("meteor", meteor);
// Every other store picture in assets/ (s4_… and animated frames s4_name_0, _1, …)
for (const [path, url] of Object.entries(import.meta.glob(["./assets/s4_*.png", "./assets/s5_*.png", "./assets/lv_*.png", "./assets/pass_ship*.png"], { eager: true, import: "default" }))) {
  registerPicture(path.split("/").pop()!.replace(".png", ""), url as string);
}

// Cut-out illustrations (s6_…): personal art kept out of the repository (assets/local is git-ignored); missing files are simply skipped
for (const [path, url] of Object.entries(import.meta.glob("./assets/local/s6_*.png", { eager: true, import: "default" }))) {
  registerPicture(path.split("/").pop()!.replace(".png", ""), url as string);
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <InboxProvider><StoreProvider>
      <FriendsProvider>
        <AccountProvider>
          <ChallengesProvider><FightClubProvider><GiftsProvider>
            <TimerProvider>
              <App />
            </TimerProvider>
          </GiftsProvider></FightClubProvider></ChallengesProvider>
        </AccountProvider>
      </FriendsProvider>
    </StoreProvider></InboxProvider>
  </React.StrictMode>,
);
