use crate::api::value_store::acquire_read_lock;
use flutter_rust_bridge::frb;
use std::{ffi::OsStr, path::Path};
use std::os::unix::fs::PermissionsExt;
use tokio::io::AsyncWriteExt;
use futures::StreamExt;


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

pub async fn get_latest_version() -> Option<String> {
    let url = "https://api.github.com/repos/ChaosTheChaotic/Adiman/releases/latest";

    let response = match reqwest::get(url).await {
        Ok(res) => res,
        Err(e) => {
            println!("Error making request to {}: {}", url, e);
            return None;
        }
    };

    if !response.status().is_success() {
        println!("HTTP request failed with status: {}", response.status());
        return None;
    }

    let json_data: serde_json::Value = match response.json().await {
        Ok(data) => data,
        Err(e) => {
            println!("Failed to parse response as JSON: {}", e);
            return None;
        }
    };

    match json_data.get("tag_name") {
        Some(version) => match version.as_str() {
            Some(v) => Some(v.to_string()),
            None => {
                println!("Version field is not a string: {:?}", version);
                None
            }
        },
        None => {
            println!("JSON response missing 'tag_name' field");
            None
        }
    }
}

pub async fn update_executable(arch: String, expath: String) -> bool {
    let darch: String =
        if arch.eq_ignore_ascii_case("aarch64") || arch.eq_ignore_ascii_case("arm64") {
            "aarch64".to_string()
        } else if arch.eq_ignore_ascii_case("x86_64") {
            "x86_64".to_string()
        } else {
            println!("Unsupported arch: {}", arch);
            return false;
        };

    let dtr = match std::path::PathBuf::from(&expath).parent() {
        Some(path) => path.to_path_buf(),
        None => {
            println!("Failed to get parent of executable path: {}", &expath);
            return false;
        }
    };

    if !dtr.is_dir() {
        println!("Cannot download into a file");
        return false;
    }

    let download_url = format!("https://github.com/ChaosTheChaotic/Adiman/releases/latest/download/Adiman-{darch}.AppImage");
    let temp_path = dtr.join(format!("Adiman-{darch}-new.AppImage"));

    if let Err(e) = download_file(&download_url, &temp_path).await {
        println!("Download failed: {}", e);
        return false;
    }

    if let Err(e) = std::fs::set_permissions(&temp_path, std::fs::Permissions::from_mode(0o755)) {
        println!("Failed to set executable permissions: {}", e);
        let _ = std::fs::remove_file(&temp_path);
        return false;
    }

    if let Err(e) = std::fs::remove_file(&expath) {
        println!("Failed to remove old executable: {}", e);
        let _ = std::fs::remove_file(&temp_path);
        return false;
    }

    if let Err(e) = std::fs::rename(&temp_path, &expath) {
        println!("Failed to rename new executable: {}", e);
        return false;
    }

    true
}

async fn download_file(url: &str, path: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let client = reqwest::Client::new();
    let response = client.get(url).send().await?;
    
    if !response.status().is_success() {
        return Err(format!("HTTP error: {}", response.status()).into());
    }

    let mut file = tokio::fs::File::create(path).await?;
    let mut stream = response.bytes_stream();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        file.write_all(&chunk).await?;
    }
    
    file.flush().await?;
    Ok(())
}
