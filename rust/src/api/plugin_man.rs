use crate::api::host_func_interface::add_functions;
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
            PluginManErr::PluginAlreadyLoaded(path) => format!("The plugin: {path} was already loaded"),
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
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct RpcConfig {
    pub key: String,
    pub ctype: String,
    pub default_val: Value,
    pub set_val: Value,
}

pub type PluginConfig = HashMap<String, ConfigTypes>; // A key-value pair with a key and a config type

pub struct PluginInode {
    pub plugin: Arc<Mutex<Plugin>>, // Plugin handle wrapped in an Arc and Mutex because frb keeps generating code trying to clone it
    pub config: PluginConfig,       // Plugins config
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

    fn read_plugin_metadata(
        metadata_path: &std::path::Path,
    ) -> Result<Vec<RpcConfig>, PluginManErr> {
        let metadata_content = std::fs::read_to_string(metadata_path).map_err(|_| {
            PluginManErr::MetadataNotFound(metadata_path.to_string_lossy().to_string())
        })?;

        let metadata: Value = from_str(&metadata_content)
            .map_err(|_| PluginManErr::InvalidMeta(metadata_path.to_string_lossy().to_string()))?;

        let rpc_array = match metadata.get("rpc") {
            Some(Value::Array(arr)) => arr,
            Some(_) => {
                // rpc exists but is not an array
                eprintln!(
                    "Warning: 'rpc' field is not an array in metadata file: {}",
                    metadata_path.display()
                );
                return Ok(Vec::new());
            }
            None => {
                // rpc doesent exist
                return Ok(Vec::new());
            }
        };

        let mut valid_configs = Vec::new();

        for (index, item) in rpc_array.iter().enumerate() {
            if let Ok(rpc_config) = from_value::<RpcConfig>(item.clone()) {
                if Self::validate_rpc(&rpc_config) {
                    valid_configs.push(rpc_config);
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

        Ok(valid_configs)
    }

    fn validate_rpc(config: &RpcConfig) -> bool {
        if config.key.is_empty() {
            return false;
        }

        match config.ctype.as_str() {
            "String" => {
                matches!(config.default_val, Value::String(_)) &&
                matches!(config.set_val, Value::String(_))
            }
            "Bool" => {
                matches!(config.default_val, Value::Bool(_)) &&
                matches!(config.set_val, Value::Bool(_))
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
                let s = if let Some(num) = config.default_val.as_u64() {
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
                let s = if let Some(_) = config.default_val.as_i64() {
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
                let s = if let Some(_) = config.default_val.as_u64() {
                    true
                } else if let Some(str_val) = config.default_val.as_str() {
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
                let s = if let Some(_) = config.default_val.as_f64() {
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
                _ => continue, // Should not happen due to validation
            };

            plugin_config.insert(config.key, config_type);
        }

        plugin_config
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

            let plugin_config = if pmet.exists() {
                match Self::read_plugin_metadata(&pmet) {
                    Ok(rpc_configs) => Self::rpc2plugin(rpc_configs),
                    Err(_) => {
                        eprintln!("Warning: Failed to read metadata, using empty config");
                        HashMap::new()
                    }
                }
            } else {
                // No metadata found
                eprintln!(
                    "Warning: Plugin: {} has no metadata file found and therefore no plugin settings will be loaded",
                    PathBuf::from(path.clone())
                        .file_stem()
                        .unwrap()
                        .to_string_lossy()
                        .to_string()
                );
                HashMap::new()
            };

            let pfile = Wasm::file(path.clone());

            let config_iter = plugin_config.iter().map(|(k, v)| {
                let value_string = match v {
                    ConfigTypes::String(s) => s.to_string(),
                    ConfigTypes::Bool(b) => b.to_string(),
                    ConfigTypes::Int(i) => i.to_string(),
                    ConfigTypes::UInt(u) => u.to_string(),
                    ConfigTypes::BigInt(i) => i.to_string(),
                    ConfigTypes::BigUInt(u) => u.to_string(),
                };
                (k.clone(), value_string)
            });

            let m = Manifest::new([pfile]).with_config(config_iter);
            let plugin: Plugin = add_functions(PluginBuilder::new(m).with_wasi(false))
                .build()
                .unwrap();

            let pin = PluginInode {
                plugin: Arc::new(Mutex::new(plugin)),
                config: plugin_config,
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

    pub fn get_plugin_config(&self, path: String) -> Result<PluginConfig, PluginManErr> {
        self.plugin_meta
            .get(&path)
            .map(|pinode| pinode.config.clone())
            .ok_or_else(|| PluginManErr::PluginNotLoaded(path))
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
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return format!("[ERR]: {}", PluginManErr::PluginManNotLoaded);
    }

    match pmg.as_ref().unwrap().get_plugin_config(path) {
        Ok(config) => serde_json::to_string(&config)
            .unwrap_or_else(|_| "Failed to serialize config".to_string()),
        Err(e) => {
            eprintln!("{}", format!("{e}"));
            format!("Failed to get plugin config: {e}")
        }
    }
}

// Returns None on error or an array of all paths (as strings) that are valid wasm file plugins
pub fn scan_dir(path: String) -> Option<Vec<String>> {
    let pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return None
    }
    pmg.as_ref().unwrap().scan_dir(PathBuf::from(path)).map(|pb| {
        pb.into_iter().filter_map(|pbuf| Some(pbuf.to_string_lossy().to_string())).collect()
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
    
    pmg.as_ref()
        .unwrap()
        .plugin_meta
        .contains_key(&path)
}

// Returns an array of loaded plugins
pub fn list_loaded_plugins() -> Vec<String> {
    let pmg = PLUGIN_MAN.lock().unwrap();
    if !check_plugin_man(&*pmg) {
        eprintln!("{}", PluginManErr::PluginManNotLoaded);
        return Vec::new();
    }
    
    pmg.as_ref()
        .unwrap()
        .plugin_meta
        .keys()
        .cloned()
        .collect()
}
