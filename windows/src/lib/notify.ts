// System notifications. In the Windows app (Tauri) they go through the plugin's toast; a plain browser uses the web Notification API
// (the Windows webview doesn't show those reliably, which is why the app never relies on them).

export const inTauri = () => typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

export async function ensureNotifyPermission(): Promise<boolean> {
  try {
    if (inTauri()) {
      const n = await import("@tauri-apps/plugin-notification");
      if (await n.isPermissionGranted()) return true;
      return (await n.requestPermission()) === "granted";
    }
    if (!("Notification" in window)) return false;
    if (Notification.permission === "default") await Notification.requestPermission();
    return Notification.permission === "granted";
  } catch { return false; }
}

/** Show a system notification when allowed (silently nothing otherwise: the in-app banners always show) */
export async function systemNotify(title: string, body: string) {
  try {
    if (!(await ensureNotifyPermission())) return;
    if (inTauri()) { (await import("@tauri-apps/plugin-notification")).sendNotification({ title, body }); return; }
    new Notification(title, { body });
  } catch { /* not supported */ }
}
