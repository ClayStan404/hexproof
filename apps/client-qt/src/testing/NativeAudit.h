// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QSize>
#include <QTimer>
#include <QVariantMap>

class QQmlApplicationEngine;
class QQuickItem;
class QQuickWindow;
class QProcess;

namespace hexproof::client {

// Linked only by hexproof_native_audit. Drivers are trusted local test code;
// direct model/route preparation must be recorded as fixture evidence.
class NativeAudit final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

  public:
    explicit NativeAudit(QQmlApplicationEngine *engine);
    static QString profileStorageRoot();
    static bool validateEnvironment(const QString &storageRoot);
    QString lastError() const;

    Q_INVOKABLE QString environment(const QString &name) const;
    Q_INVOKABLE QString readText(const QString &path);
    Q_INVOKABLE QVariantMap fileDialogState(const QString &name) const;
    Q_INVOKABLE bool chooseFile(const QString &name, const QString &path);
    Q_INVOKABLE QQuickItem *find(QObject *scope, const QString &name,
                                 const QVariantMap &identity = {});
    Q_INVOKABLE QVariantMap observe(QQuickWindow *window) const;
    Q_INVOKABLE bool canInteract(QQuickItem *item);
    Q_INVOKABLE bool click(QQuickItem *item, qreal x = -1, qreal y = -1);
    Q_INVOKABLE bool hover(QQuickItem *item);
    Q_INVOKABLE bool doubleClick(QQuickItem *item);
    Q_INVOKABLE bool rightClick(QQuickItem *item);
    Q_INVOKABLE bool activate();
    Q_INVOKABLE bool beginInput();
    Q_INVOKABLE void endInput();
    Q_INVOKABLE bool key(int key, int modifiers = 0);
    Q_INVOKABLE bool type(const QString &text);
    Q_INVOKABLE bool text(const QString &value);
    Q_INVOKABLE bool wheel(QQuickItem *item, int delta);
    Q_INVOKABLE bool wheel(QQuickItem *item, qreal x, qreal y, int delta);
    Q_INVOKABLE bool drag(QQuickItem *source, QQuickItem *target);
    Q_INVOKABLE bool drag(QQuickItem *source, QQuickItem *target, qreal sourceX, qreal sourceY);
    Q_INVOKABLE bool capture(QQuickWindow *window, const QString &name);
    Q_INVOKABLE bool record(const QString &name, const QVariant &value);
    Q_INVOKABLE QVariant readShared(const QString &name);
    Q_INVOKABLE bool share(const QString &name, const QVariant &value);
    Q_INVOKABLE void fixture(const QString &name, const QVariantMap &detail = {});
    Q_INVOKABLE bool applyRulesTableFixture(const QVariantMap &room, const QVariantMap &rules,
                                            const QVariantMap &match = {});
    Q_INVOKABLE bool interruptTransport(QObject *client);
    Q_INVOKABLE bool crashHostingHelper(QObject *client);
    Q_INVOKABLE void finish(int code);

  signals:
    void lastErrorChanged();
    void stepRequested();

  private:
    bool eventFilter(QObject *object, QEvent *event) override;
    bool osMode() const;
    QVariantMap osCommand(QVariantMap request);
    bool osInput(const QString &action, const QVariantMap &detail = {});
    QObject *fileDialogObject(const QString &name) const;
    bool fail(const QString &message);
    bool artifactFailure(const QString &message);
    bool targetPoint(QQuickItem *item, QPointF *point, qreal x = -1, qreal y = -1);
    bool inputFocus();
    void trace(const QString &action, const QVariantMap &detail, qint64 started);
    bool writeJson(const QString &directory, const QString &name, const QVariant &value);
    void startDriver();
    void heartbeat();

    QPointer<QQmlApplicationEngine> m_engine;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickWindow> m_osInputWindow;
    QPointer<QObject> m_driver;
    QProcess *m_osProcess = nullptr;
    QVariantMap m_osReceipt;
    QStringList m_osEvents;
    QVariantList m_osPointerEvents;
    bool m_osCollecting = false;
    QElapsedTimer m_elapsed;
    QTimer m_heartbeat;
    QString m_output;
    QString m_shared;
    QString m_lastError;
    QStringList m_warnings;
    int m_inputCount = 0;
    int m_fixtureCount = 0;
    int m_failedActions = 0;
    int m_artifactFailures = 0;
    int m_requestedWidth = 0;
    int m_requestedHeight = 0;
    QSize m_lastWindowSize;
    int m_geometryStableTicks = 0;
    bool m_driverStarted = false;
    bool m_finished = false;
};

} // namespace hexproof::client
