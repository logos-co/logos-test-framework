# LogosTest.cmake
# Provides logos_test() — a single CMake function that builds a complete
# Logos module test executable with mocking support and minimal boilerplate.
#
# Usage:
#   include(LogosTest)
#
#   logos_test(
#       NAME my_module_tests
#       MODULE_SOURCES ../src/my_module_impl.cpp
#       TEST_SOURCES
#           main.cpp
#           test_feature_a.cpp
#           test_feature_b.cpp
#       MOCK_C_SOURCES                    # optional: C lib mock stubs
#           mocks/mock_libcalc.cpp
#       EXTRA_INCLUDES                    # optional: additional include dirs
#           ../lib
#       GENERATED_SOURCES                 # optional: generated dispatch code
#           ../logos_provider_dispatch.cpp
#       GENERATED_DIR                     # optional: generated code dir
#           ../generated_code
#   )

cmake_minimum_required(VERSION 3.14)

#[=======================================================================[.rst:
logos_test
----------

Build a Logos module test executable.

Required:
  NAME             - Test executable name
  MODULE_SOURCES   - Module source files to compile (not the real C lib)
  TEST_SOURCES     - Test source files (main.cpp + test_*.cpp)

Optional:
  MOCK_C_SOURCES     - Mock implementations for C libraries
  EXTRA_INCLUDES     - Additional include directories
  GENERATED_SOURCES  - Generated code files (logos_provider_dispatch.cpp, etc.)
  GENERATED_DIR      - Directory containing generated code (logos_sdk.cpp, etc.)
  EXTRA_LINK_LIBS    - Additional libraries to link
