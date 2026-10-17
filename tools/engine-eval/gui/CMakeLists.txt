# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
cmake_minimum_required(VERSION 3.22)
project(HexproofEngineLaboratory LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Widgets Test)
add_executable(engine-lab main.cpp)
target_link_libraries(engine-lab PRIVATE Qt6::Widgets Qt6::Test)
