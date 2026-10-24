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
#include <functional>
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
    QString parentId, questionId;
    int questionRevision = 0;
    QJsonObject question, threadPage;
    QDateTime threadSyncedAt, threadNextAttempt;
    int apiVersion = 2;
    QJsonObject disclosure;
    QString publicationState, removalState = QStringLiteral("none"), issueUrl;
    QString caseState = QStringLiteral("open"), closurePublicationState = QStringLiteral("none");
    QString closureRequestState = QStringLiteral("none"), closureReason;
    QDateTime closedAt, closureRequestedAt;
    bool closureAuthorized = false;
    int closureAttempts = 0;
    QJsonObject context;
    QList<Attachment> attachments;
    QDateTime draftCreated, frozenAt, acceptedAt, expiresAt, nextAttempt, lastQuery;
    QByteArray secret, manifest, authorizationNonce;
    QDateTime accessExpiresAt, removalRequestedAt;
    bool removalAuthorized = false;
    int removalAttempts = 0;
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
QByteArray manifestDigest(const Record &record);
QByteArray revocationDigest(const Record &record);
bool validClosure(const QJsonObject &object);
constexpr qsizetype MaxImageBytes = 2 * 1024 * 1024;
constexpr qsizetype MaxImageInputBytes = 32 * 1024 * 1024;
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
    Q_PROPERTY(QVariantList cases READ cases NOTIFY changed)
    Q_PROPERTY(bool enabled READ enabled CONSTANT)
    Q_PROPERTY(QString configurationErrorCode READ configurationErrorCode CONSTANT)
    Q_PROPERTY(QString supportLabel READ supportLabel CONSTANT)
    Q_PROPERTY(QUrl privacyUrl READ privacyUrl CONSTANT)
    Q_PROPERTY(QString publicRepository READ publicRepository CONSTANT)
    Q_PROPERTY(QString noticeRevision READ noticeRevision CONSTANT)
    Q_PROPERTY(QString noticeText READ noticeText CONSTANT)
    Q_PROPERTY(QString providerPolicyRevision READ providerPolicyRevision CONSTANT)
    Q_PROPERTY(QString errorCode READ errorCode NOTIFY statusChanged)
    Q_PROPERTY(QString operationCode READ operationCode NOTIFY statusChanged)
    Q_PROPERTY(QString operationRecordId READ operationRecordId NOTIFY statusChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(bool saving READ saving NOTIFY statusChanged)
    Q_PROPERTY(QVariantMap thread READ thread NOTIFY changed)
    Q_PROPERTY(QVariantMap threadAttachmentPreview READ threadAttachmentPreview NOTIFY changed)
  public:
    explicit FeedbackService(const QString &storageRoot, const QJsonObject &configuration = {},
                             bool allowLoopback = false, QObject *parent = nullptr);
    ~FeedbackService() override;
    QVariantMap draft() const;
    QVariantList records() const;
    QVariantList cases() const;
    QVariantMap thread() const;
    QVariantMap threadAttachmentPreview() const
    {
        return m_threadAttachment;
    }
    bool enabled() const
    {
        return m_enabled;
    }
    QString configurationErrorCode() const
    {
        return m_configurationError;
    }
    QString supportLabel() const
    {
        return m_supportLabel;
    }
    QUrl privacyUrl() const
    {
        return m_privacyUrl;
    }
    QString publicRepository() const
    {
        return m_publicRepository;
    }
    QString noticeRevision() const
    {
        return m_noticeRevision;
    }
    QString noticeText() const
    {
        return m_noticeText;
    }
    QString providerPolicyRevision() const
    {
        return m_providerPolicyRevision;
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
               !m_threadReply.isNull() || !m_dispatchId.isEmpty();
    }
    bool saving() const
    {
        return m_loading || m_writing || !m_dirty.isEmpty() || !m_deleting.isEmpty();
    }
    Q_INVOKABLE QString createDraft(const QVariantMap &context = {});
    Q_INVOKABLE QString createReplyDraft(const QString &caseId, const QString &questionId = {},
                                         int questionRevision = 0);
    Q_INVOKABLE bool refreshThread(const QString &caseId, const QString &cursor = {});
    Q_INVOKABLE bool fetchThreadAttachment(const QString &contributionId,
                                           const QString &attachmentId);
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
    Q_INVOKABLE QVariantMap previewSubmission();
    Q_INVOKABLE bool confirmSubmission(const QString &previewDigest);
    Q_INVOKABLE bool requestRemoval(const QString &id);
    Q_INVOKABLE bool closeFeedback(const QString &id);
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
    void prepareRequest(const QString &id, bool query, bool manual = false, bool removal = false,
                        bool closure = false);
    void dispatch();
    void finishRequest(const QString &id, bool query, bool removal, bool closure);
    bool trustedQuery(const QString &endpoint) const;
    QByteArray capability(const feedback::Record &record) const;
    bool replyAllowed(const feedback::Record &record) const;
    void stopReplies(const QString &caseId);
    void startThreadRead(const QString &caseId, const QUrl &url, qsizetype limit,
                         const std::function<void(int, const QByteArray &)> &complete,
                         bool authenticate);
    void readThreadPage(const QString &caseId, const QString &cursor, QJsonObject accumulated = {});
    void setOperation(const QString &code, const QString &id);
    QString m_directory, m_selected, m_error, m_operation, m_operationRecord;
    QString m_apiBase, m_supportLabel, m_configurationError;
    QString m_threadCase, m_threadError;
    QVariantMap m_threadAttachment;
    QPointer<QNetworkReply> m_threadReply;
    QString m_publicRepository, m_noticeRevision, m_noticeText, m_providerPolicyRevision;
    std::optional<feedback::Record> m_preview;
    quint64 m_previewGeneration = 0;
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
    bool m_dispatchQuery = false, m_dispatchManual = false, m_dispatchRemoval = false;
    bool m_dispatchClosure = false;
    QTimer m_timer;
};
} // namespace hexproof::client
