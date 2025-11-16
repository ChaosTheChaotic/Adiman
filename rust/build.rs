use dotenvy::dotenv_iter;

fn main() {
    println!("cargo:rerun-if-changed=.env");
    
    for item in dotenv_iter().unwrap() {
        let (key, value) = item.unwrap();
        println!("cargo:rustc-env={key}={value}");
    }
}
