// Mock implementation of libcalc — replaces the real C library at link time.
// Each function records its call and returns the value configured via
// LogosTestContext::mockCFunction().

#include <logos_clib_mock.h>

extern "C" int calc_add(int a, int b) {
    LOGOS_CMOCK_RECORD("calc_add");
    return LOGOS_CMOCK_RETURN(int, "calc_add");
}

extern "C" const char* calc_version() {
    LOGOS_CMOCK_RECORD("calc_version");
    return LOGOS_CMOCK_RETURN_STRING("calc_version");
}
