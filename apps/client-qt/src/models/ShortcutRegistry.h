// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QString>
#include <QStringList>
#include <QVector>

namespace hexproof::client {

struct ShortcutDefinition
{
    QString id;
    QStringList defaultSequences;
};

const QVector<ShortcutDefinition> &shortcutDefinitions();
QStringList defaultShortcutSequences(const QString &actionId);
bool isKnownShortcutAction(const QString &actionId);

} // namespace hexproof::client
