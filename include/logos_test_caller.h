#ifndef LOGOS_TEST_CALLER_H
#define LOGOS_TEST_CALLER_H

// RAII stand-in for the generated logos_module_set_call_caller() push.
//
// Production glue pulls the host's CallerScope document and pushes it onto
// the module-side stack for the duration of the handler. Unit tests that
// construct an impl directly skip that glue, so they open the SAME stack
// with CallCaller. That is the supported way to simulate a dispatch for any
// C++ module — not a per-module helper and not a second identity path in
// the handler.
//
//   const auto caller = logos::CallCaller::module("chat_module");
//   impl.someMethod();  // logos::currentCaller() is that module
//
#include <logos_caller.h>

#include <string>
#include <utility>

namespace logos {

class CallCaller {
public:
    static CallCaller module(const std::string& name)
    {
        return CallCaller(std::string(R"({"kind":"module","name":")") + name + "\"}");
    }
    static CallCaller host() { return CallCaller(std::string(R"({"kind":"host"})")); }

    explicit CallCaller(const char* json)
        : CallCaller(std::string(json ? json : "")) {}

    ~CallCaller() { detail::setCallCaller(nullptr); }

    CallCaller(const CallCaller&) = delete;
    CallCaller& operator=(const CallCaller&) = delete;
    CallCaller(CallCaller&&) = delete;
    CallCaller& operator=(CallCaller&&) = delete;

private:
    explicit CallCaller(std::string json) : m_json(std::move(json))
    {
        detail::setCallCaller(m_json.c_str());
    }
    std::string m_json;
};

} // namespace logos

#endif // LOGOS_TEST_CALLER_H
