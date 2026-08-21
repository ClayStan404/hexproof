// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "deck/Deck.h"
#include "deck/DeckParser.h"
#include "models/DeckLibraryStorage.h"

#include <QAbstractListModel>
#include <QFutureWatcher>
#include <QHash>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <atomic>
#include <functional>

namespace hexproof::client {

class DeckLibraryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(
        QString formatFilter READ formatFilter WRITE setFormatFilter NOTIFY formatFilterChanged)
    Q_PROPERTY(QString currentDeckId READ currentDeckId NOTIFY currentDeckChanged)
    Q_PROPERTY(QString currentDeckName READ currentDeckName NOTIFY currentDeckChanged)
    Q_PROPERTY(QString currentDeckFormat READ currentDeckFormat NOTIFY currentDeckChanged)
    Q_PROPERTY(QString currentDeckTableMode READ currentDeckTableMode NOTIFY currentDeckChanged)
    Q_PROPERTY(QString currentCommander READ currentCommander NOTIFY currentDeckChanged)
    Q_PROPERTY(int currentMainCount READ currentMainCount NOTIFY currentDeckChanged)
    Q_PROPERTY(int currentMissingImageCount READ currentMissingImageCount NOTIFY currentDeckChanged)
    Q_PROPERTY(int currentSideboardCount READ currentSideboardCount NOTIFY currentDeckChanged)
    Q_PROPERTY(bool currentReady READ currentReady NOTIFY currentDeckChanged)
    Q_PROPERTY(QString currentStatus READ currentStatus NOTIFY currentDeckChanged)
    Q_PROPERTY(
        bool currentValidationVerified READ currentValidationVerified NOTIFY currentDeckChanged)
    Q_PROPERTY(
        QStringList currentValidationIssues READ currentValidationIssues NOTIFY currentDeckChanged)
    Q_PROPERTY(QVariantList mainCards READ mainCards NOTIFY currentDeckChanged)
    Q_PROPERTY(QVariantList sideboardCards READ sideboardCards NOTIFY currentDeckChanged)
    Q_PROPERTY(QVariantList currentTokens READ currentTokens NOTIFY currentDeckChanged)
    Q_PROPERTY(
        QVariantList activeMatchTokens READ activeMatchTokens NOTIFY activeMatchTokensChanged)
    Q_PROPERTY(bool hasMissingArt READ hasMissingArt NOTIFY countChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(
        QStringList lastImportWarnings READ lastImportWarnings NOTIFY lastImportWarningsChanged)
    Q_PROPERTY(bool importingDeck READ importingDeck NOTIFY importingDeckChanged)
    Q_PROPERTY(QString importStage READ importStage NOTIFY importStageChanged)

  public:
    enum Role
    {
        IdRole = Qt::UserRole + 1,
        NameRole,
        FormatRole,
        TableModeRole,
        MainCountRole,
        SideboardCountRole,
        ReadyRole,
        StatusRole,
        CommanderRole,
        UpdatedAtRole,
        ValidationVerifiedRole,
        ValidationIssuesRole,
    };
    Q_ENUM(Role)

    using SaveDecksFunction =
        std::function<bool(const QVector<Deck> &, quint64 generation, QString *)>;
    explicit DeckLibraryModel(QObject *parent = nullptr);
    explicit DeckLibraryModel(const QString &storageRoot, QObject *parent = nullptr);
    DeckLibraryModel(const QString &storageRoot, SaveDecksFunction saveDecks,
                     QObject *parent = nullptr);
    ~DeckLibraryModel() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString formatFilter() const
    {
        return m_formatFilter;
    }
    void setFormatFilter(const QString &filter);

    QString currentDeckId() const;
    QString currentDeckName() const;
    QString currentDeckFormat() const;
    QString currentDeckTableMode() const;
    QString currentCommander() const;
    int currentMainCount() const;
    int currentMissingImageCount() const;
    int currentSideboardCount() const;
    bool currentReady() const;
    QString currentStatus() const;
    bool currentValidationVerified() const;
    QStringList currentValidationIssues() const;
    QVariantList mainCards() const;
    QVariantList sideboardCards() const;
    QVariantList currentTokens() const;
    QVariantList activeMatchTokens() const;
    QString lastError() const
    {
        return m_lastError;
    }
    QStringList lastImportWarnings() const
    {
        return m_lastImportWarnings;
    }
    bool hasMissingArt() const;
    bool importingDeck() const
    {
        return m_importingDeck;
    }
    QString importStage() const
    {
        return m_importStage;
    }

    Q_INVOKABLE bool importDeck(const QString &name, const QString &format, const QString &text);
    Q_INVOKABLE bool importDeckAsync(const QString &name, const QString &format,
                                     const QString &text);
    Q_INVOKABLE QVariantMap loadDeckTextFile(const QUrl &fileUrl);
    Q_INVOKABLE QString exportDeckText(const QString &id) const;
    Q_INVOKABLE QString exportCurrentDeckText() const;
    Q_INVOKABLE QString suggestedExportFileName(const QString &id) const;
    Q_INVOKABLE QUrl suggestedExportUrl(const QString &id) const;
    Q_INVOKABLE bool copyDeckText(const QString &id);
    Q_INVOKABLE bool copyCurrentDeckText();
    Q_INVOKABLE bool saveDeckText(const QString &id, const QUrl &fileUrl);
    Q_INVOKABLE bool saveCurrentDeckText(const QUrl &fileUrl);
    Q_INVOKABLE bool deleteDeck(const QString &id);
    Q_INVOKABLE bool openDeck(const QString &id);
    Q_INVOKABLE void closeDeck();
    Q_INVOKABLE bool renameCurrentDeck(const QString &name);
    Q_INVOKABLE bool changeCurrentDeckFormat(const QString &format);
    Q_INVOKABLE bool setCommander(const QString &cardName);
    Q_INVOKABLE bool moveCard(const QString &cardName, bool toSideboard);
    Q_INVOKABLE bool changeCardCount(const QString &cardName, bool sideboard, int delta);
    Q_INVOKABLE bool addCard(const QString &name, const QString &localizedName,
                             const QString &typeLine, const QString &setCode,
                             const QString &collectorNumber, bool sideboard);
    Q_INVOKABLE bool setCardPrinting(const QString &cardName, bool sideboard,
                                     const QString &localizedName, const QString &typeLine,
                                     const QString &setCode, const QString &collectorNumber);
    Q_INVOKABLE bool addToken(const QVariantMap &token);
    Q_INVOKABLE bool removeToken(const QString &name, const QString &setCode,
                                 const QString &collectorNumber);
    Q_INVOKABLE bool setActiveMatchDeck(const QString &id);
    Q_INVOKABLE int currentCardCopies(const QString &cardName) const;
    Q_INVOKABLE bool canAddCard(const QString &cardName, const QString &typeLine = {}) const;
    Q_INVOKABLE QVariantList matchDecks(const QString &format, bool allowMissingArt = false) const;
    Q_INVOKABLE QVariantMap deckForMatch(const QString &id, bool allowMissingArt = false) const;
    Q_INVOKABLE void refreshCardArt();
    Q_INVOKABLE void refreshMissingArt();
    Q_INVOKABLE void cacheCurrentDeckArt();
    Q_INVOKABLE void refreshTokenMetadata();
    Q_INVOKABLE void retryMissingArt();
    Q_INVOKABLE void refreshDeckValidation();
    Q_INVOKABLE void clearLastError();
    void hydrateCatalogMetadata(bool refreshExisting = false);

#ifdef HEXPROOF_TESTING
    void flushMetadataCommitForTest()
    {
        flushMetadataCommit();
    }
    bool metadataCommitPendingForTest() const
    {
        return m_metadataCommitPending;
    }
    bool backgroundSaveRunningForTest() const
    {
        return m_backgroundSaveRunning;
    }
    quint64 persistenceGenerationForTest() const
    {
        return m_persistenceGeneration;
    }
    quint64 persistedGenerationForTest() const
    {
        return m_persistedGeneration;
    }
#endif

  public slots:
    void applyCardMetadata(const QString &requestedName, const QString &localizedName,
                           const QString &typeLine, const QString &imagePath,
                           const QString &setCode, const QString &collectorNumber);
    void applyCatalogMetadata(const QVariantList &cards);
    void applyTokenMetadata(const QVariantList &tokens);
    void applyDeckValidation(const QVariantList &results);

  signals:
    void countChanged();
    void formatFilterChanged();
    void currentDeckChanged();
    void activeMatchTokensChanged();
    void lastErrorChanged();
    void lastImportWarningsChanged();
    void importingDeckChanged();
    void importStageChanged();
    void deckImportFinished(bool success);
    void cardsNeedCachedArtLookup(const QVariantList &cards);
    void cardsNeedCaching(const QVariantList &cards);
    void cardsNeedRetry(const QVariantList &cards);
    void cardsNeedMetadata(const QVariantList &cards);
    void tokensNeedMetadata(const QVariantList &tokens);
    void decksNeedValidation(const QVariantList &decks);

  private:
    static constexpr int kMetadataCommitDelayMs = 250;

    struct BackgroundSaveResult
    {
        quint64 generation = 0;
        bool success = false;
        QString error;
    };

    const Deck *currentDeck() const;
    Deck *currentDeck();
    const Deck *deckById(const QString &id) const;
    QString exportFileNameForDeck(const Deck &deck) const;
    const Deck *activeMatchDeck() const;
    bool load();
    bool save();
    void rebuildVisibleRows();
    void rebuildCardDeckIndex();
    void notifyAllChanged();
    void notifyDecksChanged(const QSet<QString> &deckIds);
    bool validateDeckImport(const QString &name, const QString &format, QString *deckName,
                            QString *deckFormat);
    bool commitDeckImport(const QString &deckName, const QString &deckFormat,
                          const DeckParseResult &parsed);
    void finishAsyncDeckImport();
    void commitPendingAsyncDeckImport();
    void scheduleMetadataCommit();
    void flushMetadataCommit();
    void startBackgroundSave();
    void finishBackgroundSave();
    void setLastError(const QString &error);
    void setLastImportWarnings(const QStringList &warnings);
    void setImportStage(const QString &stage);
    void scheduleDeckValidation(const QString &deckId);
    void validatePendingDecks();
    QVariantMap validationForDeck(const QString &deckId) const;
    void requestCatalogMetadata(const Deck &deck, bool refreshExisting);

    DeckLibraryStorage m_storage;
    SaveDecksFunction m_saveDecks;
    QVector<Deck> m_decks;
    QVector<int> m_visibleRows;
    QString m_formatFilter = QStringLiteral("all");
    QString m_currentDeckId;
    QString m_activeMatchDeckId;
    QString m_lastError;
    QStringList m_lastImportWarnings;
    bool m_importingDeck = false;
    QString m_pendingImportName;
    QString m_pendingImportFormat;
    QString m_importStage;
    DeckParseResult m_pendingParsedImport;
    QFutureWatcher<DeckParseResult> m_importWatcher;
    QFutureWatcher<BackgroundSaveResult> m_backgroundSaveWatcher;
    QTimer m_metadataCommitTimer;
    QTimer m_validationTimer;
    QHash<QString, QVariantMap> m_deckValidations;
    QHash<QString, quint64> m_validationRevisions;
    QSet<QString> m_pendingValidationDeckIds;
    QHash<QString, QSet<int>> m_cardDeckIndex;
    QSet<QString> m_metadataChangedDeckIds;
    QSet<QString> m_backgroundSaveDeckIds;
    quint64 m_persistenceGeneration = 0;
    quint64 m_persistedGeneration = 0;
    std::atomic<quint64> m_committedGeneration{0};
    int m_backgroundSaveAttempts = 0;
    bool m_backgroundSaveRunning = false;
    bool m_metadataCommitPending = false;
};

} // namespace hexproof::client
