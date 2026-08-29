// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "TranslationController.h"

#include <QCoreApplication>
#include <QDebug>
#include <QQmlEngine>

namespace hexproof::client {

TranslationController::TranslationController(QQmlEngine *engine, QObject *parent)
    : QObject(parent),
      m_engine(engine),
      m_uiTranslator(this),
      m_dynamicTranslator(this)
{
}

TranslationController::~TranslationController()
{
    removeTranslators();
}

void TranslationController::setLanguage(const QString &language)
{
    const QString normalized = language.compare(QStringLiteral("zh"), Qt::CaseInsensitive) == 0
                                   ? QStringLiteral("zh")
                                   : QStringLiteral("en");
    if (normalized == m_language)
        return;

    removeTranslators();
    m_language = normalized;
    if (m_language == QStringLiteral("zh")) {
        const bool dynamicLoaded =
            m_dynamicTranslator.load(QStringLiteral(":/i18n/hexproof_dynamic_zh_CN.qm"));
        const bool uiLoaded = m_uiTranslator.load(QStringLiteral(":/i18n/hexproof_zh_CN.qm"));
        if (!dynamicLoaded || !uiLoaded) {
            qWarning() << "Could not load embedded Simplified Chinese translations";
        } else {
            QCoreApplication::installTranslator(&m_dynamicTranslator);
            QCoreApplication::installTranslator(&m_uiTranslator);
        }
    }
    if (m_engine)
        m_engine->retranslate();
}

void TranslationController::removeTranslators()
{
    QCoreApplication::removeTranslator(&m_uiTranslator);
    QCoreApplication::removeTranslator(&m_dynamicTranslator);
}

} // namespace hexproof::client
