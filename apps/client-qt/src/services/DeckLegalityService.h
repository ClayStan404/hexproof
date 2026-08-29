// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QFutureWatcher>
#include <QObject>
#include <QVariantList>

namespace hexproof::client {

class DeckLegalityService : public QObject
{
    Q_OBJECT

  public:
    explicit DeckLegalityService(QObject *parent = nullptr);
    explicit DeckLegalityService(const QString &storageRoot, QObject *parent = nullptr);
    ~DeckLegalityService() override;

    static QVariantList validate(const QString &databasePath, const QVariantList &decks);

  public slots:
    void validateDecks(const QVariantList &decks);

  signals:
    void validationReady(const QVariantList &results);

  private:
    void startLatestValidation();
    void finishValidation();

    QString m_databasePath;
    QVariantList m_latestDecks;
    QFutureWatcher<QVariantList> m_watcher;
    quint64 m_generation = 0;
    quint64 m_runningGeneration = 0;
};

} // namespace hexproof::client
