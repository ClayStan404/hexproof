// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QFutureWatcher>
#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>

#include <functional>
#include <memory>

class QLockFile;

namespace hexproof::client {

// Image location is separate from profile-owned indexes. A migration copies
// both image trees and atomically commits their shared location descriptor;
// the running session retains its original paths until the next launch.
class CardArtStorage final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString imageRoot READ imageRoot CONSTANT)
    Q_PROPERTY(QString customImageRoot READ customImageRoot CONSTANT)
    Q_PROPERTY(QString currentDirectory READ currentDirectory CONSTANT)
    Q_PROPERTY(QString configuredBaseDirectory READ configuredBaseDirectory CONSTANT)
    Q_PROPERTY(bool defaultLocation READ defaultLocation CONSTANT)
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool restartRequired READ restartRequired NOTIFY restartRequiredChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString lastResult READ lastResult NOTIFY lastResultChanged)
    Q_PROPERTY(QVariantMap preview READ preview NOTIFY previewChanged)

  public:
    explicit CardArtStorage(const QString &profileRoot, QObject *parent = nullptr);
    ~CardArtStorage() override;

    QString imageRoot() const
    {
        return m_imageRoot;
    }
    QString customImageRoot() const
    {
        return m_customImageRoot;
    }
    QString currentDirectory() const
    {
        return m_currentDirectory;
    }
    QString configuredBaseDirectory() const
    {
        return m_baseDirectory;
    }
    QStringList previousImageRoots() const
    {
        return m_previousImageRoots;
    }
    bool defaultLocation() const
    {
        return m_baseDirectory.isEmpty();
    }
    bool available() const
    {
        return m_available;
    }
    bool busy() const
    {
        return m_busy;
    }
    bool restartRequired() const
    {
        return m_restartRequired;
    }
    double progress() const
    {
        return m_progress;
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
    QVariantMap preview() const
    {
        return m_preview;
    }
    bool writesAllowed() const;

    // Called before copying, while no other art operation owns either tree.
    void setOperationGuard(std::function<bool()> guard);
    void setIndexFlush(std::function<void(std::function<void(bool)>)> flush);

    Q_INVOKABLE QVariantMap previewDirectory(const QUrl &directory);
    Q_INVOKABLE QVariantMap previewDefault();
    Q_INVOKABLE void migrateTo(const QUrl &directory);
    Q_INVOKABLE void resetToDefault();
    Q_INVOKABLE void clearMessages();

  signals:
    void busyChanged();
    void restartRequiredChanged();
    void progressChanged();
    void statusChanged();
    void lastErrorChanged();
    void lastResultChanged();
    void previewChanged();
    void migrationFinished(const QVariantMap &result);

  private:
    struct MigrationResult
    {
        bool ok = false;
        QString error;
        qint64 files = 0;
        qint64 bytes = 0;
    };
    QVariantMap destination(const QUrl &directory, bool useDefault) const;
    void migrate(const QVariantMap &destination);
    bool startMigration(const QVariantMap &destination);
    void initialize();
    void setError(const QString &error);
    void setStatus(const QString &status);
    void setProgress(double progress);

    QString m_profileRoot;
    QString m_profileKey;
    QString m_configPath;
    QString m_imageRoot;
    QString m_customImageRoot;
    QString m_currentDirectory;
    QString m_baseDirectory;
    QStringList m_previousImageRoots;
    QString m_status;
    QString m_lastError;
    QString m_lastResult;
    QVariantMap m_preview;
    std::function<bool()> m_operationGuard;
    std::function<void(std::function<void(bool)>)> m_indexFlush;
    std::unique_ptr<QLockFile> m_currentLock;
    std::unique_ptr<QLockFile> m_destinationLock;
    QFutureWatcher<MigrationResult> m_watcher;
    bool m_available = false;
    bool m_busy = false;
    bool m_restartRequired = false;
    double m_progress = 0;
};

} // namespace hexproof::client
