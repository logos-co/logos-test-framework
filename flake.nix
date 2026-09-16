{
  description = "Logos Test Framework — unit testing for Logos modules without Qt boilerplate";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    # logos-plugin-qt and logos-qt-sdk follow this, so the closure builds one protocol.
    logos-protocol = {
      url = "github:logos-co/logos-protocol";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # logos-qt-host: the Qt host runtime (LogosAPI, provider bases) a module test links.
    logos-plugin-qt = {
      url = "github:logos-co/logos-plugin-qt";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.logos-protocol.follows = "logos-protocol";
    };
    # Qt-typed consumer headers (logos_qt_wire.h, ...). Its plugin-qt must follow
    # ours: qt-sdk propagates the logos-qt-host it resolved.
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

          # A package-shaped library: lib/libextfixture.a, include/extfixture/.
          extfixture = pkgs.runCommandCC "extfixture" { } ''
            mkdir -p $out/lib $out/include/extfixture
            cat > $out/include/extfixture/extfixture.h <<'EOF'
            #pragma once
            #ifdef __cplusplus
            extern "C" {
            #endif
            int extfixture_answer(void);
            #ifdef __cplusplus
            }
            #endif
            EOF
            echo 'int extfixture_answer(void) { return 42; }' > extfixture.c
            $CC -c -fPIC extfixture.c -o extfixture.o
            $AR rcs $out/lib/libextfixture.a extfixture.o
          '';

          # logos_test(EXTERNAL_LIBS) from each place it looks.
          mkExternalLibTests = { name, preConfigure }:
            (import ./nix/mkLogosModuleTests.nix {
              inherit pkgs preConfigure;
              src = ./.;
              testDir = ./examples/extlib-link-test;
              logosSdk = logos-cpp-sdk.packages.${system}.default;
              logosQtHost = logos-plugin-qt.packages.${system}.logos-qt-host;
              logosQtSdk = logos-qt-sdk.packages.${system}.default;
              logosProtocol = logos-protocol.packages.${system}.default;
              testFramework = self.packages.${system}.default;
            }).overrideAttrs (_: { pname = name; });
        in {
          example-tests = mkExampleTests {
            name = "logos-test-framework-example-tests";
            logosQtHost = logos-plugin-qt.packages.${system}.logos-qt-host;
            logosQtSdk = logos-qt-sdk.packages.${system}.default;
          };

          external-libs-root = mkExternalLibTests {
            name = "logos-test-framework-external-libs-root";
            preConfigure = "export LOGOS_EXT_ROOT_EXTFIXTURE=${extfixture}";
          };

          # The module builders stage lib/* and include/* into one directory.
          external-libs-staged = mkExternalLibTests {
            name = "logos-test-framework-external-libs-staged";
            preConfigure = ''
              mkdir -p examples/lib
              cp -r ${extfixture}/lib/* ${extfixture}/include/* examples/lib/
            '';
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
