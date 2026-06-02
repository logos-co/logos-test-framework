#ifndef LOGOS_TEST_EVENTS_H
#define LOGOS_TEST_EVENTS_H

/**
 * @file logos_test_events.h
 * @brief Qt-free capture of a universal module's typed `logos_events:`.
 *
 * Universal-module unit tests construct the impl directly (no Qt provider /
 * LogosAPI), so the impl's `logos_events:` methods have no bodies linked — the
 * real ones live in the codegen-emitted `<name>_events.cpp`, which marshals
 * through Qt and which these tests deliberately don't pull in. Instead the
 * test supplies one-line std forwarder bodies that call
 * `logos_test::recordEvent(...)`, and observes them with `EventCapture` /
 * `ScopedEventSink`:
 *
 *   // <module>_events_test.cpp — one forwarder per declared event:
 *   #include <logos_test.h>
 *   #include "my_module_impl.h"
 *   void MyModuleImpl::userLoggedIn(const std::string& id) {
 *       logos_test::recordEvent("userLoggedIn", id);
 *   }
 *
 *   // in a test — declare the capture BEFORE the impl so it outlives any
 *   // background thread the impl's destructor joins:
 *   logos_test::EventCapture events;
 *   MyModuleImpl impl;
 *   impl.doThing();
 *   LOGOS_ASSERT_TRUE(events.has("userLoggedIn"));
 *
 * This is the std-only counterpart to LogosTestContext::captureEvents(), which
 * captures via the Qt provider / LogosAPI path (QVariantList) for modules that
 * inherit LogosProviderBase and are initialised through the context.
 */

#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace logos_test {

using EventSink = std::function<void(const std::string&, const std::string&)>;

// The active sink that module forwarders dispatch through. A function-local
// static gives a single instance shared across translation units without a
// separate .cpp. Null when no capture is installed → recordEvent is a no-op,
// matching production behaviour when no listener is wired.
inline EventSink& activeEventSink() {
    static EventSink sink;
    return sink;
}

// Called from a module's test-only event forwarder bodies.
inline void recordEvent(const std::string& name, const std::string& data) {
    if (auto& s = activeEventSink()) s(name, data);
}

// Thread-safe capture of (name, data) pairs, with a blocking wait helper for
// events emitted from background threads. Installs itself as the active sink
// for its lifetime — declare it before the impl under test so it outlives the
// impl's destructor (which may join an event-emitting worker thread).
class EventCapture {
public:
    struct Entry { std::string name; std::string data; };

    EventCapture() {
        activeEventSink() = [this](const std::string& n, const std::string& d) { record(n, d); };
    }
    ~EventCapture() { activeEventSink() = nullptr; }
    EventCapture(const EventCapture&) = delete;
    EventCapture& operator=(const EventCapture&) = delete;

    void record(const std::string& name, const std::string& data) {
        std::lock_guard<std::mutex> lk(m_mu);
        m_entries.push_back({name, data});
        m_cv.notify_all();
    }

    size_t size() {
        std::lock_guard<std::mutex> lk(m_mu);
        return m_entries.size();
    }

    bool has(const std::string& name) {
        std::lock_guard<std::mutex> lk(m_mu);
        for (const auto& e : m_entries) if (e.name == name) return true;
        return false;
    }

    // {name,data} copies for every matching event.
    std::vector<Entry> all(const std::string& name) {
        std::lock_guard<std::mutex> lk(m_mu);
        std::vector<Entry> out;
        for (const auto& e : m_entries) if (e.name == name) out.push_back(e);
        return out;
    }

    // Block up to `timeoutMs` for at least one entry named `name`. Returns the
    // first match (copy), or an empty-name Entry on timeout.
    Entry waitFor(const std::string& name, int timeoutMs) {
        std::unique_lock<std::mutex> lk(m_mu);
        bool got = m_cv.wait_for(lk, std::chrono::milliseconds(timeoutMs), [&] {
            for (const auto& e : m_entries) if (e.name == name) return true;
            return false;
        });
        if (!got) return {};
        for (const auto& e : m_entries) if (e.name == name) return e;
        return {};
    }

private:
    std::mutex              m_mu;
    std::condition_variable m_cv;
    std::vector<Entry>      m_entries;
};

// RAII installer for a bespoke sink lambda — for tests that capture into their
// own locals rather than a full EventCapture.
class ScopedEventSink {
public:
    explicit ScopedEventSink(EventSink f) { activeEventSink() = std::move(f); }
    ~ScopedEventSink() { activeEventSink() = nullptr; }
    ScopedEventSink(const ScopedEventSink&) = delete;
    ScopedEventSink& operator=(const ScopedEventSink&) = delete;
};

} // namespace logos_test

#endif // LOGOS_TEST_EVENTS_H
