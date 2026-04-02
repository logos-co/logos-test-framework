cmake_minimum_required(VERSION 3.14)
project(BasicModuleTest LANGUAGES CXX)

# The framework's LogosTest.cmake is found via CMAKE_MODULE_PATH
# (set by Nix or by the developer)
include(LogosTest)

logos_test(
    NAME basic_module_tests
    MODULE_SOURCES
        # In a real module: ../src/my_module_impl.cpp
    TEST_SOURCES
        main.cpp
        test_example.cpp
)
