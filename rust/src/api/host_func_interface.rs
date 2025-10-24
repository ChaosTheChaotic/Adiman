use crate::api::{
    music_handler::get_cvol,
    utils::{fpre, validate_path},
    value_store::{acquire_read_lock, check_value_store_state},
};
use extism::{convert::Json, host_fn, FromBytes, Function, PluginBuilder, ToBytes, UserData, PTR};
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File},
    path::PathBuf,
};

#[frb(ignore)]
host_fn!(pprint(user_data: (); m: String) {
    println!("[PLUGIN LOG]: {m}");
    Ok(())
});

#[frb(ignore)]
host_fn!(get_music_folder() -> String {
    if !check_value_store_state() {
        return Ok(format!("ERR: Value store state was false"))
    }
    match acquire_read_lock() {
        Ok(guard) => {
            // Use as_ref() to get Option<&ValueStore> instead of moving
            if let Some(state) = guard.as_ref() {
                Ok(state.music_folder.clone())
            } else {
                Ok("ERR: ValueStore not initialized".to_string())
            }
        }
        Err(e) => Ok(format!("ERR: Failed to aquire read lock: {}", e)),
    }
});

#[frb(ignore)]
host_fn!(get_current_song() -> Option<crate::api::music_handler::SongMetadata> {
    if !check_value_store_state() {
        return Ok(None);
    }
    match acquire_read_lock() {
        Ok(guard) => {
            if let Some(state) = guard.as_ref() {
                Ok(state.current_song.clone())
            } else {
                Ok(None)
            }
        }
        Err(_) => Ok(None)
    }
});

#[frb(ignore)]
host_fn!(get_store_state() -> bool {
    Ok(check_value_store_state())
});

#[frb(ignore)]
host_fn!(create_file(user_data: (); name: String, content: Option<String>) -> bool {
    if !validate_path(&name) {
        return Ok(false);
    }
    if content.is_none() {
        File::create(name)?;
    } else {
        fs::write(name, content.unwrap())?;
    }
    Ok(true)
});

#[frb(ignore)]
host_fn!(check_entity_exists(user_data: (); name: String) -> bool {
    if !validate_path(&name) {
        return Ok(false);
    }
    Ok(PathBuf::from(name).exists())
});

#[frb(ignore)]
host_fn!(entity_is_dir(user_data: (); name: String) -> bool {
    if !validate_path(&name) {
        return Ok(false);
    }
    Ok(PathBuf::from(name).is_dir())
});

#[frb(ignore)]
host_fn!(write_file(user_data: (); name: String, content: String) -> bool {
    if !validate_path(&name) {
        return Ok(false);
    }
    fs::write(name, content)?;
    Ok(true)
});

#[frb(ignore)]
host_fn!(delete_file(user_data: (); name: String) -> bool {
    if !validate_path(&name) {
        return Ok(false);
    }
    fs::remove_file(name)?;
    Ok(true)
});

#[frb(ignore)]
host_fn!(create_dir(user_data: (); name: String) -> bool {
    if !validate_path(&name) {
        return Ok(false);
    }
    fs::create_dir_all(name)?;
    Ok(true)
});

