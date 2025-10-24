use extism_pdk::*;
use serde::{Deserialize, Serialize};

#[host_fn]
extern "ExtismHost" {
    fn pprint(m: String);
    // Returns any errors as a string starting with ERR
    fn get_music_folder() -> String;
    fn get_current_song() -> Option<SongMetadata>;
    // Returns the state of the value store used to store a lot of the settings which sync from dart
    fn get_store_state() -> bool;
    fn create_file(name: String, content: Option<String>) -> bool;
    fn check_entity_exists(name: String) -> bool;
    fn entity_is_dir(name: String) -> bool;
    fn write_file(name: String, content: String) -> bool;
    fn delete_file(name: String) -> bool;
    fn create_dir(name: String) -> bool;
    // Retuns the error starting with ERR on failure
    fn read_file(name: String) -> String;
    // Returns empty on failure
    fn list_dir(path: String) -> DirEntities;
    fn join_paths(base: String, segment: String) -> String;
    // Returns 0 as an error or if the file has nothing inside
    fn file_size(name: String) -> u64;
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
}

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

#[derive(Debug, Serialize, Deserialize, Clone, ToBytes, FromBytes)]
#[encoding(Json)]
struct SongMetadata {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: u64,
    pub path: String,
    pub album_art: Option<Vec<u8>>,
    pub genre: String,
}
