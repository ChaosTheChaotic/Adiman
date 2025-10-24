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

#[derive(Clone)]
pub enum CurrentSongUpdate {
    NoChange,
    SetToNone,
    SetToSome(SongMetadata),
}

pub struct ValueStoreUpdate {
    pub music_folder: Option<String>,
    pub current_song: CurrentSongUpdate,
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

impl ValueStore {
    pub fn new() -> Self {
        Self {
            ..Default::default()
        }
    }
    
    pub fn update_music_folder(&mut self, folder: String) -> Result<(), String> {
        let fpbuf: PathBuf = PathBuf::from(&folder);
        if fpbuf.exists() && fpbuf.is_dir() {
            self.music_folder = folder;
            Ok(())
        } else {
            Err("The provided folder is not a folder or does not exist".to_string())
        }
    }
    
    #[frb(ignore)]
    pub fn apply_update(&mut self, update: ValueStoreUpdate) -> Result<(), String> {
        if let Some(folder) = update.music_folder {
            self.update_music_folder(folder)?;
        }
        
        match update.current_song {
            CurrentSongUpdate::NoChange => {},
            CurrentSongUpdate::SetToNone => {
                self.current_song = None;
            },
            CurrentSongUpdate::SetToSome(song) => {
                self.current_song = Some(song);
            }
        }
        
        Ok(())
    }
}

#[frb(opaque)]
pub struct ValueStoreUpdater {
    pub music_folder: Option<String>,
    pub current_song: CurrentSongUpdate,
}

impl ValueStoreUpdater {
    pub fn new() -> Self {
        Self {
            music_folder: None,
            current_song: CurrentSongUpdate::NoChange,
        }
    }
    
    #[frb]
    pub fn set_music_folder(&mut self, folder: String) -> &mut Self {
        self.music_folder = Some(folder);
        self
    }
    
    #[frb]
    pub fn set_current_song(&mut self, song: SongMetadata) -> &mut Self {
        self.current_song = CurrentSongUpdate::SetToSome(song);
        self
    }
    
    #[frb]
    pub fn clear_current_song(&mut self) -> &mut Self {
        self.current_song = CurrentSongUpdate::SetToNone;
        self
    }
    
    #[frb]
    pub fn apply(self) -> Result<(), String> {
        let update = ValueStoreUpdate {
            music_folder: self.music_folder,
            current_song: self.current_song,
        };
        update_value_store(update)
    }
}

pub fn init_value_store() -> Result<(), String> {
    let mut store = VALUE_STORE.write().map_err(|e| {
        STORE_STATE.store(false, Ordering::SeqCst);
        format!(
            "Failed to acquire write lock to global static VALUE_STORE: {}",
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
pub fn acquire_read_lock() -> Result<std::sync::RwLockReadGuard<'static, Option<ValueStore>>, String> {
    let store = VALUE_STORE.read().map_err(|e| {
        STORE_STATE.store(false, Ordering::SeqCst);
        format!("Failed to acquire read lock to VALUE_STORE: {}", e)
    })?;
    Ok(store)
}

pub fn update_value_store(update: ValueStoreUpdate) -> Result<(), String> {
    let mut store = VALUE_STORE.write().map_err(|e| {
        STORE_STATE.store(false, Ordering::SeqCst);
        format!("Failed to acquire write lock on VALUE_STORE: {}", e)
    })?;
    
    if store.is_none() { 
        STORE_STATE.store(false, Ordering::SeqCst); 
        return Err("The VALUE_STORE is None".to_string());
    }
    
    store.as_mut().unwrap().apply_update(update)
}

pub fn update_store() -> ValueStoreUpdater {
    ValueStoreUpdater::new()
}
