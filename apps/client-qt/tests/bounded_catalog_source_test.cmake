# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

if(NOT DEFINED HEXPROOF_CLIENT_SOURCE_DIR)
    message(FATAL_ERROR "HEXPROOF_CLIENT_SOURCE_DIR is required")
endif()

function(assert_body_has_no_unbounded_expansion relative_path start_marker end_marker)
    file(READ "${HEXPROOF_CLIENT_SOURCE_DIR}/${relative_path}" contents)
    string(FIND "${contents}" "${start_marker}" start_offset)
    string(FIND "${contents}" "${end_marker}" end_offset)
    if(start_offset LESS 0 OR end_offset LESS 0 OR end_offset LESS_EQUAL start_offset)
        message(FATAL_ERROR "Could not isolate ${start_marker} in ${relative_path}")
    endif()
    math(EXPR body_length "${end_offset} - ${start_offset}")
    string(SUBSTRING "${contents}" ${start_offset} ${body_length} body)
    if(body MATCHES "expandCardFaceRequests[ \t\r\n]*\\(")
        message(FATAL_ERROR "${relative_path}: ${start_marker} uses unbounded face expansion")
    endif()
endfunction()

file(READ "${HEXPROOF_CLIENT_SOURCE_DIR}/src/main.cpp" main_source)
if(main_source MATCHES "expandCardFaceRequests[ \t\r\n]*\\(")
    message(FATAL_ERROR "src/main.cpp uses synchronous unbounded face expansion")
endif()

assert_body_has_no_unbounded_expansion(
    "src/services/CardCatalogCache.cpp"
    "void CardCatalog::cacheCards("
    "void CardCatalog::cacheCardsIncrementally(")
assert_body_has_no_unbounded_expansion(
    "src/services/CardCatalogCache.cpp"
    "void CardCatalog::retryCards("
    "void CardCatalog::prioritizeCards(")
assert_body_has_no_unbounded_expansion(
    "src/services/CardCatalogLimitedArt.cpp"
    "void CardCatalog::cacheLimitedProductArt("
    "void CardCatalog::restartLimitedArtFaceExpansion(")
