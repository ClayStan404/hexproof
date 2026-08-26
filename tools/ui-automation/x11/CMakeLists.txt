# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

cmake_minimum_required(VERSION 3.20)

project(hexproof_ui_automation LANGUAGES C)

find_package(X11 REQUIRED)

foreach(tool IN ITEMS xwindow-list xshot xdrag)
    add_executable(${tool} ${tool}.c)
    target_compile_features(${tool} PRIVATE c_std_11)
    target_compile_options(${tool} PRIVATE -Wall -Wextra -Wpedantic)
    target_link_libraries(${tool} PRIVATE X11::X11)
endforeach()
