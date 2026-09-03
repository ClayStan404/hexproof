// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CardArtAudit.h"
#include "CardCatalogCommon.h"

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantMap>

#include <functional>

namespace hexproof::client {

class CardArtCache;

class CardArtManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QVariantMap inventory READ inventory NOTIFY inventoryChanged)
    Q_PROPERTY(QVariantMap packPreview READ packPreview NOTIFY packInspectionFinished)
    Q_PROPERTY(QVariantMap auditResult READ auditResult NOTIFY auditResultChanged)
    Q_PROPERTY(bool repairNeeded READ repairNeeded NOTIFY repairNeededChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastResult READ lastResult NOTIFY lastResultChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString storagePath READ storagePath CONSTANT)
    // Version of the face-cache audit this build runs; the repair notice
    // popup binds its notice version to this so both advance together.
    Q_PROPERTY(int faceAuditVersion READ faceAuditVersion CONSTANT)

  public:
    explicit CardArtManager(QString storageRoot, CardArtCache *cache, QObject *parent = nullptr);

    int faceAuditVersion() const
    {
        return catalog_internal::kCardFaceAuditVersion;
    }

    bool busy() const
    {
        return m_busy;
    }
    QVariantMap inventory() const
    {
        return m_inventory;
    }
    QVariantMap packPreview() const
    {
        return m_packPreview;
    }
    QVariantMap auditResult() const
    {
        return m_auditResult.summary();
    }
    bool repairNeeded() const
    {
        return m_repairNeeded;
    }
    QString status() const
    {
        return m_status;
    }
    QString lastResult() const
    {
        return m_lastResult;
    }
    QString lastError() const
    {
        return m_lastError;
    }
    QString storagePath() const;

    void setOperationGuard(std::function<bool()> guard);
    void setAuditRequestProvider(std::function<QVariantList()> provider,
                                 std::function<QString()> languageProvider);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void auditCardArt(bool force = true);
    Q_INVOKABLE void repairAuditedCardArt();
    Q_INVOKABLE void inspectPack(const QUrl &fileUrl);
    Q_INVOKABLE QUrl suggestedExportUrl(bool selectionOnly, const QString &setCode,
                                        const QString &imageLanguage) const;
    Q_INVOKABLE void exportPack(const QUrl &fileUrl, bool selectionOnly,
                                const QString &setCode = {}, const QString &imageLanguage = {});
    Q_INVOKABLE void importPack(const QUrl &fileUrl);
    Q_INVOKABLE void removeOrphans();
    Q_INVOKABLE void removeSelection(bool selectionOnly, const QString &setCode = {},
                                     const QString &imageLanguage = {});
    Q_INVOKABLE void clearMessages();
    void repeatAuditAfterRepair();

  signals:
    void busyChanged();
    void inventoryChanged();
    void packInspectionFinished();
    void auditResultChanged();
    void repairNeededChanged();
    void auditFinished();
    void statusChanged();
    void lastResultChanged();
    void lastErrorChanged();
    void contentsChanged();
    void repairDownloadsRequested(const QVariantList &cards);

  private:
    bool beginOperation(const QString &status);
    void startInventoryScan();
    void startAudit(const QVariantList &cards);
    void setBusy(bool busy);
    void setStatus(const QString &status);
    void setResult(const QString &result);
    void setError(const QString &error);
    QString localPath(const QUrl &fileUrl, bool forExport) const;

    QString m_storageRoot;
    QString m_databasePath;
    CardArtCache *m_cache = nullptr;
    std::function<bool()> m_operationGuard;
    std::function<QVariantList()> m_auditRequestProvider;
    std::function<QString()> m_auditLanguageProvider;
    QVariantMap m_inventory;
    QVariantMap m_packPreview;
    cardart::AuditResult m_auditResult;
    QString m_status;
    QString m_lastResult;
    QString m_lastError;
    bool m_repairNeeded = false;
    bool m_autoAuditRetryScheduled = false;
    bool m_busy = false;
};

} // namespace hexproof::client
