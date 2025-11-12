use crate::api::{host_func_interface::add_functions, utils::check_plugins_enabled};
pub use extism::{Manifest, Plugin, PluginBuilder, Wasm};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
pub use serde_json::{Value, from_str, from_value};
pub use std::{
    collections::HashMap,
    error::Error,
    ffi::OsStr,
    fs::{self, metadata},
    io::Read,
    path::PathBuf,
    sync::{Arc, Mutex},
};

static PLUGIN_MAN: Lazy<Mutex<Option<AdiPluginMan>>> = Lazy::new(|| Mutex::new(None));

static ALLOWED_BUTTON_LOCATIONS: Lazy<Vec<&'static str>> =
    Lazy::new(|| vec!["drawer", "songopts", "settings", "selectplaylist"]);

#[derive(Debug)]
pub enum PluginManErr {
    FileNotFound(String),
    BadFile(String),
    PluginError(Option<String>),
    PluginNotLoaded(String),
    PluginAlreadyLoaded(String),
    MetadataNotFound(String),
    InvalidMeta(String),
    PluginManNotLoaded,
}

impl std::fmt::Display for PluginManErr {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let err: String = match self {
            PluginManErr::FileNotFound(path) => format!("File not found: {path}"),
            PluginManErr::BadFile(path) => {
                format!("Provided file is not a wasm file or has no stem: {path}")
            }
            PluginManErr::PluginError(e) => format!(
                "A plugin error occurred: {}",
                e.clone().unwrap_or("No error message returned".into())
            ),
            PluginManErr::PluginNotLoaded(path) => format!("Plugin: {path} is not loaded"),
            PluginManErr::PluginAlreadyLoaded(path) => {
                format!("The plugin: {path} was already loaded")
            }
            PluginManErr::MetadataNotFound(path) => format!(
                "Metadata for plugin: {path} not found. Ensure it has the same name as the plugin and is json type whilst being in the same (valid) directory as the plugin"
            ),
            PluginManErr::InvalidMeta(path) => format!("Metadata found for: {path} is invalid"),
            PluginManErr::PluginManNotLoaded => format!("The plugin manager has not been loaded."),
        };
        write!(f, "{err}")
    }
}

impl Error for PluginManErr {}

