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

cmake_minimum_required(VERSION 3.15)

# Load before function(logos_test): tests/CMakeLists.txt calls logos_find_go_static_archive
# after include(LogosTest); helpers must exist at include() return (see LogosTestGoStatic.cmake).
include(${CMAKE_CURRENT_LIST_DIR}/LogosTestGoStatic.cmake)

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
  LINK_GO_STATIC_ARCHIVE - Absolute path to a Go c-archive (.a); links with
                           whole-archive / -force_load (see LogosModule.cmake)
#]=======================================================================]
function(logos_test)
    # PARSE_ARGV: CMake 3.31+ can mis-parse ${ARGN} for functions with no named parameters,
    # merging all args into LT_NAME. Read from ARGV starting at index 0 instead.
    cmake_parse_arguments(PARSE_ARGV 0 LT ""
        "NAME;GENERATED_DIR;LINK_GO_STATIC_ARCHIVE"
        "MODULE_SOURCES;TEST_SOURCES;MOCK_C_SOURCES;EXTRA_INCLUDES;GENERATED_SOURCES;EXTRA_LINK_LIBS")

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

    # ── Locate logos-cpp-sdk / logos-qt-sdk / logos-protocol ─────────────────
    # Since the qt split the SDK is three roots: the Qt-free base SDK
    # (logos_module_context.h — logos_api.h moved away), the Qt developer
    # layer (LogosAPI, provider objects, core/interface.h), and the protocol
    # layer (transports, consumer core, mock implementations).

    if(NOT DEFINED LOGOS_CPP_SDK_ROOT)
        if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
            set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}")
        else()
            message(FATAL_ERROR "LOGOS_CPP_SDK_ROOT not set. "
                                "Set it via environment or CMake variable.")
        endif()
    endif()
    if(NOT DEFINED LOGOS_QT_SDK_ROOT)
        if(DEFINED ENV{LOGOS_QT_SDK_ROOT})
            set(LOGOS_QT_SDK_ROOT "$ENV{LOGOS_QT_SDK_ROOT}")
        else()
            message(FATAL_ERROR "LOGOS_QT_SDK_ROOT not set. "
                                "Set it via environment or CMake variable.")
        endif()
    endif()
    if(NOT DEFINED LOGOS_PROTOCOL_ROOT)
        if(DEFINED ENV{LOGOS_PROTOCOL_ROOT})
            set(LOGOS_PROTOCOL_ROOT "$ENV{LOGOS_PROTOCOL_ROOT}")
        else()
            message(FATAL_ERROR "LOGOS_PROTOCOL_ROOT not set. "
                                "Set it via environment or CMake variable.")
        endif()
    endif()

    # Detect source vs installed layout per root
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/logos_module_context.h")
        set(LOGOS_CPP_SDK_IS_SOURCE TRUE)
        set(SDK_INCLUDE "${LOGOS_CPP_SDK_ROOT}/cpp")
    else()
        set(LOGOS_CPP_SDK_IS_SOURCE FALSE)
        set(SDK_INCLUDE "${LOGOS_CPP_SDK_ROOT}/include/cpp")
    endif()
    if(EXISTS "${LOGOS_QT_SDK_ROOT}/cpp/logos_api.h")
        set(LOGOS_QT_SDK_IS_SOURCE TRUE)
        set(QT_SDK_INCLUDE "${LOGOS_QT_SDK_ROOT}/cpp")
        set(SDK_CORE_INCLUDE "${LOGOS_QT_SDK_ROOT}/core")
    else()
        set(LOGOS_QT_SDK_IS_SOURCE FALSE)
        set(QT_SDK_INCLUDE "${LOGOS_QT_SDK_ROOT}/include/cpp")
        set(SDK_CORE_INCLUDE "${LOGOS_QT_SDK_ROOT}/include/core")
    endif()
    if(EXISTS "${LOGOS_PROTOCOL_ROOT}/cpp/logos_protocol.h")
        set(PROTOCOL_INCLUDE "${LOGOS_PROTOCOL_ROOT}/cpp")
        set(PROTOCOL_IMPL_INCLUDE "${LOGOS_PROTOCOL_ROOT}/cpp/implementations")
    else()
        set(PROTOCOL_INCLUDE "${LOGOS_PROTOCOL_ROOT}/include")
        set(PROTOCOL_IMPL_INCLUDE "${LOGOS_PROTOCOL_ROOT}/include/implementations")
    endif()
    # Mock transport headers live in logos-protocol since the extraction.
    set(SDK_MOCK_INCLUDE "${PROTOCOL_IMPL_INCLUDE}/mock")

    message(STATUS "[LogosTest] SDK root: ${LOGOS_CPP_SDK_ROOT} (source=${LOGOS_CPP_SDK_IS_SOURCE})")
    message(STATUS "[LogosTest] Qt SDK root: ${LOGOS_QT_SDK_ROOT}")
    message(STATUS "[LogosTest] Protocol root: ${LOGOS_PROTOCOL_ROOT}")
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

    # Qt-SDK sources (when using source layout — Nix always provides installed
    # layout). The transport/consumer core (types, api_client, token_manager,
    # mock transports, ...) lives in the logos-protocol LIBRARY and is linked
    # below instead of compiled in.
    if(LOGOS_QT_SDK_IS_SOURCE)
        list(APPEND ALL_SOURCES
            ${QT_SDK_INCLUDE}/logos_api.cpp
            ${QT_SDK_INCLUDE}/logos_api_provider.cpp
            ${QT_SDK_INCLUDE}/logos_provider_object.cpp
            ${QT_SDK_INCLUDE}/qt_provider_object.cpp
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
        # SDK headers (base, Qt layer, protocol layer)
        ${SDK_INCLUDE}
        ${QT_SDK_INCLUDE}
        ${SDK_CORE_INCLUDE}
        ${PROTOCOL_INCLUDE}
        ${SDK_MOCK_INCLUDE}
        ${PROTOCOL_IMPL_INCLUDE}/qt_local
        ${PROTOCOL_IMPL_INCLUDE}/qt_remote
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

    # Link the Qt SDK via its exported CMake target so the consumer inherits
    # the full transitive link interface (logos-protocol, and through it
    # OpenSSL / Boost::system / nlohmann_json). A bare archive on the link
    # line would leave Boost.Asio TLS symbols undefined.
    if(NOT LOGOS_QT_SDK_IS_SOURCE)
        find_package(logos-protocol REQUIRED CONFIG
            PATHS "${LOGOS_PROTOCOL_ROOT}/lib/cmake/logos-protocol"
            NO_DEFAULT_PATH)
        find_package(logos-qt-sdk REQUIRED CONFIG
            PATHS "${LOGOS_QT_SDK_ROOT}/lib/cmake/logos-qt-sdk"
            NO_DEFAULT_PATH)
        target_link_libraries(${LT_NAME} PRIVATE logos-qt-sdk::logos_qt_sdk)
    else()
        # Source-layout qt-sdk compiled in above; link the protocol library.
        if(NOT TARGET logos_protocol)
            add_subdirectory("${LOGOS_PROTOCOL_ROOT}/cpp"
                             "${CMAKE_BINARY_DIR}/logos-protocol-build")
        endif()
        target_link_libraries(${LT_NAME} PRIVATE logos_protocol)
    endif()

    # Qt-free base SDK headers (nlohmann include path for logos_json.h etc.)
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/lib/cmake/logos-cpp-sdk")
        find_package(logos-cpp-sdk REQUIRED CONFIG
            PATHS "${LOGOS_CPP_SDK_ROOT}/lib/cmake/logos-cpp-sdk"
            NO_DEFAULT_PATH)
        target_link_libraries(${LT_NAME} PRIVATE logos-cpp-sdk::logos_headers)
    else()
        find_package(nlohmann_json REQUIRED)
        target_link_libraries(${LT_NAME} PRIVATE nlohmann_json::nlohmann_json)
    endif()

    # Extra link libraries
    foreach(lib ${LT_EXTRA_LINK_LIBS})
        target_link_libraries(${LT_NAME} PRIVATE ${lib})
    endforeach()

    if(LT_LINK_GO_STATIC_ARCHIVE)
        logos_target_link_go_c_archive(${LT_NAME} "${LT_LINK_GO_STATIC_ARCHIVE}")
    endif()

    # ── CTest ────────────────────────────────────────────────────────────────

    enable_testing()
    add_test(NAME ${LT_NAME} COMMAND ${LT_NAME})

endfunction()
