// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ClientPreferencesModel.h"

#include "ApplicationPaths.h"
#include "ShortcutRegistry.h"

#include <QKeySequence>
#include <QSet>

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

QString normalizedShortcutSequence(const QString &sequence)
{
    const QString trimmed = sequence.trimmed();
    if (trimmed.isEmpty())
        return {};
    const QKeySequence keySequence = QKeySequence::fromString(trimmed, QKeySequence::PortableText);
    if (keySequence.isEmpty() || keySequence.count() != 1)
        return {};
    return keySequence.toString(QKeySequence::PortableText);
}

QStringList normalizedShortcutSequences(const QStringList &sequences, bool *valid)
{
    QStringList result;
    QSet<QString> seen;
    *valid = true;
    for (const QString &sequence : sequences) {
        const QString normalized = normalizedShortcutSequence(sequence);
        if (normalized.isEmpty()) {
            *valid = false;
            return {};
        }
        if (!seen.contains(normalized)) {
            seen.insert(normalized);
            result.append(normalized);
        }
    }
    return result;
}

bool isModifierKey(int key)
{
    return key == Qt::Key_Shift || key == Qt::Key_Control || key == Qt::Key_Meta ||
           key == Qt::Key_Alt || key == Qt::Key_AltGr || key == Qt::Key_CapsLock ||
           key == Qt::Key_NumLock || key == Qt::Key_ScrollLock;
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
    const auto overrides = m_preferences.shortcutOverrides;
    m_preferences.shortcutOverrides.clear();
    for (auto it = overrides.constBegin(); it != overrides.constEnd(); ++it) {
        if (!isKnownShortcutAction(it.key()))
            continue;
        if (it.value().isEmpty()) {
            m_preferences.shortcutOverrides.insert(it.key(), {});
            continue;
        }
        bool valid = false;
        const QStringList normalized = normalizedShortcutSequences(it.value(), &valid);
        if (valid)
            m_preferences.shortcutOverrides.insert(it.key(), normalized);
    }
    bool removedConflict = false;
    do {
        removedConflict = false;
        QHash<QString, QString> assignedActions;
        for (const ShortcutDefinition &definition : shortcutDefinitions()) {
            const QStringList sequences = m_preferences.shortcutOverrides.contains(definition.id)
                                              ? m_preferences.shortcutOverrides.value(definition.id)
                                              : definition.defaultSequences;
            for (const QString &sequence : sequences) {
                const QString previousAction = assignedActions.value(sequence);
                if (previousAction.isEmpty()) {
                    assignedActions.insert(sequence, definition.id);
                    continue;
                }
                const QString overrideToRemove =
                    m_preferences.shortcutOverrides.contains(definition.id) ? definition.id
                                                                            : previousAction;
                if (m_preferences.shortcutOverrides.remove(overrideToRemove) > 0) {
                    removedConflict = true;
                    break;
                }
            }
            if (removedConflict)
                break;
        }
    } while (removedConflict);
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

void ClientPreferencesModel::setCardArtProvider(const QString &provider)
{
    const QString lowered = provider.toLower();
    const QString normalized =
        lowered == QStringLiteral("mtgch") || lowered == QStringLiteral("scryfall")
            ? lowered
            : QStringLiteral("auto");
    if (normalized == m_preferences.cardArtProvider)
        return;
    const QString previous = m_preferences.cardArtProvider;
    m_preferences.cardArtProvider = normalized;
    if (!save()) {
        m_preferences.cardArtProvider = previous;
        return;
    }
    emit cardArtProviderChanged();
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

void ClientPreferencesModel::setAnimatePackOpenings(bool animate)
{
    if (animate == m_preferences.animatePackOpenings)
        return;
    const bool previous = m_preferences.animatePackOpenings;
    m_preferences.animatePackOpenings = animate;
    if (!save()) {
        m_preferences.animatePackOpenings = previous;
        return;
    }
    emit animatePackOpeningsChanged();
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

bool ClientPreferencesModel::sponsorAnnouncementSeen(const QString &announcementId) const
{
    const QString normalized = announcementId.trimmed().left(128);
    return !normalized.isEmpty() && normalized == m_preferences.sponsorAnnouncementId;
}

bool ClientPreferencesModel::acknowledgeSponsorAnnouncement(const QString &announcementId)
{
    const QString normalized = announcementId.trimmed().left(128);
    if (normalized.isEmpty())
        return false;
    if (normalized == m_preferences.sponsorAnnouncementId)
        return true;
    const QString previous = m_preferences.sponsorAnnouncementId;
    m_preferences.sponsorAnnouncementId = normalized;
    if (!save()) {
        m_preferences.sponsorAnnouncementId = previous;
        return false;
    }
    return true;
}

bool ClientPreferencesModel::cardArtRepairNoticeSeen(int version) const
{
    return version > 0 && m_preferences.cardArtRepairNoticeVersion >= version;
}

bool ClientPreferencesModel::acknowledgeCardArtRepairNotice(int version)
{
    if (version <= 0)
        return false;
    if (m_preferences.cardArtRepairNoticeVersion >= version)
        return true;
    const int previous = m_preferences.cardArtRepairNoticeVersion;
    m_preferences.cardArtRepairNoticeVersion = version;
    if (!save()) {
        m_preferences.cardArtRepairNoticeVersion = previous;
        return false;
    }
    return true;
}

void ClientPreferencesModel::setShortcutCaptureActive(bool active)
{
    if (m_shortcutCaptureActive == active)
        return;
    m_shortcutCaptureActive = active;
    emit shortcutCaptureActiveChanged();
}

QStringList ClientPreferencesModel::shortcutSequences(const QString &actionId) const
{
    if (!isKnownShortcutAction(actionId))
        return {};
    if (m_preferences.shortcutOverrides.contains(actionId))
        return m_preferences.shortcutOverrides.value(actionId);
    return defaultShortcutSequences(actionId);
}

QString ClientPreferencesModel::shortcutDisplay(const QString &actionId) const
{
    const QStringList sequences = shortcutSequences(actionId);
    return sequences.isEmpty() ? tr("Unassigned") : sequences.join(QStringLiteral(" / "));
}

QString ClientPreferencesModel::defaultShortcutDisplay(const QString &actionId) const
{
    const QStringList sequences = defaultShortcutSequences(actionId);
    return sequences.isEmpty() ? QString{} : sequences.join(QStringLiteral(" / "));
}

bool ClientPreferencesModel::shortcutCustomized(const QString &actionId) const
{
    return m_preferences.shortcutOverrides.contains(actionId);
}

QString ClientPreferencesModel::shortcutConflictAction(const QString &actionId,
                                                       const QString &sequence) const
{
    const QString normalized = normalizedShortcutSequence(sequence);
    if (!isKnownShortcutAction(actionId) || normalized.isEmpty())
        return {};
    for (const ShortcutDefinition &definition : shortcutDefinitions()) {
        if (definition.id == actionId)
            continue;
        const QStringList assigned = shortcutSequences(definition.id);
        for (const QString &candidate : assigned) {
            if (normalizedShortcutSequence(candidate) == normalized)
                return definition.id;
        }
    }
    return {};
}

bool ClientPreferencesModel::setShortcutSequence(const QString &actionId, const QString &sequence)
{
    if (!isKnownShortcutAction(actionId)) {
        setLastError(tr("Unknown shortcut action."));
        return false;
    }
    const QString trimmed = sequence.trimmed();
    const QString normalized = normalizedShortcutSequence(trimmed);
    if (!trimmed.isEmpty() && normalized.isEmpty()) {
        setLastError(tr("The shortcut is not a valid single key combination."));
        return false;
    }
    if (!normalized.isEmpty() && !shortcutConflictAction(actionId, normalized).isEmpty()) {
        setLastError(tr("That shortcut is already assigned to another action."));
        return false;
    }
    const QStringList assigned = normalized.isEmpty() ? QStringList{} : QStringList{normalized};
    if (m_preferences.shortcutOverrides.contains(actionId) &&
        m_preferences.shortcutOverrides.value(actionId) == assigned) {
        return true;
    }
    const auto previous = m_preferences.shortcutOverrides;
    m_preferences.shortcutOverrides.insert(actionId, assigned);
    if (!save()) {
        m_preferences.shortcutOverrides = previous;
        return false;
    }
    ++m_shortcutRevision;
    emit shortcutsChanged();
    return true;
}

bool ClientPreferencesModel::resetShortcut(const QString &actionId)
{
    if (!isKnownShortcutAction(actionId)) {
        setLastError(tr("Unknown shortcut action."));
        return false;
    }
    if (!m_preferences.shortcutOverrides.contains(actionId))
        return true;
    for (const QString &sequence : defaultShortcutSequences(actionId)) {
        if (!shortcutConflictAction(actionId, sequence).isEmpty()) {
            setLastError(tr("A default shortcut is currently assigned to another action."));
            return false;
        }
    }
    const auto previous = m_preferences.shortcutOverrides;
    m_preferences.shortcutOverrides.remove(actionId);
    if (!save()) {
        m_preferences.shortcutOverrides = previous;
        return false;
    }
    ++m_shortcutRevision;
    emit shortcutsChanged();
    return true;
}

bool ClientPreferencesModel::resetAllShortcuts()
{
    if (m_preferences.shortcutOverrides.isEmpty())
        return true;
    const auto previous = m_preferences.shortcutOverrides;
    m_preferences.shortcutOverrides.clear();
    if (!save()) {
        m_preferences.shortcutOverrides = previous;
        return false;
    }
    ++m_shortcutRevision;
    emit shortcutsChanged();
    return true;
}

QString ClientPreferencesModel::keyEventSequence(int key, int modifiers) const
{
    if (key == Qt::Key_unknown || isModifierKey(key))
        return {};
    const auto keyboardModifiers = Qt::KeyboardModifiers(modifiers) &
                                   (Qt::ShiftModifier | Qt::ControlModifier | Qt::AltModifier |
                                    Qt::MetaModifier | Qt::KeypadModifier);
    return QKeySequence(QKeyCombination(keyboardModifiers, Qt::Key(key)))
        .toString(QKeySequence::PortableText);
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
