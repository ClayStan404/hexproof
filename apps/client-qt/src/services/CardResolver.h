// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogTypes.h"

#include <QByteArray>
#include <QDateTime>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QObject>
#include <QSet>
#include <QUrl>

#include <functional>

class QNetworkAccessManager;
class QNetworkReply;

namespace hexproof::client {

class CardResolver final : public QObject
{
  public:
    enum class ArtProvider
    {
        Scryfall,
        Mtgch,
    };

    struct Callbacks
    {
        std::function<CardRecord(const CardRequest &)> lookupCatalog;
        std::function<CardRecord(const CardRequest &, const CardRecord &)> lookupLocalizedPrinting;
        std::function<void(const QJsonArray &)> persistLocalizedPrintings;
        std::function<QString(const CardRequest &, const CardRecord &)> imagePathFor;
        std::function<void(const QString &)> setStatus;
        std::function<void(const CardRequest &, CardRecord, bool, bool, const QString &)> completed;
        std::function<void()> queueMoreWork;
    };

    enum class Phase
    {
        None = 0,
        ScryfallChineseExact = 1,
        ScryfallChineseSearch = 2,
        ScryfallEnglish = 3,
        Mtgch = 4,
        Image = 5,
    };

    explicit CardResolver(QNetworkAccessManager *network, Callbacks callbacks,
                          QObject *parent = nullptr);
    ~CardResolver() override;

    QUrl chineseExactUrl(const QString &setCode, const QString &collectorNumber) const;
    QUrl chineseSearchUrl(const QString &oracleId, const QString &name) const;
    QUrl englishUrl(const QString &name, const QString &setCode,
                    const QString &collectorNumber) const;
    QUrl mtgchUrl(const QString &setCode, const QString &collectorNumber) const;

    QNetworkRequest requestFor(const QUrl &url, const QByteArray &accept,
                               int transferTimeoutMs = 15'000) const;
    QNetworkReply *requestImage(const QUrl &url);
    void requestJson(const QUrl &url, std::function<void(QNetworkReply *)> finished);

    bool active() const
    {
        return m_active;
    }
    void setPreferredProvider(ArtProvider provider)
    {
        m_configuredProvider = provider;
    }
    void resolve(CardRequest request);

    int retryDelayMs(int httpStatus, const QByteArray &retryAfter) const;
    bool hostInCooldown(const QUrl &url);
    void markHostSuccess(const QUrl &url);
    void markHostFailure(const QUrl &url, int httpStatus, const QByteArray &retryAfter,
                         int networkErrorCode = 0);
    void clearCooldowns();
    QString phaseName(Phase phase) const;

  private:
    enum class ArtStage
    {
        None,
        ScryfallChineseExact,
        ScryfallChineseAlternate,
        MtgchChinese,
        ScryfallEnglish,
        MtgchEnglish
    };

    QNetworkReply *startRequest(const QNetworkRequest &request);
    void trackReply(QNetworkReply *reply);
    void beginChineseExactRequest();
    void beginChineseAlternate();
    void beginScryfallChineseSearch();
    void beginScryfallEnglishRequest();
    void beginMtgchRequest();
    void continueAfterScryfallChinese();
    void continueAfterMtgchChinese();
    void beginNextEnglishCandidate();
    void beginImageRequest(ArtStage stage);
    void continueAfterImageFailure(bool confirmedMissing);
    void beginJsonRequest(const QUrl &url, Phase phase);
    void handleJsonReply(QNetworkReply *reply, Phase phase);
    void handleImageReply(QNetworkReply *reply);
    void applyJsonObject(Phase phase, const QJsonObject &object);
    void applyScryfallEnglishJson(const QJsonObject &object);
    void applyScryfallChineseExactJson(const QJsonObject &object);
    void applyScryfallChineseSearchJson(const QJsonObject &object);
    void applyMtgchJson(const QJsonObject &object);
    void rejectJsonReply(const QUrl &requestUrl, Phase phase, int httpStatus, int networkError,
                         const QString &networkErrorString, const QByteArray &retryAfter,
                         bool networkOk);
    void acceptImageBytes(const QUrl &requestUrl, const QByteArray &bytes);
    void continueAfterJsonFailure(Phase phase, bool confirmedMissing);
    bool retryCurrentPhase(const QUrl &url, Phase phase, int httpStatus,
                           const QByteArray &retryAfter);
    void setCurrentFailure(const QUrl &url, Phase phase, int httpStatus, int networkErrorCode,
                           const QString &networkError, const QString &validationError = {});
    void finishCurrentCard(bool success, bool cacheFailure = false);

    QNetworkAccessManager *m_network = nullptr;
    Callbacks m_callbacks;
    QSet<QNetworkReply *> m_activeReplies;
    QHash<QString, QDateTime> m_hostCooldowns;
    CardRequest m_currentRequest;
    CardRecord m_catalogRecord;
    CardRecord m_currentRecord;
    CardRecord m_mtgchEnglishRecord;
    QString m_currentFailureDetail;
    ArtStage m_currentArtStage = ArtStage::None;
    Phase m_currentPhase = Phase::None;
    int m_currentPhaseRetries = 0;
    ArtProvider m_configuredProvider = ArtProvider::Scryfall;
    ArtProvider m_currentProvider = ArtProvider::Scryfall;
    bool m_currentMtgchTried = false;
    bool m_currentScryfallEnglishTried = false;
    bool m_currentMtgchEnglishImageTried = false;
    bool m_currentConfirmedMissing = false;
    bool m_active = false;
};

} // namespace hexproof::client
