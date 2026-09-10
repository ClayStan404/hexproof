// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/LimitedDeckDraftStore.h"

#include <QFile>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QtTest>
#include <limits>

using hexproof::client::LimitedDeckDraftStore;

class LimitedDeckDraftStoreTest : public QObject
{
    Q_OBJECT
  private slots:
    void roundTripsCommanderSelectionAndArbitraryDraftMetadata()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QVariantMap draft{
            {"mainboardInstanceIds", QVariantList{"card-b", "card-a", "card-c"}},
            {"commanderInstanceIds", QVariantList{"card-b", "piper-fallback-1"}},
            {"commanderColors",
             QVariantList{QVariantMap{{"instanceId", "piper-fallback-1"}, {"color", "U"}}}},
            {"basics", QVariantMap{{"Forest", 19}, {"Island", 17}}},
            {"initialPoolChosen", true},
            {"localMetadata",
             QVariantMap{{"sortOrder", "mana"}, {"filter", QVariantList{"U", "G"}}}}};
        {
            LimitedDeckDraftStore store(dir.path());
            store.saveDraft("ws://localhost:1/ws", "COMMANDER", "p-1", draft);
            QVERIFY(store.flush());
        }
        {
            LimitedDeckDraftStore restored(dir.path());
            QCOMPARE(restored.loadDraft("ws://localhost:1/ws", "COMMANDER", "p-1"), draft);
            QVERIFY(restored.loadDraft("ws://localhost:1/ws", "COMMANDER", "p-2").isEmpty());
            QVariantMap cleared = draft;
            cleared.insert("commanderInstanceIds", QVariantList{});
            cleared.insert("commanderColors", QVariantList{});
            restored.saveDraft("ws://localhost:1/ws", "COMMANDER", "p-1", cleared);
            QVERIFY(restored.flush());
        }
        LimitedDeckDraftStore afterClear(dir.path());
        const auto restored = afterClear.loadDraft("ws://localhost:1/ws", "COMMANDER", "p-1");
        QVERIFY(restored.contains("commanderInstanceIds"));
        QVERIFY(restored.value("commanderInstanceIds").toList().isEmpty());
        QVERIFY(restored.value("commanderColors").toList().isEmpty());
        QCOMPARE(restored.value("mainboardInstanceIds"), draft.value("mainboardInstanceIds"));
        QCOMPARE(restored.value("localMetadata"), draft.value("localMetadata"));
    }

    void restoresAfterRestartAndIsolatesIdentity()
    {
        QTemporaryDir dir;
        const QVariantMap draft{{"mainboardInstanceIds", QVariantList{"card-a", "card-b"}},
                                {"basics", QVariantMap{{"Island", 17}}},
                                {"initialPoolChosen", true}};
        {
            LimitedDeckDraftStore store(dir.path());
            store.saveDraft("ws://localhost:1/ws", "EVENT1", "p-1", draft);
            QCOMPARE(store.loadDraft("ws://localhost:1/ws", "EVENT1", "p-1"), draft);
            QVERIFY(store.loadDraft("ws://localhost:2/ws", "EVENT1", "p-1").isEmpty());
            QVERIFY(store.loadDraft("ws://localhost:1/ws", "EVENT2", "p-1").isEmpty());
            QVERIFY(store.loadDraft("ws://localhost:1/ws", "EVENT1", "p-2").isEmpty());
        }
        LimitedDeckDraftStore reloaded(dir.path());
        QCOMPARE(reloaded.loadDraft("ws://localhost:1/ws", "EVENT1", "p-1"), draft);
        reloaded.removeDraft("ws://localhost:1/ws", "EVENT1", "p-1");
        QVERIFY(reloaded.flush());
        LimitedDeckDraftStore afterSubmit(dir.path());
        QVERIFY(afterSubmit.loadDraft("ws://localhost:1/ws", "EVENT1", "p-1").isEmpty());
    }

    void coalescesAndBoundsRecords()
    {
        QTemporaryDir dir;
        LimitedDeckDraftStore store(dir.path());
        for (int i = 0; i < 40; ++i) {
            store.saveDraft("server", QString::number(i), "p-1",
                            {{"mainboardInstanceIds", QVariantList{}}});
            QVERIFY(!store.loadDraft("server", QString::number(i), "p-1").isEmpty());
        }
        store.saveDraft("", "event", "p-1", {{"bad", true}});
        QVERIFY(store.flush());
        QFile file(dir.filePath("limited-deck-drafts.json"));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const auto json = QJsonDocument::fromJson(file.readAll()).object();
        QCOMPARE(json.value("drafts").toObject().size(), 32);
        store.saveDraft("server", "last", "p-1", {{"value", 1}});
        store.saveDraft("server", "last", "p-1", {{"value", 2}});
        QTest::qWait(350);
        LimitedDeckDraftStore reloaded(dir.path());
        QCOMPARE(reloaded.loadDraft("server", "last", "p-1").value("value").toInt(), 2);
    }

    void boundsRecordsWithExtremeStoredTimestamps()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QJsonObject entries;
        for (int index = 0; index < 40; ++index) {
            entries.insert(QString::number(index),
                           QJsonObject{{"savedAt", std::numeric_limits<double>::max()},
                                       {"draft", QJsonObject{{"value", index}}}});
        }
        QFile file(dir.filePath("limited-deck-drafts.json"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        const QByteArray original =
            QJsonDocument(QJsonObject{{"schemaVersion", 1}, {"drafts", entries}}).toJson();
        QCOMPARE(file.write(original), original.size());
        file.close();

        LimitedDeckDraftStore store(dir.path());
        store.saveDraft("server", "current", "player", {{"value", 42}});
        QVERIFY(store.flush());
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(QJsonDocument::fromJson(file.readAll()).object().value("drafts").toObject().size(),
                 32);
        QCOMPARE(store.loadDraft("server", "current", "player").value("value").toInt(), 42);
    }

    void reportsIoFailureAndRetainsInMemoryDraft()
    {
        QTemporaryDir dir;
        QFile blocker(dir.filePath("blocked"));
        QVERIFY(blocker.open(QIODevice::WriteOnly));
        blocker.close();
        LimitedDeckDraftStore store(blocker.fileName());
        store.saveDraft("server", "event", "p-1", {{"value", 3}});
        QVERIFY(!store.flush());
        QVERIFY(!store.lastError().isEmpty());
        QCOMPARE(store.loadDraft("server", "event", "p-1").value("value").toInt(), 3);
    }

    void preservesUnreadableStorage()
    {
        QTemporaryDir dir;
        QFile file(dir.filePath("limited-deck-drafts.json"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        const QByteArray original = "{broken drafts";
        QCOMPARE(file.write(original), original.size());
        file.close();
        {
            LimitedDeckDraftStore store(dir.path());
            QVERIFY(!store.lastError().isEmpty());
            store.saveDraft("server", "event", "p-1", {{"value", 3}});
            QVERIFY(!store.flush());
            QCOMPARE(store.loadDraft("server", "event", "p-1").value("value").toInt(), 3);
        }
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), original);
    }
};

QTEST_GUILESS_MAIN(LimitedDeckDraftStoreTest)
#include "limiteddeckdraftstore_test.moc"
