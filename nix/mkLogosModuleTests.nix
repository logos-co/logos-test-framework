# mkLogosModuleTests — Nix builder for Logos module unit tests
#
# Builds the test executable from test sources, module sources, and the
# logos-test-framework. Runs the tests as a derivation so they can be
# used as `checks.<system>.unit-tests` in a module's flake.
#
# Usage (in a module's flake.nix):
#
#   checks.${system}.unit-tests = logos-test-framework.lib.mkLogosModuleTests {
#     inherit pkgs;
#     src = ./.;
#     testDir = ./tests;
#     configFile = ./metadata.json;
#     logosSdk = logos-cpp-sdk.packages.${system}.default;
#     testFramework = logos-test-framework.packages.${system}.default;
#     moduleDeps = { test_basic_module = inputs.test_basic_module.packages.${system}.default; };
#     mockCLibs = [ "gowalletsdk" ];    # optional
#     preConfigure = "";                  # optional
#   };

{ pkgs
, src
, testDir
, configFile ? null
, logosSdk
, testFramework
, moduleDeps ? {}
, mockCLibs ? []
, preConfigure ? ""
, extraBuildInputs ? []
, extraCmakeFlags ? []
}:

let
  lib = pkgs.lib;

  # Copy dependency include files into generated_code/
  depIncludeSetup = lib.concatMapStringsSep "\n" (name:
    let dep = moduleDeps.${name} or null;
    in if dep != null then ''
      if [ -d "${dep}/include" ]; then
        echo "Copying include files from ${name}..."
        cp -r "${dep}/include"/* ./generated_code/ 2>/dev/null || true
      fi
    '' else ""
  ) (lib.attrNames moduleDeps);

in pkgs.stdenv.mkDerivation {
  pname = "logos-module-tests";
  version = "0.0.1";

  inherit src;

  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
  ] ++ extraBuildInputs;

  buildInputs = with pkgs; [
    qt6.qtbase
    qt6.qtremoteobjects
    logosSdk
    testFramework
  ];

  cmakeFlags = [
    "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
    "-DLOGOS_TEST_FRAMEWORK_ROOT=${testFramework}"
  ] ++ extraCmakeFlags;

  # Build from the test directory
  cmakeDir = toString testDir;

  preConfigure = ''
    # Set up generated code directory
    mkdir -p ./generated_code

    # Copy dependency includes
    ${depIncludeSetup}

    # Run logos-cpp-generator if available and metadata exists
    ${lib.optionalString (configFile != null) ''
      if command -v logos-cpp-generator &>/dev/null && [ -f "${configFile}" ]; then
        echo "Running logos-cpp-generator..."
        logos-cpp-generator --metadata "${configFile}" --general-only --output-dir ./generated_code || true
      fi
    ''}

    # Custom preConfigure
    ${preConfigure}
  '';

  buildPhase = ''
    cmake --build . --parallel $NIX_BUILD_CORES
  '';

  # Run the tests and store the result
  installPhase = ''
    mkdir -p $out/bin

    # Find and copy test binary
    find . -maxdepth 2 -type f -executable -name "*_tests" | head -1 | while read bin; do
      cp "$bin" $out/bin/
    done

    # Also try CTest
    ctest --output-on-failure --timeout 60 || true
  '';

  # Run tests as a check
  doCheck = true;
  checkPhase = ''
    echo "Running module unit tests..."
    ctest --output-on-failure --timeout 60
  '';
}
