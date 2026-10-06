{
  description = "PhotoCraft - An open-source, native image editor written in Rust";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [
          (import rust-overlay)
        ];

        pkgs = import nixpkgs {
          inherit system overlays;
        };

        cargoToml =
          builtins.fromTOML (builtins.readFile ./Cargo.toml);

        version = cargoToml.workspace.package.version;

        rustToolchain =
          pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "rust-analyzer"
              "clippy"
            ];
          };

        nativeBuildInputs = with pkgs; [
          pkg-config
          rustToolchain
        ];

        buildInputs = with pkgs; [
          # Wayland / X11
          libxkbcommon
          wayland
          wayland-protocols
          libX11
          libXcursor
          libXrandr
          libXi
          libXext
          libxcb

          # OpenGL / Vulkan
          libGL
          vulkan-loader
          mesa

          # Fonts / configuration
          fontconfig
          freetype

          # Notifications
          libnotify
        ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [
          alsa-lib
        ]
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          darwin.apple_sdk.frameworks.AppKit
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.Metal
          darwin.apple_sdk.frameworks.QuartzCore
          darwin.apple_sdk.frameworks.Security
        ];

        cargoExtraArgs = "--locked";

        photocraft-cli = pkgs.rustPlatform.buildRustPackage {
          pname = "photocraft-cli";
          inherit version;

          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;

          cargoBuildFlags = [
            cargoExtraArgs
            "-p"
            "photocraft-cli"
          ];

          cargoTestFlags = [
            cargoExtraArgs
            "-p"
            "photocraft-cli"
          ];

          meta = with pkgs.lib; {
            description = "Command-line interface for PhotoCraft";
            homepage = "https://getartcraft.com/apps/photocraft";
            license = with licenses; [
              mit
              asl20
            ];
            maintainers = [ ];
            mainProgram = "photocraft-cli";
          };
        };

        photocraft = pkgs.rustPlatform.buildRustPackage {
          pname = "photocraft";
          inherit version;

          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = nativeBuildInputs ++ [
            pkgs.makeWrapper
          ];

          buildInputs = buildInputs;

          cargoBuildFlags = [
            cargoExtraArgs
            "-p"
            "photocraft"
          ];

          cargoTestFlags = [
            cargoExtraArgs
            "-p"
            "photocraft"
          ];

          env = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            PHOTOCRAFT_REQUIRE_WINRES = "0";
          };

          postInstall = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            wrapProgram $out/bin/photocraft \
              --prefix LD_LIBRARY_PATH : ${
                pkgs.lib.makeLibraryPath [
                  pkgs.wayland
                  pkgs.libxkbcommon
                  pkgs.vulkan-loader
                  pkgs.libGL
                  pkgs.mesa
                ]
              }
          '';

          meta = with pkgs.lib; {
            description = "Native image editor written in Rust";
            homepage = "https://getartcraft.com/apps/photocraft";
            license = with licenses; [
              mit
              asl20
            ];
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
          inputsFrom = [
            photocraft
            photocraft-cli
          ];

          nativeBuildInputs = with pkgs; [
            rustToolchain
            cargo-edit
            cargo-watch
            cargo-deny
            cargo-nextest
            cargo-outdated
            cargo-flamegraph
            just
            trunk
            wasm-bindgen-cli
            shellcheck
            actionlint
            nfpm
          ];

          buildInputs = buildInputs ++ (with pkgs; [
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
          home.packages = with pkgs; [
            photocraft-cli
          ];
        };
      });
}
