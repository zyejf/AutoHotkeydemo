fn main() {
    tauri_build::build();

    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let manifest_path = format!("{manifest_dir}\\windows-app-manifest.xml");

    println!("cargo:rustc-link-arg-bench=/MANIFEST:EMBED");
    println!("cargo:rustc-link-arg-bench=/MANIFESTINPUT:{manifest_path}");

    if std::env::var("CARGO_FEATURE_TEST_MANIFEST").is_ok() {
        println!("cargo:rustc-link-arg=/MANIFEST:EMBED");
        println!("cargo:rustc-link-arg=/MANIFESTINPUT:{manifest_path}");
    }
}
