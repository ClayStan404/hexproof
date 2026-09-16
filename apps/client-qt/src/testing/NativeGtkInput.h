// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QString>
#include <QVariantMap>

namespace hexproof::client {

// Audit-only GTK widget events. This exercises the real file chooser's UI
// handlers, but does not establish compositor or operating-system input routing.
QVariantMap selectNativeGtkFile(const QString &title, const QString &path,
                                quintptr expectedOwnerWindow, bool save = false);

} // namespace hexproof::client
