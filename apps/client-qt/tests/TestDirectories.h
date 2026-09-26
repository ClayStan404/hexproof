// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QDir>

namespace hexproof::test {

inline QString canonicalTemporaryDirectoryTemplate()
{
    // macOS exposes its temporary root through /var -> /private/var. Storage
    // fixtures need ordinary paths so intentional symlink cases stay explicit.
    return QDir(QDir(QDir::tempPath()).canonicalPath())
        .filePath(QStringLiteral("hexproof-test-XXXXXX"));
}

} // namespace hexproof::test
