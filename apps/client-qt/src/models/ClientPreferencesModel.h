// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "models/DeckLibraryStorage.h"

#include <QObject>
#include <QString>

namespace hexproof::client {

class ClientPreferencesModel final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString uiLanguage READ uiLanguage WRITE setUiLanguage NOTIFY uiLanguageChanged)
    Q_PROPERTY(
        QString cardLanguage READ cardLanguage WRITE setCardLanguage NOTIFY cardLanguageChanged)
    Q_PROPERTY(bool reuseLocalCardArt READ reuseLocalCardArt WRITE setReuseLocalCardArt NOTIFY
                   reuseLocalCardArtChanged)
    Q_PROPERTY(qreal interfaceScale READ interfaceScale WRITE setInterfaceScale NOTIFY
                   interfaceScaleChanged)
    Q_PROPERTY(bool tableShowPlayers READ tableShowPlayers WRITE setTableShowPlayers NOTIFY
                   tableLayoutChanged)
    Q_PROPERTY(bool tableShowShared READ tableShowShared WRITE setTableShowShared NOTIFY
                   tableLayoutChanged)
    Q_PROPERTY(bool tableShowInspector READ tableShowInspector WRITE setTableShowInspector NOTIFY
                   tableLayoutChanged)
    Q_PROPERTY(bool tableShowGameLog READ tableShowGameLog WRITE setTableShowGameLog NOTIFY
                   tableLayoutChanged)
    Q_PROPERTY(int tableCounterCount READ tableCounterCount WRITE setTableCounterCount NOTIFY
                   tableLayoutChanged)
    Q_PROPERTY(qreal tableOverviewCardScale READ tableOverviewCardScale WRITE
                   setTableOverviewCardScale NOTIFY tableLayoutChanged)
    Q_PROPERTY(qreal tableFocusCardScale READ tableFocusCardScale WRITE setTableFocusCardScale
                   NOTIFY tableLayoutChanged)
    Q_PROPERTY(qreal tableBattlefieldControlX READ tableBattlefieldControlX WRITE
                   setTableBattlefieldControlX NOTIFY tableLayoutChanged)
    Q_PROPERTY(qreal tableBattlefieldControlY READ tableBattlefieldControlY WRITE
                   setTableBattlefieldControlY NOTIFY tableLayoutChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

  public:
    explicit ClientPreferencesModel(QObject *parent = nullptr);
    explicit ClientPreferencesModel(const QString &storageRoot, QObject *parent = nullptr);

    QString uiLanguage() const
    {
        return m_preferences.uiLanguage;
    }
    void setUiLanguage(const QString &language);
    QString cardLanguage() const
    {
        return m_preferences.cardLanguage;
    }
    void setCardLanguage(const QString &language);
    bool reuseLocalCardArt() const
    {
        return m_preferences.reuseLocalCardArt;
    }
    void setReuseLocalCardArt(bool reuse);
    qreal interfaceScale() const
    {
        return m_preferences.interfaceScale;
    }
    void setInterfaceScale(qreal scale);
    bool tableShowPlayers() const
    {
        return m_preferences.tableShowPlayers;
    }
    void setTableShowPlayers(bool show);
    bool tableShowShared() const
    {
        return m_preferences.tableShowShared;
    }
    void setTableShowShared(bool show);
    bool tableShowInspector() const
    {
        return m_preferences.tableShowInspector;
    }
    void setTableShowInspector(bool show);
    bool tableShowGameLog() const
    {
        return m_preferences.tableShowGameLog;
    }
    void setTableShowGameLog(bool show);
    int tableCounterCount() const
    {
        return m_preferences.tableCounterCount;
    }
    void setTableCounterCount(int count);
    qreal tableOverviewCardScale() const
    {
        return m_preferences.tableOverviewCardScale;
    }
    void setTableOverviewCardScale(qreal scale);
    qreal tableFocusCardScale() const
    {
        return m_preferences.tableFocusCardScale;
    }
    void setTableFocusCardScale(qreal scale);
    qreal tableBattlefieldControlX() const
    {
        return m_preferences.tableBattlefieldControlX;
    }
    void setTableBattlefieldControlX(qreal position);
    qreal tableBattlefieldControlY() const
    {
        return m_preferences.tableBattlefieldControlY;
    }
    void setTableBattlefieldControlY(qreal position);
    QString lastError() const
    {
        return m_lastError;
    }

    Q_INVOKABLE void clearLastError();
    Q_INVOKABLE void setTableBattlefieldControlPosition(qreal x, qreal y);

  signals:
    void uiLanguageChanged();
    void cardLanguageChanged();
    void reuseLocalCardArtChanged();
    void interfaceScaleChanged();
    void tableLayoutChanged();
    void lastErrorChanged();

  private:
    bool save();
    void setLastError(const QString &error);

    DeckLibraryStorage m_storage;
    DeckLibraryPreferences m_preferences;
    QString m_lastError;
};

} // namespace hexproof::client
