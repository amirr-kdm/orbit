import React from "react";
import ReactDOM from "react-dom/client";
import "./styles.css";
import App from "./App";
import { StoreProvider } from "./lib/store";
import { FriendsProvider } from "./lib/friends";
import { TimerProvider } from "./lib/timer";
import { registerPicture } from "./lib/planets";
import ufo from "./assets/ufo.png";
import satellite from "./assets/satellite.png";
import meteor from "./assets/meteor.png";

registerPicture("ufo", ufo);
registerPicture("satellite", satellite);
registerPicture("meteor", meteor);

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <StoreProvider>
      <FriendsProvider>
        <TimerProvider>
          <App />
        </TimerProvider>
      </FriendsProvider>
    </StoreProvider>
  </React.StrictMode>,
);
