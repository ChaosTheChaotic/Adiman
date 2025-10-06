pub use extism::{Manifest, Plugin, PluginBuilder, Wasm};
pub use std::{
    collections::HashMap,
    error::Error,
    ffi::OsStr,
    io::Read,
    sync::{Arc, Mutex},
};

#[derive(Debug)]
pub enum PluginManErr {
    FileNotFound(String),
    BadFile(String),
    PluginError(Option<String>),
    PluginNotLoaded(String),
}

impl std::fmt::Display for PluginManErr {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let err: String = match self {
            PluginManErr::FileNotFound(path) => format!("File not found: {path}"),
            PluginManErr::BadFile(path) => format!("Provided file is not a wasm file: {path}"),
            PluginManErr::PluginError(e) => format!(
                "A plugin error occurred: {}",
                e.clone().unwrap_or("No error message returned".into())
            ),
            PluginManErr::PluginNotLoaded(path) => format!("Plugin: {path} is not loaded"),
        };
        write!(f, "{err}")
    }
}

impl Error for PluginManErr {}

#[derive(Clone)]
pub enum ConfigTypes {
    String(String),
    Bool(bool),
    Int(i32),
    UInt(u32),
    BigInt(i128),
    BigUInt(u128),
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

    pub fn load_plugin(
        &mut self,
        path: String,
        pconf: Option<PluginConfig>,
    ) -> Result<(), PluginManErr> {
        let ppath = std::path::PathBuf::from(path.clone());
        if ppath.exists() {
            let ext = ppath.extension();
            let wasm_ext: bool = ext == Some(OsStr::new("wasm"));
            let stem = ppath.file_stem();
            let stem_clean: bool = stem
                .and_then(OsStr::to_str)
                .map(|s| !s.contains('.'))
                .unwrap_or(true);
            let mut fp = std::fs::File::open(ppath).expect("Failed to open file");
            let mut buf = [0; 4];
            fp.read_exact(&mut buf).expect("Faild to read from file");
            let magic_clean: bool = buf == [0x00, 0x61, 0x73, 0x6d]; // Do the first 4 bytes match the wasm magic number?
            let valid: bool = wasm_ext && stem_clean && magic_clean;
            if valid {
                let pfile = Wasm::file(path.clone());
                let config_iter;
                let m: Manifest = if let Some(ref conf) = pconf {
                    // Convert the PluginConfig into an iterator of (String, String)
                    config_iter = conf.into_iter().map(|(k, v)| {
                        let value_string = match v {
                            ConfigTypes::String(s) => s.to_string(),
                            ConfigTypes::Bool(b) => b.to_string(),
                            ConfigTypes::Int(i) => i.to_string(),
                            ConfigTypes::UInt(u) => u.to_string(),
                            ConfigTypes::BigInt(i) => i.to_string(),
                            ConfigTypes::BigUInt(u) => u.to_string(),
                        };
                        (k, value_string)
                    });
                    Manifest::new([pfile]).with_config(config_iter)
                } else {
                    Manifest::new([pfile])
                };
                let plugin: Plugin = PluginBuilder::new(m).with_wasi(false).build().unwrap();
                let pin = PluginInode {
                    plugin: Arc::new(Mutex::new(plugin)),
                    config: pconf.unwrap_or(HashMap::new()),
                };
                self.plugin_meta.insert(path.clone(), pin);
                if let Some(pentry) = self.plugin_meta.get(&path) {
                    let pluginst: &Arc<Mutex<Plugin>> = &pentry.plugin;
                    let mut pluginstl = pluginst.lock().unwrap();
                    if pluginstl.function_exists("init") {
                        let r: core::result::Result<&str, anyhow::Error> =
                            pluginstl.call("init", ());
                        if r.is_err() {
                            return Err(PluginManErr::PluginError(r.err().map(|e| e.to_string())));
                        } else {
                            return Ok(());
                        };
                    }
                }
                Ok(())
            } else {
                Err(PluginManErr::BadFile(path))
            }
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
}
