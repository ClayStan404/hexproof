// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QCache>
#include <QImage>
#include <QMutex>
#include <QQuickImageProvider>
#include <QSize>
#include <QString>

namespace hexproof::client {

class CardImageProvider final : public QQuickImageProvider
{
  public:
    CardImageProvider();

    QString sourceForPath(const QString &path);

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

    static QSize tableImageSize();

  private:
    static QString idForPath(const QString &path);
    static QImage loadTableImage(const QString &path);
    void cacheImage(const QString &id, const QImage &image);

    QMutex m_mutex;
    QCache<QString, QImage> m_images;
};

} // namespace hexproof::client
