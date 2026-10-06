{
  description = "PhotoCraft - An open-source, native image editor written in Rust";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
        version = cargoToml.workspace.package.version;

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "clippy" ];
        };

        nativeBuildInputs = with pkgs; [
          pkg-config
          rustToolchain
        ];

        buildInputs = with pkgs; [
          # Wayland/X11 dependencies for wgpu/egui
          libxkbcommon
          wayland
          wayland-protocols
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXi
          xorg.libXext
          # OpenGL/Vulkan
          libGL
          vulkan-loader
          # Font/config
          fontconfig
          freetype
          # File dialogs, clipboard
          libnotify
        ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
          alsa-lib
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          darwin.apple_sdk.frameworks.AppKit
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.Metal
          darwin.apple_sdk.frameworks.QuartzCore
          darwin.apple_sdk.frameworks.Security
        ];

        # Common build args
        cargoExtraArgs = "--locked";

        # Build the CLI
        photocraft-cli = pkgs.rustPlatform.buildRustPackage {
          pname = "photocraft-cli";
          inherit version;

          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;

          cargoBuildFlags = [ "${cargoExtraArgs}" "-p" "photocraft-cli" ];
          cargoTestFlags = [ "${cargoExtraArgs}" "-p" "photocraft-cli" ];

          meta = with pkgs.lib; {
            description = "Command-line interface for PhotoCraft";
            homepage = "https://getartcraft.com/apps/photocraft";
            license = with licenses; [ mit asl20 ];
            maintainers = [ ];
            mainProgram = "photocraft-cli";
          };
        };

        # Build the desktop app
        photocraft = pkgs.rustPlatform.buildRustPackage {
          pname = "photocraft";
          inherit version;

          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;

          cargoBuildFlags = [ "${cargoExtraArgs}" "-p" "photocraft" ];
          cargoTestFlags = [ "${cargoExtraArgs}" "-p" "photocraft" ];

          # Don't require Windows resource compiler on non-Windows builds
          env = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            PHOTOCRAFT_REQUIRE_WINRES = "0";
          };

          meta = with pkgs.lib; {
            description = "Native image editor written in Rust";
            homepage = "https://getartcraft.com/apps/photocraft";
            license = with licenses; [ mit asl20 ];
            maintainers = [ ];
            mainProgram = "photocraft";
          };
        };
      in
      {
        packages = {
          inherit photocraft-cli photocraft;
          default = photocraft;
        };

        apps = {
          photocraft-cli = flake-utils.lib.mkApp {
            drv = photocraft-cli;
            name = "photocraft-cli";
          };
          photocraft = flake-utils.lib.mkApp {
            drv = photocraft;
            name = "photocraft";
          };
          default = self.apps.${system}.photocraft;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ photocraft photocraft-cli ];
          nativeBuildInputs = with pkgs; [
            rustToolchain
            cargo-edit
            cargo-watch
            cargo-deny
            cargo-nextest
            cargo-outdated
            cargo-flamegraph
            # For xtask and other tools
            just
            # For web build if needed
            trunk
            wasm-bindgen-cli
            # For packaging linting
            shellcheck
            actionlint
            nfpm
          ];
          buildInputs = buildInputs ++ (with pkgs; [
            # Additional dev tools
            openssl
            pkg-config
          ]);
          shellHook = ''
            echo "PhotoCraft development environment"
            echo "Version: ${version}"
            echo "Rust: $(rustc --version)"
            echo "Cargo: $(cargo --version)"
          '';
        };

        formatter = pkgs.nixpkgs-fmt;

        homeManagerModules.default = { pkgs, ... }: {
          home.packages = with pkgs; [ photocraft-cli ];
        };
      });
}
