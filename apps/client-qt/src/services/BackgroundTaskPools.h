// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QThreadPool>

namespace hexproof::client {

class BackgroundTaskPools final
{
  public:
    BackgroundTaskPools() = delete;

    static QThreadPool *catalogSearch()
    {
        static QThreadPool pool;
        static const bool configured = configure(pool, 1);
        Q_UNUSED(configured);
        return &pool;
    }

    static QThreadPool *catalogMaintenance()
    {
        static QThreadPool pool;
        static const bool configured = configure(pool, 2);
        Q_UNUSED(configured);
        return &pool;
    }

    static QThreadPool *deckParsing()
    {
        static QThreadPool pool;
        static const bool configured = configure(pool, 1);
        Q_UNUSED(configured);
        return &pool;
    }

    static QThreadPool *deckPersistence()
    {
        static QThreadPool pool;
        static const bool configured = configure(pool, 1);
        Q_UNUSED(configured);
        return &pool;
    }

  private:
    static bool configure(QThreadPool &pool, int maximumThreads)
    {
        pool.setMaxThreadCount(maximumThreads);
        pool.setExpiryTimeout(30'000);
        return true;
    }
};

} // namespace hexproof::client
