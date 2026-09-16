// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardImageProvider.h"

#include <QDir>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QScopedPointer>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::CardImageProvider;

class TestCardImageProvider final : public QObject
{
    Q_OBJECT

  private slots:
    void repairedImageReloadsInQml_data() const;
    void repairedImageReloadsInQml() const;
    void evictedSourceNeverReusesAnOldRevision() const;
};

void TestCardImageProvider::repairedImageReloadsInQml_data() const
{
    QTest::addColumn<bool>("initiallyMissing");
    QTest::newRow("decoded") << false;
    QTest::newRow("missing") << true;
}

void TestCardImageProvider::repairedImageReloadsInQml() const
{
    QFETCH(bool, initiallyMissing);
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString path = storage.filePath(u"card.png"_s);
    QImage pixels(32, 44, QImage::Format_RGB32);
    pixels.fill(Qt::red);
    if (!initiallyMissing)
        QVERIFY(pixels.save(path));

    QQmlEngine engine;
    auto *provider = new CardImageProvider;
    engine.addImageProvider(u"card-table"_s, provider);
    QQmlComponent component(&engine);
    component.setData(R"(
        import QtQuick
        Image {
            width: 320; height: 448
            property bool ready: status === Image.Ready
            property bool failed: status === Image.Error
        }
    )",
                      QUrl());
    QScopedPointer<QObject> image(component.create());
    QVERIFY2(image, qPrintable(component.errorString()));
    QQuickWindow window;
    window.setTitle(u"Hexproof image recovery verification"_s);
    window.resize(320, 448);
    auto *item = qobject_cast<QQuickItem *>(image.get());
    QVERIFY(item);
    item->setParentItem(window.contentItem());
    window.show();
    if (initiallyMissing)
        QTest::ignoreMessage(QtWarningMsg,
                             QRegularExpression(u".*Failed to get image from provider.*"_s));
    const QString originalSource = provider->sourceForPath(path);
    image->setProperty("source", originalSource);
    QTRY_VERIFY(image->property(initiallyMissing ? "failed" : "ready").toBool());

    pixels.fill(Qt::blue);
    QVERIFY(pixels.save(path));
    provider->invalidatePath(path);
    const QString repairedSource = provider->sourceForPath(path);
    image->setProperty("source", repairedSource);
    QTRY_VERIFY(image->property("ready").toBool());
    QVERIFY(repairedSource != originalSource);
    QCOMPARE(
        provider->requestImage(QUrl(repairedSource).path().mid(1), nullptr, {}).pixelColor(0, 0),
        QColor(Qt::blue));
    // A native invocation can retain an owned-window rendering artifact. The
    // ordinary offscreen regression needs no desktop or artifact directory.
    const QString artifactRoot = qEnvironmentVariable("HEXPROOF_TEST_ARTIFACT_DIR");
    if (!artifactRoot.isEmpty()) {
        QTRY_COMPARE(window.grabWindow().pixelColor(160, 224), QColor(Qt::blue));
        QVERIFY(
            window.grabWindow().save(QDir(artifactRoot)
                                         .filePath(initiallyMissing ? u"recovered-missing.png"_s
                                                                    : u"replaced-decoded.png"_s)));
    }
}

void TestCardImageProvider::evictedSourceNeverReusesAnOldRevision() const
{
    CardImageProvider provider;
    const QString first = provider.sourceForPath(u"/unused/first.png"_s);
    for (int index = 0; index < 5'000; ++index)
        provider.sourceForPath(u"/unused/%1.png"_s.arg(index));
    const QString current = provider.sourceForPath(u"/unused/first.png"_s);
    QVERIFY(current != first);
    provider.invalidateAll();
    QVERIFY(provider.sourceForPath(u"/unused/first.png"_s) != current);
}

QTEST_MAIN(TestCardImageProvider)
#include "cardimageprovider_test.moc"
