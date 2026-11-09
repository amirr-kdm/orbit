//! Now Playing for the island: whatever app plays music (Spotify, browsers, Apple Music…) shows up through the Windows media controls.
//! It never polls: Windows tells us when the session, the song or play/pause changes.

use serde::Serialize;
use tauri::{AppHandle, Emitter};

#[derive(Serialize, Clone, Default)]
pub struct MediaInfo {
    pub has_track: bool,
    pub title: String,
    pub artist: String,
    pub app: String,
    pub playing: bool,
    /// data URL of the cover (empty when the app gives none)
    pub art: String,
}

#[cfg(windows)]
mod imp {
    use super::*;
    use base64::Engine;
    use std::sync::Mutex;
    use windows::Foundation::TypedEventHandler;
    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSession as Session, GlobalSystemMediaTransportControlsSessionManager as Manager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
    };
    use windows::Storage::Streams::DataReader;

    fn art_of(props: &windows::Media::Control::GlobalSystemMediaTransportControlsSessionMediaProperties) -> String {
        (|| -> windows::core::Result<String> {
            let stream = props.Thumbnail()?.OpenReadAsync()?.get()?;
            let size = stream.Size()? as u32;
            if size == 0 || size > 4_000_000 { return Ok(String::new()); }
            let reader = DataReader::CreateDataReader(&stream.GetInputStreamAt(0)?)?;
            reader.LoadAsync(size)?.get()?;
            let mut buf = vec![0u8; size as usize];
            reader.ReadBytes(&mut buf)?;
            let mime = stream.ContentType()?.to_string();
            let mime = if mime.is_empty() { "image/jpeg".to_string() } else { mime };
            Ok(format!("data:{};base64,{}", mime, base64::engine::general_purpose::STANDARD.encode(buf)))
        })()
        .unwrap_or_default()
    }

    pub fn snapshot(mgr: &Manager) -> MediaInfo {
        (|| -> windows::core::Result<MediaInfo> {
            let s = mgr.GetCurrentSession()?;
            let props = s.TryGetMediaPropertiesAsync()?.get()?;
            let playing = s.GetPlaybackInfo()?.PlaybackStatus()? == Status::Playing;
            let title = props.Title()?.to_string();
            Ok(MediaInfo { has_track: !title.is_empty(), title, artist: props.Artist()?.to_string(),
                app: s.SourceAppUserModelId()?.to_string(), playing, art: art_of(&props) })
        })()
        .unwrap_or_default()
    }

    fn watch(app: &AppHandle, mgr: &Manager, s: &Session) {
        let (a1, m1) = (app.clone(), mgr.clone());
        let _ = s.MediaPropertiesChanged(&TypedEventHandler::new(move |_, _| { let _ = a1.emit("media-changed", snapshot(&m1)); Ok(()) }));
        let (a2, m2) = (app.clone(), mgr.clone());
        let _ = s.PlaybackInfoChanged(&TypedEventHandler::new(move |_, _| { let _ = a2.emit("media-changed", snapshot(&m2)); Ok(()) }));
    }

    static MANAGER: Mutex<Option<Manager>> = Mutex::new(None);

    pub fn start(app: AppHandle) {
        std::thread::spawn(move || {
            let Ok(op) = Manager::RequestAsync() else { return };
            let Ok(mgr) = op.get() else { return };
            *MANAGER.lock().unwrap() = Some(mgr.clone());
            if let Ok(s) = mgr.GetCurrentSession() { watch(&app, &mgr, &s); }
            let (a, m) = (app.clone(), mgr.clone());
            let _ = mgr.CurrentSessionChanged(&TypedEventHandler::new(move |_, _| {
                if let Ok(s) = m.GetCurrentSession() { watch(&a, &m, &s); }
                let _ = a.emit("media-changed", snapshot(&m));
                Ok(())
            }));
            let _ = app.emit("media-changed", snapshot(&mgr));
            // keep this thread (and so the handlers' owner) alive for the life of the app
            loop { std::thread::park(); }
        });
    }

    pub fn current() -> MediaInfo {
        MANAGER.lock().unwrap().as_ref().map(snapshot).unwrap_or_default()
    }

    pub fn command(cmd: &str) {
        let Some(mgr) = MANAGER.lock().unwrap().clone() else { return };
        let Ok(s) = mgr.GetCurrentSession() else { return };
        let _ = match cmd {
            "toggle" => s.TryTogglePlayPauseAsync().map(|_| ()),
            "next" => s.TrySkipNextAsync().map(|_| ()),
            "previous" => s.TrySkipPreviousAsync().map(|_| ()),
            _ => Ok(()),
        };
    }
}

#[cfg(windows)]
pub fn start(app: AppHandle) { imp::start(app) }
#[cfg(not(windows))]
pub fn start(_app: AppHandle) {}

#[tauri::command]
pub fn media_current() -> MediaInfo {
    #[cfg(windows)]
    { return imp::current(); }
    #[cfg(not(windows))]
    MediaInfo::default()
}

#[tauri::command]
pub fn media_command(cmd: String) {
    #[cfg(windows)]
    imp::command(&cmd);
    #[cfg(not(windows))]
    let _ = cmd;
}
