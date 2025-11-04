use crate::api::{music_handler::SongMetadata, utils::check_dir};
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
    pub plugins_enabled: bool,
    pub plugin_rw_dir: String,
    pub unsafe_apis: bool,
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
    pub plugins_enabled: Option<bool>,
    pub plugin_rw_dir: Option<String>,
    pub unsafe_apis: Option<bool>,
}

impl Default for ValueStore {
    fn default() -> Self {
        let home_dir: PathBuf = PathBuf::from(std::env::var("HOME").unwrap_or("/home".to_string()));
        Self {
            music_folder: home_dir.join("Music").to_string_lossy().to_string(),
            current_song: None,
            plugins_enabled: false,
            plugin_rw_dir: home_dir.join("AdiDir").to_string_lossy().to_string(),
            unsafe_apis: false,
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
        if check_dir(&folder) {
            self.music_folder = folder;
            Ok(())
        } else {
            Err("The provided folder is not a folder or does not exist".to_string())
        }
    }

    pub fn update_plugin_rw_dir(&mut self, folder: String) -> Result<(), String> {
        if check_dir(&folder) {
            self.plugin_rw_dir = folder;
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

        if let Some(pen) = update.plugins_enabled {
            self.plugins_enabled = pen;
        }

        if let Some(folder) = update.plugin_rw_dir {
            self.update_plugin_rw_dir(folder)?;
        }

        if let Some(uapis) = update.unsafe_apis {
            self.unsafe_apis = uapis;
        }

        match update.current_song {
            CurrentSongUpdate::NoChange => {}
            CurrentSongUpdate::SetToNone => {
                self.current_song = None;
            }
            CurrentSongUpdate::SetToSome(song) => {
                self.current_song = Some(song);
            }
        }

        Ok(())
    }
}

#[frb(opaque)]
#[derive(Clone)]
pub struct ValueStoreUpdater {
    pub music_folder: Option<String>,
    pub current_song: CurrentSongUpdate,
    pub plugins_enabled: Option<bool>,
    pub plugin_rw_dir: Option<String>,
    pub unsafe_apis: Option<bool>,
}

impl ValueStoreUpdater {
    pub fn new() -> Self {
        Self {
            music_folder: None,
            current_song: CurrentSongUpdate::NoChange,
            plugins_enabled: None,
            plugin_rw_dir: None,
            unsafe_apis: None,
        }
    }

    #[frb]
    pub fn set_music_folder(&mut self, folder: String) -> &mut Self {
        self.music_folder = Some(folder);
        self
    }

    #[frb]
    pub fn set_plugins_enabled(&mut self, val: bool) -> &mut Self {
        self.plugins_enabled = Some(val);
        self
    }

    #[frb]
    pub fn set_plugin_rw_dir(&mut self, folder: String) -> &mut Self {
        self.plugin_rw_dir = Some(folder);
        self
    }

    #[frb]
    pub fn set_unsafe_apis(&mut self, value: bool) -> &mut Self {
        self.unsafe_apis = Some(value);
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
            plugins_enabled: self.plugins_enabled,
            plugin_rw_dir: self.plugin_rw_dir,
            unsafe_apis: self.unsafe_apis,
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
pub fn acquire_read_lock() -> Result<std::sync::RwLockReadGuard<'static, Option<ValueStore>>, String>
{
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
