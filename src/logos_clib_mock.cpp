#include "logos_clib_mock.h"
#include <cstdint>

// ---------------------------------------------------------------------------
// LogosCMockStore singleton
// ---------------------------------------------------------------------------

LogosCMockStore& LogosCMockStore::instance() {
    static LogosCMockStore store;
    return store;
}

void LogosCMockStore::reset() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_returns.clear();
    m_calls.clear();
}

// ---------------------------------------------------------------------------
// Expectation setup
// ---------------------------------------------------------------------------

LogosCMockStore::ExpectationBuilder LogosCMockStore::when(const std::string& funcName) {
    return ExpectationBuilder(funcName);
}

LogosCMockStore::ExpectationBuilder::ExpectationBuilder(const std::string& funcName)
    : m_funcName(funcName) {}

LogosCMockStore::ExpectationBuilder& LogosCMockStore::ExpectationBuilder::returns(int value) {
    LogosCMockStore::instance().setReturn(m_funcName, &value, sizeof(value));
    return *this;
}

LogosCMockStore::ExpectationBuilder& LogosCMockStore::ExpectationBuilder::returns(bool value) {
    LogosCMockStore::instance().setReturn(m_funcName, &value, sizeof(value));
    return *this;
}

LogosCMockStore::ExpectationBuilder& LogosCMockStore::ExpectationBuilder::returns(double value) {
    LogosCMockStore::instance().setReturn(m_funcName, &value, sizeof(value));
    return *this;
}

LogosCMockStore::ExpectationBuilder& LogosCMockStore::ExpectationBuilder::returns(const char* value) {
    LogosCMockStore::instance().setReturnPtr(m_funcName, static_cast<const void*>(value));
    return *this;
}

LogosCMockStore::ExpectationBuilder& LogosCMockStore::ExpectationBuilder::returns(const std::string& value) {
    LogosCMockStore::instance().setReturnPtr(m_funcName, static_cast<const void*>(value.c_str()));
    return *this;
}

LogosCMockStore::ExpectationBuilder& LogosCMockStore::ExpectationBuilder::returnsPtr(const void* ptr) {
    LogosCMockStore::instance().setReturnPtr(m_funcName, ptr);
    return *this;
}

LogosCMockStore::ExpectationBuilder& LogosCMockStore::ExpectationBuilder::returnsRaw(const void* data, size_t size) {
    LogosCMockStore::instance().setReturn(m_funcName, data, size);
    return *this;
}

// ---------------------------------------------------------------------------
// Call recording
// ---------------------------------------------------------------------------

void LogosCMockStore::recordCall(const std::string& funcName) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_calls[funcName]++;
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

bool LogosCMockStore::wasCalled(const std::string& funcName) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_calls.find(funcName);
    return it != m_calls.end() && it->second > 0;
}

int LogosCMockStore::callCount(const std::string& funcName) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_calls.find(funcName);
    return (it != m_calls.end()) ? it->second : 0;
}

// ---------------------------------------------------------------------------
// String return specialization
// ---------------------------------------------------------------------------

const char* LogosCMockStore::getReturnString(const std::string& funcName) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_returns.find(funcName);
    if (it == m_returns.end()) return "";

    const auto& data = it->second;
    if (data.size() < sizeof(uintptr_t)) return "";

    uintptr_t ptr;
    std::memcpy(&ptr, data.data(), sizeof(ptr));
    return reinterpret_cast<const char*>(ptr);
}

// ---------------------------------------------------------------------------
// Low-level storage
// ---------------------------------------------------------------------------

void LogosCMockStore::setReturn(const std::string& funcName, const void* data, size_t size) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto& vec = m_returns[funcName];
    vec.resize(size);
    std::memcpy(vec.data(), data, size);
}

void LogosCMockStore::setReturnPtr(const std::string& funcName, const void* ptr) {
    uintptr_t addr = reinterpret_cast<uintptr_t>(ptr);
    setReturn(funcName, &addr, sizeof(addr));
}
