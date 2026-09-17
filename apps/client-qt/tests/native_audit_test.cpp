// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "testing/NativeAudit.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using hexproof::client::NativeAudit;

class NativeAuditTest : public QObject
{
    Q_OBJECT

  private slots:
    void explicitProfileIsIndependentOfPlatformAppData()
    {
        const QByteArray original = qgetenv("HEXPROOF_TEST_PROFILE_ROOT");
        const auto restore = qScopeGuard([original] {
            if (original.isNull())
                qunsetenv("HEXPROOF_TEST_PROFILE_ROOT");
            else
                qputenv("HEXPROOF_TEST_PROFILE_ROOT", original);
        });
        QTemporaryDir temporary;
        QVERIFY(temporary.isValid());
        qputenv("HEXPROOF_TEST_PROFILE_ROOT", temporary.path().toUtf8());
        QCOMPARE(NativeAudit::profileStorageRoot(),
                 QDir(QFileInfo(temporary.path()).canonicalFilePath())
                     .filePath(QStringLiteral("data/Hexproof/Hexproof")));
        for (const QByteArray &invalid :
             {QByteArray(), QByteArray("relative"), QDir::rootPath().toUtf8(),
              temporary.filePath(QStringLiteral("missing")).toUtf8()}) {
            qputenv("HEXPROOF_TEST_PROFILE_ROOT", invalid);
            QVERIFY(NativeAudit::profileStorageRoot().isEmpty());
        }
    }

    void windowFixture_data()
    {
        QTest::addColumn<bool>("windowed");
        QTest::newRow("maximized-default") << false;
        QTest::newRow("explicit-window-size") << true;
    }

    void windowFixture()
    {
        QFETCH(bool, windowed);
        QTemporaryDir temporary;
        QVERIFY(temporary.isValid());
        qputenv("HEXPROOF_AUDIT_OUTPUT", temporary.path().toUtf8());
        qputenv("HEXPROOF_AUDIT_WIDTH", windowed ? "900" : "");
        qputenv("HEXPROOF_AUDIT_HEIGHT", windowed ? "620" : "");
        qunsetenv("AUDIT_WIDTH");
        qunsetenv("AUDIT_HEIGHT");
        QFile driver(temporary.filePath(QStringLiteral("driver.qml")));
        QVERIFY(driver.open(QIODevice::WriteOnly));
        driver.write("import QtQml\nQtObject {}\n");
        driver.close();
        qputenv("HEXPROOF_AUDIT_DRIVER", driver.fileName().toUtf8());

        QQmlApplicationEngine engine;
        NativeAudit audit(&engine);
        QSignalSpy steps(&audit, &NativeAudit::stepRequested);
        engine.loadData(R"(
import QtQuick
Window {
    width: 1000; height: 700; visible: true
    MouseArea { objectName: "viewport"; anchors.fill: parent }
}
)");
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        QTRY_COMPARE(window->visibility(), windowed ? QWindow::Windowed : QWindow::Maximized);
        QFile startup(temporary.filePath(QStringLiteral("startup.json")));
        QTRY_VERIFY(startup.exists());
        QTRY_VERIFY(steps.size() >= 2);
        QVERIFY(startup.open(QIODevice::ReadOnly));
        const QVariantMap observed = QJsonDocument::fromJson(startup.readAll())
                                         .toVariant()
                                         .toMap()
                                         .value(QStringLiteral("window"))
                                         .toMap();
        const QString mode = windowed ? QStringLiteral("windowed") : QStringLiteral("maximized");
        QCOMPARE(observed.value(QStringLiteral("requestedWindowMode")).toString(), mode);
        QCOMPARE(observed.value(QStringLiteral("windowMode")).toString(), mode);
        QCOMPARE(observed.value(QStringLiteral("width")).toInt(), window->width());
        QCOMPARE(observed.value(QStringLiteral("height")).toInt(), window->height());
        QCOMPARE(observed.value(QStringLiteral("screenGeometry")).toList().size(), 4);
        QCOMPARE(observed.value(QStringLiteral("screenAvailableGeometry")).toList().size(), 4);
        if (windowed) {
            QCOMPARE(window->width(), 900);
            QCOMPARE(window->height(), 620);
        }
        QVERIFY(audit.click(audit.find(window, QStringLiteral("viewport"))));
        QFile actions(temporary.filePath(QStringLiteral("actions.jsonl")));
        QVERIFY(actions.open(QIODevice::ReadOnly));
        const QVariantMap action = QJsonDocument::fromJson(actions.readLine()).toVariant().toMap();
        QCOMPARE(action.value(QStringLiteral("window"))
                     .toMap()
                     .value(QStringLiteral("windowMode"))
                     .toString(),
                 mode);
    }

    void fileChooserUsesPathInput_data()
    {
        QTest::addColumn<bool>("exists");
        QTest::newRow("existing-file-is-accepted") << true;
        QTest::newRow("missing-file-is-not-accepted") << false;
    }

