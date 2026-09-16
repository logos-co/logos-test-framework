cmake_minimum_required(VERSION 3.14)
project(ExtlibLinkTest LANGUAGES CXX)

include(LogosTest)

# Links the real library: from $LOGOS_EXT_ROOT_EXTFIXTURE when set, else from ../lib.
logos_test(
    NAME extlib_link_tests
    TEST_SOURCES
        main.cpp
        test_extlib_link.cpp
    EXTERNAL_LIBS
        extfixture
)
