{
  description = "Logos Test Framework — unit testing for Logos modules without Qt boilerplate";

  # One of the five inputs below is still rev-pinned; the rest track master.
  # Most of the Qt host split (B1–B4) has landed: logos-protocol#59,
  # logos-cpp-sdk#138 and logos-plugin-qt#19 are all MERGED, so the three revs
  # this file used to pin are on their repos' masters and the plain urls below
  # both evaluate and compile. logos-qt-sdk is the exception — logos-qt-sdk#33
  # is still OPEN, so its master still re-exports the host headers this repo
  # stopped taking from it. That one pin stays until #33 merges.
  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    # Tracks master again. The a04b2788 pin existed to reach the capability
    # split; logos-cpp-sdk#138 ("split the SDK by capability, retire the
    # provider-header path, and harden the cdylib decode") MERGED, and master
    # (95d7b3a) carries cpp/logos_host_services.h and the rest of it. The PR was
    # squash-merged, so a04b2788 is not an ancestor of master — its content is.
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    # Tracks master again. The c8bab12 pin covered TokenManager::forIdentity /
    # isolateIdentity and the host-services C ABI; logos-protocol#59
    # ("per-client token store, the host-services C ABI, and a container
    # shape-check") MERGED, and master (f4407ff) has both
    # (forIdentity/isolateIdentity in cpp/token_manager.h,
    # lp_grant_host_services/lp_token_keys in cpp/logos_protocol.h). The PR was
    # squash-merged, so c8bab12 is not an ancestor of master — its content is.
    # logos-plugin-qt and logos-qt-sdk both `follows` this input, so the closure
    # still holds exactly one protocol.
    logos-protocol = {
      url = "github:logos-co/logos-protocol";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Qt HOST RUNTIME a module test links: LogosAPI, LogosAPIProvider and
    # the provider bases, shipped as `logos-qt-host`. It used to come from
    # logos-qt-sdk; LogosTest.cmake now names logos-qt-host::logos_qt_host.
    #
    # Tracks master again. The cc24fa1 pin existed because `logos-qt-host` did
    # not yet exist on plugin-qt's master; logos-plugin-qt#19 ("the Qt host
    # runtime and cdylib-glue generator") MERGED, and master (9b2c64e)
    # publishes logos-qt-host keyed by forAllTargets. The PR was squash-merged,
    # so cc24fa1 is not an ancestor of master — its content is.
    #
    # Still load-bearing: this must resolve to the SAME logos-qt-host that
    # logos-qt-sdk pulls in, or the example tests would link two copies of the
    # host runtime. logos-qt-sdk is still rev-pinned (below) and pins its own
    # logos-plugin-qt, so that input is made to `follows` this one.
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
    #
    # THE ONE PIN THAT STAYS. logos-qt-sdk#33 ("split the SDK by capability, and
    # retire the Qt-module backends") is still OPEN, so unlike the three inputs
    # above there is nothing on master to retire this rev in favour of: qt-sdk's
    # master still carries the forwarding headers this repo's LOGOS_QT_SDK_ROOT
    # block no longer expects to find. Drop the rev once #33 merges.
    #
    # Unpinned: feat/sdk-codegen-b3-d11 merged (logos-qt-sdk#33), so master has
    # the B3 shape this repo compiles against.
    #
    # The `logos-plugin-qt` follows below STAYS, and is now the only thing
    # holding the property the rev pin used to hold with it: qt-sdk's default
    # package propagates whatever logos-qt-host it resolved, so without the
    # follows the example tests could see two logos-qt-host store paths — one via
    # this input, one via the direct `logos-plugin-qt` — which is the duplicate-
    # host split-brain these pins were keeping shut. (qt-sdk master no longer
    # rev-pins plugin-qt itself, so both sides land on plugin-qt master; the
    # follows is what guarantees it rather than leaving it to coincidence.)
    logos-qt-sdk = {
      url = "github:logos-co/logos-qt-sdk";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-protocol.follows = "logos-protocol";
      inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
      inputs.logos-plugin-qt.follows = "logos-plugin-qt";
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
