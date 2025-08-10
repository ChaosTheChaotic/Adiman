use flutter_rust_bridge::frb;
use std::{ffi::OsStr, path::Path};

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
