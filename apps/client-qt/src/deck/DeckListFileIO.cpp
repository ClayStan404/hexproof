// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckListFileIO.h"

#include <QFile>
#include <QFileInfo>
#include <QTextStream>

namespace hexproof::client {

namespace {

constexpr qint64 kMaximumDeckListBytes = 1024 * 1024;

DeckListFileData failure(const QString &error)
{
    return {{}, {}, error};
}

} // namespace

DeckListFileData loadDeckListFile(const QUrl &fileUrl)
{
    if (!fileUrl.isLocalFile() || fileUrl.toLocalFile().isEmpty())
        return failure(QStringLiteral("Choose a readable local deck list file."));

    const QString path = fileUrl.toLocalFile();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return failure(QStringLiteral("The deck list file could not be read."));
    if (file.size() > kMaximumDeckListBytes)
        return failure(QStringLiteral("The deck list file is too large."));

    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);
    const QString text = stream.readAll();
    if (stream.status() != QTextStream::Ok)
        return failure(QStringLiteral("The deck list file could not be read."));
    if (text.trimmed().isEmpty())
        return failure(QStringLiteral("The deck list file is empty."));

    return {
        .text = text,
        .suggestedName = QFileInfo(path).completeBaseName().simplified(),
        .error = {},
    };
}

} // namespace hexproof::client
