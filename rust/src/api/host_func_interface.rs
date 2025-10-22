use extism::{host_fn, CurrentPlugin, Function, PluginBuilder, UserData, Val, PTR};
use flutter_rust_bridge::frb;
use crate::api::settings_store::MUSIC_FOLDER;

#[frb(ignore)]
host_fn!(pprint(user_data: (); m: String) {
    println!("[PLUGIN LOG]: {m}");
    Ok(())
});

#[frb(ignore)]
host_fn!(get_music_folder(user_data: ()) -> String {
    let g = MUSIC_FOLDER.lock().unwrap();
    Ok((*g).clone())
});

// A template set that most functions I add will conform to
fn generic_func_template_r<F>(name: &str, func: F) -> Function
where
    F: Sync
        + Send
        + 'static
        + Fn(&mut CurrentPlugin, &[Val], &mut [Val], UserData<()>) -> Result<(), extism::Error>,
{
    Function::new(name, [PTR], [PTR], UserData::new(()), func)
}

fn generic_func_template<F>(name: &str, func: F) -> Function
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
    let f = vec![generic_func_template("pprint", pprint)];
    b.with_functions(f)
}
