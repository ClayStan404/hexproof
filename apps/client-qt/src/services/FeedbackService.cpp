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
    const QSet<QString> keys{u"schemaVersion"_s, u"enabled"_s,    u"apiBase"_s,
                             u"supportLabel"_s,  u"privacyUrl"_s, u"receiptOnlyApiBases"_s};
    bool valid = config.value(u"schemaVersion"_s).toInt() == 1;
    for (auto it = config.begin(); it != config.end(); ++it)
        valid = valid && keys.contains(it.key());
    m_supportLabel = config.value(u"supportLabel"_s).toString().left(120);
    m_privacyUrl = feedback::safeEndpoint(config.value(u"privacyUrl"_s).toString(), loopback);
    m_apiBase = feedback::safeEndpoint(config.value(u"apiBase"_s).toString(), loopback).toString();
    if (config.value(u"enabled"_s).toBool() &&
        (m_apiBase.isEmpty() || m_supportLabel.isEmpty() || m_privacyUrl.isEmpty()))
        valid = false;
    m_enabled = valid && config.value(u"enabled"_s).toBool();
    if (!valid)
        m_error = u"configuration_invalid"_s;
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
            {u"replyEmail"_s, r.email},
            {u"context"_s, r.context.toVariantMap()},
            {u"attachments"_s, attachments},
            {u"receipt"_s, r.receipt},
            {u"acceptedAt"_s, r.acceptedAt.toString(Qt::ISODateWithMs)},
            {u"createdAt"_s, r.draftCreated.toString(Qt::ISODateWithMs)},
            {u"reason"_s, r.reason},
            {u"editable"_s, r.state == u"draft"},
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
feedback::Record *FeedbackService::editable()
{
    if (m_loading || !m_records.contains(m_selected)) {
        fail(u"record_unavailable"_s);
        return nullptr;
    }
    if (m_records[m_selected].state != u"draft") {
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
        if (r.state != u"received")
            ++count;
    if (count >= 20 || payloadBytes() >= feedback::MaxStoreBytes) {
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
    const auto email = fields.value(u"replyEmail"_s, r->email).toString();
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
    if (email.toUtf8().size() > 254)
        return fail(u"invalid_email"_s);
    if (!QStringList{u"problem"_s, u"suggestion"_s, u"other"_s}.contains(category))
        return fail(u"unsupported_content"_s);
    if (payloadBytes() - r->description.toUtf8().size() + description.toUtf8().size() >
        feedback::MaxStoreBytes)
        return fail(u"storage_full"_s);
    r->description = description;
    r->email = email;
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
    const auto created = createDraft(old.context.toVariantMap());
    if (created.isEmpty())
        return {};
    auto &r = m_records[created];
    r.description = old.description;
    r.email = old.email;
    r.category = old.category;
    r.attachments = old.attachments;
    r.context = old.context;
    changedRecord(created);
    return created;
}
bool FeedbackService::submit()
{
    auto *r = editable();
    if (!r)
        return false;
    if (!m_enabled)
        return fail(u"disabled"_s);
    if (m_attachmentBusy)
        return fail(u"busy"_s);
    if (r->description.trimmed().isEmpty())
        return fail(u"invalid_description"_s);
    static const QRegularExpression email(
        u"^[^\\s@<>\\r\\n]+@[^\\s@<>\\r\\n]+\\.[^\\s@<>\\r\\n]+$"_s);
    if (!r->email.isEmpty() && !email.match(r->email).hasMatch())
        return fail(u"invalid_email"_s);
    if (m_storageFailed)
        return fail(u"storage_unavailable"_s);
    r->frozenAt = QDateTime::currentDateTimeUtc();
    r->endpoint = m_apiBase;
    r->authorized = true;
    r->state = u"queued"_s;
    r->reason.clear();
    r->secret.resize(32);
    QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(r->secret.data()), 8);
    r->manifest = QJsonDocument(feedback::manifest(*r)).toJson(QJsonDocument::Compact);
    if (r->manifest.size() > 16384) {
        r->authorized = false;
        r->state = u"draft"_s;
        r->manifest.clear();
        r->secret.clear();
        r->endpoint.clear();
        r->frozenAt = {};
        return fail(u"unsupported_content"_s);
    }
    m_error.clear();
    changedRecord(r->id);
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
                                feedback::digest(r.secret)))
        return fail(u"storage_unavailable"_s);
    r.authorized = false;
    if (r.state != u"received" && r.state != u"draft") {
        r.state = r.dispatched ? u"unconfirmed"_s : u"draft"_s;
        r.reason = u"stopped"_s;
        if (!r.dispatched) {
            r.manifest.clear();
            r.secret.clear();
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
