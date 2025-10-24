use crate::api::music_handler::SongMetadata;
use flutter_rust_bridge::frb;
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        RwLock,
    },
};

// Represents the state of the store. Tells us if the store is in a usable state
pub static STORE_STATE: AtomicBool = AtomicBool::new(false);
// The actual value store
pub static VALUE_STORE: RwLock<Option<ValueStore>> = RwLock::new(None);

#[frb(ignore)]
#[derive(Clone)]
pub struct ValueStore {
    pub music_folder: String,
    pub current_song: Option<SongMetadata>,
}

impl Default for ValueStore {
    fn default() -> Self {
        Self {
            music_folder: PathBuf::from(std::env::var("HOME").unwrap_or("/home".to_string()))
                .join("Music")
                .to_string_lossy()
                .to_string(),
            current_song: None,
        }
    }
}

// This store will mainly be read by plugins and not by dart which is why I am not providing
// methods for dart to read this. This might happen in the future if I can get dart plugins working
// in the way I originally envisioned
impl ValueStore {
    // Initializes a new ValueStore with the default params
    pub fn new() -> Self {
        Self {
            ..Default::default()
        }
    }
    pub fn update_music_folder(&mut self, folder: String) -> Result<(), String> {
        let fpbuf: PathBuf = PathBuf::from(&folder);
        if fpbuf.exists() && fpbuf.is_dir() {
            self.music_folder = folder;
            return Ok(());
        } else {
            return Err("The provided folder is not a folder or does not exist".to_string());
        }
    }
    //pub fn get_music_folder(self) -> String {
    //    self.music_folder
    //}
    //pub fn set_current_song(&mut self, song: SongMetadata) {
    //    self.current_song = Some(song);
    //}
    //pub fn get_current_song(self) -> Option<SongMetadata> {
    //    self.current_song
    //}
}

pub fn init_value_store() -> Result<(), String> {
    let mut store = VALUE_STORE.write().map_err(|e| {
        STORE_STATE.store(false, Ordering::SeqCst);
        format!(
            "Failed to aquire write lock to global static VALUE_STORE: {}",
            e
        )
    })?;
    *store = Some(ValueStore::new());
    STORE_STATE.store(true, Ordering::SeqCst);
    Ok(())
}

#[frb(ignore)]
pub fn check_value_store_state() -> bool {
    let store_try = VALUE_STORE.read();
    if !store_try.is_ok() {
        STORE_STATE.store(false, Ordering::SeqCst);
        return false;
    }
    let store = store_try.unwrap();
    store.is_some()
}

#[frb(ignore)]
pub fn aquire_read_lock() -> Result<std::sync::RwLockReadGuard<'static, Option<ValueStore>>, String> {
    let store = VALUE_STORE.read().map_err(|e| {
        STORE_STATE.store(false, Ordering::SeqCst);
        format!("Failed to aquire read lock to VALUE_STORE: {}", e)
    })?;
    Ok(store)
}

pub fn update_music_folder(folder: String) -> Result<(), String> {
    let mut store = VALUE_STORE.write().map_err(|e| {
        STORE_STATE.store(false, Ordering::SeqCst);
        format!("Failed to aquire write lock on VALUE_STORE: {}", e)
    })?;
    if store.is_none() { STORE_STATE.store(false, Ordering::SeqCst); return Err(format!("The VALUE_STORE is None"))}
    store.as_mut().unwrap().update_music_folder(folder)
}
