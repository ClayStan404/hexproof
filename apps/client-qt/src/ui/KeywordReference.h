// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace hexproof::client {

// Bundled public reference only: no session, card catalog or network access.
class KeywordReference : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap document READ document CONSTANT)

  public:
    explicit KeywordReference(QObject *parent = nullptr);
    QVariantMap document() const
    {
        return m_document;
    }

  private:
    QVariantMap m_document;
};

} // namespace hexproof::client
