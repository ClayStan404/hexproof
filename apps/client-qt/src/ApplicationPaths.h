// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QDir>
#include <QStandardPaths>
#include <QString>

namespace hexproof::client {

inline QString defaultStorageRoot()
{
    QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (path.isEmpty())
        path = QDir::home().filePath(QStringLiteral(".hexproof"));
    return path;
}

} // namespace hexproof::client
