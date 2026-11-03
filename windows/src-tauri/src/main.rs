#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;
use tauri::Manager;
use tauri_plugin_notification::NotificationExt;

/// Which alarm is the current one: scheduling or cancelling bumps it, so an older alarm that wakes up later stays quiet
static ALARM: AtomicU64 = AtomicU64::new(0);

/// A Pomodoro alarm: after `seconds` show a system notification. It lives in a thread of its own, so it still goes off on time
/// when the window is minimised or hidden (the web page's timers are slowed right down then).
#[tauri::command]
fn schedule_alarm(app: tauri::AppHandle, seconds: u64, title: String, body: String) {
    let mine = ALARM.fetch_add(1, Ordering::SeqCst) + 1;
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(seconds));
        // (no toast when Orbit is the window in front: the app plays its sound itself)
        let in_front = app.get_webview_window("main").and_then(|w| w.is_focused().ok()).unwrap_or(false);
        if ALARM.load(Ordering::SeqCst) == mine && !in_front {
            let _ = app.notification().builder().title(title).body(body).show();
        }
    });
}

#[tauri::command]
fn cancel_alarm() {
    ALARM.fetch_add(1, Ordering::SeqCst);
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![schedule_alarm, cancel_alarm])
        .run(tauri::generate_context!())
        .expect("error while running Orbit");
}
