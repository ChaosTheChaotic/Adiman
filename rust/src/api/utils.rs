use flutter_rust_bridge::frb;
use std::{ffi::OsStr, path::Path};
use crate::api::value_store::acquire_read_lock;

#[frb(ignore)]
// Stolen from rust path source code and slightly refactored since (as of writing this) its a nightly only feature and im not bothered.
pub fn fpre(fpath: &Path) -> Option<&OsStr> {
    fn split_file_at_dot(file: &OsStr) -> (&OsStr, Option<&OsStr>) {
        let slice = file.as_encoded_bytes();
        if slice == b".." {
            return (file, None);
        }
        // The unsafety here stems from converting between &OsStr and &[u8]
        // and back. This is safe to do because (1) we only look at ASCII
        // contents of the encoding and (2) new &OsStr values are produced
        // only from ASCII-bounded slices of existing &OsStr values.
        let i = match slice[1..].iter().position(|b| *b == b'.') {
            Some(i) => i + 1,
            None => return (file, None),
        };
        let before = &slice[..i];
        let after = &slice[i + 1..];
        unsafe {
            (
                OsStr::from_encoded_bytes_unchecked(before),
                Some(OsStr::from_encoded_bytes_unchecked(after)),
            )
        }
    }
    fpath
        .file_name()
        .map(split_file_at_dot)
        .and_then(|(before, _after)| Some(before))
}

#[frb(ignore)]
pub fn check_dir(folder: impl AsRef<std::path::Path>) -> bool {
    folder.as_ref().exists() && folder.as_ref().is_dir()
}

#[frb(ignore)]
pub fn validate_path(name: impl AsRef<str>) -> bool {
    let path = name.as_ref();
    if path.contains("..")
        || path.starts_with('/')
        || path.starts_with('~')
        || path.is_empty()
        || path.chars().any(|c| c.is_control() || c == '\0')
    {
        false
    } else {
        true
    }
}

// Returns the value of unsafe api returning false on error because better safe than sorry
pub fn check_unsafe_api() -> bool {
    match acquire_read_lock() {
        Ok(guard) => {
            if let Some(store) = guard.as_ref() {
                return store.unsafe_apis;
            } else {
                return false;
            }
        }
        Err(_) => return false,
    }
}

pub fn check_plugins_enabled() -> bool {
    match acquire_read_lock() {
        Ok(guard) => {
            if let Some(store) = guard.as_ref() {
                return store.plugins_enabled;
            } else {
                return false;
            }
        }
        Err(_) => return false,
    }
}
