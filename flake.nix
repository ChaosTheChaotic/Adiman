{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, flake-utils, naersk, nixpkgs, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = (import nixpkgs) {
          inherit system overlays;
        };

        graphics = with pkgs; [
          vulkan-headers
          vulkan-loader
          vulkan-tools
          vulkan-validation-layers
          shaderc
          shaderc.bin
          shaderc.static
          shaderc.dev
          shaderc.lib
        ];

        buildInputs = with pkgs; [
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          udev
          alsa-lib
          libxkbcommon

          zlib
          
          gdb
          flutter
	  flutter_rust_bridge_codegen
          libayatana-appindicator # For flutter notifications plugin
          gtk3
          wayland
          
          openssl
          openssl.dev

	  libcdio
	  libcdio-paranoia
	  cdparanoia
        ];

        nativeBuildInputs = with pkgs; [
          libsigcxx
          stdenv.cc
          gnumake
          binutils
          ncurses5
          libGLU
          libGL
          pkg-config
          gcc-unwrapped
          clang
          ninja
          llvmPackages.libclang
          lld
          mold
          rustup
	  cargo-expand
        ];
        
        all_deps = with pkgs; [
          nixpkgs-fmt
          cmake
          protoc-gen-prost
          just
        ] ++ buildInputs ++ nativeBuildInputs ++ graphics;
      in
      rec {
        devShell = pkgs.mkShell {

          nativeBuildInputs = all_deps;

          VULKAN_LIB_DIR="${pkgs.shaderc.dev}/lib";
          VULKAN_SDK="${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";

          FLUTTER_ROOT = "${pkgs.flutter}";

          CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "${pkgs.llvmPackages.clangUseLLVM}/bin/clang";

          RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
          PATH = "~/.cargo/bin:$PATH"; # So that cargo binaries are available

          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath all_deps}";
          
          HF_HUB_ENABLE_HF_TRANSFER = 1;
          
          shellHook = ''
            export CARGO_MANIFEST_DIR=$(pwd) # This is declared here because it seems the project root is not accessible in the flake
            export LD_LIBRARY_PATH="$(pwd)/build/linux/x64/debug/bundle/lib:$(pwd)/build/linux/x64/release/bundle/lib:$(pwd)/build/linux/arm64/debug/bundle/lib:$(pwd)/build/linux/arm64/release/bundle/lib:$LD_LIBRARY_PATH"
          ''; # That last line is so that dart can find the rust libs
        };
      }
    );
}
