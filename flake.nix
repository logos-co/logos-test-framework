{
  description = "Logos Test Framework — unit testing for Logos modules without Qt boilerplate";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    nixpkgs.follows = "logos-nix/nixpkgs";
  };

  outputs = { self, nixpkgs, logos-nix, logos-cpp-sdk, ... }:
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

      # Development shell for working on the framework
      devShells = forAllSystems ({ pkgs, system, ... }:
        let
          logosSdk = logos-cpp-sdk.packages.${system}.default;
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
            ];
            shellHook = ''
              export LOGOS_CPP_SDK_ROOT="${logosSdk}"
              export LOGOS_TEST_FRAMEWORK_ROOT="${./.}"
              echo "Logos Test Framework development environment"
            '';
          };
        }
      );
    };
}
