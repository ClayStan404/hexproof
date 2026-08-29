// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QTranslator>

class QQmlEngine;

namespace hexproof::client {

class TranslationController : public QObject
{
    Q_OBJECT

  public:
    explicit TranslationController(QQmlEngine *engine, QObject *parent = nullptr);
    ~TranslationController() override;

    Q_INVOKABLE void setLanguage(const QString &language);

  private:
    void removeTranslators();

    QQmlEngine *m_engine = nullptr;
    QTranslator m_uiTranslator;
    QTranslator m_dynamicTranslator;
    QString m_language;
};

} // namespace hexproof::client
