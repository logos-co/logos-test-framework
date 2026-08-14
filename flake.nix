{
  description = "Logos Test Framework — unit testing for Logos modules without Qt boilerplate";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-protocol = {
      url = "github:logos-co/logos-protocol";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Qt HOST RUNTIME a module test links: LogosAPI, LogosAPIProvider and
    # the provider bases, shipped as `logos-qt-host`. It used to come from
    # logos-qt-sdk; LogosTest.cmake now names logos-qt-host::logos_qt_host.
    logos-plugin-qt = {
      url = "github:logos-co/logos-plugin-qt";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-protocol.follows = "logos-protocol";
    };
    # Still an input: logos-qt-sdk ships the Qt-typed consumer headers that are
    # NOT part of the host runtime (logos_qt_lp_bridge.h, logos_qt_wire.h,
    # logos_ui_plugin_context.h), and LogosTest.cmake keeps accepting
    # LOGOS_QT_SDK_ROOT for callers that have not moved yet.
    logos-qt-sdk = {
      url = "github:logos-co/logos-qt-sdk";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-protocol.follows = "logos-protocol";
      inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    };
    nixpkgs.follows = "logos-nix/nixpkgs";
  };

  outputs = { self, nixpkgs, logos-nix, logos-cpp-sdk, logos-protocol, logos-plugin-qt, logos-qt-sdk, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
      });
    in
    {
      # Library functions for building module tests
      lib = {
        mkLogosModuleTests = args: import ./nix/mkLogosModuleTests.nix args;
      };

      # The framework as a package (headers + cmake + sources)
      packages = forAllSystems ({ pkgs, system, ... }:
        let
          logosSdk = logos-cpp-sdk.packages.${system}.default;

          frameworkPkg = pkgs.stdenv.mkDerivation {
            pname = "logos-test-framework";
            version = "0.1.0";
            src = ./.;

            # No build step — just install headers, cmake, and sources
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/include $out/cmake $out/src

              cp include/*.h $out/include/
              cp cmake/*.cmake $out/cmake/
              cp src/*.cpp $out/src/
            '';

            meta = with pkgs.lib; {
              description = "Logos Module Test Framework";
              license = licenses.mit;
            };
          };
        in {
          default = frameworkPkg;
        }
      );

      # Build the shipped examples through LogosTest.cmake. This is the only
      # place the framework's own CMake gets exercised: every other consumer
      # drives it from their repo, so without these a repoint of the host
      # runtime would be unverifiable here.
      #
      # Both roots are covered on purpose. `example-tests` is the repointed
      # path (logos-qt-host::logos_qt_host); `example-tests-qt-sdk` is the
      # pre-split path callers still take until they pass LOGOS_QT_HOST_ROOT,
      # and it is here so a change to the new path cannot quietly break it.
      checks = forAllSystems ({ pkgs, system, ... }:
        let
          mkExampleTests = { name, logosQtHost ? null, logosQtSdk ? null }:
            (import ./nix/mkLogosModuleTests.nix {
              inherit pkgs logosQtHost logosQtSdk;
              src = ./.;
              testDir = ./examples/basic-module-test;
              logosSdk = logos-cpp-sdk.packages.${system}.default;
              logosProtocol = logos-protocol.packages.${system}.default;
              testFramework = self.packages.${system}.default;
            }).overrideAttrs (_: { pname = name; });
        in {
          example-tests = mkExampleTests {
            name = "logos-test-framework-example-tests";
            logosQtHost = logos-plugin-qt.packages.${system}.logos-qt-host;
          };

          example-tests-qt-sdk = mkExampleTests {
            name = "logos-test-framework-example-tests-qt-sdk";
            logosQtSdk = logos-qt-sdk.packages.${system}.default;
          };
        }
      );

      # Development shell for working on the framework
      devShells = forAllSystems ({ pkgs, system, ... }:
        let
          logosSdk = logos-cpp-sdk.packages.${system}.default;
          logosQtHost = logos-plugin-qt.packages.${system}.logos-qt-host;
          logosQtSdk = logos-qt-sdk.packages.${system}.default;
          logosProtocol = logos-protocol.packages.${system}.default;
        in {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              cmake
              pkg-config
              qt6.wrapQtAppsHook
            ];
            buildInputs = with pkgs; [
              qt6.qtbase
              qt6.qtremoteobjects
              logosSdk
              logosQtHost
              logosQtSdk
              logosProtocol
            ];
            shellHook = ''
              export LOGOS_CPP_SDK_ROOT="${logosSdk}"
              export LOGOS_QT_HOST_ROOT="${logosQtHost}"
              export LOGOS_QT_SDK_ROOT="${logosQtSdk}"
              export LOGOS_PROTOCOL_ROOT="${logosProtocol}"
              export LOGOS_TEST_FRAMEWORK_ROOT="${./.}"
              echo "Logos Test Framework development environment"
            '';
          };
        }
      );
    };
}
