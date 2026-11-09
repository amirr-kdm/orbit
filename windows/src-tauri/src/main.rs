#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod media;
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

/// Seconds since the last key press or mouse move anywhere in Windows (0 if unknown)
#[tauri::command]
fn idle_seconds() -> u64 {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::System::SystemInformation::GetTickCount;
        use windows_sys::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
        let mut info = LASTINPUTINFO { cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32, dwTime: 0 };
        if GetLastInputInfo(&mut info) != 0 {
            return (GetTickCount().wrapping_sub(info.dwTime) / 1000) as u64;
        }
    }
    0
}

/// File name (lower case, e.g. "telegram.exe") of the program whose window is in front; empty if unknown
#[tauri::command]
fn foreground_app() -> String {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::Foundation::CloseHandle;
        use windows_sys::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION};
        use windows_sys::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
        let hwnd = GetForegroundWindow();
        if hwnd.is_null() { return String::new(); }
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, &mut pid);
        if pid == 0 { return String::new(); }
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h.is_null() { return String::new(); }
        let mut buf = [0u16; 520];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, 0, buf.as_mut_ptr(), &mut len);
        CloseHandle(h);
        if ok != 0 {
            let path = String::from_utf16_lossy(&buf[..len as usize]);
            return path.rsplit('\\').next().unwrap_or("").to_lowercase();
        }
    }
    String::new()
}

const ISLAND_W: f64 = 274.0;
const ISLAND_H: f64 = 32.0;

/// Put the island (a small always-on-top window at the top centre of the screen) on or off
#[tauri::command]
fn island_show(app: tauri::AppHandle, show: bool) {
    if let Some(w) = app.get_webview_window("island") {
        if !show { let _ = w.close(); }
        return;
    }
    if !show { return; }
    let built = tauri::WebviewWindowBuilder::new(&app, "island", tauri::WebviewUrl::App("index.html?island=1".into()))
        .title("Orbit island")
        .inner_size(ISLAND_W, ISLAND_H)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .shadow(false)
        .focused(false)
        .build();
    if let Ok(w) = built { place_island(&w, ISLAND_W); }
}

/// Keep the island centred at the top while its size changes (hover opens it, leaving closes it)
fn place_island(w: &tauri::WebviewWindow, width: f64) {
    if let Ok(Some(mon)) = w.primary_monitor() {
        let scale = mon.scale_factor();
        let mw = mon.size().width as f64 / scale;
        let _ = w.set_position(tauri::LogicalPosition::new(((mw - width) / 2.0).max(0.0), 0.0));
    }
}

#[tauri::command]
fn island_resize(app: tauri::AppHandle, width: f64, height: f64) {
    if let Some(w) = app.get_webview_window("island") {
        let _ = w.set_size(tauri::LogicalSize::new(width.clamp(120.0, 600.0), height.clamp(24.0, 400.0)));
        place_island(&w, width.clamp(120.0, 600.0));
    }
}

/// Bring the main Orbit window to the front (from the island)
#[tauri::command]
fn open_main(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .setup(|app| { media::start(app.handle().clone()); Ok(()) })
        .on_window_event(|window, event| {
            // closing the main window quits Orbit, even while the island window is open
            if window.label() == "main" {
                if let tauri::WindowEvent::Destroyed = event { window.app_handle().exit(0); }
            }
        })
        .invoke_handler(tauri::generate_handler![schedule_alarm, cancel_alarm, idle_seconds, foreground_app, island_show, island_resize, open_main, media::media_current, media::media_command])
        .run(tauri::generate_context!())
        .expect("error while running Orbit");
}
