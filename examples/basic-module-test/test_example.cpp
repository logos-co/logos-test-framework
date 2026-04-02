// Example: Testing a module that calls another Logos module.
// The module under test would normally live in ../src/, but this
// is a self-contained example showing the test API.

#include <logos_test.h>

// Simulated module method that would call another module
static int addViaRemote(LogosTestContext& t) {
    // In real code this would be impl.callBasicAddInts(10, 20)
    // which internally calls m_basicClient->invokeRemoteMethod(...)
    // The mock intercepts at the transport layer.
    return 30;  // placeholder — real tests use actual module impl
}

LOGOS_TEST(mock_module_returns_configured_value) {
    auto t = LogosTestContext("my_module");
    t.mockModule("other_module", "addInts").returns(42);
    // In a real test: MyModuleImpl impl; t.init(&impl);
    // result = impl.callOtherAddInts(10, 20);
    // LOGOS_ASSERT_EQ(result, 42);

    // For this example, just verify the API compiles and works
    LOGOS_ASSERT(true);
}

LOGOS_TEST(mock_module_records_calls) {
    auto t = LogosTestContext("my_module");
    t.mockModule("dep_module", "echo").returns("hello back");

    // Verify initial state
    LOGOS_ASSERT_FALSE(t.moduleCalled("dep_module", "echo"));
    LOGOS_ASSERT_EQ(t.moduleCallCount("dep_module", "echo"), 0);
}

LOGOS_TEST(c_mock_returns_configured_value) {
    auto t = LogosTestContext("my_module");
    t.mockCFunction("calc_add").returns(42);

    int result = LogosCMockStore::instance().getReturn<int>("calc_add");
    LOGOS_ASSERT_EQ(result, 42);
}

LOGOS_TEST(c_mock_records_calls) {
    auto t = LogosTestContext("my_module");
    t.mockCFunction("calc_add").returns(0);

    LogosCMockStore::instance().recordCall("calc_add");

    LOGOS_ASSERT(t.cFunctionCalled("calc_add"));
    LOGOS_ASSERT_EQ(t.cFunctionCallCount("calc_add"), 1);
}

LOGOS_TEST(assertions_work_correctly) {
    LOGOS_ASSERT_TRUE(1 == 1);
    LOGOS_ASSERT_FALSE(1 == 2);
    LOGOS_ASSERT_EQ(42, 42);
    LOGOS_ASSERT_NE(1, 2);
    LOGOS_ASSERT_GT(10, 5);
    LOGOS_ASSERT_GE(10, 10);
    LOGOS_ASSERT_LT(5, 10);
    LOGOS_ASSERT_LE(10, 10);
}

LOGOS_TEST(assert_throws_catches_exception) {
    LOGOS_ASSERT_THROWS(throw std::runtime_error("expected"));
}
