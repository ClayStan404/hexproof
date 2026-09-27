// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "TranslationController.h"

#include "UiLanguages.h"

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
    const QString normalized = uiLanguages::normalize(language);
    if (normalized == m_language)
        return;

    removeTranslators();
    m_language = normalized;
    for (const uiLanguages::UiLanguage &entry : uiLanguages::languages()) {
        if (entry.code != normalized)
            continue;
        // English ships no catalogs: its source strings are the fallback for
        // every entry, so an unsupported catalog install cannot leave stale
        // translations installed for this language.
        if (!entry.uiCatalog.isEmpty()) {
            const bool dynamicLoaded = m_dynamicTranslator.load(
                QStringLiteral(":/i18n/") + entry.dynamicCatalog + QStringLiteral(".qm"));
            const bool uiLoaded = m_uiTranslator.load(QStringLiteral(":/i18n/") + entry.uiCatalog +
                                                      QStringLiteral(".qm"));
            if (!dynamicLoaded || !uiLoaded) {
                qWarning() << "Could not load embedded" << normalized << "translations";
            } else {
                QCoreApplication::installTranslator(&m_dynamicTranslator);
                QCoreApplication::installTranslator(&m_uiTranslator);
            }
        }
        break;
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
