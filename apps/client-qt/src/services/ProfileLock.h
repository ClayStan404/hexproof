// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QDir>
#include <QLockFile>
#include <memory>

namespace hexproof::client {

// Whole-profile ownership, not a per-write mutex: two stale library snapshots
// must never be allowed to overwrite each other. Independent profiles can run
// concurrently. Acquire before constructing any persistent application model.
class ProfileLock final
{
  public:
    explicit ProfileLock(const QString &storageRoot)
    {
        if (!QDir().mkpath(storageRoot))
            return;
        const QString canonicalRoot = QDir(storageRoot).canonicalPath();
        if (canonicalRoot.isEmpty())
            return;
        m_lock = std::make_unique<QLockFile>(
            QDir(canonicalRoot).filePath(QStringLiteral("profile.lock")));
        // A running game may last hours. Only dead-process detection may reclaim
        // this lock; its age alone must never let another writer in.
        m_lock->setStaleLockTime(0);
    }

    bool tryLock()
    {
        return m_lock && m_lock->tryLock(0);
    }
    bool occupied() const
    {
        return m_lock && m_lock->error() == QLockFile::LockFailedError;
    }

  private:
    std::unique_ptr<QLockFile> m_lock;
};

} // namespace hexproof::client
