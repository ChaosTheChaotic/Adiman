# Plugins
As of update 1.3.0, Adiman now supports plugins.
# Adding plugins
> [!WARNING]
> Adding plugins is unsafe in itself as you allow random people to run arbitrary code on your machine.
> I have done my best to ensure a level of security with the safe and unsafe APIs.
> By choosing to add to plugins you accept all risk that comes with it
> By enabling unsafe APIs (which let plugins to essentially anything on your machine), you also accept the greater risk that comes with it
- In the app in settings, enable plugins and specify a plugin directory (or use the default one)
- Create a folder inside the plugin directory (optional)
- Ensure the `.json` file (if any) has the same name as the `.wasm` file (the `.wasm` file is checked for first)
- Add the `.wasm` and `.json` plugin files inside the created directry or the plugin directory
- Go to the plugins section inside the app and enable it (the set directory is scanned and valid plugins are recognised and loaded automatically)

## Troubleshooting
- Make sure that the plugin is enabled (this happens more than you think)
- Make sure that settings are done right (this also happens more than you think)
- Run the app through in a terminal (by simply running the path to the apps executable) and see if any errors get printed out
- Fix the plugin yourself
- Contact the plugin developer for help

# Developing plugins
You may develop plugins in any language that [extism](https://github.com/extism/extism) supports (as it is the framework I use for plugins)

## Starting
- First create a new plugin using extism and ensure it works
- After this you may then import the host functions I provide from the app including:
    - Filesystem APIs
    - App interaction APIs
    - System info APIs
    - Utility APIs
    - Logging API
    - Unsafe APIs (APIs which let you do almost anything to the system, turned off by default and heavily discouraged but can be used)
        - Filesystem APIs
        - Command APIs
        - Network APIs
        - Utility APIs
- To see (and copy) all functions exported by my app see the [host_functions](host_functions.rs)
- Now you may make functions that the app will call (if the plugin exports that function)
- Functions that are called by the app that you could add:
    - init - When the plugin initializes, this is called
    - stop - When the plugin is disabled or stops, this is called
    - play_song - Called when a song is played
    - pause_song - Called when a song is paused
    - resume_song - Called when a song is resumed
    - seek_to_position - Called when user seeks through the song
    - set_volume - Called when user sets volume

### A simple example plugin in rust
```rs
use extism_pdk::*;
use serde::{Deserialize, Serialize};

#[host_fn]
extern "ExtismHost" {
    fn pprint(m: String);
    fn get_music_folder() -> String;
    fn get_current_song() -> Option<SongMetadata>;
    fn get_store_state() -> bool;
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

fn gprint_times() -> u32 {
    let ptms = config::get("print_times").expect("print_times key set in config");
    let pt = ptms.unwrap_or("1".to_owned());
    let t: u32 = pt.parse().expect("Failed to parse print_times to an int");
    t
}

#[plugin_fn]
pub fn init() -> FnResult<()> {
    let pt = gprint_times();
    for n in 0..=pt {
        let _ = unsafe { pprint(format!("Hello, world! {n}").to_string()) };
    }
    let _ = unsafe { pprint(format!("The value store is fine?: {}", get_store_state().unwrap_or(false)))};
    let _ = unsafe { pprint(format!("{}", get_music_folder().unwrap_or("None".to_string())).to_string()) };
    Ok(())
}

#[plugin_fn]
pub fn stop() -> FnResult<()> {
    let pt = gprint_times();
    for n in 0..=pt {
        let _ = unsafe { pprint(format!("Stop {n}").to_string()) };
    }
    let _ = unsafe { pprint("Stopping".to_string()) };
    Ok(())
}

#[plugin_fn]
pub fn play_song() -> FnResult<()> {
    let _ = unsafe {
        pprint(format!("Current song: {}", get_current_song()?.unwrap().title))
    };
    Ok(())
}
```
#### Other notes
- Every host function returns a Result enum and every plugin returns a Result enum too
- You can handle errors in communication using the `?` operator to return an error from the plugin
- Plugin functions returns are ignored, the app just checks for errors

## Plugin Metadata
The above plugin would have the following json metadata in order to work
```json
{
  "rpc": [
    {
      "ctype": "UInt",
      "default_val": 1,
      "key": "print_times",
      "set_val": 1
    }
  ]
}
```
The rpc field is an array of configs
Each config takes
- ctype - The type of the config that should be taken in
    - The config type has restrictions on allowed types being
        - String
        - Bool
        - Int (i32, a signed 32 bit int)
        - UInt (u32, an unsigned 32 bit int)
        - BigInt (i128, a signed 128 bit int)
        - BigUInt (u128, an unsigned 128 bit int),
        - Float (f64, a 64 bit float)
    - The BigInt and BigUInt can be passed in as numbers/values or as strings
- default_val - The default value of the config, must match the ctype set above
- key - The key via which your plugin might access the value
- set_val - The value set by the user and what will be passed in through the key
