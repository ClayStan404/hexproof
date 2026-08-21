// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ClientPreferencesModel.h"

#include "ApplicationPaths.h"

#include <algorithm>
#include <cmath>

namespace hexproof::client {

namespace {

qreal normalizedTableCardScale(qreal scale)
{
    if (!std::isfinite(scale) || scale <= 0.0)
        return 0.0;
    return std::clamp(std::round(scale * 20.0) / 20.0, 0.5, 1.25);
}

qreal normalizedTableControlPosition(qreal position)
{
    if (!std::isfinite(position) || position < 0.0)
        return -1.0;
    return std::clamp(position, 0.0, 1.0);
}

} // namespace

ClientPreferencesModel::ClientPreferencesModel(QObject *parent)
    : ClientPreferencesModel(defaultStorageRoot(), parent)
{
}

ClientPreferencesModel::ClientPreferencesModel(const QString &storageRoot, QObject *parent)
    : QObject(parent),
      m_storage(storageRoot),
      m_preferences(m_storage.loadPreferences())
{
}

void ClientPreferencesModel::setUiLanguage(const QString &language)
{
    const QString normalized =
        language.toLower() == QStringLiteral("zh") ? QStringLiteral("zh") : QStringLiteral("en");
    if (normalized == m_preferences.uiLanguage)
        return;
    const QString previous = m_preferences.uiLanguage;
    m_preferences.uiLanguage = normalized;
    // A reverted value did not change, so notifying would make bindings and the
    // wired catalog/art refreshes react to a preference that was never stored.
    // save() already reports the failure through lastError.
    if (!save()) {
        m_preferences.uiLanguage = previous;
        return;
    }
    emit uiLanguageChanged();
}

void ClientPreferencesModel::setCardLanguage(const QString &language)
{
    const QString normalized =
        language.toLower() == QStringLiteral("zh") ? QStringLiteral("zh") : QStringLiteral("en");
    if (normalized == m_preferences.cardLanguage)
        return;
    const QString previous = m_preferences.cardLanguage;
    m_preferences.cardLanguage = normalized;
    if (!save()) {
        m_preferences.cardLanguage = previous;
        return;
    }
    emit cardLanguageChanged();
}

void ClientPreferencesModel::setReuseLocalCardArt(bool reuse)
{
    if (reuse == m_preferences.reuseLocalCardArt)
        return;
    const bool previous = m_preferences.reuseLocalCardArt;
    m_preferences.reuseLocalCardArt = reuse;
    if (!save()) {
        m_preferences.reuseLocalCardArt = previous;
        return;
    }
    emit reuseLocalCardArtChanged();
}

void ClientPreferencesModel::setInterfaceScale(qreal scale)
{
    if (!std::isfinite(scale))
        scale = 1.0;
    const qreal normalized = std::clamp(std::round(scale * 20.0) / 20.0, 0.75, 1.5);
    if (normalized == m_preferences.interfaceScale)
        return;
    const qreal previous = m_preferences.interfaceScale;
    m_preferences.interfaceScale = normalized;
    if (!save()) {
        m_preferences.interfaceScale = previous;
        return;
    }
    emit interfaceScaleChanged();
}

void ClientPreferencesModel::setTableShowPlayers(bool show)
{
    if (show == m_preferences.tableShowPlayers)
        return;
    const bool previous = m_preferences.tableShowPlayers;
    m_preferences.tableShowPlayers = show;
    if (!save()) {
        m_preferences.tableShowPlayers = previous;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::setTableShowShared(bool show)
{
    if (show == m_preferences.tableShowShared)
        return;
    const bool previous = m_preferences.tableShowShared;
    m_preferences.tableShowShared = show;
    if (!save()) {
        m_preferences.tableShowShared = previous;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::setTableShowInspector(bool show)
{
    if (show == m_preferences.tableShowInspector)
        return;
    const bool previous = m_preferences.tableShowInspector;
    m_preferences.tableShowInspector = show;
    if (!save()) {
        m_preferences.tableShowInspector = previous;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::setTableShowGameLog(bool show)
{
    if (show == m_preferences.tableShowGameLog)
        return;
    const bool previous = m_preferences.tableShowGameLog;
    m_preferences.tableShowGameLog = show;
    if (!save()) {
        m_preferences.tableShowGameLog = previous;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::setTableCounterCount(int count)
{
    const int normalized = std::clamp(count, 0, 7);
    if (normalized == m_preferences.tableCounterCount)
        return;
    const int previous = m_preferences.tableCounterCount;
    m_preferences.tableCounterCount = normalized;
    if (!save()) {
        m_preferences.tableCounterCount = previous;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::setTableOverviewCardScale(qreal scale)
{
    const qreal normalized = normalizedTableCardScale(scale);
    if (normalized == m_preferences.tableOverviewCardScale)
        return;
    const qreal previous = m_preferences.tableOverviewCardScale;
    m_preferences.tableOverviewCardScale = normalized;
    if (!save()) {
        m_preferences.tableOverviewCardScale = previous;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::setTableFocusCardScale(qreal scale)
{
    const qreal normalized = normalizedTableCardScale(scale);
    if (normalized == m_preferences.tableFocusCardScale)
        return;
    const qreal previous = m_preferences.tableFocusCardScale;
    m_preferences.tableFocusCardScale = normalized;
    if (!save()) {
        m_preferences.tableFocusCardScale = previous;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::setTableBattlefieldControlX(qreal position)
{
    setTableBattlefieldControlPosition(position, m_preferences.tableBattlefieldControlY);
}

void ClientPreferencesModel::setTableBattlefieldControlY(qreal position)
{
    setTableBattlefieldControlPosition(m_preferences.tableBattlefieldControlX, position);
}

void ClientPreferencesModel::setTableBattlefieldControlPosition(qreal x, qreal y)
{
    const qreal normalizedX = normalizedTableControlPosition(x);
    const qreal normalizedY = normalizedTableControlPosition(y);
    if (normalizedX == m_preferences.tableBattlefieldControlX &&
        normalizedY == m_preferences.tableBattlefieldControlY) {
        return;
    }
    const qreal previousX = m_preferences.tableBattlefieldControlX;
    const qreal previousY = m_preferences.tableBattlefieldControlY;
    m_preferences.tableBattlefieldControlX = normalizedX;
    m_preferences.tableBattlefieldControlY = normalizedY;
    if (!save()) {
        m_preferences.tableBattlefieldControlX = previousX;
        m_preferences.tableBattlefieldControlY = previousY;
        return;
    }
    emit tableLayoutChanged();
}

void ClientPreferencesModel::clearLastError()
{
    setLastError({});
}

bool ClientPreferencesModel::save()
{
    QString error;
    if (!m_storage.savePreferences(m_preferences, &error)) {
        setLastError(error);
        return false;
    }
    setLastError({});
    return true;
}

void ClientPreferencesModel::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

} // namespace hexproof::client
