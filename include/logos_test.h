#ifndef LOGOS_TEST_H
#define LOGOS_TEST_H

/**
 * @file logos_test.h
 * @brief Logos Module Test Framework — write unit tests without Qt boilerplate.
 *
 * Single include for the full test API: runner, assertions, module mocking,
 * C library mocking, and event testing.
 *
 *   #include <logos_test.h>
 *
 *   LOGOS_TEST(my_feature_works) {
 *       auto t = LogosTestContext("my_module");
 *       t.mockModule("dep", "method").returns(42);
 *       MyImpl impl;
 *       t.init(&impl);
 *       LOGOS_ASSERT_EQ(impl.callDep(), 42);
 *   }
 */

#include <string>
#include <vector>
#include <functional>
#include <sstream>
#include <stdexcept>
#include <chrono>
#include <iostream>
#include <cstring>
#include <memory>
#include <type_traits>

// Allow QString and QVariant to be streamed (defined when Qt headers are included)
#ifdef QT_CORE_LIB
#include <QString>
#include <QVariant>
inline std::ostream& operator<<(std::ostream& os, const QString& s)  { return os << s.toStdString(); }
inline std::ostream& operator<<(std::ostream& os, const QVariant& v) { return os << v.toString().toStdString(); }
#endif

// ---------------------------------------------------------------------------
// Test failure exception
// ---------------------------------------------------------------------------

class LogosTestFailure : public std::runtime_error {
public:
    explicit LogosTestFailure(const std::string& msg) : std::runtime_error(msg) {}
};

// ---------------------------------------------------------------------------
// Assertion macros
// ---------------------------------------------------------------------------

#define LOGOS_ASSERT(expr) \
    do { \
        if (!(expr)) { \
            std::ostringstream _oss; \
            _oss << "ASSERT failed: " #expr \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_TRUE(expr)  LOGOS_ASSERT(expr)
#define LOGOS_ASSERT_FALSE(expr) LOGOS_ASSERT(!(expr))

#define LOGOS_ASSERT_EQ(actual, expected) \
    do { \
        auto _logos_a = (actual); \
        auto _logos_e = (expected); \
        if (!(_logos_a == _logos_e)) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_EQ failed: expected [" \
                 << _logos_e << "] but got [" << _logos_a << "]" \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_NE(actual, expected) \
    do { \
        auto _logos_a = (actual); \
        auto _logos_e = (expected); \
        if (_logos_a == _logos_e) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_NE failed: both equal [" << _logos_a << "]" \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_GT(actual, threshold) \
    do { \
        auto _logos_a = (actual); \
        auto _logos_t = (threshold); \
        if (!(_logos_a > _logos_t)) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_GT failed: " << _logos_a << " is not > " << _logos_t \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_GE(actual, threshold) \
    do { \
        auto _logos_a = (actual); \
        auto _logos_t = (threshold); \
        if (!(_logos_a >= _logos_t)) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_GE failed: " << _logos_a << " is not >= " << _logos_t \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_LT(actual, threshold) \
    do { \
        auto _logos_a = (actual); \
        auto _logos_t = (threshold); \
        if (!(_logos_a < _logos_t)) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_LT failed: " << _logos_a << " is not < " << _logos_t \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_LE(actual, threshold) \
    do { \
        auto _logos_a = (actual); \
        auto _logos_t = (threshold); \
        if (!(_logos_a <= _logos_t)) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_LE failed: " << _logos_a << " is not <= " << _logos_t \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_CONTAINS(haystack, needle) \
    do { \
        auto _logos_h = (haystack); \
        auto _logos_n = (needle); \
        if (_logos_h.find(_logos_n) == std::string::npos && \
            std::string(_logos_h).find(std::string(_logos_n)) == std::string::npos) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_CONTAINS failed: [" << _logos_h << "] does not contain [" \
                 << _logos_n << "]" \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

#define LOGOS_ASSERT_THROWS(expr) \
    do { \
        bool _logos_threw = false; \
        try { expr; } catch (...) { _logos_threw = true; } \
        if (!_logos_threw) { \
            std::ostringstream _oss; \
            _oss << "ASSERT_THROWS failed: no exception thrown" \
                 << "  (" << __FILE__ << ":" << __LINE__ << ")"; \
            throw LogosTestFailure(_oss.str()); \
        } \
    } while (false)

// ---------------------------------------------------------------------------
// Test runner — auto-registers tests via static init
// ---------------------------------------------------------------------------

class LogosTestRunner {
public:
    struct TestEntry {
        std::string name;
        std::function<void()> fn;
    };

    static LogosTestRunner& instance() {
        static LogosTestRunner runner;
        return runner;
    }

    bool registerTest(const char* name, std::function<void()> fn) {
        m_tests.push_back({name, std::move(fn)});
        return true;
    }

    // Run all tests. Call from main() — handles arg parsing, QCoreApplication, output.
    int run(int argc, char* argv[]);

private:
    LogosTestRunner() = default;

    struct RunConfig {
        std::string filter;
        bool json = false;
        bool noColor = false;
    };

    RunConfig parseArgs(int argc, char* argv[]);
    bool matchesFilter(const std::string& name, const std::string& filter);

    // Output helpers
    static bool isTTY();
    static std::string colorGreen(bool enabled)  { return enabled ? "\033[32m" : ""; }
    static std::string colorRed(bool enabled)    { return enabled ? "\033[31m" : ""; }
    static std::string colorYellow(bool enabled) { return enabled ? "\033[33m" : ""; }
    static std::string colorCyan(bool enabled)   { return enabled ? "\033[36m" : ""; }
    static std::string colorDim(bool enabled)    { return enabled ? "\033[2m" : ""; }
    static std::string colorBold(bool enabled)   { return enabled ? "\033[1m" : ""; }
    static std::string colorReset(bool enabled)  { return enabled ? "\033[0m" : ""; }

    std::vector<TestEntry> m_tests;
};

// ---------------------------------------------------------------------------
// LOGOS_TEST macro — register a test function at static init time
// ---------------------------------------------------------------------------

#define LOGOS_TEST(name) \
    static void _logos_test_fn_##name(); \
    static bool _logos_test_reg_##name = \
        LogosTestRunner::instance().registerTest(#name, _logos_test_fn_##name); \
    static void _logos_test_fn_##name()

// ---------------------------------------------------------------------------
// LOGOS_TEST_MAIN — generates main() with QCoreApplication + runner
// ---------------------------------------------------------------------------

#define LOGOS_TEST_MAIN() \
    int main(int argc, char* argv[]) { \
        return LogosTestRunner::instance().run(argc, argv); \
    }

// ---------------------------------------------------------------------------
// Include sub-headers (available after including logos_test.h)
// ---------------------------------------------------------------------------

#include "logos_test_context.h"
#include "logos_clib_mock.h"

#endif // LOGOS_TEST_H
