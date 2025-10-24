use crate::api::value_store::{check_value_store_state, acquire_read_lock};
use extism::{host_fn, CurrentPlugin, Function, PluginBuilder, UserData, Val, PTR};
use flutter_rust_bridge::frb;

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
host_fn!(get_store_state() -> bool {
    Ok(check_value_store_state())
});
// A template set that most functions I add will conform to
fn generic_func_template_pr<F>(name: &str, func: F) -> Function
where
    F: Sync
        + Send
        + 'static
        + Fn(&mut CurrentPlugin, &[Val], &mut [Val], UserData<()>) -> Result<(), extism::Error>,
{
    Function::new(name, [PTR], [PTR], UserData::new(()), func)
}

fn generic_func_template_r<F>(name: &str, func: F) -> Function
where
    F: Sync
        + Send
        + 'static
        + Fn(&mut CurrentPlugin, &[Val], &mut [Val], UserData<()>) -> Result<(), extism::Error>,
{
    Function::new(name, [], [PTR], UserData::new(()), func)
}

fn generic_func_template_p<F>(name: &str, func: F) -> Function
where
    F: Sync
        + Send
        + 'static
        + Fn(&mut CurrentPlugin, &[Val], &mut [Val], UserData<()>) -> Result<(), extism::Error>,
{
    Function::new(name, [PTR], [], UserData::new(()), func)
}

#[frb(ignore)]
pub fn add_functions(b: PluginBuilder) -> PluginBuilder {
    let f = vec![
        generic_func_template_p("pprint", pprint),
        generic_func_template_r("get_music_folder", get_music_folder),
        generic_func_template_r("get_store_state", get_store_state),
    ];
    b.with_functions(f)
}
