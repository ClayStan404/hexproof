// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogCancellation.h"
#include "CatalogTypes.h"
#include <QBuffer>
#include <QByteArrayView>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QThread>
#include <QTimer>

#include <array>
#include <limits>
#include <utility>

#include <zlib.h>

namespace hexproof::client {
Q_DECLARE_LOGGING_CATEGORY(cardCatalogLog)
namespace catalog_internal {

inline constexpr auto kScryfallNamedUrl = "https://api.scryfall.com/cards/named";
inline constexpr auto kScryfallSearchUrl = "https://api.scryfall.com/cards/search";
inline constexpr auto kMtgchCardBaseUrl = "https://mtgch.com/api/v1/card/";
inline constexpr auto kOfficialCatalogManifestUrl =
    "https://github.com/ClayStan404/hexproof/releases/download/card-data/"
    "card-database-manifest.json";
inline constexpr auto kOfficialCatalogAssetUrl =
    "https://github.com/ClayStan404/hexproof/releases/download/card-data/"
    "hexproof-default-cards.sqlite.gz";
inline constexpr qint64 kMaximumBulkExpandedBytes = 2LL * 1024 * 1024 * 1024;
inline constexpr qint64 kMaximumLocalizedBulkExpandedBytes = 8LL * 1024 * 1024 * 1024;
inline constexpr qint64 kMaximumOfficialCatalogBytes = 512LL * 1024 * 1024;
inline constexpr qint64 kMaximumOfficialCatalogExpandedBytes = 1024LL * 1024 * 1024;
inline constexpr qint64 kMaximumBulkRecordBytes = 4LL * 1024 * 1024;
inline constexpr qint64 kMaximumChineseNameFileBytes = 96LL * 1024 * 1024;
inline constexpr int kCardResolutionVersion = 6;
inline constexpr int kScryfallPlaceholderPolicyVersion = 6;
inline constexpr int kCompatibleResolutionVersionBeforePlaceholderPolicy = 5;
inline constexpr int kNegativeCacheVersion = 2;
inline constexpr int kMaximumConcurrentImageDownloads = 6;
inline constexpr int kLargeDownloadTransferTimeoutMs = 5 * 60 * 1000;
inline constexpr int kCardImageTransferTimeoutMs = 30'000;
inline constexpr int kHostCooldownSeconds = 60;
inline constexpr int kMaximumRetryAfterSeconds = 30;
inline constexpr int kEnhancedCatalogIndexVersion = 6;
inline constexpr int kLegalityCatalogIndexVersion = 8;
inline constexpr int kCatalogIndexVersion = 10;

inline bool cancelCatalogImportIfRequested(CatalogImportStopToken stopToken,
                                           CatalogImportResult *result)
{
    if (!stopToken.stopRequested())
        return false;
    result->ok = false;
    result->error.clear();
    result->cancelled = true;
    return true;
}

inline bool isSha256(const QByteArray &value)
{
    if (value.size() != 64)
        return false;
    for (const char byte : value) {
        if (!((byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f')))
            return false;
    }
    return true;
}

inline QByteArray fileSha256(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&file))
        return {};
    return hash.result().toHex();
}

inline QString supportedImageFormatsForLog()
{
    QStringList formats;
    for (const QByteArray &format : QImageReader::supportedImageFormats())
        formats.append(QString::fromLatin1(format).toLower());
    formats.removeDuplicates();
    formats.sort();
    return formats.join(QLatin1Char(','));
}

inline bool imageFormatSupported(const QByteArray &wantedFormat)
{
    for (const QByteArray &format : QImageReader::supportedImageFormats()) {
        if (format.compare(wantedFormat, Qt::CaseInsensitive) == 0)
            return true;
    }
    return false;
}

inline QString imagePayloadKind(const QByteArray &bytes)
{
    if (bytes.size() >= 12 && bytes.left(4) == QByteArrayLiteral("RIFF") &&
        bytes.mid(8, 4) == QByteArrayLiteral("WEBP")) {
        return QStringLiteral("webp");
    }
    if (bytes.size() >= 8 && static_cast<uchar>(bytes[0]) == 0x89 &&
        bytes.mid(1, 3) == QByteArrayLiteral("PNG")) {
        return QStringLiteral("png");
    }
    if (bytes.size() >= 3 && static_cast<uchar>(bytes[0]) == 0xff &&
        static_cast<uchar>(bytes[1]) == 0xd8 && static_cast<uchar>(bytes[2]) == 0xff) {
        return QStringLiteral("jpeg");
    }

    const QByteArray prefix = bytes.left(256).trimmed().toLower();
    if (prefix.startsWith(QByteArrayLiteral("<!doctype html")) ||
        prefix.startsWith(QByteArrayLiteral("<html"))) {
        return QStringLiteral("html");
    }
    if (prefix.startsWith('{') || prefix.startsWith('['))
        return QStringLiteral("json");
    if (bytes.isEmpty())
        return QStringLiteral("empty");
    return QStringLiteral("unknown");
}

struct ImagePayloadInspection
{
    bool canRead = false;
    QByteArray format;
    QString error;
};

inline ImagePayloadInspection inspectImagePayload(const QByteArray &bytes)
{
    ImagePayloadInspection inspection;
    if (bytes.isEmpty()) {
        inspection.error = QStringLiteral("empty payload");
        return inspection;
    }
    QBuffer buffer;
    buffer.setData(bytes);
    buffer.open(QIODevice::ReadOnly);
    QImageReader reader(&buffer);
    reader.setDecideFormatFromContent(true);
    inspection.canRead = reader.canRead();
    inspection.format = reader.format();
    inspection.error = inspection.canRead ? QStringLiteral("<none>") : reader.errorString();
    return inspection;
}

inline bool writeBytesAtomically(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit();
}

inline QString printablePayloadPreview(const QByteArray &bytes)
{
    QByteArray preview = bytes.left(160);
    for (char &byte : preview) {
        const uchar value = static_cast<uchar>(byte);
        if (value < 0x20 || value > 0x7e)
            byte = '.';
    }
    return QString::fromLatin1(preview);
}

inline QString diagnosticResponseHeaders(QNetworkReply *reply)
{
    static constexpr std::array<const char *, 12> headerNames{
        "Content-Encoding", "Content-Range",   "Last-Modified", "ETag",   "Server",          "Age",
        "X-Cache",          "EO-Cache-Status", "X-DataSrc",     "X-Info", "X-CI-Request-ID", "Size",
    };
    QStringList headers;
    for (const char *name : headerNames) {
        QByteArray value = reply->rawHeader(QByteArray(name)).simplified();
        if (value.isEmpty())
            continue;
        value.truncate(160);
        headers.append(
            QStringLiteral("%1=%2").arg(QString::fromLatin1(name), QString::fromLatin1(value)));
    }
    return headers.join(QLatin1Char(';'));
}

inline QString imageUrlFromUris(const QJsonObject &imageUris)
{
    QString url = imageUris.value(QStringLiteral("normal")).toString();
    if (url.isEmpty())
        url = imageUris.value(QStringLiteral("large")).toString();
    if (url.isEmpty())
        url = imageUris.value(QStringLiteral("small")).toString();
    return url;
}

inline bool imageStatusAllowsArt(const QString &imageStatus)
{
    const QString normalized = imageStatus.trimmed().toLower();
    return normalized != QStringLiteral("missing") && normalized != QStringLiteral("placeholder");
}

inline bool imageStatusAllowsArt(const QJsonObject &card)
{
    return imageStatusAllowsArt(card.value(QStringLiteral("image_status")).toString());
}

inline QString upgradeLegacySmallImageUrl(const QString &url)
{
    QUrl parsed(url);
    if (parsed.host().compare(QStringLiteral("cards.scryfall.io"), Qt::CaseInsensitive) != 0)
        return url;
    QString path = parsed.path();
    if (!path.contains(QStringLiteral("/small/")))
        return url;
    path.replace(QStringLiteral("/small/"), QStringLiteral("/large/"));
    parsed.setPath(path);
    return parsed.toString(QUrl::FullyEncoded);
}

inline QString normalImageUrl(const QJsonObject &object)
{
    QJsonObject imageUris = object.value(QStringLiteral("image_uris")).toObject();
    if (imageUris.isEmpty()) {
        const QJsonArray faces = object.value(QStringLiteral("card_faces")).toArray();
        if (!faces.isEmpty())
            imageUris = faces.first().toObject().value(QStringLiteral("image_uris")).toObject();
    }
    return imageUrlFromUris(imageUris);
}

inline QString localizedImageUrl(const QJsonObject &object)
{
    QJsonObject imageUris = object.value(QStringLiteral("zhs_image_uris")).toObject();
    const QStringList faceKeys{
        QStringLiteral("card_faces"),
        QStringLiteral("faces"),
        QStringLiteral("other_faces"),
    };
    for (const QString &key : faceKeys) {
        if (!imageUris.isEmpty())
            break;
        const QJsonArray faces = object.value(key).toArray();
        for (const QJsonValue &face : faces) {
            imageUris = face.toObject().value(QStringLiteral("zhs_image_uris")).toObject();
            if (!imageUris.isEmpty())
                break;
        }
    }
    return imageUrlFromUris(imageUris);
}

inline bool looksLikeChinese(const QString &value)
{
    for (const QChar character : value) {
        const ushort code = character.unicode();
        if ((code >= 0x3400 && code <= 0x4dbf) || (code >= 0x4e00 && code <= 0x9fff))
            return true;
    }
    return false;
}

inline QJsonObject recordToJson(const CardRecord &record)
{
    return {
        {QStringLiteral("requestedName"), record.requestedName},
        {QStringLiteral("name"), record.name},
        {QStringLiteral("oracleId"), record.oracleId},
        {QStringLiteral("faceName"), record.faceName},
        {QStringLiteral("localizedName"), record.localizedName},
        {QStringLiteral("typeLine"), record.typeLine},
        {QStringLiteral("setCode"), record.setCode},
        {QStringLiteral("collectorNumber"), record.collectorNumber},
        {QStringLiteral("illustrationId"), record.illustrationId},
        {QStringLiteral("imageUrl"), record.imageUrl},
        {QStringLiteral("imagePath"), record.imagePath},
        {QStringLiteral("imageLanguage"), record.imageLanguage},
        {QStringLiteral("resolutionVersion"), record.resolutionVersion},
        {QStringLiteral("usesSubstituteArt"), record.usesSubstituteArt},
        {QStringLiteral("reusesLocalArt"), record.reusesLocalArt},
    };
}

inline CardRecord recordFromJson(const QJsonObject &object)
{
    CardRecord record;
    record.requestedName = object.value(QStringLiteral("requestedName")).toString();
    record.name = object.value(QStringLiteral("name")).toString();
    record.oracleId = object.value(QStringLiteral("oracleId")).toString();
    record.faceName = object.value(QStringLiteral("faceName")).toString();
    record.localizedName = object.value(QStringLiteral("localizedName")).toString();
    record.typeLine = object.value(QStringLiteral("typeLine")).toString();
    record.setCode = object.value(QStringLiteral("setCode")).toString();
    record.collectorNumber = object.value(QStringLiteral("collectorNumber")).toString();
    record.illustrationId = object.value(QStringLiteral("illustrationId")).toString();
    record.imageUrl = object.value(QStringLiteral("imageUrl")).toString();
    record.imagePath = object.value(QStringLiteral("imagePath")).toString();
    record.imageLanguage = object.value(QStringLiteral("imageLanguage")).toString();
    record.resolutionVersion = object.value(QStringLiteral("resolutionVersion")).toInt();
    record.usesSubstituteArt = object.value(QStringLiteral("usesSubstituteArt")).toBool();
    record.reusesLocalArt = object.value(QStringLiteral("reusesLocalArt")).toBool();
    return record;
}

inline QString sqlConnectionName(const QString &prefix)
{
    return prefix + QString::number(reinterpret_cast<quintptr>(QThread::currentThreadId())) +
           QLatin1Char('-') + QString::number(QDateTime::currentMSecsSinceEpoch());
}

inline QByteArray takeAvailableData(QNetworkReply *reply)
{
    if (!reply || !reply->isOpen())
        return {};
    const qint64 available = reply->bytesAvailable();
    return available > 0 ? reply->read(available) : QByteArray{};
}

inline qint64 retryAfterDelayMs(const QByteArray &header)
{
    const QByteArray value = header.trimmed();
    if (value.isEmpty())
        return -1;
    bool secondsOk = false;
    const qint64 seconds = value.toLongLong(&secondsOk);
    if (secondsOk && seconds >= 0)
        return seconds > std::numeric_limits<qint64>::max() / 1000 ? -1 : seconds * 1000;
    const QDateTime date =
        QDateTime::fromString(QString::fromLatin1(value), Qt::RFC2822Date).toUTC();
    if (!date.isValid())
        return -1;
    return qMax<qint64>(0, QDateTime::currentDateTimeUtc().msecsTo(date));
}

} // namespace catalog_internal
} // namespace hexproof::client
