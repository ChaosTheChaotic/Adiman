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
	  pipewire
	  alsa-plugins
	  libpulseaudio
          libxkbcommon

          zlib
          
          gdb
          flutter329
	  flutter_rust_bridge_codegen
          libayatana-appindicator # For flutter notifications plugin
          gtk3
          wayland
          
          openssl
          openssl.dev

	  libcdio
	  libcdio-paranoia
	  cdparanoia

	  sqlite
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

	alsaConfig = pkgs.writeText "alsa-nix.conf" ''
    <${pkgs.alsa-lib}/share/alsa/alsa.conf>

    pcm_type.pipewire {
      lib ${pkgs.pipewire}/lib/alsa-lib/libasound_module_pcm_pipewire.so
    }
    ctl_type.pipewire {
      lib ${pkgs.pipewire}/lib/alsa-lib/libasound_module_ctl_pipewire.so
    }
    pcm_type.pulse {
      lib ${pkgs.alsa-plugins}/lib/alsa-lib/libasound_module_pcm_pulse.so
    }
    ctl_type.pulse {
      lib ${pkgs.alsa-plugins}/lib/alsa-lib/libasound_module_ctl_pulse.so
    }

    pcm.!default {
      type pipewire
    }
    ctl.!default {
      type pipewire
    }
	'';
      in
      rec {
        devShell = pkgs.mkShell {

          nativeBuildInputs = all_deps;

          VULKAN_LIB_DIR="${pkgs.shaderc.dev}/lib";
          VULKAN_SDK="${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";

          FLUTTER_ROOT = "${pkgs.flutter329}";

          CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "${pkgs.llvmPackages.clangUseLLVM}/bin/clang";

          RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
          PATH = "~/.cargo/bin:$PATH"; # So that cargo binaries are available

          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath all_deps}";
          
          HF_HUB_ENABLE_HF_TRANSFER = 1;

	  STORE_LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath all_deps;

	  ALSA_PLUGIN_DIRS = "${pkgs.alsa-plugins}/lib/alsa-lib:${pkgs.pipewire}/lib/alsa-lib";

	  ALSA_CONFIG_PATH = alsaConfig;

	  shellHook = ''
    	    export CARGO_MANIFEST_DIR=$(pwd)
            BUNDLE_PATH="$(pwd)/build/linux/x64/debug/bundle/lib:$(pwd)/build/linux/x64/release/bundle/lib:$(pwd)/build/linux/arm64/debug/bundle/lib:$(pwd)/build/linux/arm64/release/bundle/lib"
    	    export LD_LIBRARY_PATH="$STORE_LD_LIBRARY_PATH:$BUNDLE_PATH:$LD_LIBRARY_PATH"
    	  '';
        };
      }
    );
}