#[derive(Clone, Serialize, Deserialize)]
pub enum ConfigTypes {
    String(String),
    Bool(bool),
    Int(i32),
    UInt(u32),
    BigInt(i128),
    BigUInt(u128),
    Float(f64),
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct RpcConfig {
    pub key: String,
    pub ctype: String,
    pub default_val: Value,
    pub set_val: Value,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct FadButton {
    pub name: String,
    pub icon: Option<String>,
    pub location: Option<String>,
    pub callback: String,
}

impl FadButton {
    pub fn is_valid(&self) -> bool {
        if let Some(location) = &self.location {
            if !ALLOWED_BUTTON_LOCATIONS.contains(&location.as_str()) {
                eprintln!(
                    "Warning: Invalid button location '{}' for button '{}'",
                    location, self.name
                );
                return false;
            }
        }

        if self.name.trim().is_empty() {
            eprintln!("Warning: Button has empty name");
            return false;
        }

        if self.callback.trim().is_empty() {
            eprintln!("Warning: Button '{}' has empty callback", self.name);
            return false;
        }

        true
    }
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct FadLabel {
    pub size: f64,
    pub text: String,
    pub color: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct FadPopup {
    pub title: Option<String>,
    pub buttons: Option<Vec<FadButton>>,
    pub labels: Option<Vec<FadLabel>>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct FadScreen {
    pub title: Option<String>,
    pub buttons: Option<Vec<FadButton>>,
    pub labels: Option<Vec<FadLabel>>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct FadConfig {
    pub screens: Option<Vec<FadScreen>>,
    pub popups: Option<Vec<FadPopup>>,
    pub buttons: Option<Vec<FadButton>>,
}

pub type PluginConfig = HashMap<String, ConfigTypes>; // A key-value pair with a key and a config type

pub struct PluginInode {
    pub plugin: Arc<Mutex<Plugin>>, // Plugin handle wrapped in an Arc and Mutex because frb keeps generating code trying to clone it
    pub config: Option<PluginConfig>, // Plugins config
    pub fad: Option<FadConfig>,     // Frontend additions config
}

pub type AdimanPlugin = HashMap<String, PluginInode>; // Key value with plugins meta and its path

#[flutter_rust_bridge::frb(ignore)]
pub struct AdiPluginMan {
    pub plugin_meta: AdimanPlugin,
}

impl AdiPluginMan {
    pub fn new() -> Self {
        AdiPluginMan {
            plugin_meta: HashMap::new(),
        }
    }

    fn validate_and_filter_fad_config(fad_config: &mut FadConfig) {
        // Validate and filter top-level buttons
        if let Some(buttons) = &mut fad_config.buttons {
            buttons.retain(|button| button.is_valid());
            if buttons.is_empty() {
                fad_config.buttons = None;
            }
        }

        // Validate and filter screen buttons and labels
        if let Some(screens) = &mut fad_config.screens {
            for mut screen in screens.clone() {
                if let Some(buttons) = &mut screen.buttons {
                    buttons.retain(|button| button.is_valid());
                    if buttons.is_empty() {
                        screen.buttons = None;
                    }
                }

                if let Some(labels) = &mut screen.labels {
                    labels.retain(|label| {
                        let valid = !label.text.trim().is_empty() && label.size > 0.0;
                        if !valid {
                            eprintln!("Warning: Invalid label found and removed");
                        }
                        valid
                    });
                    if labels.is_empty() {
                        screen.labels = None;
                    }
                }
            }

            // Remove empty screens
            screens.retain(|screen| screen.buttons.is_some() || screen.labels.is_some());

            if screens.is_empty() {
                fad_config.screens = None;
            }
        }

        // Validate and filter popup buttons and labels
        if let Some(popups) = &mut fad_config.popups {
            for mut popup in popups.clone() {
                if let Some(buttons) = &mut popup.buttons {
                    buttons.retain(|button| button.is_valid());
                    if buttons.is_empty() {
                        popup.buttons = None;
                    }
                }

                if let Some(labels) = &mut popup.labels {
                    labels.retain(|label| {
                        let valid = !label.text.trim().is_empty() && label.size > 0.0;
                        if !valid {
                            eprintln!("Warning: Invalid label found and removed");
                        }
                        valid
                    });
                    if labels.is_empty() {
                        popup.labels = None;
                    }
                }
            }

            // Remove empty popups
            popups.retain(|popup| popup.buttons.is_some() || popup.labels.is_some());

            if popups.is_empty() {
                fad_config.popups = None;
            }
        }
    }

    fn read_plugin_metadata(
        metadata_path: &std::path::Path,
    ) -> Result<(Option<Vec<RpcConfig>>, Option<FadConfig>), PluginManErr> {
        let metadata_content = std::fs::read_to_string(metadata_path).map_err(|_| {
            PluginManErr::MetadataNotFound(metadata_path.to_string_lossy().to_string())
        })?;

        let metadata: Value = from_str(&metadata_content)
            .map_err(|_| PluginManErr::InvalidMeta(metadata_path.to_string_lossy().to_string()))?;

        let rpc_array = match metadata.get("rpc") {
            Some(Value::Array(arr)) => Some(arr),
            Some(_) => {
                // rpc exists but is not an array
                eprintln!(
                    "Warning: 'rpc' field is not an array in metadata file: {}",
                    metadata_path.display()
                );
                None
            }
            None => {
                // rpc doesent exist
                None
            }
        };

        let mut valid_configs: Option<Vec<RpcConfig>> = None;
        if let Some(arr) = rpc_array {
            valid_configs = Some(Vec::new());
            let inner = valid_configs.as_mut().unwrap();
            for (index, item) in arr.iter().enumerate() {
                if let Ok(rpc_config) = from_value::<RpcConfig>(item.clone()) {
                    if Self::validate_rpc(&rpc_config) {
                        inner.push(rpc_config);
                    } else {
                        eprintln!(
                            "Warning: Invalid RPC config at index {} in metadata file: {}",
                            index,
                            metadata_path.display()
                        );
                    }
                } else {
                    eprintln!(
                        "Warning: Failed to parse RPC config at index {} in metadata file: {}",
                        index,
                        metadata_path.display()
                    );
                }
            }
        }

        let fad_config = match metadata.get("fad") {
            Some(fad_value) => match from_value::<FadConfig>(fad_value.clone()) {
                Ok(mut fad) => {
                    // Validate and filter out invalid FAD configurations
                    Self::validate_and_filter_fad_config(&mut fad);
                    Some(fad)
                }
                Err(e) => {
                    eprintln!(
                        "Warning: Failed to parse FAD config in metadata file: {}, error: {}",
                        metadata_path.display(),
                        e
                    );
                    None
                }
            },
            None => None,
        };

        Ok((valid_configs, fad_config))
    }

    fn validate_rpc(config: &RpcConfig) -> bool {
        if config.key.is_empty() {
            return false;
        }

        match config.ctype.as_str() {
            "String" => {
                matches!(config.default_val, Value::String(_))
                    && matches!(config.set_val, Value::String(_))
            }
            "Bool" => {
                matches!(config.default_val, Value::Bool(_))
                    && matches!(config.set_val, Value::Bool(_))
            }
            "Int" => {
                let d = if let Some(num) = config.default_val.as_i64() {
                    num >= i32::MIN as i64 && num <= i32::MAX as i64
                } else {
                    false
                };
                let s = if let Some(num) = config.set_val.as_i64() {
                    num >= i32::MIN as i64 && num <= i32::MAX as i64
                } else {
                    false
                };
                d && s
            }
            "UInt" => {
                let d = if let Some(num) = config.default_val.as_u64() {
                    num <= u32::MAX as u64
                } else {
                    false
                };
                let s = if let Some(num) = config.set_val.as_u64() {
                    num <= u32::MAX as u64
                } else {
                    false
                };
                d && s
            }
            "BigInt" => {
                // BigInt can be number or string of digits (with optional minus)
                let d = if let Some(_) = config.default_val.as_i64() {
                    true
                } else if let Some(str_val) = config.default_val.as_str() {
                    // Must be all digits with optional minus at start
                    let mut chars = str_val.chars();
                    let first_char = chars.next();
                    let rest: String = chars.collect();

                    (first_char == Some('-')
                        || first_char.map(|c| c.is_ascii_digit()).unwrap_or(false))
                        && rest.chars().all(|c| c.is_ascii_digit())
                        && !rest.is_empty()
                } else {
                    false
                };
                let s = if let Some(_) = config.set_val.as_i64() {
                    true
                } else if let Some(str_val) = config.set_val.as_str() {
                    // Must be all digits with optional minus at start
                    let mut chars = str_val.chars();
                    let first_char = chars.next();
                    let rest: String = chars.collect();

                    (first_char == Some('-')
                        || first_char.map(|c| c.is_ascii_digit()).unwrap_or(false))
                        && rest.chars().all(|c| c.is_ascii_digit())
                        && !rest.is_empty()
                } else {
                    false
                };
                d && s
            }
            "BigUInt" => {
                // BigUInt can be number or string of digits
                let d = if let Some(_) = config.default_val.as_u64() {
                    true
                } else if let Some(str_val) = config.default_val.as_str() {
                    // Must be all digits
                    !str_val.is_empty() && str_val.chars().all(|c| c.is_ascii_digit())
                } else {
                    false
                };
                let s = if let Some(_) = config.set_val.as_u64() {
                    true
                } else if let Some(str_val) = config.set_val.as_str() {
                    // Must be all digits
                    !str_val.is_empty() && str_val.chars().all(|c| c.is_ascii_digit())
                } else {
                    false
                };
                d && s
            }
            "Float" => {
                let d = if let Some(_) = config.default_val.as_f64() {
                    true
                } else {
                    false
                };
                let s = if let Some(_) = config.set_val.as_f64() {
                    true
                } else {
                    false
                };
                d && s
            }
            _ => {
                // Unknown config type
                false
            }
        }
    }

    fn rpc2plugin(rpc_configs: Vec<RpcConfig>) -> PluginConfig {
        let mut plugin_config = HashMap::new();

        for config in rpc_configs {
            let config_type = match config.ctype.as_str() {
                "String" => {
                    if let Value::String(s) = config.set_val {
                        ConfigTypes::String(s)
                    } else {
                        continue; // Should not happen due to validation
                    }
                }
                "Bool" => {
                    if let Value::Bool(b) = config.set_val {
                        ConfigTypes::Bool(b)
                    } else {
                        continue;
                    }
                }
                "Int" => {
                    if let Some(i) = config.set_val.as_i64() {
                        ConfigTypes::Int(i as i32)
                    } else {
                        continue;
                    }
                }
                "UInt" => {
                    if let Some(u) = config.set_val.as_u64() {
                        ConfigTypes::UInt(u as u32)
                    } else {
                        continue;
                    }
                }
                "BigInt" => {
                    if let Some(i) = config.set_val.as_i64() {
                        ConfigTypes::BigInt(i as i128)
                    } else if let Value::String(s) = &config.set_val {
                        if let Ok(i) = s.parse::<i128>() {
                            ConfigTypes::BigInt(i)
                        } else {
                            continue;
                        }
                    } else {
                        continue;
                    }
                }
                "BigUInt" => {
                    if let Some(u) = config.set_val.as_u64() {
                        ConfigTypes::BigUInt(u as u128)
                    } else if let Value::String(s) = &config.set_val {
                        if let Ok(u) = s.parse::<u128>() {
                            ConfigTypes::BigUInt(u)
                        } else {
                            continue;
                        }
                    } else {
                        continue;
                    }
                }
                "Float" => {
                    if let Some(f) = config.set_val.as_f64() {
                        ConfigTypes::Float(f as f64)
                    } else {
                        continue;
                    }
                }
                _ => continue, // Should not happen due to validation
            };

            plugin_config.insert(config.key, config_type);
        }

        plugin_config
    }

    pub fn set_plugin_config(
        &mut self,
        path: String,
        key: String,
        value: ConfigTypes,
    ) -> Result<(), PluginManErr> {
        let ppath = std::path::PathBuf::from(path.clone());
        let ppar = ppath.parent().ok_or_else(|| {
            PluginManErr::MetadataNotFound("Cannot determine plugin directory".to_string())
        })?;

        // Build metadata file path
        let stem: PathBuf = PathBuf::from(ppath.file_stem().unwrap());
        let nfn = stem.with_extension("json");
        let pmet = ppar.join(nfn);

        // Check if metadata file exists
        if !pmet.exists() {
            return Err(PluginManErr::MetadataNotFound(
                pmet.to_string_lossy().to_string(),
            ));
        }

        // Read and parse existing metadata
        let metadata_content = fs::read_to_string(&pmet)
            .map_err(|_| PluginManErr::MetadataNotFound(pmet.to_string_lossy().to_string()))?;

        let mut metadata: Value = from_str(&metadata_content)
            .map_err(|_| PluginManErr::InvalidMeta(pmet.to_string_lossy().to_string()))?;

        // Find and update the specific RPC config
        if let Some(Value::Array(rpc_array)) = metadata.get_mut("rpc") {
            let mut found = false;

            for item in rpc_array.iter_mut() {
                if let Some(Value::String(item_key)) = item.get("key") {
                    if item_key == &key {
                        // Convert ConfigTypes to Value for serialization
                        let new_value = match &value {
                            ConfigTypes::String(s) => Value::String(s.clone()),
                            ConfigTypes::Bool(b) => Value::Bool(*b),
                            ConfigTypes::Int(i) => Value::Number(serde_json::Number::from(*i)),
                            ConfigTypes::UInt(u) => Value::Number(serde_json::Number::from(*u)),
                            ConfigTypes::BigInt(i) => {
                                if let Some(num) = serde_json::Number::from_f64(*i as f64) {
                                    Value::Number(num)
                                } else {
                                    Value::String(i.to_string())
                                }
                            }
                            ConfigTypes::BigUInt(u) => {
                                if let Some(num) = serde_json::Number::from_f64(*u as f64) {
                                    Value::Number(num)
                                } else {
                                    Value::String(u.to_string())
                                }
                            }
                            ConfigTypes::Float(f) => {
                                if let Some(n) = serde_json::Number::from_f64(*f as f64) {
                                    Value::Number(n)
                                } else {
                                    Value::String(f.to_string())
                                }
                            }
                        };

                        item["set_val"] = new_value;
                        found = true;
                        break;
                    }
                }
            }

            if !found {
                return Err(PluginManErr::InvalidMeta(format!(
                    "Key '{}' not found in plugin metadata",
                    key
                )));
            }
        } else {
            return Err(PluginManErr::InvalidMeta(
                "No RPC configuration found in metadata".to_string(),
            ));
        }

        // Write updated metadata back to file
        let updated_content = serde_json::to_string_pretty(&metadata).map_err(|_| {
            PluginManErr::InvalidMeta("Failed to serialize updated metadata".to_string())
        })?;

        fs::write(&pmet, updated_content).map_err(|_| {
            PluginManErr::InvalidMeta("Failed to write updated metadata file".to_string())
        })?;

        // Update in-memory configuration only if plugin is loaded
        if let Some(plugin_inode) = self.plugin_meta.get_mut(&path) {
            if let Some(config) = &mut plugin_inode.config {
                config.insert(key, value);
            } else {
                // If no config exists yet, create a new one
                let mut new_config = PluginConfig::new();
                new_config.insert(key, value);
                plugin_inode.config = Some(new_config);
            }
        }

        Ok(())
    }

    fn valid_extension(&self, path: &PathBuf) -> bool {
        if path.extension() == Some(OsStr::new("wasm")) {
            true
        } else {
            false
        }
    }

    fn valid_stem(&self, path: &PathBuf) -> bool {
        let stem = path.file_stem();
        if stem.is_none() {
            false
        } else {
            stem.and_then(OsStr::to_str)
                .map(|s| !s.contains('.'))
                .unwrap_or(true)
        }
    }

    fn valid_magic(&self, path: &PathBuf) -> bool {
        let mut fp = std::fs::File::open(path).expect("Failed to open file");
        let mut buf = [0; 4];
        fp.read_exact(&mut buf).expect("Failed to read from file");
        buf == [0x00, 0x61, 0x73, 0x6d] // Does the file have the magic bytes of a wasm file?
    }

    fn plugin_file_validity(&self, path: PathBuf) -> bool {
        self.valid_extension(&path) && self.valid_magic(&path) && self.valid_stem(&path)
    }

    pub fn scan_dir(&self, path: PathBuf) -> Option<Vec<PathBuf>> {
        // Make sure the path is valid
        if !path.exists() {
            return None;
        }
        if !path.is_dir() {
            return None;
        }
        let mut ppaths: Vec<PathBuf> = vec![];
        // Iterate through each entry
        for e in fs::read_dir(path).ok()? {
            let e = e.ok()?;
            // If its a dir (we do this because we want to follow symlinks)
            if metadata(e.path()).ok()?.is_dir() {
                // Iterate through everything inside it to see if its a valid plugin
                for w in fs::read_dir(e.path()).ok()? {
                    let w = w.ok()?;
                    if metadata(w.path()).ok()?.is_file() {
                        if self.plugin_file_validity(w.path()) {
                            ppaths.push(w.path());
                        }
                    }
                }
                // If its a file check if its a valid plugin
            } else if metadata(e.path()).ok()?.is_file() {
                if self.plugin_file_validity(e.path()) {
                    ppaths.push(e.path());
                }
            }
        }
        Some(ppaths)
    }

    pub fn load_plugin(&mut self, path: String) -> Result<(), PluginManErr> {
        let ppath = std::path::PathBuf::from(path.clone());
        if ppath.exists() {
            if self.plugin_meta.contains_key(&path) {
                eprintln!("Plugin already loaded");
                return Err(PluginManErr::PluginAlreadyLoaded(path));
            }
            if !self.valid_extension(&PathBuf::from(path.clone())) {
                eprintln!("Invalid plugin extension");
                return Err(PluginManErr::BadFile(path));
            }
            if !self.valid_stem(&PathBuf::from(path.clone())) {
                eprintln!(
                    "Plugin file has no stem, add a name before the extension to ensure the metadata can be reliably read"
                );
                return Err(PluginManErr::BadFile(path));
            }
            if !self.valid_magic(&PathBuf::from(path.clone())) {
                eprintln!(
                    "The wasm file provided does not have the valid magic numbers which could mean it is not a wasm file"
                );
                return Err(PluginManErr::BadFile(path));
            }
            let ppar = ppath.parent();
            if ppar.is_none() {
                eprintln!(
                    "The parent dir is either root or an empty string, fix this to ensure the plugin and metadata can be used correctly"
                );
                return Err(PluginManErr::MetadataNotFound(path));
            }
            let stem: PathBuf = PathBuf::from(PathBuf::from(path.clone()).file_stem().unwrap());
            let nfn = stem.with_extension("json");
            let pmet = ppar.unwrap().join(nfn);

            let (rpc_configs, fad_config) = if pmet.exists() {
                match Self::read_plugin_metadata(&pmet) {
                    Ok((rpc, fad)) => (rpc, fad),
                    Err(_) => {
                        eprintln!("Warning: Failed to read metadata, using empty config");
                        (Some(Vec::new()), None)
                    }
                }
            } else {
                eprintln!("Warning: No metadata found, using empty config");
                (Some(Vec::new()), None)
            };

            let mut plugin_config: Option<PluginConfig> = None;
            if let Some(configs) = rpc_configs {
                plugin_config = Some(Self::rpc2plugin(configs));
            }

            let pfile = Wasm::file(path.clone());
            let mut m = Manifest::new([pfile]);

            if let Some(config) = &plugin_config {
                let config_iter = config.iter().map(|(k, v)| {
                    let value_string = match v {
                        ConfigTypes::String(s) => s.to_string(),
                        ConfigTypes::Bool(b) => b.to_string(),
                        ConfigTypes::Int(i) => i.to_string(),
                        ConfigTypes::UInt(u) => u.to_string(),
                        ConfigTypes::BigInt(i) => i.to_string(),
                        ConfigTypes::BigUInt(u) => u.to_string(),
                        ConfigTypes::Float(f) => f.to_string(),
                    };
                    (k.clone(), value_string)
                });
                m = m.with_config(config_iter);
            }

            let plugin: Plugin = add_functions(PluginBuilder::new(m).with_wasi(false))
                .build()
                .unwrap();

            let pin = PluginInode {
                plugin: Arc::new(Mutex::new(plugin)),
                config: plugin_config,
                fad: fad_config,
            };

            self.plugin_meta.insert(path.clone(), pin);

            if let Some(pentry) = self.plugin_meta.get(&path) {
                let pluginst: &Arc<Mutex<Plugin>> = &pentry.plugin;
                let mut pluginstl = pluginst.lock().unwrap();
                if pluginstl.function_exists("init") {
                    let r: core::result::Result<&str, anyhow::Error> = pluginstl.call("init", ());
                    if r.is_err() {
                        return Err(PluginManErr::PluginError(r.err().map(|e| e.to_string())));
                    } else {
                        return Ok(());
                    };
                }
            }
            Ok(())
        } else {
            Err(PluginManErr::FileNotFound(path))
        }
    }

    pub fn remove_plugin(&mut self, path: String) -> Result<(), PluginManErr> {
        let pentry = self
            .plugin_meta
            .remove(&path)
            .ok_or_else(|| PluginManErr::PluginNotLoaded(path.clone()))?;

        let mut pluginstl = pentry.plugin.lock().unwrap();
        if pluginstl.function_exists("stop") {
            let r: core::result::Result<&str, anyhow::Error> = pluginstl.call("stop", ());
            if let Err(e) = r {
                return Err(PluginManErr::PluginError(Some(e.to_string())));
            }
        }

        Ok(())
    }

    pub fn reload_plugin(&mut self, path: String) -> Result<(), PluginManErr> {
        let r = self.remove_plugin(path.clone());
        if r.is_err() {
            return r;
        } else {
            let l = self.load_plugin(path);
            if l.is_err() {
                return l;
            } else {
                Ok(())
            }
        }
    }

    pub fn get_plugin_config(&self, path: String) -> Result<Option<PluginConfig>, PluginManErr> {
        self.plugin_meta
            .get(&path)
            .map(|pinode| pinode.config.clone())
            .ok_or_else(|| PluginManErr::PluginNotLoaded(path))
    }

    pub fn get_plugin_meta(&self, path: String) -> Result<String, String> {
        let ppath = std::path::PathBuf::from(path.clone());
        let ppar = ppath
            .parent()
            .ok_or_else(|| "Cannot determine plugin directory".to_string())?;

        let stem: PathBuf = PathBuf::from(
            ppath
                .file_stem()
                .ok_or_else(|| "Invalid plugin file name".to_string())?,
        );
        let nfn = stem.with_extension("json");
        let pmet = ppar.join(nfn);

        if !pmet.exists() {
            return Err("Metadata file not found".to_string());
        }

        let metadata_content =
            fs::read_to_string(&pmet).map_err(|_| "Failed to read metadata file".to_string())?;

        Ok(metadata_content)
    }

    pub fn call_func_plugins(&self, func: &str) {
        for (path, plugin_inode) in &self.plugin_meta {
            let plugin = &plugin_inode.plugin;
            let mut plugin_guard = match plugin.lock() {
                Ok(guard) => guard,
                Err(e) => {
                    eprintln!("Failed to lock plugin mutex for {}: {}", path, e);
                    continue;
                }
            };

            if plugin_guard.function_exists(func) {
                let result: Result<&str, extism::Error> = plugin_guard.call(func, ());
                if let Err(e) = result {
                    eprintln!(
                        "Error running function '{}' on plugin '{}': {}",
                        func, path, e
                    );
                }
            }
        }
    }

    pub fn call_plugin_func(&self, func: &str, plugin: &str) -> bool {
        if let Some(pin) = &self.plugin_meta.get(plugin) {
            let ph = &pin.plugin;
            let mut plugin_guard = match ph.lock() {
                Ok(guard) => guard,
                Err(e) => {
                    eprintln!("Failed to lock plugin mutex for {plugin}: {e}");
                    return false;
                }
            };
            if plugin_guard.function_exists(func) {
                let res: Result<&str, extism::Error> = plugin_guard.call(func, ());
                if let Err(e) = res {
                    eprintln!("Failed running function {func} on {plugin} due to: {e}");
                    return false;
                }
                return true;
            } else {
                return false;
            }
        } else {
            eprintln!("Failed to find {plugin} within hashmap");
            return false;
        }
    }

    pub fn get_all_buttons(&self, location_filter: Option<&str>) -> Vec<(String, FadButton)> {
        let mut all_buttons = Vec::new();

        // Validate the location filter if provided
        if let Some(location) = location_filter {
            if !ALLOWED_BUTTON_LOCATIONS.contains(&location) {
                eprintln!(
                    "Warning: Invalid location filter '{}', returning no buttons",
                    location
                );
                return all_buttons;
            }
        }

        for (plugin_path, plugin_inode) in &self.plugin_meta {
            if let Some(fad_config) = &plugin_inode.fad {
                // Get top-level buttons
                if let Some(buttons) = &fad_config.buttons {
                    for button in buttons {
                        if location_filter.map_or(true, |loc| {
                            button
                                .location
                                .as_ref()
                                .map_or(false, |btn_loc| btn_loc == loc)
                        }) {
                            all_buttons.push((plugin_path.clone(), button.clone()));
                        }
                    }
                }

                // Get buttons from screens
                if let Some(screens) = &fad_config.screens {
                    for screen in screens {
                        if let Some(buttons) = &screen.buttons {
                            for button in buttons {
                                if location_filter.map_or(true, |loc| {
                                    button
                                        .location
                                        .as_ref()
                                        .map_or(false, |btn_loc| btn_loc == loc)
                                }) {
                                    all_buttons.push((plugin_path.clone(), button.clone()));
                                }
                            }
                        }
                    }
                }

                // Get buttons from popups
                if let Some(popups) = &fad_config.popups {
                    for popup in popups {
                        if let Some(buttons) = &popup.buttons {
                            for button in buttons {
                                if location_filter.map_or(true, |loc| {
                                    button
                                        .location
                                        .as_ref()
                                        .map_or(false, |btn_loc| btn_loc == loc)
                                }) {
                                    all_buttons.push((plugin_path.clone(), button.clone()));
                                }
                            }
                        }
                    }
                }
            }
        }

        all_buttons
    }

    // Get all screens from all plugins
    pub fn get_all_screens(&self) -> Vec<(String, FadScreen)> {
        let mut all_screens = Vec::new();

        for (plugin_path, plugin_inode) in &self.plugin_meta {
            if let Some(fad_config) = &plugin_inode.fad {
                if let Some(screens) = &fad_config.screens {
                    for screen in screens {
                        all_screens.push((plugin_path.clone(), screen.clone()));
                    }
                }
            }
        }

        all_screens
    }

    // Get all popups from all plugins
    pub fn get_all_popups(&self) -> Vec<(String, FadPopup)> {
        let mut all_popups = Vec::new();

        for (plugin_path, plugin_inode) in &self.plugin_meta {
            if let Some(fad_config) = &plugin_inode.fad {
                if let Some(popups) = &fad_config.popups {
                    for popup in popups {
                        all_popups.push((plugin_path.clone(), popup.clone()));
                    }
                }
            }
        }

        all_popups
    }

    // Get FAD configuration for a specific plugin
    pub fn get_plugin_fad_config(&self, path: String) -> Option<FadConfig> {
        self.plugin_meta
            .get(&path)
            .and_then(|pinode| pinode.fad.clone())
    }

    // Find buttons by name (across all plugins)
    pub fn find_buttons_by_name(&self, name: &str) -> Vec<(String, FadButton)> {
        self.get_all_buttons(None)
            .into_iter()
            .filter(|(_, button)| button.name == name)
            .collect()
    }

    // Find items by callback (buttons, screens, popups that have this callback)
    pub fn find_items_by_callback(&self, callback: &str) -> Vec<(String, String)> {
        let mut results = Vec::new();

        for (plugin_path, plugin_inode) in &self.plugin_meta {
            if let Some(fad_config) = &plugin_inode.fad {
                // Check top-level buttons
                if let Some(buttons) = &fad_config.buttons {
                    for button in buttons {
                        if button.callback == callback {
                            results.push((plugin_path.clone(), format!("button:{}", button.name)));
                        }
                    }
                }

                // Check screen buttons
                if let Some(screens) = &fad_config.screens {
                    for (screen_idx, screen) in screens.iter().enumerate() {
                        if let Some(buttons) = &screen.buttons {
                            for button in buttons {
                                if button.callback == callback {
                                    results.push((
                                        plugin_path.clone(),
                                        format!("screen_{}:button:{}", screen_idx, button.name),
                                    ));
                                }
                            }
                        }
                    }
                }

                // Check popup buttons
                if let Some(popups) = &fad_config.popups {
                    for (popup_idx, popup) in popups.iter().enumerate() {
                        if let Some(buttons) = &popup.buttons {
                            for button in buttons {
                                if button.callback == callback {
                                    results.push((
                                        plugin_path.clone(),
                                        format!("popup_{}:button:{}", popup_idx, button.name),
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }

        results
    }
}

unsafe impl Send for AdiPluginMan {}
unsafe impl Sync for AdiPluginMan {}

// Initialzes the plugin manager in a static variable
pub fn init_plugin_man() {
    let mut pmg = PLUGIN_MAN.lock().unwrap();
    if pmg.is_none() {
        *pmg = Some(AdiPluginMan::new())
    }
}

// Checks if the plugin manager is initialized
pub fn check_plugin_man(pmg: &Option<AdiPluginMan>) -> bool {
    if pmg.is_some() { true } else { false }
}

// Loads a plugin using the given path
pub fn load_plugin(path: String) -> Result<String, String> {
    let mut pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return Err(format!("[ERR]: {}", PluginManErr::PluginManNotLoaded));
    }
    let res: Result<(), PluginManErr> = pmg.as_mut().unwrap().load_plugin(path.clone());
    match res {
        Ok(()) => Ok(format!(
            "Loaded plugin: {}",
            PathBuf::from(path)
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .to_string()
        )),
        Err(e) => {
            eprintln!("{}", format!("{e}"));
            Err(format!("Failed to load plugin: {e}"))
        }
    }
}

// Removes a plugin (if loaded) at a given path
pub fn remove_plugin(path: String) -> Result<String, String> {
    let mut pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return Err(format!("[ERR]: {}", PluginManErr::PluginManNotLoaded));
    }
    let res: Result<(), PluginManErr> = pmg.as_mut().unwrap().remove_plugin(path.clone());
    match res {
        Ok(()) => Ok(format!(
            "Removed plugin {}",
            PathBuf::from(path)
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .to_string()
        )),
        Err(e) => {
            eprintln!("{}", format!("{e}"));
            Err(format!("Failed to remove plugin: {e}"))
        }
    }
}

// Returns a json string which is the plugins config
pub fn get_plugin_config(path: String) -> String {
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        match plugin_man.get_plugin_meta(path) {
            Ok(metadata_content) => metadata_content,
            Err(e) => {
                eprintln!("Failed to get plugin config from metadata: {}", e);
                format!("Failed to get plugin config: {}", e)
            }
        }
    } else {
        format!("{}", PluginManErr::PluginManNotLoaded)
    }
}

// Returns None on error or an array of all paths (as strings) that are valid wasm file plugins
pub fn scan_dir(path: String) -> Option<Vec<String>> {
    let pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return None;
    }
    pmg.as_ref()
        .unwrap()
        .scan_dir(PathBuf::from(path))
        .map(|pb| {
            pb.into_iter()
                .filter_map(|pbuf| Some(pbuf.to_string_lossy().to_string()))
                .collect()
        })
}

// Reloads the plugin given as a path
pub fn reload_plugin(path: String) -> Result<String, String> {
    let mut pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return Err("[ERR]: Plugin man not loaded".to_string());
    }

    let res: Result<(), PluginManErr> = pmg.as_mut().unwrap().reload_plugin(path.clone());
    match res {
        Ok(()) => Ok(format!(
            "Reloaded plugin: {}",
            PathBuf::from(path)
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .to_string()
        )),
        Err(e) => {
            eprintln!("{}", format!("{e}"));
            Err(format!("Failed to reload plugin: {e}"))
        }
    }
}

// Checks if the given path is a loaded plugin
pub fn is_plugin_loaded(path: String) -> bool {
    let pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return false;
    }

    pmg.as_ref().unwrap().plugin_meta.contains_key(&path)
}

// Returns an array of loaded plugins
pub fn list_loaded_plugins() -> Vec<String> {
    let pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return Vec::new();
    }

    pmg.as_ref().unwrap().plugin_meta.keys().cloned().collect()
}

pub fn set_plugin_config(path: String, key: String, value: ConfigTypes) -> Result<String, String> {
    let mut pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return Err(format!("[ERR]: {}", PluginManErr::PluginManNotLoaded));
    }

    match pmg
        .as_mut()
        .unwrap()
        .set_plugin_config(path.clone(), key.clone(), value)
    {
        Ok(()) => Ok(format!(
            "Updated config key '{}' for plugin: {}",
            key,
            PathBuf::from(path)
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .to_string()
        )),
        Err(e) => {
            eprintln!("{}", format!("{e}"));
            Err(format!("Failed to set plugin config: {e}"))
        }
    }
}

pub fn call_func_plugins(func: String) {
    if !check_plugins_enabled() {
        return;
    }
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        plugin_man.call_func_plugins(&func);
    } else {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
    }
}

pub fn call_plugin_func(func: String, plugin: String) -> bool {
    if !check_plugins_enabled() {
        return false;
    }
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        plugin_man.call_plugin_func(&func, &plugin)
    } else {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return false;
    }
}

// Get all buttons, optionally filtered by location
pub fn get_all_buttons(location_filter: Option<String>) -> String {
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        let buttons = plugin_man.get_all_buttons(location_filter.as_deref());
        serde_json::to_string(&buttons).unwrap_or_else(|_| "[]".to_string())
    } else {
        "[]".to_string()
    }
}

// Get all screens
pub fn get_all_screens() -> String {
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        let screens = plugin_man.get_all_screens();
        serde_json::to_string(&screens).unwrap_or_else(|_| "[]".to_string())
    } else {
        "[]".to_string()
    }
}

// Get all popups
pub fn get_all_popups() -> String {
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        let popups = plugin_man.get_all_popups();
        serde_json::to_string(&popups).unwrap_or_else(|_| "[]".to_string())
    } else {
        "[]".to_string()
    }
}

// Get FAD config for a specific plugin
pub fn get_plugin_fad_config(path: String) -> String {
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        if let Some(fad_config) = plugin_man.get_plugin_fad_config(path) {
            serde_json::to_string(&fad_config).unwrap_or_else(|_| "null".to_string())
        } else {
            "null".to_string()
        }
    } else {
        "null".to_string()
    }
}

// Find buttons by name
pub fn find_buttons_by_name(name: String) -> String {
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        let buttons = plugin_man.find_buttons_by_name(&name);
        serde_json::to_string(&buttons).unwrap_or_else(|_| "[]".to_string())
    } else {
        "[]".to_string()
    }
}

// Find items by callback
pub fn find_items_by_callback(callback: String) -> String {
    let pmg = PLUGIN_MAN.lock().unwrap();

    if let Some(plugin_man) = pmg.as_ref() {
        let items = plugin_man.find_items_by_callback(&callback);
        serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string())
    } else {
        "[]".to_string()
    }
}
