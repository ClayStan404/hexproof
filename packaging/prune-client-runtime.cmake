# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

cmake_minimum_required(VERSION 3.21)

if(NOT DEFINED HEXPROOF_PACKAGE_ROOT
        OR NOT IS_DIRECTORY "${HEXPROOF_PACKAGE_ROOT}")
    message(FATAL_ERROR
        "HEXPROOF_PACKAGE_ROOT must name the staged client package.")
endif()

file(GLOB_RECURSE package_entries
    LIST_DIRECTORIES TRUE
    "${HEXPROOF_PACKAGE_ROOT}/*")

set(non_basic_style_pattern
    "^(FluentWinUI3|Fusion|Imagine|Material|Universal|Windows|iOS|macOS)$")
set(non_basic_style_runtime_pattern
    "^(lib)?Qt6QuickControls2(FluentWinUI3|Fusion|Imagine|Material|Universal|Windows|IOS|MacOS|NativeStyle).*[.](dll|dylib|so)([.].*)?$")

set(remove_paths)
foreach(entry IN LISTS package_entries)
    get_filename_component(entry_name "${entry}" NAME)
    get_filename_component(parent_path "${entry}" DIRECTORY)
    get_filename_component(parent_name "${parent_path}" NAME)

    if(IS_DIRECTORY "${entry}")
        if((entry_name STREQUAL "qmltooling"
                AND parent_name MATCHES "^(plugins|PlugIns)$")
                OR (entry_name STREQUAL "QtTest"
                    AND parent_name STREQUAL "qml")
                OR (parent_name STREQUAL "Controls"
                    AND entry_name MATCHES "${non_basic_style_pattern}")
                OR (entry_name STREQUAL "NativeStyle"
                    AND parent_name STREQUAL "QtQuick")
                OR (parent_name STREQUAL "Frameworks"
                    AND entry_name
                        MATCHES "^QtQuickControls2.*[.]framework$"
                    AND NOT entry_name
                        MATCHES "^QtQuickControls2(Basic|BasicStyleImpl|Impl)?[.]framework$")
                OR entry_name MATCHES "^Qt(Quick)?Test[.]framework$")
            list(APPEND remove_paths "${entry}")
        endif()
        continue()
    endif()

    if(entry_name
            MATCHES "^(lib)?Qt6(Quick)?Test[.](dll|dylib|so)([.].*)?$")
        list(APPEND remove_paths "${entry}")
    elseif(entry_name MATCHES "${non_basic_style_runtime_pattern}")
        list(APPEND remove_paths "${entry}")
    elseif(parent_name STREQUAL "sqldrivers"
            AND NOT entry_name
                MATCHES "^(lib)?qsqlite(d)?[.](dll|dylib|so)$")
        list(APPEND remove_paths "${entry}")
    endif()
endforeach()

list(REMOVE_DUPLICATES remove_paths)
foreach(path IN LISTS remove_paths)
    message(STATUS "Pruning unused client runtime: ${path}")
    file(REMOVE_RECURSE "${path}")
endforeach()
