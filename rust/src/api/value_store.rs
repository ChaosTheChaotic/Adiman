use once_cell::sync::Lazy;
use std::{path::PathBuf, sync::Mutex};
use crate::api::music_handler::SongMetadata;

pub static MUSIC_FOLDER: Lazy<Mutex<String>> = Lazy::new(|| {
    Mutex::new(
        PathBuf::from(std::env::var("HOME").unwrap_or("/home".to_string()))
            .join("Music")
            .to_string_lossy()
            .to_string(),
    )
});

pub fn update_music_folder(f: String) {
    let mut g = MUSIC_FOLDER.lock().unwrap();
    *g = f;
}

pub static CURRENT_SONG: Lazy<Mutex<Option<SongMetadata>>> = Lazy::new(|| {
    Mutex::new(None)
});

pub fn update_current_song(s: SongMetadata) {
    let mut g = CURRENT_SONG.lock().unwrap();
    *g = Some(s);
}