    void fileChooserUsesPathInput()
    {
        QFETCH(bool, exists);
        QTemporaryDir temporary;
        QVERIFY(temporary.isValid());
        qputenv("HEXPROOF_AUDIT_OUTPUT", temporary.path().toUtf8());
        qputenv("HEXPROOF_AUDIT_WIDTH", "900");
        qputenv("HEXPROOF_AUDIT_HEIGHT", "620");
        QFile driver(temporary.filePath(QStringLiteral("driver.qml")));
        QVERIFY(driver.open(QIODevice::WriteOnly));
        driver.write("import QtQml\nQtObject {}\n");
        driver.close();
        qputenv("HEXPROOF_AUDIT_DRIVER", driver.fileName().toUtf8());
        const QString source = temporary.filePath(QStringLiteral("catalog with spaces.sqlite"));
        QFile fixture(source);
        if (exists) {
            QVERIFY(fixture.open(QIODevice::WriteOnly));
            fixture.write("file chooser fixture");
            fixture.close();
        }

        QQmlApplicationEngine engine;
        NativeAudit audit(&engine);
        engine.loadData(R"(
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
Window {
    width: 900; height: 620; visible: true
    property url acceptedFile
    Button { objectName: "openFile"; text: "Import"; onClicked: chooser.open() }
    FileDialog {
        id: chooser
        objectName: "testFileChooser"
        options: FileDialog.DontUseNativeDialog
        onAccepted: acceptedFile = selectedFile
    }
}
)");
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(QTest::qWaitForWindowExposed(window));
        QVERIFY(audit.click(audit.find(window, QStringLiteral("openFile"))));
        QTRY_VERIFY(audit.fileDialogState(QStringLiteral("testFileChooser"))
                        .value(QStringLiteral("visible"))
                        .toBool());
        QTest::qWait(250);
        if (exists) {
            QVERIFY2(audit.chooseFile(QStringLiteral("testFileChooser"), source),
                     qPrintable(audit.lastError()));
            QTRY_COMPARE(window->property("acceptedFile").toUrl(), QUrl::fromLocalFile(source));
        } else {
            QVERIFY(!audit.chooseFile(QStringLiteral("testFileChooser"), source));
            QVERIFY(window->property("acceptedFile").toUrl().isEmpty());
        }
    }

