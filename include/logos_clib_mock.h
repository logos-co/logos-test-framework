#ifndef LOGOS_CLIB_MOCK_H
#define LOGOS_CLIB_MOCK_H

/**
 * @file logos_clib_mock.h
 * @brief C library function mock store for link-time substitution.
 *
 * When building tests, the real C library is NOT linked. Instead, mock source
 * files provide the same function signatures backed by LogosCMockStore.
 *
 * Example mock file (mocks/mock_libcalc.cpp):
 *
 *   #include <logos_clib_mock.h>
 *   extern "C" { #include "libcalc.h" }
 *
 *   extern "C" int calc_add(int a, int b) {
 *       LOGOS_CMOCK_RECORD("calc_add");
 *       return LOGOS_CMOCK_RETURN(int, "calc_add");
 *   }
 *
 * In tests:
 *
 *   LOGOS_TEST(add_works) {
 *       auto t = LogosTestContext("my_module");
 *       t.mockCFunction("calc_add").returns(42);
 *       // ... use module that calls calc_add() ...
 *   }
 */

#include <string>
#include <unordered_map>
#include <vector>
#include <cstring>
#include <mutex>
#include <cstdint>

// ---------------------------------------------------------------------------
// LogosCMockStore — singleton registry for C function mocks
// ---------------------------------------------------------------------------

class LogosCMockStore {
public:
    static LogosCMockStore& instance();

    void reset();

    // -- Expectation setup ----------------------------------------------------

    class ExpectationBuilder {
    public:
        explicit ExpectationBuilder(const std::string& funcName);

        ExpectationBuilder& returns(int value);
        ExpectationBuilder& returns(bool value);
        ExpectationBuilder& returns(double value);
        ExpectationBuilder& returns(const char* value);
        ExpectationBuilder& returns(const std::string& value);
        ExpectationBuilder& returnsPtr(const void* ptr);
        ExpectationBuilder& returnsRaw(const void* data, size_t size);

    private:
        std::string m_funcName;
    };

    ExpectationBuilder when(const std::string& funcName);

    // -- Call recording (used by mock implementations) ------------------------

    void recordCall(const std::string& funcName);

    template<typename T>
    T getReturn(const std::string& funcName) const {
        std::lock_guard<std::mutex> lock(m_mutex);
        auto it = m_returns.find(funcName);
        if (it == m_returns.end()) return T{};

        const auto& data = it->second;
        if (data.size() < sizeof(T)) return T{};

        T val;
        std::memcpy(&val, data.data(), sizeof(T));
        return val;
    }

    // Specialization for const char* — returns a pointer stored as uintptr_t
    const char* getReturnString(const std::string& funcName) const;

    // -- Verification ---------------------------------------------------------

    bool wasCalled(const std::string& funcName) const;
    int callCount(const std::string& funcName) const;

    // -- Storage (low-level) --------------------------------------------------

    void setReturn(const std::string& funcName, const void* data, size_t size);
    void setReturnPtr(const std::string& funcName, const void* ptr);

private:
    LogosCMockStore() = default;
    LogosCMockStore(const LogosCMockStore&) = delete;
    LogosCMockStore& operator=(const LogosCMockStore&) = delete;

    mutable std::mutex m_mutex;
    std::unordered_map<std::string, std::vector<uint8_t>> m_returns;
    std::unordered_map<std::string, int> m_calls;
};

// ---------------------------------------------------------------------------
// Convenience macros for mock implementations
// ---------------------------------------------------------------------------

#define LOGOS_CMOCK_RECORD(funcName) \
    LogosCMockStore::instance().recordCall(funcName)

#define LOGOS_CMOCK_RETURN(type, funcName) \
    LogosCMockStore::instance().getReturn<type>(funcName)

#define LOGOS_CMOCK_RETURN_STRING(funcName) \
    LogosCMockStore::instance().getReturnString(funcName)

#endif // LOGOS_CLIB_MOCK_H
