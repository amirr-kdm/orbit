import React from "react";
import ReactDOM from "react-dom/client";
import "./styles.css";
import App from "./App";
import { StoreProvider } from "./lib/store";
import { FriendsProvider } from "./lib/friends";
import { TimerProvider } from "./lib/timer";

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
