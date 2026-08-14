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
#     logosQtHost = logos-plugin-qt.packages.${system}.logos-qt-host;
#     logosProtocol = logos-protocol.packages.${system}.default;
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
  # The Qt host runtime (logos-plugin-qt's `logos-qt-host`). Preferred.
, logosQtHost ? null
  # Pre-split home of the same runtime. Still accepted so callers that have not
  # moved keep building; logosQtHost wins when both are given.
, logosQtSdk ? null
, logosProtocol
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

  # LogosTest.cmake refuses to configure without a host runtime; say so here,
  # where the caller can see which argument is missing.
  qtLayerRoots = lib.optional (logosQtHost != null) logosQtHost
              ++ lib.optional (logosQtSdk != null) logosQtSdk;

in
assert lib.assertMsg (qtLayerRoots != [])
  ("mkLogosModuleTests: pass logosQtHost (logos-plugin-qt's logos-qt-host "
   + "package) — or, for the pre-split layout, logosQtSdk.");

pkgs.stdenv.mkDerivation {
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
    logosProtocol
    testFramework
  ] ++ qtLayerRoots;

  cmakeFlags = [
    "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
    "-DLOGOS_PROTOCOL_ROOT=${logosProtocol}"
    "-DLOGOS_TEST_FRAMEWORK_ROOT=${testFramework}"
    # A test CMakeLists starts with `include(LogosTest)`, which resolves off
    # CMAKE_MODULE_PATH. Without this the configure fails on an unknown
    # `logos_test` command, never reaching any of the roots above.
    "-DCMAKE_MODULE_PATH=${testFramework}/cmake"
  ]
  ++ lib.optional (logosQtHost != null) "-DLOGOS_QT_HOST_ROOT=${logosQtHost}"
  ++ lib.optional (logosQtSdk != null) "-DLOGOS_QT_SDK_ROOT=${logosQtSdk}"
  ++ extraCmakeFlags;

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

  installPhase = ''
    mkdir -p $out/bin

    find . -maxdepth 2 -type f -executable \( -name "*_tests" -o -name "*_test" \) | while read bin; do
      cp "$bin" $out/bin/
    done
  '';

  # Run tests as a check.
  #
  # The binaries are located and executed directly rather than through ctest.
  # `ctest` reports "No tests were found!!!" and exits 0, so a test project
  # that registered nothing — a real outcome here — produced a green check
  # that ran no tests at all. Finding zero binaries is now a hard failure.
  doCheck = true;
  checkPhase = ''
    runHook preCheck

    echo "Running module unit tests..."
    testBins=$(find . -maxdepth 2 -type f -executable \( -name "*_tests" -o -name "*_test" \) | sort)
    if [ -z "$testBins" ]; then
      echo "ERROR: no test executable was built (looked for *_tests / *_test)" >&2
      exit 1
    fi
    for bin in $testBins; do
      echo "Executing: $bin"
      "$bin"
    done

    runHook postCheck
  '';
}
