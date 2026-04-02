#include "logos_test_context.h"
#include "logos_clib_mock.h"

#include <logos_api.h>
#include <logos_mode.h>
#include <token_manager.h>
#include <logos_provider_object.h>
#include <implementations/mock/logos_mock.h>
#include <implementations/mock/mock_store.h>

#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QMetaObject>
#include <QDebug>
#include <vector>
#include <string>

// ---------------------------------------------------------------------------
// Internal event record with full QVariantList
// ---------------------------------------------------------------------------

struct InternalEventRecord {
    std::string name;
    QVariantList data;
};

// ---------------------------------------------------------------------------
// Impl — private implementation hiding all Qt/SDK details
// ---------------------------------------------------------------------------

struct LogosTestContext::Impl {
    std::string moduleName;
    LogosMockSetup* mockSetup = nullptr;
    LogosAPI* api = nullptr;
    bool capturingEvents = false;
    std::vector<InternalEventRecord> events;
    static QVariantList s_emptyVariantList;
};

QVariantList LogosTestContext::Impl::s_emptyVariantList;

// ---------------------------------------------------------------------------
// LogosTestContext
// ---------------------------------------------------------------------------

LogosTestContext::LogosTestContext(const std::string& moduleName)
    : d(std::make_unique<Impl>())
{
    d->moduleName = moduleName;

    // Reset C mock store for each test context
    LogosCMockStore::instance().reset();

    // Activate SDK mock mode (clears MockStore + TokenManager)
    d->mockSetup = new LogosMockSetup();

    // Create LogosAPI for this module
    d->api = new LogosAPI(QString::fromStdString(moduleName));
}

LogosTestContext::~LogosTestContext() {
    delete d->api;
    delete d->mockSetup;
}

// -- Module mocking -----------------------------------------------------------

MockBuilder LogosTestContext::mockModule(const std::string& module, const std::string& method) {
    // Seed a mock token for the target module so LogosAPIClient skips capability_module lookup.
    // The actual return value expectation is set by MockBuilder::returns().
    TokenManager::instance().saveToken(QString::fromStdString(module),
                                        "mock-token-" + QString::fromStdString(module));
    return MockBuilder(module, method);
}

bool LogosTestContext::moduleCalled(const std::string& module, const std::string& method) const {
    return d->mockSetup->wasCalled(QString::fromStdString(module), QString::fromStdString(method));
}

bool LogosTestContext::moduleCalledWith(const std::string& module, const std::string& method,
                                         const QVariantList& args) const {
    return d->mockSetup->wasCalledWith(QString::fromStdString(module),
                                        QString::fromStdString(method), args);
}

int LogosTestContext::moduleCallCount(const std::string& module, const std::string& method) const {
    return d->mockSetup->callCount(QString::fromStdString(module), QString::fromStdString(method));
}

// -- C library mocking --------------------------------------------------------

LogosTestContext::CMockBuilder LogosTestContext::mockCFunction(const std::string& funcName) {
    return CMockBuilder(funcName);
}

bool LogosTestContext::cFunctionCalled(const std::string& funcName) const {
    return LogosCMockStore::instance().wasCalled(funcName);
}

int LogosTestContext::cFunctionCallCount(const std::string& funcName) const {
    return LogosCMockStore::instance().callCount(funcName);
}

// -- Event capture ------------------------------------------------------------

void LogosTestContext::captureEvents() {
    d->capturingEvents = true;
}

bool LogosTestContext::eventEmitted(const std::string& eventName) const {
    for (const auto& ev : d->events) {
        if (ev.name == eventName) return true;
    }
    return false;
}

int LogosTestContext::eventCount(const std::string& eventName) const {
    int count = 0;
    for (const auto& ev : d->events) {
        if (ev.name == eventName) ++count;
    }
    return count;
}

const QVariantList& LogosTestContext::lastEventData(const std::string& eventName) const {
    for (auto it = d->events.rbegin(); it != d->events.rend(); ++it) {
        if (it->name == eventName) return it->data;
    }
    return Impl::s_emptyVariantList;
}

// -- Module initialization ----------------------------------------------------

void LogosTestContext::initProvider(void* impl) {
    auto* provider = static_cast<LogosProviderBase*>(impl);

    if (d->capturingEvents) {
        auto* events = &d->events;
        provider->setEventListener([events](const QString& name, const QVariantList& data) {
            events->push_back({name.toStdString(), data});
        });
    }

    provider->init(static_cast<void*>(d->api));
}

