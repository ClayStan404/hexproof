// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "FeedbackService.h"
#include "ForgeCrashReportService.h"
#include "ForgeHostDiagnostics.h"
#include <QBuffer>
#include <QClipboard>
#include <QFile>
#include <QFutureWatcher>
#include <QGuiApplication>
#include <QImageReader>
#include <QImageWriter>
#include <QJsonDocument>
#include <QPainter>
#include <QUuid>
#include <QtConcurrentRun>
#include <cmath>

namespace hexproof::client {
using namespace Qt::StringLiterals;
namespace {
struct NormalizedImage
{
    QByteArray bytes;
    QString error;
};
bool safeSize(const QSize &s)
{
    return s.width() > 0 && s.height() > 0 && s.width() <= 8192 && s.height() <= 8192 &&
           qint64(s.width()) * s.height() <= 16'000'000;
}
bool animatedPng(const QByteArray &data)
{
    if (!data.startsWith("\x89PNG\r\n\x1a\n"))
        return false;
    qsizetype at = 8;
    while (at + 12 <= data.size()) {
        quint32 length = 0;
        for (int i = 0; i < 4; ++i)
            length = (length << 8) | quint8(data[at + i]);
        if (data.mid(at + 4, 4) == "acTL")
            return true;
        if (length > quint64(data.size() - at - 12))
            break;
        at += length + 12;
    }
    return false;
}
feedback::Attachment attachment(const QString &kind, const QString &media, const QByteArray &bytes)
{
    auto id = QUuid::createUuid().toString(QUuid::Id128);
    return {{{u"id"_s, id},
             {u"kind"_s, kind},
             {u"mediaType"_s, media},
             {u"byteLength"_s, bytes.size()},
             {u"sha256"_s, QString::fromLatin1(feedback::digest(bytes))}},
            bytes};
}
} // namespace
bool FeedbackService::addAttachment(feedback::Attachment a, const QString &recordId)
{
    const auto id = recordId.isEmpty() ? m_selected : recordId;
    if (!m_records.contains(id) || m_records[id].state != u"draft")
        return fail(u"not_editable"_s);
    auto *r = &m_records[id];
    const auto kind = a.descriptor.value(u"kind"_s).toString();
    int count = 0;
    for (const auto &old : r->attachments)
        if (old.descriptor.value(u"kind"_s) == kind)
            ++count;
    if (count >= (kind == u"screenshot" ? 2 : 1))
        return fail(u"attachment_limit"_s);
    prune(a.bytes.size());
    r = &m_records[id];
    if (payloadBytes() + a.bytes.size() > feedback::MaxStoreBytes)
        return fail(u"storage_full"_s);
    r->attachments.append(a);
    m_error.clear();
    changedRecord(r->id);
    return true;
}
bool FeedbackService::attachCrashReport(const QVariantMap &report)
{
    if (!editable())
        return false;
    const auto clean = normalizedForgeCrashReport(QJsonObject::fromVariantMap(report));
    if (clean.isEmpty())
        return fail(u"invalid_attachment"_s);
    const auto bytes = QJsonDocument(clean).toJson(QJsonDocument::Compact);
    if (bytes.size() > 65536)
        return fail(u"attachment_limit"_s);
    auto a = attachment(u"forge_crash"_s, u"application/json"_s, bytes);
    a.descriptor.insert(u"reportId"_s, clean.value(u"reportId"_s));
    a.descriptor.insert(u"revision"_s, clean.value(u"revision"_s));
    a.descriptor.insert(u"capturedAt"_s, clean.value(u"occurredAt"_s));
    return addAttachment(a);
}
bool FeedbackService::attachHostingDiagnostics(const QVariantMap &report)
{
    if (!editable())
        return false;
    const auto clean = ForgeHostDiagnostics::sanitizedReport(QJsonObject::fromVariantMap(report));
    if (clean.isEmpty())
        return fail(u"invalid_attachment"_s);
    const auto bytes = QJsonDocument(clean).toJson(QJsonDocument::Compact);
    if (bytes.size() > 524288)
        return fail(u"attachment_limit"_s);
    auto a = attachment(u"hosting_diagnostics"_s, u"application/json"_s, bytes);
    a.descriptor.insert(u"capturedAt"_s, clean.value(u"exportedAt"_s));
    return addAttachment(a);
}
bool FeedbackService::attachImage(const QUrl &source)
{
    if (!source.isLocalFile())
        return fail(u"invalid_attachment"_s);
    return normalizeImage(source, {});
}
bool FeedbackService::pasteImage()
{
    if (!qobject_cast<QGuiApplication *>(QCoreApplication::instance()) ||
        !QGuiApplication::clipboard())
        return fail(u"invalid_attachment"_s);
    return normalizeImage({}, QGuiApplication::clipboard()->image());
}
bool FeedbackService::normalizeImage(const QUrl &source, const QImage &input)
{
    if (!editable())
        return false;
    if (m_attachmentBusy)
        return fail(u"busy"_s);
    if (source.isEmpty() && !safeSize(input.size()))
        return fail(input.isNull() ? u"invalid_attachment"_s : u"image_too_large"_s);
    m_attachmentBusy = true;
    emit statusChanged();
    const auto id = m_selected;
    auto *watcher = new QFutureWatcher<NormalizedImage>(this);
    connect(watcher, &QFutureWatcher<NormalizedImage>::finished, this, [this, watcher, id] {
        const auto result = watcher->result();
        watcher->deleteLater();
        m_attachmentBusy = false;
        if (!result.error.isEmpty())
            fail(result.error);
        else if (m_records.contains(id) && m_records[id].state == u"draft") {
            addAttachment(attachment(u"screenshot"_s, u"image/png"_s, result.bytes), id);
        }
        emit statusChanged();
    });
    watcher->setFuture(QtConcurrent::run(&m_io, [source, input]() -> NormalizedImage {
        QImage image = input;
        if (!source.isEmpty()) {
            QFile file(source.toLocalFile());
            if (!file.open(QIODevice::ReadOnly))
                return {{}, u"invalid_attachment"_s};
            if (file.size() > feedback::MaxImageInputBytes)
                return {{}, u"image_too_large"_s};
            const auto data = file.read(feedback::MaxImageInputBytes + 1);
            if (data.size() > feedback::MaxImageInputBytes)
                return {{}, u"image_too_large"_s};
            if (animatedPng(data))
                return {{}, u"invalid_attachment"_s};
            QBuffer buffer;
            buffer.setData(data);
            buffer.open(QIODevice::ReadOnly);
            QImageReader reader(&buffer);
            if (!QList<QByteArray>{"png", "jpeg", "jpg"}.contains(reader.format()) ||
                reader.size().isEmpty() || reader.imageCount() > 1)
                return {{}, u"invalid_attachment"_s};
            if (!safeSize(reader.size()))
                return {{}, u"image_too_large"_s};
            reader.setAutoTransform(true);
            image = reader.read();
        }
        if (image.isNull())
            return {{}, u"invalid_attachment"_s};
        if (!safeSize(image.size()))
            return {{}, u"image_too_large"_s};
        QImage pixels(image.size(), QImage::Format_ARGB32);
        if (pixels.isNull())
            return {{}, u"invalid_attachment"_s};
        pixels.fill(Qt::transparent);
        {
            QPainter painter(&pixels);
            painter.drawImage(0, 0, image);
        }
        image = {};
        const auto original = pixels;
        // Keep full resolution when possible. The source-file limit is separate
        // from the receiver's PNG limit, including for JPEG and clipboard input.
        for (int attempt = 0; attempt < 16; ++attempt) {
            QByteArray result;
            QBuffer output(&result);
            output.open(QIODevice::WriteOnly);
            QImageWriter writer(&output, "png");
            // Maximum PNG compression is disproportionately slow on screenshots.
            writer.setCompression(50);
            if (!writer.write(pixels))
                return {{}, u"invalid_attachment"_s};
            if (result.size() <= feedback::MaxImageBytes)
                return {result, {}};
            const double scale = qMin(
                0.85, 0.95 * std::sqrt(double(feedback::MaxImageBytes) / double(result.size())));
            const QSize next(qMax(1, int(pixels.width() * scale)),
                             qMax(1, int(pixels.height() * scale)));
            pixels = original.scaled(next, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            if (pixels.isNull())
                return {{}, u"invalid_attachment"_s};
        }
        return {{}, u"image_too_large"_s};
    }));
    return true;
}
bool FeedbackService::removeAttachment(const QString &id)
{
    auto *r = editable();
    if (!r)
        return false;
    for (qsizetype i = 0; i < r->attachments.size(); ++i)
        if (r->attachments[i].descriptor.value(u"id"_s) == id) {
            r->attachments.removeAt(i);
            changedRecord(r->id);
            return true;
        }
    return fail(u"invalid_attachment"_s);
}
QString FeedbackService::attachmentPreview(const QString &id) const
{
    for (const auto &a : m_records.value(m_selected).attachments)
        if (a.descriptor.value(u"id"_s) == id) {
            const auto media = a.descriptor.value(u"mediaType"_s).toString();
            if (media == u"image/png" || media == u"image/jpeg")
                return u"data:"_s + media + u";base64,"_s + QString::fromLatin1(a.bytes.toBase64());
            return QString::fromUtf8(
                QJsonDocument::fromJson(a.bytes).toJson(QJsonDocument::Indented));
        }
    return {};
}
} // namespace hexproof::client
