cmake_minimum_required(VERSION 3.14)
project(IpcModuleTest LANGUAGES CXX)

include(LogosTest)

logos_test(
    NAME ipc_module_tests
    MODULE_SOURCES
        # In real module: ../src/test_ipc_new_api_impl.cpp
        #                 ../logos_provider_dispatch.cpp
    TEST_SOURCES
        main.cpp
        test_ipc.cpp
    # GENERATED_SOURCES
    #     ../logos_provider_dispatch.cpp
    # GENERATED_DIR
    #     ../generated_code
)