void LogosTestContext::initLegacyPlugin(void* impl) {
    auto* obj = static_cast<QObject*>(impl);

    int methodIdx = obj->metaObject()->indexOfMethod("initLogos(LogosAPI*)");
    if (methodIdx != -1) {
        QMetaObject::invokeMethod(obj, "initLogos",
                                  Qt::DirectConnection,
                                  Q_ARG(LogosAPI*, d->api));
    } else {
        qWarning() << "LogosTestContext: legacy plugin has no initLogos(LogosAPI*) slot";
    }
}

LogosAPI* LogosTestContext::api() const {
    return d->api;
}

// ---------------------------------------------------------------------------
// MockBuilder
// ---------------------------------------------------------------------------

MockBuilder::MockBuilder(const std::string& module, const std::string& method)
    : m_module(module), m_method(method) {}

MockBuilder& MockBuilder::returns(int value) {
    MockStore::instance().when(QString::fromStdString(m_module),
                                QString::fromStdString(m_method))
        .thenReturn(QVariant(value));
    return *this;
}

MockBuilder& MockBuilder::returns(bool value) {
    MockStore::instance().when(QString::fromStdString(m_module),
                                QString::fromStdString(m_method))
        .thenReturn(QVariant(value));
    return *this;
}

MockBuilder& MockBuilder::returns(double value) {
    MockStore::instance().when(QString::fromStdString(m_module),
                                QString::fromStdString(m_method))
        .thenReturn(QVariant(value));
    return *this;
}

MockBuilder& MockBuilder::returns(const char* value) {
    MockStore::instance().when(QString::fromStdString(m_module),
                                QString::fromStdString(m_method))
        .thenReturn(QVariant(QString::fromUtf8(value)));
    return *this;
}

MockBuilder& MockBuilder::returns(const std::string& value) {
    MockStore::instance().when(QString::fromStdString(m_module),
                                QString::fromStdString(m_method))
        .thenReturn(QVariant(QString::fromStdString(value)));
    return *this;
}

MockBuilder& MockBuilder::returnsVariant(const QVariant& value) {
    MockStore::instance().when(QString::fromStdString(m_module),
                                QString::fromStdString(m_method))
        .thenReturn(value);
    return *this;
}

MockBuilder& MockBuilder::withArgs(const QVariantList& args) {
    MockStore::instance().when(QString::fromStdString(m_module),
                                QString::fromStdString(m_method))
        .withArgs(args);
    return *this;
}

// ---------------------------------------------------------------------------
// CMockBuilder
// ---------------------------------------------------------------------------

LogosTestContext::CMockBuilder::CMockBuilder(const std::string& funcName)
    : m_funcName(funcName) {}

LogosTestContext::CMockBuilder& LogosTestContext::CMockBuilder::returns(int value) {
    LogosCMockStore::instance().setReturn(m_funcName, &value, sizeof(value));
    return *this;
}

LogosTestContext::CMockBuilder& LogosTestContext::CMockBuilder::returns(bool value) {
    LogosCMockStore::instance().setReturn(m_funcName, &value, sizeof(value));
    return *this;
}

LogosTestContext::CMockBuilder& LogosTestContext::CMockBuilder::returns(double value) {
    LogosCMockStore::instance().setReturn(m_funcName, &value, sizeof(value));
    return *this;
}

LogosTestContext::CMockBuilder& LogosTestContext::CMockBuilder::returns(const char* value) {
    LogosCMockStore::instance().setReturnPtr(m_funcName, static_cast<const void*>(value));
    return *this;
}

LogosTestContext::CMockBuilder& LogosTestContext::CMockBuilder::returns(const std::string& value) {
    // Store a pointer to intern'd string data — caller must keep value alive
    // For safety, store the pointer via setReturnPtr
    LogosCMockStore::instance().setReturnPtr(m_funcName, static_cast<const void*>(value.c_str()));
    return *this;
}

LogosTestContext::CMockBuilder& LogosTestContext::CMockBuilder::returnsPtr(const void* ptr) {
    LogosCMockStore::instance().setReturnPtr(m_funcName, ptr);
    return *this;
}

LogosTestContext::CMockBuilder& LogosTestContext::CMockBuilder::returnsRaw(const void* data, size_t size) {
    LogosCMockStore::instance().setReturn(m_funcName, data, size);
    return *this;
}