    void selectorsAndInput()
    {
        QTemporaryDir temporary;
        QVERIFY(temporary.isValid());
        qputenv("HEXPROOF_AUDIT_OUTPUT", temporary.path().toUtf8());
        qputenv("HEXPROOF_AUDIT_WIDTH", "900");
        qputenv("HEXPROOF_AUDIT_HEIGHT", "620");
        const QString driverPath = temporary.filePath(QStringLiteral("driver.qml"));
        QFile driver(driverPath);
        QVERIFY(driver.open(QIODevice::WriteOnly));
        driver.write("import QtQml\nQtObject {}\n");
        driver.close();
        qputenv("HEXPROOF_AUDIT_DRIVER", driverPath.toUtf8());

        QQmlApplicationEngine engine;
        NativeAudit audit(&engine);
        engine.loadData(R"(
import QtQuick
import QtQuick.Controls.Basic
Window {
    width: 480; height: 360; visible: true
    property int clicks: 0
    property bool covered: true
    function beginTransition() { navigation.push(nextPage) }
    function openModal() { modalPopup.open() }
    function closeModal() { modalPopup.close() }
    Popup { id: modalPopup; x: 420; y: 400; width: 150; height: 150; modal: true; closePolicy: Popup.NoAutoClose }
    StackView {
        id: navigation
        x: 0; y: 210; width: 120; height: 100
        initialItem: Item {}
        pushEnter: Transition { NumberAnimation { property: "x"; from: 120; to: 0; duration: 400 } }
    }
    Component {
        id: nextPage
        Rectangle { objectName: "transitionTarget"; width: 120; height: 100 }
    }
    Rectangle {
        objectName: "clippedScope"
        width: 100; height: 100; clip: true
        Rectangle { objectName: "outside"; y: 120; width: 80; height: 40 }
    }
    Rectangle { objectName: "hidden"; visible: false; width: 80; height: 40 }
    Rectangle { objectName: "disabled"; enabled: false; x: 110; width: 80; height: 40 }
    Item {
        objectName: "group"
        y: 120; width: 100; height: 90
        Repeater {
            model: 2
            Rectangle {
                required property int index
                property string entityKey: String(index)
                objectName: "duplicate"
                x: index * 45; width: 40; height: 50
            }
        }
    }
    Rectangle {
        objectName: "target"
        x: 220; y: 20; width: 90; height: 50
        MouseArea { anchors.fill: parent; onClicked: parent.Window.window.clicks++ }
    }
    Rectangle {
        objectName: "cover"
        x: 220; y: 20; width: 90; height: 50
        visible: Window.window.covered
        MouseArea { anchors.fill: parent }
    }
    TextInput { objectName: "input"; x: 220; y: 120; width: 200; height: 50 }
    ComboBox { objectName: "combo"; x: 330; y: 220; width: 130; model: ["One", "Two", "Three"] }
    TextField { objectName: "paddedInput"; x: 130; y: 285; width: 200; height: 54; leftPadding: 14 }
}
)");
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        QCOMPARE(window->width(), 900);
        QCOMPARE(window->height(), 620);
        QCOMPARE(audit.observe(window).value(QStringLiteral("requestedWidth")).toInt(), 900);
        QVERIFY2(audit.activate(), qPrintable(audit.lastError()));
        QVERIFY(window->isActive());

        QVERIFY(!audit.find(window, QStringLiteral("hidden")));
        QVERIFY(!audit.find(window, QStringLiteral("disabled")));
        QVERIFY(!audit.find(window, QStringLiteral("outside")));
        QVERIFY(!audit.find(window, QStringLiteral("duplicate")));
        auto *group = audit.find(window, QStringLiteral("group"));
        QVERIFY(group);
        auto *entity = audit.find(group, QStringLiteral("duplicate"),
                                  {{QStringLiteral("entityKey"), QStringLiteral("1")}});
        QVERIFY(entity);
        QCOMPARE(entity->property("entityKey").toString(), QStringLiteral("1"));
        QVERIFY(!audit.find(window, QStringLiteral("target")));
        window->setProperty("covered", false);
        auto *target = audit.find(window, QStringLiteral("target"));
        QVERIFY2(target, qPrintable(audit.lastError()));
        QVERIFY(audit.click(target));
        QCOMPARE(window->property("clicks").toInt(), 1);

        auto *input = audit.find(window, QStringLiteral("input"));
        QVERIFY(input);
        QVERIFY(audit.click(input));
        QVERIFY(audit.type(QStringLiteral("English 中文")));
        QCOMPARE(input->property("text").toString(), QStringLiteral("English 中文"));
        QVERIFY(audit.key(Qt::Key_A, Qt::ControlModifier));
        QVERIFY(audit.type(QStringLiteral("Replacement")));
        QCOMPARE(input->property("text").toString(), QStringLiteral("Replacement"));

        QVERIFY(QMetaObject::invokeMethod(window, "beginTransition"));
        QVERIFY(!audit.find(window, QStringLiteral("transitionTarget")));
        QTRY_VERIFY(audit.find(window, QStringLiteral("transitionTarget")));

        auto *combo = audit.find(window, QStringLiteral("combo"));
        QVERIFY(combo);
        QVERIFY(audit.click(combo));
        QTest::qWait(150);
        QVERIFY2(audit.key(Qt::Key_Home), qPrintable(audit.lastError()));
        QVERIFY(audit.key(Qt::Key_Down));
        QVERIFY(audit.key(Qt::Key_Return));
        QCOMPARE(combo->property("currentIndex").toInt(), 1);

        auto *padded = audit.find(window, QStringLiteral("paddedInput"));
        QVERIFY2(padded, qPrintable(audit.lastError()));
        QVERIFY2(audit.click(padded, padded->width() - 12, padded->height() / 2),
                 qPrintable(audit.lastError()));
        QVERIFY(audit.type(QStringLiteral("Padded input")));
        QCOMPARE(padded->property("text").toString(), QStringLiteral("Padded input"));

        QVERIFY(QMetaObject::invokeMethod(window, "openModal"));
        QTest::qWait(150);
        QVERIFY(!audit.find(window, QStringLiteral("paddedInput")));
        QVERIFY(QMetaObject::invokeMethod(window, "closeModal"));
        QTRY_VERIFY(audit.find(window, QStringLiteral("paddedInput")));
        QVERIFY(audit.click(padded));
        QVERIFY(audit.key(Qt::Key_A, Qt::ControlModifier));
        QVERIFY(audit.type(QStringLiteral("After modal")));
        QCOMPARE(padded->property("text").toString(), QStringLiteral("After modal"));

        const QVariantList items = audit.observe(window).value(QStringLiteral("items")).toList();
        bool disabledObserved = false;
        for (const QVariant &value : items) {
            const QVariantMap item = value.toMap();
            if (item.value(QStringLiteral("objectName")) == QStringLiteral("disabled")) {
                disabledObserved = true;
                QCOMPARE(item.value(QStringLiteral("enabled")).toBool(), false);
            }
        }
        QVERIFY(disabledObserved);
        QVERIFY(audit.record(QStringLiteral("checks"), QVariantList{true, QStringLiteral("ok")}));
        QVERIFY(!audit.record(QStringLiteral("../escape"), QVariantMap{}));
        QVERIFY(QDir(temporary.path()).mkdir(QStringLiteral("blocked.json")));
        QVERIFY(!audit.record(QStringLiteral("blocked"), QVariantMap{}));
        QVERIFY(QDir(temporary.path()).mkdir(QStringLiteral("blocked-image.png")));
        QVERIFY(!audit.capture(window, QStringLiteral("blocked-image")));
        QCOMPARE(audit.observe(window).value(QStringLiteral("artifactFailures")).toInt(), 3);
        QVERIFY(QFile::exists(temporary.filePath(QStringLiteral("actions.jsonl"))));
    }
};

QTEST_MAIN(NativeAuditTest)
#include "native_audit_test.moc"
