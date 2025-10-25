use extism_pdk::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[host_fn]
extern "ExtismHost" {
    fn pprint(m: String);
    // Returns any errors as a string starting with ERR
    fn get_music_folder() -> String;
    fn get_current_song() -> Option<SongMetadata>;
    // Returns the state of the value store used to store a lot of the settings which sync from dart
    fn get_store_state() -> bool;
    fn create_file(path: String, content: Option<String>) -> bool;
    // Check if a file/directory exists. When follow_symlinks is true, checks the target of symlinks
    fn check_entity_exists(path: String, follow_symlinks: bool) -> bool;
    // Get the type of entity. When follow_symlinks is true, returns the type of the symlink target
    fn entity_type(path: String, follow_symlinks: bool) -> Option<EntityType>;
    fn write_file(path: String, content: String) -> bool;
    fn delete_file(path: String) -> bool;
    fn delete_dir(path: String) -> bool;
    fn create_dir(path: String) -> bool;
    // Returns the error starting with ERR on failure
    fn read_file(path: String) -> String;
    // List directory contents. When follow_symlinks is true, symlinks are resolved to their target type
    fn list_dir(path: String, follow_symlinks: bool) -> DirEntities;
    fn join_paths(base: String, segment: String) -> String;
    // Returns 0 as an error or if the file has nothing inside
    fn file_size(path: String) -> u64;
    // Gets the extension of a file by parsing from the front (using rust std version)
    fn get_file_extension_std(path: String) -> String;
    // Gets the extension of a file by parsing from the back (using rust nightly version)
    fn get_file_extension_nightly(path: String) -> String;
    fn rename_file(old: String, new: String) -> bool;
    fn copy_file(from: String, to: String) -> bool;
    fn get_arch() -> String;
    // Returns a chrono::Utc::now().timestamp()
    fn get_time() -> i64;
    // Returns the current volume
    fn get_current_vol() -> f32;
    // Returns the position in the song
    fn get_song_pos() -> f32;
    // Returns if we are playing or not (paused or not)
    fn get_is_playing() -> bool;
    // Returns if unsafe APIs are enabled
    fn get_unsafe_api() -> bool;
    // Unsafe filesystem functions (require unsafe APIs to be enabled)
    fn unsafe_create_file(path: String, content: Option<String>) -> bool;
    fn unsafe_check_entity_exists(path: String, follow_symlinks: bool) -> bool;
    fn unsafe_entity_type(path: String, follow_symlinks: bool) -> Option<EntityType>;
    fn unsafe_write_file(path: String, content: String) -> bool;
    fn unsafe_delete_file(path: String) -> bool;
    fn unsafe_delete_dir(path: String) -> bool;
    fn unsafe_create_dir(path: String) -> bool;
    fn unsafe_read_file(path: String) -> String;
    fn unsafe_list_dir(path: String, follow_symlinks: bool) -> DirEntities;
    fn unsafe_file_size(path: String) -> u64;
    fn unsafe_rename_file(old: String, new: String) -> bool;
    fn unsafe_copy_file(from: String, to: String) -> bool;
    fn unsafe_get_file_extension_std(path: String) -> String;
    fn unsafe_get_file_extension_nightly(path: String) -> String;
    fn unsafe_run_command(command: CommandTR) -> CommandResult;
    fn unsafe_request(request: HttpRequest) -> HttpResponse;
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
// EntityType represents the type of filesystem entity
// When follow_symlinks is true in host functions, symlinks return the type of their target
// When follow_symlinks is false, symlinks are identified as Symlink
pub enum EntityType {
    File,
    Directory,
    Symlink,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct DirEntity {
    pub path: String,
    pub entity_type: EntityType,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct DirEntities {
    pub contents: Vec<DirEntity>,
}

#[derive(Debug, Serialize, Deserialize, Clone, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct SongMetadata {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: u64,
    pub path: String,
    pub album_art: Option<Vec<u8>>,
    pub genre: String,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct CommandTR {
    pub command: String,
    pub args: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct CommandResult {
    pub success: bool,
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct HttpRequest {
    pub url: String,
    pub method: String, // "GET", "POST", "PUT", "DELETE", etc.
    pub headers: Option<HashMap<String, String>>,
    pub body: Option<String>,
    pub timeout_seconds: Option<u64>,
}

#[derive(Serialize, Deserialize, ToBytes, FromBytes)]
#[encoding(Json)]
pub struct HttpResponse {
    pub status_code: u16,
    pub headers: HashMap<String, String>,
    pub body: String,
    pub success: bool,
    pub error: Option<String>,
}
