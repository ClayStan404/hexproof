// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QHash>
#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <functional>
#include <memory>

class QTemporaryDir;
template <typename T> class QFutureWatcher;

namespace hexproof::client {
namespace customart {
struct WorkResult;
}

class CustomCardArtStore final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    Q_PROPERTY(QVariantMap preview READ preview NOTIFY inspectionFinished)
    Q_PROPERTY(QString imageRoot READ imageRoot NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY messagesChanged)
    Q_PROPERTY(QString lastResult READ lastResult NOTIFY messagesChanged)
    Q_PROPERTY(int revision READ revision NOTIFY changed)

  public:
    explicit CustomCardArtStore(QString profileRoot, QString imageRoot = {},
                                QObject *parent = nullptr);
    ~CustomCardArtStore() override;

    bool busy() const
    {
        return m_busy;
    }
    bool hasEntries() const
    {
        return !m_entries.isEmpty();
    }
    QVariantList entries() const;
    QVariantMap preview() const
    {
        return m_preview;
    }
    QString imageRoot() const
    {
        return m_imageRoot;
    }
    QString status() const
    {
        return m_status;
    }
    QString lastError() const
    {
        return m_lastError;
    }
    QString lastResult() const
    {
        return m_lastResult;
    }
    int revision() const
    {
        return m_revision;
    }

    void load();
    bool setImageRoot(const QString &path);
    void setOperationGuard(std::function<bool()> guard);
    QString imagePath(const QString &name, const QString &setCode, const QString &collectorNumber,
                      const QString &oracleId = {}) const;

    Q_INVOKABLE QVariantMap entryFor(const QVariantMap &binding) const;
    Q_INVOKABLE QString imagePathForBinding(const QVariantMap &binding) const;
    Q_INVOKABLE void inspectImage(const QUrl &fileUrl);
    Q_INVOKABLE void setImage(const QUrl &fileUrl, const QVariantMap &binding);
    Q_INVOKABLE void removeEntry(const QString &id);
    Q_INVOKABLE void removeBindings(const QVariantMap &binding, bool allFaces = false);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void inspectDirectory(const QUrl &directoryUrl);
    Q_INVOKABLE void inspectPack(const QUrl &fileUrl);
    Q_INVOKABLE void importPreview(bool replaceExisting = false);
    Q_INVOKABLE void exportPack(const QUrl &fileUrl, const QStringList &ids = {});
    Q_INVOKABLE QUrl suggestedExportUrl() const;
    Q_INVOKABLE void clearMessages();

  signals:
    void busyChanged();
    void changed();
    // Identity-only delta, including removed/replaced bindings. An empty list
    // is reserved for complete reloads or a change of managed image root.
    void bindingsChanged(const QVariantList &bindings);
    void inspectionFinished();
    void statusChanged();
    void messagesChanged();
    void operationFinished(const QVariantMap &result);

  private:
    bool begin(const QString &operation, const QString &fileUrl = {});
    void reject(const QString &operation, const QString &error, const QString &fileUrl = {});
    void run(const QString &operation, const QString &fileUrl,
             std::function<customart::WorkResult()> work);
    void rebuildLookup();
    void removeIds(const QStringList &ids, const QString &operation);

    QString m_profileRoot;
    QString m_indexPath;
    QString m_databasePath;
    QString m_imageRoot;
    QVariantList m_entries;
    QVariantList m_displayEntries;
    QVariantList m_pendingEntries;
    QVariantMap m_preview;
    QHash<QString, QString> m_lookup;
    QHash<QString, QVariantMap> m_entriesById;
    QString m_status;
    QString m_lastError;
    QString m_lastResult;
    std::function<bool()> m_operationGuard;
    std::shared_ptr<QTemporaryDir> m_staging;
    QFutureWatcher<customart::WorkResult> *m_worker = nullptr;
    bool m_busy = false;
    bool m_indexReadable = true;
    int m_revision = 0;
    quint64 m_presentationGeneration = 0;
};

} // namespace hexproof::client
