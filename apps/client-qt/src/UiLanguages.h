// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QList>
#include <QString>
#include <QVariantList>

namespace hexproof::client::uiLanguages {

// The single authoritative UI-language registry. The stored preference code,
// the language's own display name, and the embedded QM catalog base names are
// defined together here so the settings screen, preference persistence, and
// TranslationController cannot drift apart. English is the source language and
// intentionally carries no catalogs; source strings are its fallback.
struct UiLanguage
{
    QString code;
    QString nativeName;
    QString uiCatalog;      // QM base name under :/i18n, empty for source English
    QString dynamicCatalog; // QM base name under :/i18n, empty for source English
};

inline QList<UiLanguage> languages()
{
    return {
        {QStringLiteral("en"), QStringLiteral("English"), QString(), QString()},
        {QStringLiteral("zh"), QStringLiteral("简体中文"), QStringLiteral("hexproof_zh_CN"),
         QStringLiteral("hexproof_dynamic_zh_CN")},
        {QStringLiteral("ja"), QStringLiteral("日本語"), QStringLiteral("hexproof_ja"),
         QStringLiteral("hexproof_dynamic_ja")},
        {QStringLiteral("fr"), QStringLiteral("Français"), QStringLiteral("hexproof_fr"),
         QStringLiteral("hexproof_dynamic_fr")},
        {QStringLiteral("de"), QStringLiteral("Deutsch"), QStringLiteral("hexproof_de"),
         QStringLiteral("hexproof_dynamic_de")},
        {QStringLiteral("es"), QStringLiteral("Español"), QStringLiteral("hexproof_es"),
         QStringLiteral("hexproof_dynamic_es")},
        {QStringLiteral("it"), QStringLiteral("Italiano"), QStringLiteral("hexproof_it"),
         QStringLiteral("hexproof_dynamic_it")},
        {QStringLiteral("pt_BR"), QStringLiteral("Português (Brasil)"),
         QStringLiteral("hexproof_pt_BR"), QStringLiteral("hexproof_dynamic_pt_BR")},
        {QStringLiteral("zh_TW"), QStringLiteral("繁體中文"), QStringLiteral("hexproof_zh_TW"),
         QStringLiteral("hexproof_dynamic_zh_TW")},
    };
}

// Canonical stored code for a raw setting value. "zh_cn" is accepted as a
// legacy-friendly spelling of Simplified Chinese; anything unknown falls back
// to English instead of keeping a language with no catalogs.
inline QString normalize(const QString &raw)
{
    const QString lowered = raw.trimmed().toLower();
    if (lowered == QStringLiteral("zh_cn"))
        return QStringLiteral("zh");
    for (const UiLanguage &language : languages()) {
        if (language.code.compare(lowered, Qt::CaseInsensitive) == 0)
            return language.code;
    }
    return QStringLiteral("en");
}

inline QVariantList qmlOptions()
{
    QVariantList options;
    for (const UiLanguage &language : languages()) {
        options.append(QVariantMap{{QStringLiteral("code"), language.code},
                                   {QStringLiteral("label"), language.nativeName}});
    }
    return options;
}

} // namespace hexproof::client::uiLanguages
