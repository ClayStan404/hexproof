// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "KeywordReference.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

static void initializeKeywordResource()
{
    Q_INIT_RESOURCE(keyword_reference);
}

namespace hexproof::client {

KeywordReference::KeywordReference(QObject *parent)
    : QObject(parent)
{
    initializeKeywordResource();
    QFile file(QStringLiteral(":/resources/keyword-reference.json"));
    if (file.open(QIODevice::ReadOnly))
        m_document = QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
}

} // namespace hexproof::client
