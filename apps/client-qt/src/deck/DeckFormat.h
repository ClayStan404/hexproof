// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QString>
#include <QStringList>

namespace hexproof::client {

inline constexpr auto kTableModeOneVsOne = "modern";
inline constexpr auto kTableModeDuel = "duel";
inline constexpr auto kTableModeEDH = "edh";

inline constexpr auto kDeckFormatCustom = "custom";
inline constexpr auto kDeckFormatStandard = "standard";
inline constexpr auto kDeckFormatPioneer = "pioneer";
inline constexpr auto kDeckFormatModern = "modern";
inline constexpr auto kDeckFormatLegacy = "legacy";
inline constexpr auto kDeckFormatVintage = "vintage";
inline constexpr auto kDeckFormatPauper = "pauper";
inline constexpr auto kDeckFormatDuel = "duel";
inline constexpr auto kDeckFormatCommander = "commander";
inline constexpr auto kDeckFormatCube = "cube";

QString normalizedDeckFormat(const QString &format);
bool supportedDeckFormat(const QString &format);
bool supportedTableMode(const QString &mode);
bool isCommanderTableMode(const QString &mode);
bool isCubeDeckFormat(const QString &format);
bool isNamedConstructedFormat(const QString &format);
QString tableModeForDeckFormat(const QString &format);
QString defaultDeckFormatForTableMode(const QString &mode);
QStringList supportedDeckFormats();

} // namespace hexproof::client
