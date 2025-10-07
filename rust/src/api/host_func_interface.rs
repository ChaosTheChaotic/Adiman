use extism::{CurrentPlugin, Function, PTR, PluginBuilder, UserData, Val, host_fn};
use flutter_rust_bridge::frb;

#[frb(ignore)]
host_fn!(pprint(user_data: (); m: String) {
    println!("[PLUGIN LOG]: {m}");
    Ok(())
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
