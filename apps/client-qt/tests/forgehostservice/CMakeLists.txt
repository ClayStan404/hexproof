# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

# Run the production service regression independently on every desktop platform.
cmake_minimum_required(VERSION 3.21)
project(hexproof_forgehostservice_tests LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Test)
enable_testing()

if(MSVC)
    add_compile_options(/W4 /WX)
else()
    add_compile_options(-Wall -Wextra -Wpedantic -Werror)
endif()

add_executable(hexproof_forgehostservice_test
    ../forgehostservice_test.cpp
    ../../src/services/ForgeHostDiagnostics.cpp
    ../../src/services/ForgeHostService.cpp
    ../../src/services/ForgeHostService.h)
target_include_directories(hexproof_forgehostservice_test PRIVATE ../../src)
target_link_libraries(hexproof_forgehostservice_test PRIVATE Qt6::Core Qt6::Test)
add_custom_command(TARGET hexproof_forgehostservice_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:hexproof_forgehostservice_test>"
        "$<TARGET_FILE_DIR:hexproof_forgehostservice_test>/hexproof-forge-host${CMAKE_EXECUTABLE_SUFFIX}"
    VERBATIM)
add_test(NAME forgehostservice COMMAND hexproof_forgehostservice_test
    -o -,txt -o forgehostservice-results.txt,txt)
set_tests_properties(forgehostservice PROPERTIES TIMEOUT 90)
