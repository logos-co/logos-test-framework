#ifndef LOGOS_TEST_CONTEXT_H
#define LOGOS_TEST_CONTEXT_H

/**
 * @file logos_test_context.h
 * @brief LogosTestContext — hides all Qt/SDK boilerplate from test code.
 *
 * Creates LogosAPI in mock mode, manages LogosMockSetup lifecycle, provides
 * fluent APIs for module mocking, C library mocking, and event capture.
 */

#include <string>
#include <memory>
#include <vector>
#include <type_traits>

// Forward-declare Qt types (only real classes, not typedefs like QVariantList)
class QVariant;
class LogosAPI;

#ifdef QT_CORE_LIB
#include <QVariantList>
#endif

// ---------------------------------------------------------------------------
// MockBuilder — fluent builder returned by mockModule()
// ---------------------------------------------------------------------------

class MockBuilder {
public:
    MockBuilder(const std::string& module, const std::string& method);

    MockBuilder& returns(int value);
    MockBuilder& returns(bool value);
    MockBuilder& returns(double value);
    MockBuilder& returns(const char* value);
    MockBuilder& returns(const std::string& value);
    // For callers that need to pass a QVariant directly (advanced use)
    MockBuilder& returnsVariant(const QVariant& value);
#ifdef QT_CORE_LIB
    MockBuilder& withArgs(const QVariantList& args);
#endif

private:
    std::string m_module;
    std::string m_method;
};

// ---------------------------------------------------------------------------
// EventRecord — captured event data
// ---------------------------------------------------------------------------

struct EventRecord {
    std::string name;
    std::vector<std::string> dataStrings;
    // Internal: holds the raw QVariantList data (accessible via eventData())
    void* rawData = nullptr;
};

// ---------------------------------------------------------------------------
// LogosTestContext
// ---------------------------------------------------------------------------

class LogosTestContext {
public:
    explicit LogosTestContext(const std::string& moduleName);
    ~LogosTestContext();

    // Non-copyable, non-movable
    LogosTestContext(const LogosTestContext&) = delete;
    LogosTestContext& operator=(const LogosTestContext&) = delete;

    // -- Module mocking (wraps LogosMockSetup) --------------------------------

    MockBuilder mockModule(const std::string& module, const std::string& method);
    bool moduleCalled(const std::string& module, const std::string& method) const;
#ifdef QT_CORE_LIB
    bool moduleCalledWith(const std::string& module, const std::string& method,
                          const QVariantList& args) const;
#endif
    int moduleCallCount(const std::string& module, const std::string& method) const;

    // -- C library mocking (delegates to LogosCMockStore) ---------------------

    class CMockBuilder {
    public:
        explicit CMockBuilder(const std::string& funcName);
        CMockBuilder& returns(int value);
        CMockBuilder& returns(bool value);
        CMockBuilder& returns(double value);
        CMockBuilder& returns(const char* value);
        CMockBuilder& returns(const std::string& value);
        CMockBuilder& returnsPtr(const void* ptr);
        CMockBuilder& returnsRaw(const void* data, size_t size);
    private:
        std::string m_funcName;
    };

    CMockBuilder mockCFunction(const std::string& funcName);
    bool cFunctionCalled(const std::string& funcName) const;
    int cFunctionCallCount(const std::string& funcName) const;

    // -- Event capture --------------------------------------------------------

    void captureEvents();
    bool eventEmitted(const std::string& eventName) const;
    int eventCount(const std::string& eventName) const;
#ifdef QT_CORE_LIB
    const QVariantList& lastEventData(const std::string& eventName) const;
#endif

    // -- Module initialization ------------------------------------------------

    /**
     * Initialize a new-API module (inherits LogosProviderBase).
     * Calls impl->init(&logosAPI) internally.
     */
    template<typename T>
    auto init(T* impl) -> typename std::enable_if<
        std::is_member_function_pointer<decltype(&T::init)>::value>::type
    {
        initProvider(static_cast<void*>(impl));
    }

    /**
     * Fallback for legacy QObject-based modules with initLogos(LogosAPI*).
     * Detected via SFINAE when init() is not available.
     */
    template<typename T>
    auto initLegacy(T* impl) -> void
    {
        initLegacyPlugin(static_cast<void*>(impl));
    }

    // Access the underlying LogosAPI (advanced use only)
    LogosAPI* api() const;

private:
    void initProvider(void* impl);
    void initLegacyPlugin(void* impl);

    struct Impl;
    std::unique_ptr<Impl> d;
};

#endif // LOGOS_TEST_CONTEXT_H
