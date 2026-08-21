// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "deck/Deck.h"

#include <QString>
#include <QVector>

#include <atomic>
#include <memory>

class QMutex;

namespace hexproof::client {

struct DeckLibraryPreferences
{
    QString uiLanguage = QStringLiteral("en");
    QString cardLanguage = QStringLiteral("en");
    bool reuseLocalCardArt = true;
    qreal interfaceScale = 1.0;
    bool tableShowPlayers = true;
    bool tableShowShared = true;
    bool tableShowInspector = true;
    bool tableShowGameLog = true;
    int tableCounterCount = 0;
    qreal tableOverviewCardScale = 0.0;
    qreal tableFocusCardScale = 0.0;
    qreal tableBattlefieldControlX = -1.0;
    qreal tableBattlefieldControlY = -1.0;
};

class DeckLibraryStorage
{
  public:
    explicit DeckLibraryStorage(const QString &storageRoot);

    bool loadDecks(QVector<Deck> *decks, QString *error);
    bool saveDecks(const QVector<Deck> &decks, QString *error) const;
    bool saveDecksIfNewer(const QVector<Deck> &decks, quint64 generation,
                          std::atomic<quint64> *committedGeneration, QString *error) const;
    bool libraryWritable() const
    {
        return m_libraryWritable;
    }
    DeckLibraryPreferences loadPreferences();
    bool savePreferences(const DeckLibraryPreferences &preferences, QString *error) const;

  private:
    bool writeDecksLocked(const QVector<Deck> &decks, QString *error) const;
    QString m_libraryPath;
    QString m_settingsPath;
    std::shared_ptr<QMutex> m_writeMutex;
    bool m_libraryWritable = true;
    bool m_settingsWritable = true;
};

} // namespace hexproof::client
