# Logos Test Framework

Unit testing framework for Logos modules. Supports mocking calls to other modules and to libraries.

## Features

- **Module mocking** — mock calls to other Logos modules with a fluent API
- **C library mocking** — link-time substitution for external C/C++ libraries
- **Event testing** — capture and assert on events emitted by the module
- **Color terminal output** — auto-detects TTY, clean pass/fail formatting
- **JSON output** — `--json` flag for CI and agent consumption
- **Test filtering** — `--filter <pattern>` to run a subset of tests
- **10-line CMake** — `logos_test()` replaces ~150 lines of boilerplate
- **Nix integration** — `mkLogosModuleTests` for zero-config builds

## Quick Start

### 1. Write tests

```cpp
// tests/test_my_feature.cpp
#include <logos_test.h>
#include "my_module_impl.h"

LOGOS_TEST(feature_returns_expected_value) {
    auto t = LogosTestContext("my_module");
    t.mockModule("other_module", "getData").returns(42);

    MyModuleImpl impl;
    t.init(&impl);

    auto result = impl.fetchData();
    LOGOS_ASSERT_EQ(result, 42);
    LOGOS_ASSERT(t.moduleCalled("other_module", "getData"));
}
```

```cpp
// tests/main.cpp
#include <logos_test.h>
LOGOS_TEST_MAIN()
```

### 2. CMake (tests/CMakeLists.txt)

```cmake
cmake_minimum_required(VERSION 3.14)
project(MyModuleTests LANGUAGES CXX)

include(LogosTest)

logos_test(
    NAME my_module_tests
    MODULE_SOURCES ../src/my_module_impl.cpp
    TEST_SOURCES
        main.cpp
        test_my_feature.cpp
)
```

### 3. Run

```bash
./my_module_tests                    # colored output
./my_module_tests --json             # machine-readable
./my_module_tests --filter feature   # run matching tests
```

## Mocking Other Modules

```cpp
LOGOS_TEST(calls_waku_module) {
    auto t = LogosTestContext("chat_module");
    t.mockModule("waku_module", "relayPublish").returns(true);

    ChatImpl impl;
    t.init(&impl);

    impl.sendMessage("hello");
    LOGOS_ASSERT(t.moduleCalled("waku_module", "relayPublish"));
    LOGOS_ASSERT_EQ(t.moduleCallCount("waku_module", "relayPublish"), 1);
}
```

## Mocking C Libraries

### 1. Write mock stubs (`tests/mocks/mock_libcalc.cpp`)

```cpp
#include <logos_clib_mock.h>
extern "C" { #include "libcalc.h" }

extern "C" int calc_add(int a, int b) {
    LOGOS_CMOCK_RECORD("calc_add");
    return LOGOS_CMOCK_RETURN(int, "calc_add");
}

extern "C" const char* calc_version() {
    LOGOS_CMOCK_RECORD("calc_version");
    return LOGOS_CMOCK_RETURN_STRING("calc_version");
}
```

### 2. Reference in CMake

```cmake
logos_test(
    NAME calc_module_tests
    MODULE_SOURCES ../src/calc_module_impl.cpp
    TEST_SOURCES main.cpp test_calc.cpp
    MOCK_C_SOURCES mocks/mock_libcalc.cpp
)
```

### 3. Use in tests

```cpp
LOGOS_TEST(add_returns_mocked_value) {
    auto t = LogosTestContext("calc_module");
    t.mockCFunction("calc_add").returns(99);

    CalcModuleImpl impl;
    t.init(&impl);

    auto result = impl.add(10, 20);
    LOGOS_ASSERT_EQ(result, 99);
    LOGOS_ASSERT(t.cFunctionCalled("calc_add"));
}
```

## Event Testing

```cpp
LOGOS_TEST(method_emits_event) {
    auto t = LogosTestContext("my_module");
    t.captureEvents();

    MyModuleImpl impl;
    t.init(&impl);

    impl.doSomething("data");

    LOGOS_ASSERT(t.eventEmitted("myEvent"));
    LOGOS_ASSERT_EQ(t.eventCount("myEvent"), 1);
    LOGOS_ASSERT_EQ(t.lastEventData("myEvent").at(0).toString(), "data");
}
```

## Assertions

| Macro | Description |
|-------|-------------|
| `LOGOS_ASSERT(expr)` | Expression is truthy |
| `LOGOS_ASSERT_TRUE(expr)` | Alias for LOGOS_ASSERT |
| `LOGOS_ASSERT_FALSE(expr)` | Expression is falsy |
| `LOGOS_ASSERT_EQ(a, b)` | `a == b` with diff on failure |
| `LOGOS_ASSERT_NE(a, b)` | `a != b` |
| `LOGOS_ASSERT_GT(a, b)` | `a > b` |
| `LOGOS_ASSERT_GE(a, b)` | `a >= b` |
| `LOGOS_ASSERT_LT(a, b)` | `a < b` |
| `LOGOS_ASSERT_LE(a, b)` | `a <= b` |
| `LOGOS_ASSERT_CONTAINS(h, n)` | String `h` contains `n` |
| `LOGOS_ASSERT_THROWS(expr)` | Expression throws |

## Terminal Output

```
 ── my_module_tests ─────────────────────────

   PASS  feature_returns_expected_value            2ms
   PASS  handles_empty_input                       1ms
   FAIL  handles_error_case                        3ms
         ASSERT_EQ failed: expected [true] got [false]
         at test_my_feature.cpp:42

 ── Results: 2 passed, 1 failed (6ms) ──────
```

## Nix Integration

### In module's flake.nix

```nix
checks.${system}.unit-tests = logos-test-framework.lib.mkLogosModuleTests {
  inherit pkgs;
  src = ./.;
  testDir = ./tests;
  configFile = ./metadata.json;
  logosSdk = logos-cpp-sdk.packages.${system}.default;
  testFramework = logos-test-framework.packages.${system}.default;
};
```

### Via logos-module-builder (ultimate goal)

```nix
logos-module-builder.lib.mkLogosModule {
  src = ./.;
  configFile = ./metadata.json;
  flakeInputs = inputs;
  tests = {
    dir = ./tests;
    mockCLibs = ["gowalletsdk"];
  };
};
```

## CLI Options

```
./my_module_tests [options]
  --filter <pattern>  Run only tests whose name contains pattern
  --json              Output results as JSON (for CI/agents)
  --no-color          Disable colored output
  --help              Show help
```