#[frb(ignore)]
host_fn!(read_file(user_data: (); name: String) -> String {
    if !validate_path(&name) {
        return Ok("ERR: Invalid path".to_string());
    }
    match fs::read_to_string(name) {
        Ok(content) => Ok(content),
        Err(e) => Ok(format!("ERR: {}", e)),
    }
});

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub enum EntityType {
    File,
    Directory,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct DirEntity {
    pub name: String,
    pub entity_type: EntityType,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct DirEntities {
    pub contents: Vec<DirEntity>,
}

#[frb(ignore)]
host_fn!(list_dir(user_data: (); path: String) -> DirEntities {
    if !validate_path(&path) {
        return Ok(DirEntities { contents: Vec::new() });
    }
    match fs::read_dir(path) {
        Ok(entries) => {
            let mut results: Vec<DirEntity> = Vec::new();
            for entry in entries {
                if let Ok(entry) = entry {
                    if let Some(file_name) = entry.file_name().to_str() {
                        if let Ok(file_type) = entry.file_type() {
                            let entity_type = match () {
                                _ if file_type.is_dir() => EntityType::Directory,
                                _ => EntityType::File,
                            };
                            results.push(DirEntity {
                                name: file_name.to_string(),
                                entity_type,
                            })
                        }
                    }
                }
            }
            Ok(DirEntities { contents: results })
        }
        Err(_) => Ok(DirEntities { contents: Vec::new() }),
    }
});

#[frb(ignore)]
host_fn!(join_paths(user_data: (); base: String, segment: String) -> String {
    let path = PathBuf::from(base).join(segment);
    Ok(path.to_string_lossy().to_string())
});

#[frb(ignore)]
host_fn!(file_size(user_data: (); name: String) -> u64 {
    if !validate_path(&name) {
        return Ok(0);
    }
    match fs::metadata(name) {
        Ok(metadata) => Ok(metadata.len()),
        Err(_) => Ok(0),
    }
});

#[frb(ignore)]
host_fn!(get_file_extension_std(user_data: (); path: String) -> String {
    Ok(PathBuf::from(path)
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_string())
});

#[frb(ignore)]
host_fn!(get_file_extension_nightly(user_data: (); path: String) -> String {
    Ok(fpre(&PathBuf::from(path).as_path()).unwrap_or_default().to_string_lossy().to_string())
});

#[frb(ignore)]
host_fn!(rename_file(user_data: (); old: String, new: String) -> bool {
    if !(validate_path(&old) || validate_path(&new)) {
        return Ok(false);
    }
    fs::rename(old, new)?;
    Ok(true)
});

#[frb(ignore)]
host_fn!(copy_file(user_data: (); from: String, to: String) -> bool {
    if !(validate_path(&from) || validate_path(&to)) {
        return Ok(false)
    }
    fs::copy(from, to)?;
    Ok(true)
});

#[frb(ignore)]
host_fn!(get_arch() -> &str {
    Ok(std::env::consts::ARCH)
});

#[frb(ignore)]
host_fn!(get_time() -> i64 {
    Ok(chrono::Utc::now().timestamp())
});

#[frb(ignore)]
host_fn!(get_current_vol() -> f32 {
    Ok(get_cvol())
});

// A macro to decide how to format the functions for me
macro_rules! get_fn_signature {
    // With params and return
    (($func:ident) fn $name:ident($($param:tt)+) -> $ret:ty) => {
        Function::new(stringify!($name), [PTR], [PTR], UserData::new(()), $func)
    };

    // With return only
    (($func:ident) fn $name:ident() -> $ret:ty) => {
        Function::new(stringify!($name), [], [PTR], UserData::new(()), $func)
    };

    // With params only
    (($func:ident) fn $name:ident($($param:tt)+)) => {
        Function::new(stringify!($name), [PTR], [], UserData::new(()), $func)
    };

    // No params or return
    (($func:ident) fn $name:ident()) => {
        Function::new(stringify!($name), [], [], UserData::new(()), $func)
    };
}

// The main macro
macro_rules! generic_func {
    ($func:ident($($input:tt)*) -> $ret:ty) => {
        get_fn_signature!(($func) fn $func($($input)*) -> $ret)
    };

    ($func:ident($($input:tt)*)) => {
        get_fn_signature!(($func) fn $func($($input)*))
    };

    ($func:ident) => {
        get_fn_signature!(($func) fn $func())
    };
}

#[frb(ignore)]
pub fn add_functions(b: PluginBuilder) -> PluginBuilder {
    let f = vec![
        generic_func!(pprint(text: &str)),
        generic_func!(get_music_folder() -> &str),
        generic_func!(get_store_state() -> &str),
        generic_func!(get_current_song() -> &str),
        generic_func!(create_file(path: &str) -> bool),
        generic_func!(check_entity_exists(path: &str) -> bool),
        generic_func!(entity_is_dir(path: &str) -> bool),
        generic_func!(write_file(path: &str, content: &str) -> bool),
        generic_func!(delete_file(path: &str) -> bool),
        generic_func!(create_dir(path: &str) -> bool),
        generic_func!(list_dir(path: &str) -> &str),
        generic_func!(join_paths(path1: &str, path2: &str) -> &str),
        generic_func!(file_size(path: &str) -> u64),
        generic_func!(rename_file(old: String, new: String) -> bool),
        generic_func!(copy_file(from: String, to: String) -> bool),
        generic_func!(get_arch() -> &str),
        generic_func!(get_time() -> &str),
        generic_func!(get_file_extension_std(path: &str) -> &str),
        generic_func!(get_file_extension_nightly(path: &str) -> &str),
        generic_func!(get_current_vol() -> f32),
    ];
    b.with_functions(f)
}
