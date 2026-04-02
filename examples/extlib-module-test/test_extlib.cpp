// Example: Testing a module that wraps a C library.
// The C library is mocked at link time — mock stubs in mocks/ replace
// the real library functions.

#include <logos_test.h>

// Pretend this is the module's C library header
extern "C" {
    int calc_add(int a, int b);
    const char* calc_version();
}

LOGOS_TEST(calc_add_returns_mocked_value) {
    auto t = LogosTestContext("calc_module");
    t.mockCFunction("calc_add").returns(99);

    // When the module calls calc_add(), it gets the mocked value
    int result = calc_add(10, 20);
    LOGOS_ASSERT_EQ(result, 99);
    LOGOS_ASSERT(t.cFunctionCalled("calc_add"));
}

LOGOS_TEST(calc_version_returns_mocked_string) {
    auto t = LogosTestContext("calc_module");
    t.mockCFunction("calc_version").returns("mock-1.0");

    const char* ver = calc_version();
    LOGOS_ASSERT_EQ(std::string(ver), std::string("mock-1.0"));
    LOGOS_ASSERT(t.cFunctionCalled("calc_version"));
}

LOGOS_TEST(calc_functions_track_call_count) {
    auto t = LogosTestContext("calc_module");
    t.mockCFunction("calc_add").returns(0);

    calc_add(1, 2);
    calc_add(3, 4);
    calc_add(5, 6);

    LOGOS_ASSERT_EQ(t.cFunctionCallCount("calc_add"), 3);
}
