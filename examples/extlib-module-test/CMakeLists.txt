cmake_minimum_required(VERSION 3.14)
project(ExtlibModuleTest LANGUAGES CXX)

include(LogosTest)

logos_test(
    NAME extlib_module_tests
    MODULE_SOURCES
        # In real module: ../src/calc_module_impl.cpp
    TEST_SOURCES
        main.cpp
        test_extlib.cpp
    MOCK_C_SOURCES
        mocks/mock_libcalc.cpp
)
