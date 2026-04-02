// Example: Testing a module that calls other Logos modules via IPC.
// Uses LogosTestContext to mock remote module calls.
// This mirrors what test-ipc-module-new-api does, but with the new framework.

#include <logos_test.h>

// In a real test, you'd include the module's impl header:
// #include "test_ipc_new_api_impl.h"

LOGOS_TEST(mock_basic_addInts) {
    auto t = LogosTestContext("test_ipc_module");
    t.mockModule("test_basic_module", "addInts").returns(30);

    // With real module:
    //   TestIpcNewApiImpl impl;
    //   t.init(&impl);
    //   int result = impl.callBasicAddInts(10, 20);
    //   LOGOS_ASSERT_EQ(result, 30);

    // Verify mock API works
    LOGOS_ASSERT_FALSE(t.moduleCalled("test_basic_module", "addInts"));
}

LOGOS_TEST(mock_extlib_reverse) {
    auto t = LogosTestContext("test_ipc_module");
    t.mockModule("test_extlib_module", "reverseString").returns("olleh");

    // With real module:
    //   TestIpcNewApiImpl impl;
    //   t.init(&impl);
    //   QString result = impl.callExtlibReverse("hello");
    //   LOGOS_ASSERT_EQ(result, QString("olleh"));

    LOGOS_ASSERT_EQ(t.moduleCallCount("test_extlib_module", "reverseString"), 0);
}

LOGOS_TEST(mock_chained_calls) {
    auto t = LogosTestContext("test_ipc_module");
    t.mockModule("test_basic_module", "echo").returns("hello");
    t.mockModule("test_extlib_module", "reverseString").returns("olleh");

    // With real module:
    //   TestIpcNewApiImpl impl;
    //   t.init(&impl);
    //   QString result = impl.chainEchoThenReverse("hello");
    //   LOGOS_ASSERT_EQ(result, QString("olleh"));
    //   LOGOS_ASSERT(t.moduleCalled("test_basic_module", "echo"));
    //   LOGOS_ASSERT(t.moduleCalled("test_extlib_module", "reverseString"));

    LOGOS_ASSERT(true);  // API compiles correctly
}

LOGOS_TEST(event_capture_api) {
    auto t = LogosTestContext("test_ipc_module");
    t.captureEvents();

    // With real module:
    //   TestIpcNewApiImpl impl;
    //   t.init(&impl);
    //   impl.triggerBasicEvent("data");
    //   LOGOS_ASSERT(t.eventEmitted("triggeredBasicEvent"));
    //   LOGOS_ASSERT_EQ(t.eventCount("triggeredBasicEvent"), 1);

    // Verify event API compiles
    LOGOS_ASSERT_FALSE(t.eventEmitted("nonexistent"));
    LOGOS_ASSERT_EQ(t.eventCount("nonexistent"), 0);
}

LOGOS_TEST(context_per_test_isolation) {
    // Each LogosTestContext resets all mocks and state
    auto t = LogosTestContext("module_a");
    t.mockCFunction("some_func").returns(100);
    LogosCMockStore::instance().recordCall("some_func");
    LOGOS_ASSERT(t.cFunctionCalled("some_func"));

    // Create a new context — state should be fresh
    auto t2 = LogosTestContext("module_b");
    LOGOS_ASSERT_FALSE(t2.cFunctionCalled("some_func"));
    LOGOS_ASSERT_EQ(t2.cFunctionCallCount("some_func"), 0);
}
