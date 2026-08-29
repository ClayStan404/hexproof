// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardImageProvider.h"

#include <QFileInfo>
#include <QImageReader>
#include <QMutexLocker>

#include <algorithm>
#include <limits>

namespace hexproof::client {

namespace {

constexpr int kTableImageWidth = 320;
constexpr int kTableImageHeight = 448;
constexpr int kImageCacheKiB = 128 * 1024;

} // namespace

CardImageProvider::CardImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image),
      m_images(kImageCacheKiB)
{
}

QString CardImageProvider::sourceForPath(const QString &path)
{
    if (path.isEmpty() || !QFileInfo::exists(path))
        return {};

    const QString id = idForPath(path);
    return QStringLiteral("image://card-table/%1").arg(id);
}

QImage CardImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    Q_UNUSED(requestedSize);

    QString path;
    {
        const QMutexLocker locker(&m_mutex);
        if (const QImage *cached = m_images.object(id)) {
            if (size)
                *size = cached->size();
            return *cached;
        }
    }
    path = QString::fromUtf8(QByteArray::fromBase64(id.toLatin1(), QByteArray::Base64UrlEncoding));

    const QImage image = loadTableImage(path);
    if (!image.isNull())
        cacheImage(id, image);
    if (size)
        *size = image.size();
    return image;
}

QSize CardImageProvider::tableImageSize()
{
    return {kTableImageWidth, kTableImageHeight};
}

QString CardImageProvider::idForPath(const QString &path)
{
    return QString::fromLatin1(
        path.toUtf8().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

QImage CardImageProvider::loadTableImage(const QString &path)
{
    if (path.isEmpty())
        return {};

    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QSize originalSize = reader.size();
    if (originalSize.isValid())
        reader.setScaledSize(originalSize.scaled(tableImageSize(), Qt::KeepAspectRatio));

    QImage image = reader.read();
    if (image.isNull())
        return {};
    if (image.width() > kTableImageWidth || image.height() > kTableImageHeight) {
        image = image.scaled(tableImageSize(), Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    return image;
}

void CardImageProvider::cacheImage(const QString &id, const QImage &image)
{
    const qsizetype bytes = image.sizeInBytes();
    const int cost = static_cast<int>(std::min<qsizetype>(
        std::max<qsizetype>(1, (bytes + 1023) / 1024), std::numeric_limits<int>::max()));
    const QMutexLocker locker(&m_mutex);
    m_images.insert(id, new QImage(image), cost);
}

} // namespace hexproof::client
