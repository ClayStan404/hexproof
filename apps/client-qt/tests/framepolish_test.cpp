// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ui/FramePolish.h"

#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

#include <functional>
#include <memory>

using hexproof::client::FramePolish;

class EvaluationRecorder : public QObject
{
    Q_OBJECT

  public:
    int calls = 0;
    std::function<void()> onRecord;

    Q_INVOKABLE QVariant record(const QVariant &value)
    {
        ++calls;
        if (onRecord)
            onRecord();
        return value;
    }
};

class FramePolishTest : public QObject
{
    Q_OBJECT

  private slots:
    void requestsCoalesce()
    {
        FramePolish item;
        QSignalSpy ready(&item, &FramePolish::ready);
        for (int i = 0; i < 100; ++i)
            item.request();
        QCOMPARE(ready.count(), 0);
        item.ensurePolished();
        QCOMPARE(ready.count(), 1);
        item.ensurePolished();
        QCOMPARE(ready.count(), 1);
    }

    void publicationCanRequestAnotherPolish()
    {
        FramePolish item;
        QSignalSpy ready(&item, &FramePolish::ready);
        connect(&item, &FramePolish::ready, &item, [&] {
            if (ready.count() == 1)
                item.request();
        });
        item.request();
        item.ensurePolished();
        QCOMPARE(ready.count(), 1);
        item.ensurePolished();
        QCOMPARE(ready.count(), 2);
        item.ensurePolished();
        QCOMPARE(ready.count(), 2);
    }

