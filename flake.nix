{
  description = "Logos Test Framework — unit testing for Logos modules without Qt boilerplate";

  # Four of the five inputs below are rev-pinned rather than master-tracking.
  # The Qt host split (B1–B4) lives on branches: the `logos-qt-host` package
  # this repo's LogosTest.cmake links does not exist on logos-plugin-qt's
  # master, logos-qt-sdk's master still re-exports the host headers this repo
  # stopped taking from it, and both need TokenManager::forIdentity from
  # logos-protocol's feat/per-client-token-store. An unpinned url would lock
  # onto masters that do not evaluate (missing package) or do not compile.
  # Re-point every one of them at master once the chain merges.
  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    # a04b2788 is the tip of logos-cpp-sdk's feat/sdk-codegen-b3-d11, a
    # fast-forward from that repo's master (contains e3744fb8).
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk/a04b27888e1d126578f639ed46dae0c777990a10";
    # c8bab12 is the tip of feat/per-client-token-store, a fast-forward from
    # protocol master (contains e6d5b57). logos-plugin-qt, logos-qt-sdk and
    # logos-cpp-sdk all pin this same rev, so the closure holds one protocol.
    logos-protocol = {
      url = "github:logos-co/logos-protocol/c8bab12834dbf92155b483546875e6078d17c74e";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Qt HOST RUNTIME a module test links: LogosAPI, LogosAPIProvider and
    # the provider bases, shipped as `logos-qt-host`. It used to come from
    # logos-qt-sdk; LogosTest.cmake now names logos-qt-host::logos_qt_host.
    #
    # cc24fa1 is the tip of feat/b4-qt-host-windows-target, rebased onto
    # plugin-qt master (8846fc5 is an ancestor of it). It replaces the previous
    # 8ccb1fc pin, which is a stale commit on feat/sdk-codegen-b3-d11 and is an
    # ancestor of NEITHER b4 branch. It must stay the same rev logos-qt-sdk
    # pins below, or the example tests would link two different qt-host copies.
    logos-plugin-qt = {
      url = "github:logos-co/logos-plugin-qt/cc24fa1c0c43b2d96c1dc165ee545a0321318b59";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-protocol.follows = "logos-protocol";
    };
    # Still an input: logos-qt-sdk ships the Qt-typed consumer headers that are
    # NOT part of the host runtime (logos_qt_lp_bridge.h, logos_qt_wire.h,
    # logos_ui_plugin_context.h), and LogosTest.cmake keeps accepting
    # LOGOS_QT_SDK_ROOT for callers that have not moved yet.
    #
    # 8a06b870 is the tip of feat/sdk-codegen-b3-d11, a fast-forward from
    # qt-sdk master (contains c6be61d). Its master still carries the forwarding
    # headers this repo's LOGOS_QT_SDK_ROOT block no longer expects to find.
    logos-qt-sdk = {
      url = "github:logos-co/logos-qt-sdk/8a06b870e59afca3392de2bddf8eec5fe3b85225";
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
      # drives it from their repo, so without this a repoint of the host
      # runtime would be unverifiable here.
      #
      # There used to be a second check, `example-tests-qt-sdk`, covering the
      # pre-split path where LOGOS_QT_SDK_ROOT alone supplied the host runtime.
      # logos-qt-sdk no longer carries those headers, so that path does not
      # exist to be covered — LogosTest.cmake now demands LOGOS_QT_HOST_ROOT.
      checks = forAllSystems ({ pkgs, system, ... }:
        let
          mkExampleTests = { name, logosQtHost, logosQtSdk ? null }:
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
