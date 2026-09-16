# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

cmake_minimum_required(VERSION 3.20)

project(hexproof_ui_automation LANGUAGES C)

find_package(X11 REQUIRED)
if(NOT TARGET X11::Xtst)
    message(FATAL_ERROR "xfile-dialog requires the XTest extension development library")
endif()

foreach(tool IN ITEMS xwindow-list xshot xdrag xfile-dialog xwindow-owned)
    add_executable(${tool} ${tool}.c)
    target_compile_features(${tool} PRIVATE c_std_11)
    target_compile_options(${tool} PRIVATE -Wall -Wextra -Wpedantic)
    target_link_libraries(${tool} PRIVATE X11::X11)
endforeach()
target_link_libraries(xfile-dialog PRIVATE X11::Xtst)

include(CTest)
if(BUILD_TESTING)
    add_executable(xfile-dialog-test xfile-dialog-test.c)
    target_compile_features(xfile-dialog-test PRIVATE c_std_11)
    target_compile_options(xfile-dialog-test PRIVATE -Wall -Wextra -Wpedantic)
    target_link_libraries(xfile-dialog-test PRIVATE X11::X11 X11::Xtst)
    add_test(NAME xfile-dialog-ownership COMMAND xfile-dialog-test)
endif()
