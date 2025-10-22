use once_cell::sync::Lazy;
use std::{path::PathBuf, sync::Mutex};

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
