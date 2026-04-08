# Go c-archive helpers for LogosTest.cmake (LINK_GO_STATIC_ARCHIVE, logos_find_go_static_archive).
# Included from LogosTest.cmake after its cmake_minimum_required (not between function/endfunction).

function(logos_find_go_static_archive out_var base_name)
    find_library(_logos_go_arch
        NAMES lib${base_name}.a lib${base_name}.lib ${base_name}.a ${base_name}.lib
        PATHS "${CMAKE_CURRENT_SOURCE_DIR}/../lib"
        NO_DEFAULT_PATH)
    set(${out_var} "${_logos_go_arch}" PARENT_SCOPE)
endfunction()

function(logos_target_link_go_c_archive target_name archive_path)
    if(NOT archive_path OR archive_path MATCHES "-NOTFOUND$")
        return()
    endif()
    find_package(Threads REQUIRED)
    target_link_libraries(${target_name} PRIVATE Threads::Threads)
    if(APPLE)
        target_link_options(${target_name} PRIVATE
            "-Wl,-force_load,${archive_path}"
            -Wl,-undefined,dynamic_lookup)
        target_link_libraries(${target_name} PRIVATE
            "-framework CoreFoundation"
            "-framework Security")
    else()
        target_link_options(${target_name} PRIVATE
            -Wl,--whole-archive
            ${archive_path}
            -Wl,--no-whole-archive)
    endif()
endfunction()
