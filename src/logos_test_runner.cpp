#include "logos_test.h"
#include <QCoreApplication>
#include <algorithm>
#include <iomanip>

#ifdef _WIN32
#include <io.h>
#define isatty _isatty
#define fileno _fileno
#else
#include <unistd.h>
#endif

// ---------------------------------------------------------------------------
// TTY detection
// ---------------------------------------------------------------------------

bool LogosTestRunner::isTTY() {
    return isatty(fileno(stdout)) != 0;
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

LogosTestRunner::RunConfig LogosTestRunner::parseArgs(int argc, char* argv[]) {
    RunConfig cfg;
    cfg.noColor = !isTTY();

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--json") {
            cfg.json = true;
        } else if (arg == "--no-color") {
            cfg.noColor = true;
        } else if (arg == "--filter" && i + 1 < argc) {
            cfg.filter = argv[++i];
        } else if (arg.rfind("--filter=", 0) == 0) {
            cfg.filter = arg.substr(9);
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: " << (argc > 0 ? argv[0] : "test") << " [options]\n"
                      << "  --filter <pattern>  Run only tests matching pattern\n"
                      << "  --json              Output results as JSON\n"
                      << "  --no-color          Disable colored output\n"
                      << "  --help              Show this help\n";
            std::exit(0);
        }
    }
    return cfg;
}

// ---------------------------------------------------------------------------
// Filter matching — simple substring match
// ---------------------------------------------------------------------------

bool LogosTestRunner::matchesFilter(const std::string& name, const std::string& filter) {
    if (filter.empty()) return true;
    return name.find(filter) != std::string::npos;
}

// ---------------------------------------------------------------------------
// JSON string escaping
// ---------------------------------------------------------------------------

static std::string jsonEscape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += c;      break;
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// Main run method
// ---------------------------------------------------------------------------

int LogosTestRunner::run(int argc, char* argv[]) {
    QCoreApplication app(argc, argv);

    RunConfig cfg = parseArgs(argc, argv);
    bool color = !cfg.noColor && !cfg.json;

    // Collect tests that match filter
    std::vector<const TestEntry*> toRun;
    for (const auto& t : m_tests) {
        if (matchesFilter(t.name, cfg.filter))
            toRun.push_back(&t);
    }

    // Determine suite name from argv[0]
    std::string suiteName = "logos_tests";
    if (argc > 0) {
        std::string exe = argv[0];
        auto pos = exe.find_last_of("/\\");
        if (pos != std::string::npos) exe = exe.substr(pos + 1);
        if (!exe.empty()) suiteName = exe;
    }

    int passed = 0;
    int failed = 0;
    int skipped = static_cast<int>(m_tests.size()) - static_cast<int>(toRun.size());

    struct TestResult {
        std::string name;
        bool pass;
        double duration_ms;
        std::string error;
    };
    std::vector<TestResult> results;

    auto totalStart = std::chrono::steady_clock::now();

    // Header
    if (!cfg.json) {
        std::cout << "\n"
                  << colorDim(color) << " ── " << colorReset(color)
                  << colorBold(color) << suiteName << colorReset(color)
                  << colorDim(color) << " ──────────────────────────────────" << colorReset(color)
                  << "\n\n";
    }

    // Run tests
    for (const auto* t : toRun) {
        auto start = std::chrono::steady_clock::now();
        TestResult r;
        r.name = t->name;
        r.pass = true;

        if (!cfg.json) {
            // No prefix here — we'll print result after
        }

        try {
            t->fn();
        } catch (const LogosTestFailure& ex) {
            r.pass = false;
            r.error = ex.what();
        } catch (const std::exception& ex) {
            r.pass = false;
            r.error = std::string("Unexpected exception: ") + ex.what();
        } catch (...) {
            r.pass = false;
            r.error = "Unknown exception";
        }

        auto end = std::chrono::steady_clock::now();
        r.duration_ms = std::chrono::duration<double, std::milli>(end - start).count();

        if (!cfg.json) {
            if (r.pass) {
                std::cout << "   " << colorGreen(color) << "PASS" << colorReset(color)
                          << "  " << r.name
                          << colorDim(color) << "  "
                          << std::fixed << std::setprecision(0)
                          << r.duration_ms << "ms" << colorReset(color) << "\n";
                ++passed;
            } else {
                std::cout << "   " << colorRed(color) << "FAIL" << colorReset(color)
                          << "  " << r.name
                          << colorDim(color) << "  "
                          << std::fixed << std::setprecision(0)
                          << r.duration_ms << "ms" << colorReset(color) << "\n"
                          << "         " << colorRed(color) << r.error << colorReset(color) << "\n";
                ++failed;
            }
        } else {
            if (r.pass) ++passed; else ++failed;
        }

        results.push_back(std::move(r));
    }

    auto totalEnd = std::chrono::steady_clock::now();
    double totalMs = std::chrono::duration<double, std::milli>(totalEnd - totalStart).count();

    // Footer / summary
    if (cfg.json) {
        std::cout << "{\"suite\":\"" << jsonEscape(suiteName) << "\",\"tests\":[";
        for (size_t i = 0; i < results.size(); ++i) {
            const auto& r = results[i];
            if (i > 0) std::cout << ",";
            std::cout << "{\"name\":\"" << jsonEscape(r.name) << "\","
                      << "\"status\":\"" << (r.pass ? "pass" : "fail") << "\","
                      << "\"duration_ms\":" << std::fixed << std::setprecision(1) << r.duration_ms;
            if (!r.pass) {
                std::cout << ",\"error\":\"" << jsonEscape(r.error) << "\"";
            }
            std::cout << "}";
        }
        std::cout << "],\"passed\":" << passed
                  << ",\"failed\":" << failed
                  << ",\"skipped\":" << skipped
                  << ",\"duration_ms\":" << std::fixed << std::setprecision(1) << totalMs
                  << "}\n";
    } else {
        std::cout << "\n"
                  << colorDim(color) << " ── Results: " << colorReset(color);
        if (passed > 0)
            std::cout << colorGreen(color) << passed << " passed" << colorReset(color);
        if (passed > 0 && failed > 0)
            std::cout << ", ";
        if (failed > 0)
            std::cout << colorRed(color) << failed << " failed" << colorReset(color);
        if (passed == 0 && failed == 0)
            std::cout << colorYellow(color) << "no tests matched" << colorReset(color);
        if (skipped > 0)
            std::cout << colorDim(color) << ", " << skipped << " skipped" << colorReset(color);
        std::cout << colorDim(color) << " (" << std::fixed << std::setprecision(0)
                  << totalMs << "ms)" << colorReset(color);
        if (toRun.empty()) {
            std::cout << colorYellow(color) << " (no tests registered!)" << colorReset(color);
        }
        std::cout << colorDim(color) << " ──────" << colorReset(color) << "\n\n";
    }

    return failed > 0 ? 1 : 0;
}
