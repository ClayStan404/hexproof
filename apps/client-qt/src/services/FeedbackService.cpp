// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "FeedbackService.h"
#include <QClipboard>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFutureWatcher>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUuid>
#include <QtConcurrentRun>
#include <algorithm>

static void feedbackResources()
{
    Q_INIT_RESOURCE(feedback_defaults);
}
namespace hexproof::client {
using namespace Qt::StringLiterals;
FeedbackService::FeedbackService(const QString &root, const QJsonObject &configuration,
                                 bool loopback, QObject *parent)
    : QObject(parent),
      m_directory(QDir(root).filePath(u"feedback"_s)),
      m_allowLoopback(loopback)
{
    m_io.setMaxThreadCount(1);
    auto config = configuration;
    if (config.isEmpty()) {
        feedbackResources();
        QFile file(u":/config/feedback.json"_s);
        if (file.open(QIODevice::ReadOnly) && file.size() <= 16384)
            config = QJsonDocument::fromJson(file.readAll()).object();
    }
    const QSet<QString> keys{u"schemaVersion"_s,    u"enabled"_s,
                             u"apiBase"_s,          u"supportLabel"_s,
                             u"privacyUrl"_s,       u"receiptOnlyApiBases"_s,
                             u"publicRepository"_s, u"noticeRevision"_s,
                             u"noticeText"_s,       u"providerPolicyRevision"_s};
    const int version = config.value(u"schemaVersion"_s).toInt();
    bool valid = version == 1 || version == 2;
    for (auto it = config.begin(); it != config.end(); ++it)
        valid = valid && keys.contains(it.key());
    m_supportLabel = config.value(u"supportLabel"_s).toString().left(120);
    m_privacyUrl = feedback::safeEndpoint(config.value(u"privacyUrl"_s).toString(), loopback);
    m_apiBase = feedback::safeEndpoint(config.value(u"apiBase"_s).toString(), loopback).toString();
    m_publicRepository = config.value(u"publicRepository"_s).toString();
    m_noticeRevision = config.value(u"noticeRevision"_s).toString();
    m_noticeText = config.value(u"noticeText"_s).toString();
    m_providerPolicyRevision = config.value(u"providerPolicyRevision"_s).toString();
    if (config.value(u"enabled"_s).toBool() &&
        (m_apiBase.isEmpty() || m_supportLabel.isEmpty() || m_privacyUrl.isEmpty()))
        valid = false;
    if (version == 2 && config.value(u"enabled"_s).toBool()) {
        static const QRegularExpression repository(
            u"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$"_s);
        static const QRegularExpression revision(u"^[A-Za-z0-9_.-]{1,80}$"_s);
        const bool safeNotice =
            std::none_of(m_noticeText.begin(), m_noticeText.end(),
                         [](QChar ch) { return ch.unicode() < 32 && ch != u'\n' && ch != u'\t'; });
        valid = valid && QUrl(m_apiBase).path() == u"/feedback/v2" &&
                repository.match(m_publicRepository).hasMatch() &&
                m_publicRepository.size() <= 200 && revision.match(m_noticeRevision).hasMatch() &&
                revision.match(m_providerPolicyRevision).hasMatch() &&
                !m_noticeText.trimmed().isEmpty() && m_noticeText.toUtf8().size() <= 8192 &&
                safeNotice;
    }
    // Legacy settings authorize receipt lookup only; they never activate public
    // submissions or replay the private outbox after the public cutover.
    m_enabled = valid && version == 2 && config.value(u"enabled"_s).toBool();
    if (!valid) {
        m_configurationError = u"configuration_invalid"_s;
        m_error = m_configurationError;
    }
    if (valid) {
        if (!m_apiBase.isEmpty())
            m_queryEndpoints.insert(m_apiBase);
        const auto old = config.value(u"receiptOnlyApiBases"_s).toArray();
        if (old.size() <= 8)
            for (const auto &value : old) {
                auto url = feedback::safeEndpoint(value.toString(), loopback);
                if (!url.isEmpty())
                    m_queryEndpoints.insert(url.toString());
            }
    }
    if (!QDir().mkpath(m_directory)) {
        m_loading = false;
        m_storageFailed = true;
        m_error = u"storage_unavailable"_s;
        return;
    }
    QFile::setPermissions(m_directory,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    m_lock = std::make_unique<QLockFile>(m_directory + u"/profile.lock"_s);
    if (!m_lock->tryLock(0)) {
        m_loading = false;
        m_storageFailed = true;
        m_error = u"storage_unavailable"_s;
        return;
    }
    connect(&m_timer, &QTimer::timeout, this, &FeedbackService::pump);
    m_timer.start(1000);
    auto *maintenance = new QTimer(this);
    connect(maintenance, &QTimer::timeout, this, [this] { prune(); });
    maintenance->start(60000);
    load();
}
FeedbackService::~FeedbackService()
{
    m_timer.stop();
    if (m_reply) {
        disconnect(m_reply, nullptr, this, nullptr);
        m_reply->abort();
    }
    if (m_threadReply) {
        disconnect(m_threadReply, nullptr, this, nullptr);
        m_threadReply->abort();
    }
    m_io.waitForDone();
    if (m_lock && m_lock->isLocked()) {
        for (const auto &id : m_dirty)
            if (m_records.contains(id))
                feedback::writePrivate(m_directory + u"/"_s + id + u".json"_s,
                                       QJsonDocument(feedback::encode(m_records[id], true))
                                           .toJson(QJsonDocument::Compact));
        for (const auto &id : m_deleting)
            QFile::remove(m_directory + u"/"_s + id + u".json"_s);
    }
}
bool FeedbackService::fail(const QString &code)
{
    m_error = code;
    emit statusChanged();
    return false;
}
void FeedbackService::setOperation(const QString &code, const QString &id)
{
    m_operation = code;
    m_operationRecord = id;
    emit statusChanged();
}
QVariantMap FeedbackService::project(const feedback::Record &r) const
{
    QVariantList attachments;
    for (const auto &a : r.attachments) {
        auto descriptor = a.descriptor.toVariantMap();
        descriptor.insert(
            u"name"_s,
            descriptor.value(u"kind"_s).toString() + u"-"_s +
                descriptor.value(u"id"_s).toString().left(8) +
                (descriptor.value(u"mediaType"_s).toString() == u"image/png"    ? u".png"_s
                 : descriptor.value(u"mediaType"_s).toString() == u"image/jpeg" ? u".jpg"_s
                                                                                : u".json"_s));
        attachments.append(descriptor);
    }
    return {{u"id"_s, r.id},
            {u"state"_s, r.state},
            {u"category"_s, r.category},
            {u"description"_s, r.description},
            {u"isPublic"_s, r.apiVersion == 2},
            {u"isReply"_s, !r.parentId.isEmpty()},
            {u"parentAvailable"_s, r.parentId.isEmpty() || m_records.contains(r.parentId)},
            {u"parentSubmissionId"_s, r.parentId},
            {u"questionId"_s, r.questionId},
            {u"questionRevision"_s, r.questionRevision},
            {u"question"_s, r.question.toVariantMap()},
            {u"questionText"_s, r.question.value(u"description"_s).toString()},
            {u"questionCode"_s, r.question.value(u"code"_s).toString()},
            {u"publicationState"_s, r.publicationState},
            {u"removalState"_s, r.removalState},
            {u"caseState"_s, r.caseState},
            {u"closureRequestState"_s, r.closureRequestState},
            {u"closurePublicationState"_s, r.closurePublicationState},
            {u"closureReason"_s, r.closureReason},
            {u"closedAt"_s, r.closedAt.toString(Qt::ISODateWithMs)},
            {u"issueUrl"_s, r.issueUrl},
            {u"context"_s, r.context.toVariantMap()},
            {u"attachments"_s, attachments},
            {u"receipt"_s, r.receipt},
            {u"acceptedAt"_s, r.acceptedAt.toString(Qt::ISODateWithMs)},
            {u"accessExpiresAt"_s, r.accessExpiresAt.toString(Qt::ISODateWithMs)},
            {u"createdAt"_s, r.draftCreated.toString(Qt::ISODateWithMs)},
            {u"reason"_s, r.reason},
            {u"editable"_s, r.state == u"draft" && r.apiVersion == 2},
            {u"uploadAuthorized"_s, r.authorized},
            {u"payloadAvailable"_s, r.payloadAvailable}};
}
QVariantMap FeedbackService::draft() const
{
    return m_records.contains(m_selected) ? project(m_records.value(m_selected)) : QVariantMap{};
}
QVariantList FeedbackService::records() const
{
    auto values = m_records.values();
    std::sort(values.begin(), values.end(),
              [](const auto &a, const auto &b) { return a.draftCreated > b.draftCreated; });
    QVariantList result;
    for (const auto &r : values)
        result.append(project(r));
    return result;
}
QVariantList FeedbackService::cases() const
{
    QVariantList result;
    for (const auto &value : records()) {
        auto row = value.toMap();
        const auto id = row.value(u"id"_s).toString();
        const auto current = m_records.constFind(id);
        const auto &record = current.value();
        const auto parent = m_records.constFind(record.parentId);
        // A retained orphan must remain accessible after local parent deletion.
        if (!record.parentId.isEmpty() && parent != m_records.cend() &&
            parent->parentId.isEmpty() && parent->apiVersion == 2)
            continue;
        int localReplies = 0;
        for (const auto &reply : m_records)
            if (reply.parentId == id && reply.state != u"accepted")
                ++localReplies;
        row.insert(u"localReplyCount"_s, localReplies);
        row.insert(u"workState"_s, record.threadPage.value(u"workState"_s).toString());
        row.insert(u"syncedAt"_s, record.threadSyncedAt.toString(Qt::ISODateWithMs));
        result.append(row);
    }
    return result;
}
feedback::Record *FeedbackService::editable()
{
    if (m_loading || !m_records.contains(m_selected)) {
        fail(u"record_unavailable"_s);
        return nullptr;
    }
    if (m_records[m_selected].state != u"draft" || m_records[m_selected].apiVersion != 2) {
        fail(u"not_editable"_s);
        return nullptr;
    }
    return &m_records[m_selected];
}
QString FeedbackService::createDraft(const QVariantMap &context)
{
    if (m_loading || !m_lock || !m_lock->isLocked()) {
        fail(u"storage_unavailable"_s);
        return {};
    }
    prune(1);
    int count = 0;
    for (const auto &r : m_records)
        if (r.state != u"received" && r.state != u"accepted")
            ++count;
    if (count >= 20 || m_records.size() >= 120 || payloadBytes() >= feedback::MaxStoreBytes) {
        fail(u"storage_full"_s);
        return {};
    }
    feedback::Record r;
    r.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    r.draftCreated = QDateTime::currentDateTimeUtc();
    QVariantMap defaults{{u"appVersion"_s, QCoreApplication::applicationVersion()},
                         {u"architecture"_s, QSysInfo::currentCpuArchitecture()},
                         {u"osFamily"_s, QSysInfo::kernelType() == u"winnt"    ? u"windows"_s
                                         : QSysInfo::kernelType() == u"darwin" ? u"macos"_s
                                         : QSysInfo::kernelType() == u"linux"  ? u"linux"_s
                                                                               : u"other"_s}};
    for (auto it = context.begin(); it != context.end(); ++it)
        defaults.insert(it.key(), it.value());
    r.context = feedback::safeContext(defaults);
    m_selected = r.id;
    m_threadCase = r.id;
    m_threadAttachment.clear();
    m_records.insert(r.id, r);
    m_error.clear();
    changedRecord(r.id);
    return r.id;
}
bool FeedbackService::selectRecord(const QString &id)
{
    if (!m_records.contains(id))
        return fail(u"record_unavailable"_s);
    m_selected = id;
    m_threadCase = m_records[id].parentId.isEmpty() ? id : m_records[id].parentId;
    m_threadError.clear();
    m_threadAttachment.clear();
    m_error.clear();
    emit changed();
    emit statusChanged();
    return true;
}
bool FeedbackService::updateDraft(const QVariantMap &fields)
{
    auto *r = editable();
    if (!r)
        return false;
    const auto description = fields.value(u"description"_s, r->description).toString();
    const auto category = fields.value(u"category"_s, r->category).toString();
    bool safeDescription = description.toUtf8().size() <= 8192;
    for (const auto ch : description) {
        if ((ch.category() == QChar::Other_Control && ch != u'\n' && ch != u'\r' && ch != u'\t') ||
            ch.category() == QChar::Other_Format || ch.category() == QChar::Separator_Line ||
            ch.category() == QChar::Separator_Paragraph)
            safeDescription = false;
    }
    if (!safeDescription)
        return fail(u"invalid_description"_s);
    if (fields.contains(u"replyEmail"_s))
        return fail(u"unsupported_content"_s);
    if (!QStringList{u"problem"_s, u"suggestion"_s, u"other"_s}.contains(category))
        return fail(u"unsupported_content"_s);
    if (!r->parentId.isEmpty() && category != r->category)
        return fail(u"unsupported_content"_s);
    if (payloadBytes() - r->description.toUtf8().size() + description.toUtf8().size() >
        feedback::MaxStoreBytes)
        return fail(u"storage_full"_s);
    r->description = description;
    r->category = category;
    if (fields.contains(u"context"_s)) {
        const auto context = feedback::safeContext(fields.value(u"context"_s).toMap());
        for (auto it = context.begin(); it != context.end(); ++it)
            r->context.insert(it.key(), it.value());
    }
    m_error.clear();
    changedRecord(r->id);
    return true;
}
QString FeedbackService::cloneDraft(const QString &id)
{
    if (!m_records.contains(id) || !m_records[id].payloadAvailable) {
        fail(u"record_unavailable"_s);
        return {};
    }
    const auto old = m_records.value(id);
    qsizetype size = old.description.toUtf8().size();
    for (const auto &a : old.attachments)
        size += a.bytes.size();
    if (payloadBytes() + size > feedback::MaxStoreBytes) {
        fail(u"storage_full"_s);
        return {};
    }
    const auto created = old.parentId.isEmpty()
                             ? createDraft(old.context.toVariantMap())
                             : createReplyDraft(old.parentId, old.questionId, old.questionRevision);
    if (created.isEmpty())
        return {};
    auto &r = m_records[created];
    r.description = old.description;
    r.category = old.category;
    r.attachments = old.attachments;
    r.context = old.context;
    changedRecord(created);
    return created;
}
bool FeedbackService::submit()
{
    if (!m_enabled)
        return fail(u"disabled"_s);
    return fail(u"preview_required"_s);
}
QVariantMap FeedbackService::previewSubmission()
{
    auto *r = editable();
    if (!r)
        return {};
    if (!replyAllowed(*r)) {
        fail(u"parent_unavailable"_s);
        return {};
    }
    if (!r->parentId.isEmpty() &&
        (m_records[r->parentId].endpoint != m_apiBase ||
         m_records[r->parentId].disclosure.value(u"repository"_s).toString() !=
             m_publicRepository)) {
        fail(u"endpoint_changed"_s);
        return {};
    }
    const auto error = !m_enabled                           ? u"disabled"_s
                       : m_attachmentBusy                   ? u"busy"_s
                       : r->description.trimmed().isEmpty() ? u"invalid_description"_s
                       : m_storageFailed                    ? u"storage_unavailable"_s
                                                            : QString{};
    if (!error.isEmpty()) {
        fail(error);
        return {};
    }
    auto frozen = *r;
    frozen.frozenAt = QDateTime::currentDateTimeUtc();
    frozen.endpoint = m_apiBase;
    frozen.disclosure = {
        {u"revision"_s, m_noticeRevision},
        {u"sha256"_s, QString::fromLatin1(feedback::digest(m_noticeText.toUtf8()))},
        {u"repository"_s, m_publicRepository},
        {u"providerPolicyRevision"_s, m_providerPolicyRevision}};
    frozen.manifest = QJsonDocument(feedback::manifest(frozen)).toJson(QJsonDocument::Compact);
    if (frozen.manifest.size() > 16384) {
        fail(u"unsupported_content"_s);
        return {};
    }
    m_preview = frozen;
    m_previewGeneration = m_generation.value(r->id);
    auto preview = project(frozen);
    preview.insert(u"digest"_s, QString::fromLatin1(feedback::manifestDigest(frozen)));
    preview.insert(u"manifest"_s, QString::fromUtf8(frozen.manifest));
    preview.insert(u"publicRepository"_s, m_publicRepository);
    preview.insert(u"noticeRevision"_s, m_noticeRevision);
    preview.insert(u"noticeText"_s, m_noticeText);
    preview.insert(u"providerPolicyRevision"_s, m_providerPolicyRevision);
    m_error.clear();
    emit statusChanged();
    return preview;
}
bool FeedbackService::confirmSubmission(const QString &previewDigest)
{
    auto *r = editable();
    if (!r)
        return false;
    if (!m_enabled)
        return fail(u"disabled"_s);
    if (m_storageFailed)
        return fail(u"storage_unavailable"_s);
    if (!replyAllowed(*r))
        return fail(u"parent_unavailable"_s);
    if (m_attachmentBusy || !m_preview || m_preview->id != r->id ||
        m_previewGeneration != m_generation.value(r->id) ||
        previewDigest.toLatin1() != feedback::manifestDigest(*m_preview) ||
        m_preview->frozenAt.addSecs(600) < QDateTime::currentDateTimeUtc())
        return fail(u"preview_changed"_s);
    *r = *m_preview;
    m_preview.reset();
    r->authorized = true;
    r->state = u"queued"_s;
    r->reason.clear();
    if (r->parentId.isEmpty()) {
        r->secret.resize(32);
        QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(r->secret.data()), 8);
    } else {
        // This local identity binds revocation to one explicit confirmation.
        // It is not a receiver capability and never leaves private storage.
        r->authorizationNonce.resize(32);
        QRandomGenerator::system()->fillRange(
            reinterpret_cast<quint32 *>(r->authorizationNonce.data()), 8);
    }
    m_error.clear();
    changedRecord(r->id);
    return true;
}
bool FeedbackService::closeFeedback(const QString &id)
{
    if (!m_records.contains(id))
        return fail(u"record_unavailable"_s);
    auto &r = m_records[id];
    if (r.apiVersion != 2 || !r.parentId.isEmpty() || r.state != u"accepted" ||
        r.secret.size() != 32 || r.removalState != u"none" || r.removalAuthorized)
        return fail(u"record_unavailable"_s);
    if (r.caseState == u"closed" || r.closureAuthorized)
        return true;
    if (!trustedQuery(r.endpoint))
        return fail(u"endpoint_untrusted"_s);
    if (m_storageFailed || m_dirty.contains(id))
        return fail(u"storage_unavailable"_s);
    const auto now = QDateTime::currentDateTimeUtc();
    const QJsonObject journal{{u"secretDigest"_s, QString::fromLatin1(feedback::digest(r.secret))},
                              {u"requestedAt"_s, now.toString(Qt::ISODateWithMs)}};
    if (!feedback::writePrivate(m_directory + u"/"_s + id + u".closure"_s,
                                QJsonDocument(journal).toJson(QJsonDocument::Compact)))
        return fail(u"storage_unavailable"_s);
    r.authorized = false;
    r.closureAuthorized = true;
    r.closureRequestedAt = now;
    r.closureAttempts = 0;
    r.closureRequestState = u"requested"_s;
    r.nextAttempt = now;
    r.reason.clear();
    stopReplies(id);
    m_error.clear();
    changedRecord(id);
    return true;
}
bool FeedbackService::requestRemoval(const QString &id)
{
    if (!m_records.contains(id))
        return fail(u"record_unavailable"_s);
    auto &r = m_records[id];
    if (r.apiVersion != 2 || !r.parentId.isEmpty() || !r.acceptedAt.isValid() ||
        r.secret.size() != 32)
        return fail(u"record_unavailable"_s);
    if (!trustedQuery(r.endpoint))
        return fail(u"endpoint_untrusted"_s);
    if (m_storageFailed || m_dirty.contains(id))
        return fail(u"storage_unavailable"_s);
    if (r.removalState == u"removed" || r.removalAuthorized)
        return true;
    const auto now = QDateTime::currentDateTimeUtc();
    // A small independent journal makes the user's removal request durable
    // before acknowledgement, even if the next full-record write is interrupted.
    const QJsonObject journal{{u"secretDigest"_s, QString::fromLatin1(feedback::digest(r.secret))},
                              {u"requestedAt"_s, now.toString(Qt::ISODateWithMs)}};
    if (!feedback::writePrivate(m_directory + u"/"_s + id + u".removal"_s,
                                QJsonDocument(journal).toJson(QJsonDocument::Compact)))
        return fail(u"storage_unavailable"_s);
    r.authorized = false;
    r.removalAuthorized = true;
    r.closureAuthorized = false;
    r.closureRequestState = u"none"_s;
    r.removalRequestedAt = now;
    r.removalAttempts = 0;
    r.removalState = u"requested"_s;
    r.nextAttempt = now;
    r.reason.clear();
    stopReplies(id);
    m_error.clear();
    changedRecord(id);
    return true;
}
bool FeedbackService::stop(const QString &id)
{
    if (!m_records.contains(id))
        return fail(u"record_unavailable"_s);
    auto &r = m_records[id];
    // This tiny journal is committed before acknowledging revocation. A previous
    // large background record write may still contain authorization; recovery
    // always checks the journal before considering any upload.
    if (!feedback::writePrivate(m_directory + u"/"_s + id + u".revoked"_s,
                                feedback::revocationDigest(r)))
        return fail(u"storage_unavailable"_s);
    r.authorized = false;
    if (r.state != u"received" && r.state != u"accepted" && r.state != u"draft") {
        r.state = r.dispatched ? u"unconfirmed"_s : u"draft"_s;
        r.reason = u"stopped"_s;
        if (!r.dispatched) {
            r.manifest.clear();
            r.secret.clear();
            r.authorizationNonce.clear();
            r.endpoint.clear();
            r.frozenAt = {};
        }
    }
    if (m_dispatchId == id) {
        m_dispatchId.clear();
        if (m_reply)
            m_reply->abort();
    }
    changedRecord(id);
    return true;
}
bool FeedbackService::deleteRecord(const QString &id)
{
    if (!m_records.contains(id))
        return fail(u"record_unavailable"_s);
    if (!feedback::writePrivate(m_directory + u"/"_s + id + u".deleted"_s, "deleted"))
        return fail(u"storage_unavailable"_s);
    stopReplies(id);
    if (m_threadCase == id && m_threadReply)
        m_threadReply->abort();
    // The deletion journal also revokes upload authority, including after an
    // abrupt exit before asynchronous file deletion has completed.
    m_records[id].authorized = false;
    if (m_dispatchId == id) {
        m_dispatchId.clear();
        if (m_reply)
            m_reply->abort();
    }
    m_records.remove(id);
    m_dirty.remove(id);
    m_deleting.insert(id);
    if (m_selected == id)
        m_selected.clear();
    emit changed();
    emit statusChanged();
    writeNext();
    return true;
}
QUrl FeedbackService::suggestedExport(const QString &id) const
{
    if (!m_records.contains(id))
        return {};
    return QUrl::fromLocalFile(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) +
                               u"/hexproof-feedback-"_s + id + u".json"_s);
}
bool FeedbackService::exportRecord(const QString &id, const QUrl &url)
{
    if (!m_records.contains(id) || !m_records[id].payloadAvailable)
        return fail(u"record_unavailable"_s);
    if (!url.isLocalFile() || m_exportBusy)
        return fail(u"export_failed"_s);
    m_exportBusy = true;
    setOperation({}, id);
    const auto record = m_records.value(id);
    auto *watcher = new QFutureWatcher<bool>(this);
    connect(watcher, &QFutureWatcher<bool>::finished, this, [this, watcher, id] {
        const bool ok = watcher->result();
        watcher->deleteLater();
        m_exportBusy = false;
        setOperation(ok ? u"exported"_s : u"export_failed"_s, id);
    });
    watcher->setFuture(QtConcurrent::run(&m_io, [record, url] {
        return feedback::writePrivate(
            url.toLocalFile(),
            QJsonDocument(feedback::encode(record, false)).toJson(QJsonDocument::Indented), false);
    }));
    return true;
}
bool FeedbackService::copyReceipt(const QString &id)
{
    const auto receipt = m_records.value(id).receipt;
    if (receipt.isEmpty() || !qobject_cast<QGuiApplication *>(QCoreApplication::instance()) ||
        !QGuiApplication::clipboard()) {
        setOperation(u"copy_failed"_s, id);
        return false;
    }
    QGuiApplication::clipboard()->setText(receipt);
    setOperation(u"copied"_s, id);
    return true;
}
} // namespace hexproof::client