#]=======================================================================]
function(logos_test)
    cmake_parse_arguments(LT ""
        "NAME;GENERATED_DIR"
        "MODULE_SOURCES;TEST_SOURCES;MOCK_C_SOURCES;EXTRA_INCLUDES;GENERATED_SOURCES;EXTRA_LINK_LIBS"
        ${ARGN})

    if(NOT LT_NAME)
        message(FATAL_ERROR "logos_test: NAME is required")
    endif()

    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_AUTOMOC ON)

    # ── Locate logos-test-framework ──────────────────────────────────────────

    if(NOT DEFINED LOGOS_TEST_FRAMEWORK_ROOT)
        if(DEFINED ENV{LOGOS_TEST_FRAMEWORK_ROOT})
            set(LOGOS_TEST_FRAMEWORK_ROOT "$ENV{LOGOS_TEST_FRAMEWORK_ROOT}")
        else()
            message(FATAL_ERROR "LOGOS_TEST_FRAMEWORK_ROOT not set. "
                                "Set it via environment or CMake variable.")
        endif()
    endif()

    # ── Locate logos-cpp-sdk ─────────────────────────────────────────────────

    if(NOT DEFINED LOGOS_CPP_SDK_ROOT)
        if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
            set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}")
        else()
            message(FATAL_ERROR "LOGOS_CPP_SDK_ROOT not set. "
                                "Set it via environment or CMake variable.")
        endif()
    endif()

    # Detect source vs installed layout for SDK
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.h")
        set(LOGOS_CPP_SDK_IS_SOURCE TRUE)
        set(SDK_INCLUDE "${LOGOS_CPP_SDK_ROOT}/cpp")
        set(SDK_MOCK_INCLUDE "${LOGOS_CPP_SDK_ROOT}/cpp/implementations/mock")
    else()
        set(LOGOS_CPP_SDK_IS_SOURCE FALSE)
        set(SDK_INCLUDE "${LOGOS_CPP_SDK_ROOT}/include/cpp")
        set(SDK_MOCK_INCLUDE "${LOGOS_CPP_SDK_ROOT}/include/cpp/implementations/mock")
    endif()

    # Detect interface.h location (core/interface.h in SDK)
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/core/interface.h")
        set(SDK_CORE_INCLUDE "${LOGOS_CPP_SDK_ROOT}/core")
    elseif(EXISTS "${LOGOS_CPP_SDK_ROOT}/include/core/interface.h")
        set(SDK_CORE_INCLUDE "${LOGOS_CPP_SDK_ROOT}/include/core")
    else()
        set(SDK_CORE_INCLUDE "${SDK_INCLUDE}")
    endif()

    message(STATUS "[LogosTest] SDK root: ${LOGOS_CPP_SDK_ROOT} (source=${LOGOS_CPP_SDK_IS_SOURCE})")
    message(STATUS "[LogosTest] Framework root: ${LOGOS_TEST_FRAMEWORK_ROOT}")

    # ── Qt ───────────────────────────────────────────────────────────────────

    find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core RemoteObjects)
    find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core RemoteObjects)

    # ── Collect sources ──────────────────────────────────────────────────────

    set(ALL_SOURCES
        ${LT_TEST_SOURCES}
        ${LT_MODULE_SOURCES}
        ${LT_MOCK_C_SOURCES}
        ${LT_GENERATED_SOURCES}
        # Framework implementation sources
        ${LOGOS_TEST_FRAMEWORK_ROOT}/src/logos_test_runner.cpp
        ${LOGOS_TEST_FRAMEWORK_ROOT}/src/logos_test_context.cpp
        ${LOGOS_TEST_FRAMEWORK_ROOT}/src/logos_clib_mock.cpp
    )

    # SDK sources (when using source layout — Nix always provides installed layout)
    if(LOGOS_CPP_SDK_IS_SOURCE)
        list(APPEND ALL_SOURCES
            ${SDK_INCLUDE}/logos_types.cpp
            ${SDK_INCLUDE}/logos_api.cpp
            ${SDK_INCLUDE}/logos_api_client.cpp
            ${SDK_INCLUDE}/logos_api_consumer.cpp
            ${SDK_INCLUDE}/logos_api_provider.cpp
            ${SDK_INCLUDE}/module_proxy.cpp
            ${SDK_INCLUDE}/token_manager.cpp
            ${SDK_INCLUDE}/logos_transport_factory.cpp
            ${SDK_INCLUDE}/logos_registry_factory.cpp
            ${SDK_INCLUDE}/logos_provider_object.cpp
            ${SDK_INCLUDE}/qt_provider_object.cpp
            ${SDK_INCLUDE}/implementations/qt_local/local_transport.cpp
            ${SDK_INCLUDE}/implementations/qt_remote/remote_transport.cpp
            ${SDK_INCLUDE}/implementations/qt_remote/qt_remote_registry.cpp
            ${SDK_INCLUDE}/implementations/mock/mock_store.cpp
            ${SDK_INCLUDE}/implementations/mock/mock_transport.cpp
        )
    endif()

    # Look for generated logos_sdk.cpp in GENERATED_DIR
    if(LT_GENERATED_DIR)
        if(EXISTS "${LT_GENERATED_DIR}/logos_sdk.cpp")
            list(APPEND ALL_SOURCES "${LT_GENERATED_DIR}/logos_sdk.cpp")
            set_source_files_properties("${LT_GENERATED_DIR}/logos_sdk.cpp"
                PROPERTIES SKIP_AUTOMOC ON)
        elseif(EXISTS "${LT_GENERATED_DIR}/include/logos_sdk.cpp")
            list(APPEND ALL_SOURCES "${LT_GENERATED_DIR}/include/logos_sdk.cpp")
            set_source_files_properties("${LT_GENERATED_DIR}/include/logos_sdk.cpp"
                PROPERTIES SKIP_AUTOMOC ON)
        endif()
    endif()

    # Skip AUTOMOC on generated dispatch files
    foreach(src ${LT_GENERATED_SOURCES})
        set_source_files_properties(${src} PROPERTIES SKIP_AUTOMOC ON)
    endforeach()

    # ── Build test executable ────────────────────────────────────────────────

    add_executable(${LT_NAME} ${ALL_SOURCES})

    target_compile_definitions(${LT_NAME} PRIVATE LOGOS_TESTING=1)

    target_include_directories(${LT_NAME} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/..
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
        ${CMAKE_CURRENT_BINARY_DIR}
        # Framework headers
        ${LOGOS_TEST_FRAMEWORK_ROOT}/include
        # SDK headers
        ${SDK_INCLUDE}
        ${SDK_CORE_INCLUDE}
        ${SDK_MOCK_INCLUDE}
        ${SDK_INCLUDE}/implementations/qt_local
        ${SDK_INCLUDE}/implementations/qt_remote
    )

    # Generated code include
    if(LT_GENERATED_DIR)
        target_include_directories(${LT_NAME} PRIVATE
            ${LT_GENERATED_DIR}
            ${LT_GENERATED_DIR}/include
        )
    endif()

    # Extra includes
    foreach(dir ${LT_EXTRA_INCLUDES})
        target_include_directories(${LT_NAME} PRIVATE ${dir})
    endforeach()

    # ── Link ─────────────────────────────────────────────────────────────────

    target_link_libraries(${LT_NAME} PRIVATE
        Qt${QT_VERSION_MAJOR}::Core
        Qt${QT_VERSION_MAJOR}::RemoteObjects
    )

    # In installed layout, link against pre-built SDK library
    if(NOT LOGOS_CPP_SDK_IS_SOURCE)
        find_library(LOGOS_SDK_LIB logos_sdk
            PATHS "${LOGOS_CPP_SDK_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
        target_link_libraries(${LT_NAME} PRIVATE ${LOGOS_SDK_LIB})
    endif()

    # Extra link libraries
    foreach(lib ${LT_EXTRA_LINK_LIBS})
        target_link_libraries(${LT_NAME} PRIVATE ${lib})
    endforeach()

    # ── CTest ────────────────────────────────────────────────────────────────

    enable_testing()
    add_test(NAME ${LT_NAME} COMMAND ${LT_NAME})

endfunction()
