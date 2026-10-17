// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#pragma once

#include <QDateTime>
#include <QHash>
#include <QImage>
#include <QJsonObject>
#include <QLockFile>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSet>
#include <QThreadPool>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <memory>
#include <optional>

namespace hexproof::client {
namespace feedback {
struct Attachment
{
    QJsonObject descriptor;
    QByteArray bytes;
};
struct Record
{
    QString id, state = QStringLiteral("draft"), category = QStringLiteral("problem");
    QString description, email, endpoint, reason, receipt;
    QJsonObject context;
    QList<Attachment> attachments;
    QDateTime draftCreated, frozenAt, acceptedAt, expiresAt, nextAttempt, lastQuery;
    QByteArray secret, manifest;
    bool authorized = false, dispatched = false, payloadAvailable = true;
    int attempts = 0, queries = 0;
};
QJsonObject manifest(const Record &record);
QJsonObject encode(const Record &record, bool privateFields);
std::optional<Record> decode(const QJsonObject &object);
QJsonObject safeContext(const QVariantMap &context);
QUrl safeEndpoint(const QString &value, bool allowLoopback);
bool writePrivate(const QString &path, const QByteArray &data, bool secureDirectory = true);
QByteArray digest(const QByteArray &bytes);
constexpr qsizetype MaxImageBytes = 2 * 1024 * 1024;
constexpr qsizetype MaxStoreBytes = 64 * 1024 * 1024;
} // namespace feedback

// Owns feedback independently of game/account networking. Secrets never enter
// QML projections. One I/O lane and GUI-thread transitions serialize persistence
// and dispatch; every network request requires a durable current generation.
class FeedbackService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap draft READ draft NOTIFY changed)
    Q_PROPERTY(QVariantList records READ records NOTIFY changed)
    Q_PROPERTY(bool enabled READ enabled CONSTANT)
    Q_PROPERTY(QString supportLabel READ supportLabel CONSTANT)
    Q_PROPERTY(QUrl privacyUrl READ privacyUrl CONSTANT)
    Q_PROPERTY(QString errorCode READ errorCode NOTIFY statusChanged)
    Q_PROPERTY(QString operationCode READ operationCode NOTIFY statusChanged)
    Q_PROPERTY(QString operationRecordId READ operationRecordId NOTIFY statusChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(bool saving READ saving NOTIFY statusChanged)
  public:
    explicit FeedbackService(const QString &storageRoot, const QJsonObject &configuration = {},
                             bool allowLoopback = false, QObject *parent = nullptr);
    ~FeedbackService() override;
    QVariantMap draft() const;
    QVariantList records() const;
    bool enabled() const
    {
        return m_enabled;
    }
    QString supportLabel() const
    {
        return m_supportLabel;
    }
    QUrl privacyUrl() const
    {
        return m_privacyUrl;
    }
    QString errorCode() const
    {
        return m_error;
    }
    QString operationCode() const
    {
        return m_operation;
    }
    QString operationRecordId() const
    {
        return m_operationRecord;
    }
    bool busy() const
    {
        return m_loading || m_attachmentBusy || m_exportBusy || !m_reply.isNull() ||
               !m_dispatchId.isEmpty();
    }
    bool saving() const
    {
        return m_loading || m_writing || !m_dirty.isEmpty() || !m_deleting.isEmpty();
    }
    Q_INVOKABLE QString createDraft(const QVariantMap &context = {});
    Q_INVOKABLE bool selectRecord(const QString &id);
    Q_INVOKABLE bool updateDraft(const QVariantMap &fields);
    Q_INVOKABLE QString cloneDraft(const QString &id);
    Q_INVOKABLE bool attachImage(const QUrl &source);
    Q_INVOKABLE bool pasteImage();
    Q_INVOKABLE bool attachCrashReport(const QVariantMap &report);
    Q_INVOKABLE bool attachHostingDiagnostics(const QVariantMap &report);
    Q_INVOKABLE bool removeAttachment(const QString &id);
    Q_INVOKABLE QString attachmentPreview(const QString &id) const;
    Q_INVOKABLE bool submit();
    Q_INVOKABLE bool stop(const QString &id);
    Q_INVOKABLE bool queryReceipt(const QString &id);
    Q_INVOKABLE bool deleteRecord(const QString &id);
    Q_INVOKABLE bool exportRecord(const QString &id, const QUrl &destination);
    Q_INVOKABLE bool copyReceipt(const QString &id);
    Q_INVOKABLE QUrl suggestedExport(const QString &id) const;
    Q_INVOKABLE void retryStorage();
  signals:
    void changed();
    void statusChanged();

  private:
    friend class FeedbackServiceTest;
    bool fail(const QString &code);
    feedback::Record *editable();
    QVariantMap project(const feedback::Record &record) const;
    void changedRecord(const QString &id);
    void load();
    void writeNext();
    void prune(qsizetype additionalBytes = 0);
    qsizetype payloadBytes() const;
    bool addAttachment(feedback::Attachment attachment, const QString &recordId = {});
    bool normalizeImage(const QUrl &source, const QImage &image);
    void pump();
    void prepareRequest(const QString &id, bool query, bool manual = false);
    void dispatch();
    void finishRequest(const QString &id, bool query);
    bool trustedQuery(const QString &endpoint) const;
    void setOperation(const QString &code, const QString &id);
    QString m_directory, m_selected, m_error, m_operation, m_operationRecord;
    QString m_apiBase, m_supportLabel;
    QUrl m_privacyUrl;
    QSet<QString> m_queryEndpoints;
    bool m_enabled = false, m_allowLoopback = false, m_loading = true;
    bool m_writing = false, m_storageFailed = false, m_attachmentBusy = false, m_exportBusy = false;
    std::unique_ptr<QLockFile> m_lock;
    QHash<QString, feedback::Record> m_records;
    QHash<QString, quint64> m_generation, m_persisted;
    QSet<QString> m_dirty, m_deleting;
    QThreadPool m_io;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QByteArray m_response;
    bool m_responseOversized = false;
    QString m_dispatchId;
    bool m_dispatchQuery = false, m_dispatchManual = false;
    QTimer m_timer;
};
} // namespace hexproof::client
