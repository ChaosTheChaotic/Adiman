use crate::api::{
    music_handler::get_cvol,
    utils::{check_unsafe_api, fpre, validate_path},
    value_store::{acquire_read_lock, check_value_store_state},
};
use extism::{FromBytes, Function, PTR, PluginBuilder, ToBytes, UserData, convert::Json, host_fn};
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs::{self, File},
    path::PathBuf,
};

fn confine_path(path: impl AsRef<std::path::Path>) -> Result<String, ()> {
    let path = path.as_ref();
    let plugin_rw_dir: String = match acquire_read_lock() {
        Ok(guard) => {
            if let Some(state) = guard.as_ref() {
                state.plugin_rw_dir.clone()
            } else {
                return Err(());
            }
        }
        Err(_) => return Err(()),
    };
    let prwd = PathBuf::from(plugin_rw_dir);
    Ok(prwd.join(path).to_string_lossy().to_string())
}

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
host_fn!(create_file(user_data: (); path: String, content: Option<String>) -> bool {
    if !validate_path(&path) {
        return Ok(false);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    if content.is_none() {
        return Ok(File::create(&joined_path).is_ok());
    } else {
        return Ok(fs::write(&joined_path, content.unwrap()).is_ok());
    }
    Ok(true)
});

#[frb(ignore)]
host_fn!(check_entity_exists(user_data: (); path: String, follow_symlinks: bool) -> bool {
    if !validate_path(&path) {
        return Ok(false);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    if !follow_symlinks {
        return Ok(PathBuf::from(&joined_path).exists());
    } else {
        return match fs::metadata(&joined_path) {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        };
    }
});

#[frb(ignore)]
host_fn!(entity_type(user_data: (); path: String, follow_symlinks: bool) -> Option<EntityType> {
    if !validate_path(&path) {
        return Ok(None);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(None),
    };
    if !follow_symlinks {
        let pbn = PathBuf::from(&joined_path);
        if pbn.is_dir() {
            return Ok(Some(EntityType::Directory));
        } else if pbn.is_symlink() {
            return Ok(Some(EntityType::Symlink));
        } else {
            return Ok(Some(EntityType::File));
        }
    } else {
        return match fs::metadata(&joined_path) {
            Ok(m) => {
                if m.is_dir() {
                    return Ok(Some(EntityType::Directory));
                } else {
                    return Ok(Some(EntityType::File));
                }
            },
            Err(_) => Ok(None),
        }
    }
});

#[frb(ignore)]
host_fn!(write_file(user_data: (); path: String, content: String) -> bool {
    if !validate_path(&path) {
        return Ok(false);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    Ok(fs::write(&joined_path, content).is_ok())
});

#[frb(ignore)]
host_fn!(delete_file(user_data: (); path: String) -> bool {
    if !validate_path(&path) {
        return Ok(false);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    Ok(fs::remove_file(&joined_path).is_ok())
});

#[frb(ignore)]
host_fn!(delete_dir(user_data: (); path: String) -> bool {
    if !validate_path(&path) {
        return Ok(false);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    Ok(fs::remove_dir_all(&joined_path).is_ok())
});

#[frb(ignore)]
host_fn!(create_dir(user_data: (); path: String) -> bool {
    if !validate_path(&path) {
        return Ok(false);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    Ok(fs::create_dir_all(&joined_path).is_ok())
});

#[frb(ignore)]
host_fn!(read_file(user_data: (); path: String) -> String {
    if !validate_path(&path) {
        return Ok("ERR: Invalid path".to_string());
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok("ERR: Failed to confine path to the plugin r/w dir".to_string()),
    };
    match fs::read_to_string(&joined_path) {
        Ok(content) => Ok(content),
        Err(e) => Ok(format!("ERR: {}", e)),
    }
});

#[frb(ignore)]
#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub enum EntityType {
    File,
    Directory,
    Symlink,
}

#[frb(ignore)]
#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct DirEntity {
    pub path: String,
    pub entity_type: EntityType,
}

#[frb(ignore)]
#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct DirEntities {
    pub contents: Vec<DirEntity>,
}

#[frb(ignore)]
host_fn!(list_dir(user_data: (); path: String, follow_symlinks: bool) -> DirEntities {
    if !validate_path(&path) {
        return Ok(DirEntities { contents: Vec::new() });
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(DirEntities { contents: Vec::new() }),
    };
    match fs::read_dir(&joined_path) {
        Ok(entries) => {
            let mut results: Vec<DirEntity> = Vec::new();
            for entry in entries {
                if let Ok(entry) = entry {
                    if !follow_symlinks {
                        if let Some(file_path) = entry.path().to_str() {
                            if let Ok(file_type) = entry.file_type() {
                                let entity_type = match () {
                                    _ if file_type.is_dir() => EntityType::Directory,
                                    _ if file_type.is_symlink() => EntityType::Symlink,
                                    _ => EntityType::File,
                                };
                                results.push(DirEntity {
                                    path: file_path.to_string(),
                                    entity_type,
                                })
                            }
                        }
                    } else {
                        if let Ok(m) = fs::metadata(entry.path()) {
                            let entity_type = match () {
                                _ if m.is_dir() => EntityType::Directory,
                                _ => EntityType::File,
                            };
                            results.push(DirEntity { path: entry.path().to_string_lossy().to_string(), entity_type, })
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
host_fn!(file_size(user_data: (); path: String) -> u64 {
    if !validate_path(&path) {
        return Ok(0);
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok(0),
    };
    match fs::metadata(&joined_path) {
        Ok(metadata) => Ok(metadata.len()),
        Err(_) => Ok(0),
    }
});

#[frb(ignore)]
host_fn!(get_file_extension_std(user_data: (); path: String) -> String {
    if !validate_path(&path) {
        return Ok("".to_string());
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok("".to_string()),
    };
    Ok(PathBuf::from(&joined_path)
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_string())
});

#[frb(ignore)]
host_fn!(get_file_extension_nightly(user_data: (); path: String) -> String {
    if !validate_path(&path) {
        return Ok("".to_string());
    }
    let joined_path: String = match confine_path(&path) {
        Ok(p) => p,
        Err(_) => return Ok("".to_string()),
    };
    Ok(fpre(&PathBuf::from(&joined_path).as_path()).unwrap_or_default().to_string_lossy().to_string())
});

#[frb(ignore)]
host_fn!(rename_file(user_data: (); old: String, new: String) -> bool {
    if !(validate_path(&old) || validate_path(&new)) {
        return Ok(false);
    }
    let joined_path_old: String = match confine_path(&old) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    let joined_path_new: String = match confine_path(&new) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    Ok(fs::rename(&joined_path_old, &joined_path_new).is_ok())
});

#[frb(ignore)]
host_fn!(copy_file(user_data: (); from: String, to: String) -> bool {
    if !(validate_path(&from) || validate_path(&to)) {
        return Ok(false)
    }
    let joined_path_from: String = match confine_path(&from) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    let joined_path_to: String = match confine_path(&to) {
        Ok(p) => p,
        Err(_) => return Ok(false),
    };
    Ok(fs::copy(&joined_path_from, &joined_path_to).is_ok())
});

#[frb(ignore)]
host_fn!(get_arch() -> String {
    Ok(String::from(std::env::consts::ARCH))
});

#[frb(ignore)]
host_fn!(get_time() -> i64 {
    Ok(chrono::Utc::now().timestamp())
});

#[frb(ignore)]
host_fn!(get_current_vol() -> f32 {
    Ok(get_cvol())
});

#[frb(ignore)]
host_fn!(get_song_pos() -> f32 {
    Ok(crate::api::music_handler::get_playback_position())
});

#[frb(ignore)]
host_fn!(get_is_playing() -> bool {
    Ok(crate::api::music_handler::is_playing())
});

#[frb(ignore)]
host_fn!(get_unsafe_api() -> bool {
    Ok(check_unsafe_api())
});

#[frb(ignore)]
host_fn!(unsafe_create_file(user_data: (); path: String, content: Option<String>) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    if content.is_some() {
        return Ok(fs::write(&path, content.unwrap()).is_ok());
    } else {
        return Ok(File::create(&path).is_ok());
    }
});

#[frb(ignore)]
host_fn!(unsafe_check_entity_exists(user_data: (); path: String, follow_symlinks: bool) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    if follow_symlinks {
        return Ok(match fs::metadata(&path) {
            Ok(_) => true,
            Err(_) => false,
        });
    } else {
        return Ok(PathBuf::from(&path).exists())
    }
});

#[frb(ignore)]
host_fn!(unsafe_entity_type(user_data: (); path: String, follow_symlinks: bool) -> Option<EntityType> {
    if !check_unsafe_api() {
        return Ok(None);
    }
    if follow_symlinks {
        return Ok(match fs::metadata(&path) {
            Ok(m) => {
                if m.is_dir() {
                    Some(EntityType::Directory)
                } else {
                    Some(EntityType::File)
                }
            },
            Err(_) => None,
        });
    } else {
        let pbn = PathBuf::from(&path);
        if pbn.is_dir() {
            return Ok(Some(EntityType::Directory));
        } else if pbn.is_symlink() {
            return Ok(Some(EntityType::Symlink));
        } else {
            return Ok(Some(EntityType::File));
        }
    }
});

#[frb(ignore)]
host_fn!(unsafe_write_file(user_data: (); path: String, content: String) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    Ok(fs::write(&path, content).is_ok())
});

#[frb(ignore)]
host_fn!(unsafe_delete_file(user_data: (); path: String) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    Ok(fs::remove_file(&path).is_ok())
});

#[frb(ignore)]
host_fn!(unsafe_delete_dir(user_data: (); path: String) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    Ok(fs::remove_dir_all(&path).is_ok())
});

#[frb(ignore)]
host_fn!(unsafe_create_dir(user_data: (); path: String) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    Ok(fs::create_dir_all(&path).is_ok())
});

#[frb(ignore)]
host_fn!(unsafe_read_file(user_data: (); path: String) -> String {
    if !check_unsafe_api() {
        return Ok("ERR: Unsafe API was false".to_string())
    }
    match fs::read_to_string(&path) {
        Ok(c) => Ok(c),
        Err(e) => Ok(format!("ERR: Failed to read file to string: {e}"))
    }
});

#[frb(ignore)]
host_fn!(unsafe_list_dir(user_data: (); path: String, follow_symlinks: bool) -> DirEntities {
    if !check_unsafe_api() {
        return Ok(DirEntities { contents: Vec::new() });
    }
    match fs::read_dir(&path) {
        Ok(entries) => {
            let mut res: Vec<DirEntity> = Vec::new();
            for entry in entries {
                if let Ok(entry) = entry {
                    if !follow_symlinks {
                        if let Some(file_path) = entry.path().to_str() {
                            if let Ok(file_type) = entry.file_type() {
                                let entity_type = match () {
                                    _ if file_type.is_dir() => EntityType::Directory,
                                    _ if file_type.is_symlink() => EntityType::Symlink,
                                    _ => EntityType::File,
                                };
                                res.push(DirEntity {
                                    path: file_path.to_string(),
                                    entity_type,
                                })
                            }
                        }
                    } else {
                        if let Ok(m) = fs::metadata(entry.path()) {
                            let entity_type = match () {
                                _ if m.is_dir() => EntityType::Directory,
                                _ => EntityType::File,
                            };
                            res.push(DirEntity {
                                path: entry.path().to_string_lossy().to_string(),
                                entity_type,
                            })
                        }
                    }
                }
            }
            Ok(DirEntities { contents: res })
        }
        Err(_) => Ok(DirEntities { contents: Vec::new() }),
    }
});

#[frb(ignore)]
host_fn!(unsafe_file_size(user_data: (); path: String) -> u64 {
    if !check_unsafe_api() {
        return Ok(0);
    }
    match fs::metadata(&path) {
        Ok(m) => Ok(m.len()),
        Err(_) => Ok(0),
    }
});

#[frb(ignore)]
host_fn!(unsafe_get_file_extension_std(user_data: (); path: String) -> String {
    if !check_unsafe_api() {
        return Ok("".to_string())
    }
    Ok(PathBuf::from(&path)
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_string())
});

#[frb(ignore)]
host_fn!(unsafe_get_file_extension_nightly(user_data: (); path: String) -> String {
    if !check_unsafe_api() {
        return Ok("".to_string());
    }
    Ok(fpre(&PathBuf::from(&path).as_path()).unwrap_or_default().to_string_lossy().to_string())
});

#[frb(ignore)]
host_fn!(unsafe_rename_file(user_data: (); from: String, to: String) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    Ok(fs::rename(&from, &to).is_ok())
});

#[frb(ignore)]
host_fn!(unsafe_copy_file(user_data: (); from: String, to: String) -> bool {
    if !check_unsafe_api() {
        return Ok(false);
    }
    Ok(fs::copy(&from, &to).is_ok())
});

#[frb(ignore)]
#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct CommandTR {
    pub command: String,
    pub args: Option<Vec<String>>,
}

#[frb(ignore)]
#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct CommandResult {
    pub success: bool,
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

#[frb(ignore)]
host_fn!(unsafe_run_command(user_data: (); command: CommandTR) -> CommandResult {
    if !check_unsafe_api() {
        return Ok(CommandResult {
            success: false,
            exit_code: -1,
            stdout: String::new(),
            stderr: "ERR: Unsafe API disabled".to_string(),
        })
    }
    let mut cmd = std::process::Command::new(command.command);
    if let Some(args) = command.args {
        cmd.args(args);
    }
    match cmd.output() {
        Ok(output) => {
            let exit_code = output.status.code().unwrap_or(-1);
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();

            Ok(CommandResult {
                success: output.status.success(),
                exit_code,
                stdout,
                stderr,
            })
        }
        Err(e) => Ok(CommandResult {
            success: false,
            exit_code: -1,
            stdout: String::new(),
            stderr: format!("ERR: Failed to execute command: {}", e),
        }),
    }
});

#[frb(ignore)]
#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct HttpRequest {
    pub url: String,
    pub method: String, // "GET", "POST", "PUT", "DELETE", etc.
    pub headers: Option<HashMap<String, String>>,
    pub body: Option<String>,
    pub timeout_seconds: Option<u64>,
}

#[frb(ignore)]
#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct HttpResponse {
    pub status_code: u16,
    pub headers: HashMap<String, String>,
    pub body: String,
    pub success: bool,
    pub error: Option<String>,
}

#[frb(ignore)]
host_fn!(unsafe_request(user_data: (); request: HttpRequest) -> HttpResponse {
    if !check_unsafe_api() {
        return Ok(HttpResponse {
            status_code: 0,
            headers: HashMap::new(),
            body: String::new(),
            success: false,
            error: Some("ERR: Unsafe API disabled".to_string()),
        });
    }

    let client_builder = reqwest::blocking::Client::builder();
    let client_builder = if let Some(timeout) = request.timeout_seconds {
        client_builder.timeout(std::time::Duration::from_secs(timeout))
    } else {
        client_builder
    };

    let client = match client_builder.build() {
        Ok(client) => client,
        Err(e) => {
            return Ok(HttpResponse {
                status_code: 0,
                headers: HashMap::new(),
                body: String::new(),
                success: false,
                error: Some(format!("ERR: Failed to build HTTP client: {}", e)),
            });
        }
    };

    let mut req_builder = match request.method.to_uppercase().as_str() {
        "GET" => client.get(&request.url),
        "POST" => client.post(&request.url),
        "PUT" => client.put(&request.url),
        "DELETE" => client.delete(&request.url),
        "PATCH" => client.patch(&request.url),
        "HEAD" => client.head(&request.url),
        _ => {
            return Ok(HttpResponse {
                status_code: 0,
                headers: HashMap::new(),
                body: String::new(),
                success: false,
                error: Some(format!("ERR: Unsupported HTTP method: {}", request.method)),
            });
        }
    };

    if let Some(headers) = request.headers {
        for (key, value) in headers {
            req_builder = req_builder.header(&key, value);
        }
    }

    if let Some(body) = request.body {
        req_builder = req_builder.body(body);
    }

    match req_builder.send() {
        Ok(response) => {
            let status_code = response.status().as_u16();

            // Extract headers
            let mut headers = HashMap::new();
            for (key, value) in response.headers() {
                if let (Some(key_str), Ok(value_str)) = (key.as_str().to_string().into(), value.to_str()) {
                    headers.insert(key_str, value_str.to_string());
                }
            }

            // Read response body
            match response.text() {
                Ok(body) => Ok(HttpResponse {
                    status_code,
                    headers,
                    body,
                    success: status_code < 400,
                    error: None,
                }),
                Err(e) => Ok(HttpResponse {
                    status_code,
                    headers,
                    body: String::new(),
                    success: false,
                    error: Some(format!("ERR: Failed to read response body: {}", e)),
                }),
            }
        }
        Err(e) => Ok(HttpResponse {
            status_code: 0,
            headers: HashMap::new(),
            body: String::new(),
            success: false,
            error: Some(format!("ERR: Request failed: {}", e)),
        }),
    }
});

#[frb(ignore)]
host_fn!(unsafe_get_env_var(user_data: (); var: String) -> String {
    if !check_unsafe_api() {
        return Ok("ERR: Unsafe API disabled".to_string());
    }
    Ok(std::env::var(var).unwrap_or_else(|e| {
        format!("ERR: Failed to get env var: {}", e)
    }))
});

#[frb(ignore)]
host_fn!(unsafe_set_env_var(user_data: (); var: String, value: String) -> bool {
    if !check_unsafe_api() {
        return Ok(false)
    }
    unsafe { std::env::set_var(var, value) };
    Ok(true)
});

#[frb(ignore)]
host_fn!(call_plugin_func(user_data: (); func: String, plugin_name: String) -> bool {
    Ok(crate::api::plugin_man::call_plugin_func(func, plugin_name))
});

// A macro to decide how to format the functions for me
macro_rules! get_fn_signature {
    // With params and return - count the parameters to determine the correct signature
    (($func:ident) fn $path:ident($($param:ident: $param_type:ty),+) -> $ret:ty) => {
        {
            let param_count = count_params!($($param),+);
            Function::new(stringify!($path), vec![PTR; param_count], [PTR], UserData::new(()), $func)
        }
    };

    // With return only - no parameters
    (($func:ident) fn $path:ident() -> $ret:ty) => {
        Function::new(stringify!($path), [], [PTR], UserData::new(()), $func)
    };

    // With params only - no return
    (($func:ident) fn $path:ident($($param:ident: $param_type:ty),+)) => {
        {
            let param_count = count_params!($($param),+);
            Function::new(stringify!($path), vec![PTR; param_count], [], UserData::new(()), $func)
        }
    };

    // No params or return
    (($func:ident) fn $path:ident()) => {
        Function::new(stringify!($path), [], [], UserData::new(()), $func)
    };
}

macro_rules! count_params {
    () => (0);
    ($first:ident) => (1);
    ($first:ident, $($rest:ident),+) => (1 + count_params!($($rest),+));
}

// The main macro
macro_rules! generic_func {
    ($func:ident($($param:ident: $param_type:ty),+) -> $ret:ty) => {
        get_fn_signature!(($func) fn $func($($param: $param_type),+) -> $ret)
    };

    ($func:ident($($param:ident: $param_type:ty),+)) => {
        get_fn_signature!(($func) fn $func($($param: $param_type),+))
    };

    ($func:ident() -> $ret:ty) => {
        get_fn_signature!(($func) fn $func() -> $ret)
    };

    ($func:ident()) => {
        get_fn_signature!(($func) fn $func())
    };
}

#[frb(ignore)]
pub fn add_functions(b: PluginBuilder) -> PluginBuilder {
    let f = vec![
        // Logging utils
        generic_func!(pprint(text: String)),
        // Store retrival
        generic_func!(get_music_folder() -> String),
        generic_func!(get_store_state() -> bool),
        generic_func!(get_current_song() -> Option<crate::api::music_handler::SongMetadata>),
        generic_func!(get_unsafe_api() -> bool),
        // Safe filesystem functions
        generic_func!(create_file(path: String, content: Option<String>) -> bool),
        generic_func!(check_entity_exists(path: String, follow_symlinks: bool) -> bool),
        generic_func!(entity_type(path: String, follow_symlinks: bool) -> Option<EntityType>),
        generic_func!(write_file(path: String, content: String) -> bool),
        generic_func!(delete_file(path: String) -> bool),
        generic_func!(delete_dir(path: String) -> bool),
        generic_func!(create_dir(path: String) -> bool),
        generic_func!(read_file(path: String) -> String),
        generic_func!(list_dir(path: String, follow_symlinks: bool) -> DirEntities),
        generic_func!(join_paths(path1: String, path2: String) -> String),
        generic_func!(file_size(path: String) -> u64),
        generic_func!(rename_file(old: String, new: String) -> bool),
        generic_func!(copy_file(from: String, to: String) -> bool),
        generic_func!(get_file_extension_std(path: String) -> String),
        generic_func!(get_file_extension_nightly(path: String) -> String),
        // System info functions
        generic_func!(get_arch() -> String),
        generic_func!(get_time() -> i64),
        generic_func!(get_current_vol() -> f32),
        // App info functions
        generic_func!(get_song_pos() -> f32),
        generic_func!(get_is_playing() -> bool),
        // Unsafe filesystem functions
        generic_func!(unsafe_create_file(path: String, content: Option<String>) -> bool),
        generic_func!(unsafe_check_entity_exists(path: String, follow_symlinks: bool) -> bool),
        generic_func!(unsafe_entity_type(path: String, follow_symlinks: bool) -> Option<EntityType>),
        generic_func!(unsafe_write_file(path: String, content: String) -> bool),
        generic_func!(unsafe_delete_file(path: String) -> bool),
        generic_func!(unsafe_delete_dir(path: String) -> bool),
        generic_func!(unsafe_create_dir(path: String) -> bool),
        generic_func!(unsafe_list_dir(path: String, follow_symlinks: bool) -> DirEntities),
        generic_func!(unsafe_file_size(path: String) -> u64),
        generic_func!(unsafe_rename_file(old: String, new: String) -> bool),
        generic_func!(unsafe_copy_file(from: String, to: String) -> bool),
        generic_func!(unsafe_get_file_extension_std(path: String) -> String),
        generic_func!(unsafe_get_file_extension_nightly(path: String) -> String),
        // Unsafe command functions
        generic_func!(unsafe_run_command(command: CommandTR) -> CommandResult),
        // Unsafe network functions
        generic_func!(unsafe_request(request: HttpRequest) -> HttpResponse),
        // Unsafe utility functions
        generic_func!(unsafe_get_env_var(var: String) -> String),
        generic_func!(unsafe_set_env_var(var: String, value: String) -> bool),
        // Other plugin functions
        generic_func!(call_plugin_func(func: String, plugin_name: String) -> bool),
    ];
    b.with_functions(f)
}