    void expressionInvalidationsCoalesceAndSwitchDependencies()
    {
        EvaluationRecorder recorder;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("recorder", &recorder);
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Hexproof.Native 1.0
            Item {
                id: root
                property int first: 1
                property int second: 2
                property bool useFirst: true
                FramePolish {
                    objectName: "publisher"
                    expression: recorder.record(root.useFirst ? root.first : root.second)
                }
            }
        )",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY(root);
        auto *publisher = root->findChild<FramePolish *>("publisher");
        QVERIFY(publisher);
        QCOMPARE(recorder.calls, 0);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 1);
        QCOMPARE(publisher->value().toInt(), 1);

        for (int i = 3; i <= 100; ++i)
            root->setProperty("first", i);
        QCOMPARE(recorder.calls, 1);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 2);
        QCOMPARE(publisher->value().toInt(), 100);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 2);

        root->setProperty("useFirst", false);
        root->setProperty("second", 200);
        QCOMPARE(recorder.calls, 2);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 3);
        QCOMPARE(publisher->value().toInt(), 200);
        root->setProperty("first", 101);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 3);
        root->setProperty("second", 201);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 4);
        QCOMPARE(publisher->value().toInt(), 201);
    }

    void disabledExpressionResumesWithLatestValue()
    {
        EvaluationRecorder recorder;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("recorder", &recorder);
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Hexproof.Native 1.0
            Item {
                id: root
                property int source: 1
                FramePolish {
                    objectName: "publisher"
                    expression: recorder.record(root.source)
                }
            }
        )",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY(root);
        auto *publisher = root->findChild<FramePolish *>("publisher");
        QVERIFY(publisher);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 1);
        root->setProperty("source", 2);
        publisher->setEnabled(false);
        root->setProperty("source", 3);
        publisher->request();
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 1);
        QCOMPARE(publisher->value().toInt(), 1);
        publisher->setEnabled(true);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 2);
        QCOMPARE(publisher->value().toInt(), 3);
        root->setProperty("source", 4);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 3);
        QCOMPARE(publisher->value().toInt(), 4);
    }

    void expressionTracksDependencyDestructionAndCanBeCleared()
    {
        EvaluationRecorder recorder;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("recorder", &recorder);
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Hexproof.Native 1.0
            Item {
                id: root
                property QtObject source: QtObject { property int amount: 7 }
                FramePolish {
                    objectName: "publisher"
                    expression: recorder.record(root.source ? root.source.amount : -1)
                }
            }
        )",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY(root);
        auto *publisher = root->findChild<FramePolish *>("publisher");
        QVERIFY(publisher);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 1);
        QCOMPARE(publisher->value().toInt(), 7);
        delete root->property("source").value<QObject *>();
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 2);
        QCOMPARE(publisher->value().toInt(), -1);

        const QQmlScriptString expression = publisher->expression();
        publisher->setExpression(QQmlScriptString());
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 2);
        QVERIFY(!publisher->value().isValid());
        publisher->setExpression(expression);
        QPointer<FramePolish> guard(publisher);
        root.reset();
        QVERIFY(guard.isNull());
        QCoreApplication::processEvents();
    }

    void expressionPublishesJavascriptArrays()
    {
        EvaluationRecorder recorder;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("recorder", &recorder);
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Hexproof.Native 1.0
            Item {
                id: root
                property int source: 1
                property int publishedSource: publisher.value ? publisher.value[0] : -1
                property rect publishedRect: publisher.value ? publisher.value[1] : Qt.rect(0, 0, 0, 0)
                function collect() {
                    recorder.record(root.source)
                    return [root.source, Qt.rect(root.source, 2, 3, 4)]
                }
                FramePolish {
                    id: publisher
                    objectName: "publisher"
                    expression: root.collect()
                }
            }
        )",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY(root);
        auto *publisher = root->findChild<FramePolish *>("publisher");
        QVERIFY(publisher);
        QSignalSpy changes(publisher, &FramePolish::valueChanged);
        publisher->ensurePolished();
        QCOMPARE(root->property("publishedSource").toInt(), 1);
        QCOMPARE(root->property("publishedRect").toRectF(), QRectF(1, 2, 3, 4));
        for (int i = 2; i <= 100; ++i)
            root->setProperty("source", i);
        QCOMPARE(recorder.calls, 1);
        publisher->ensurePolished();
        QCOMPARE(recorder.calls, 2);
        QCOMPARE(changes.count(), 2);
        QCOMPARE(root->property("publishedSource").toInt(), 100);
        QCOMPARE(root->property("publishedRect").toRectF(), QRectF(100, 2, 3, 4));
    }

    void evaluationCallbacksCannotPublishStaleResults()
    {
        EvaluationRecorder recorder;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("recorder", &recorder);
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Hexproof.Native 1.0
            Item {
                id: root
                property int source: 1
                FramePolish {
                    objectName: "publisher"
                    expression: recorder.record(root.source)
                }
            }
        )",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY(root);
        auto *publisher = root->findChild<FramePolish *>("publisher");
        QVERIFY(publisher);
        publisher->ensurePolished();
        QCOMPARE(publisher->value().toInt(), 1);

        recorder.onRecord = [publisher] { publisher->setEnabled(false); };
        root->setProperty("source", 2);
        publisher->ensurePolished();
        QCOMPARE(publisher->value().toInt(), 1);
        QVERIFY(!publisher->isEnabled());
        recorder.onRecord = {};
        publisher->setEnabled(true);
        publisher->ensurePolished();
        QCOMPARE(publisher->value().toInt(), 2);

        recorder.onRecord = [publisher] { publisher->setExpression(QQmlScriptString()); };
        root->setProperty("source", 3);
        publisher->ensurePolished();
        QCOMPARE(publisher->value().toInt(), 2);
        publisher->ensurePolished();
        QVERIFY(!publisher->value().isValid());
    }

    void synchronousGrabEvaluatesLatestExpression()
    {
        EvaluationRecorder recorder;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("recorder", &recorder);
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Hexproof.Native 1.0
            Rectangle {
                id: root
                width: 160; height: 80; color: "black"
                property real sourceX: 10
                FramePolish {
                    id: publisher
                    expression: recorder.record(root.sourceX)
                }
                Rectangle {
                    width: 10; height: 10; y: 20
                    x: publisher.value || 0
                    color: "red"
                }
            }
        )",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> object(component.create());
        auto *root = qobject_cast<QQuickItem *>(object.get());
        QVERIFY(root);
        QQuickWindow window;
        window.resize(160, 80);
        root->setParentItem(window.contentItem());
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        QVERIFY(!window.grabWindow().isNull());
        QCOMPARE(recorder.calls, 1);
        for (int x = 20; x <= 100; ++x)
            root->setProperty("sourceX", x);
        QCOMPARE(recorder.calls, 1);
        const QImage frame = window.grabWindow();
        QVERIFY(!frame.isNull());
        QCOMPARE(recorder.calls, 2);
        const qreal scale = window.devicePixelRatio();
        QCOMPARE(frame.pixelColor(qRound(105 * scale), qRound(25 * scale)), QColor(Qt::red));
        QCOMPARE(frame.pixelColor(qRound(15 * scale), qRound(25 * scale)), QColor(Qt::black));
        root->setParentItem(nullptr);
    }

    void synchronousGrabUsesLatestGeometry()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Hexproof.Native 1.0
            Rectangle {
                width: 160; height: 80; color: "black"
                property real sourceX: 10
                property int publications: 0
                onSourceXChanged: publisher.request()
                FramePolish {
                    id: publisher
                    onReady: {
                        marker.x = sourceX
                        ++publications
                    }
                }
                Rectangle {
                    id: marker
                    width: 10; height: 10; y: 20; x: 10; color: "red"
                }
            }
        )",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> object(component.create());
        auto *root = qobject_cast<QQuickItem *>(object.get());
        QVERIFY(root);
        QQuickWindow window;
        window.resize(160, 80);
        root->setParentItem(window.contentItem());
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        QVERIFY(!window.grabWindow().isNull());
        for (int x = 20; x <= 100; ++x)
            root->setProperty("sourceX", x);
        QCOMPARE(root->property("publications").toInt(), 0);
        // No event processing between the last mutation and this capture.
        const QImage frame = window.grabWindow();
        QVERIFY(!frame.isNull());
        QCOMPARE(root->property("publications").toInt(), 1);
        const qreal scale = window.devicePixelRatio();
        QCOMPARE(frame.pixelColor(qRound(105 * scale), qRound(25 * scale)), QColor(Qt::red));
        QCOMPARE(frame.pixelColor(qRound(15 * scale), qRound(25 * scale)), QColor(Qt::black));
        root->setParentItem(nullptr);
    }
};

QTEST_MAIN(FramePolishTest)
#include "framepolish_test.moc"
