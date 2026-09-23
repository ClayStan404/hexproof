// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/PublicContentSchema.h"
#include "services/PublicContentService.h"

#include <QBuffer>
#include <QDirIterator>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;
using namespace hexproof::client;
using namespace hexproof::client::public_content;

namespace {
QByteArray json(const QJsonObject &object)
{
    return QJsonDocument(object).toJson();
}

class ContentHost : public QTcpServer
{
  public:
    QHash<QString, QByteArray> files;
    QHash<QString, int> requests;
    QHash<QString, int> bodies;
    QSet<QString> held;
    QList<QPointer<QTcpSocket>> waiting;
    QJsonObject sponsors{
        {u"schemaVersion"_s, 1}, {u"revision"_s, 2}, {u"sponsors"_s, QJsonArray{}}};
    QJsonObject news{{u"schemaVersion"_s, 1},
                     {u"revision"_s, 2},
                     {u"display"_s, QJsonObject{{u"mode"_s, u"recent"_s},
                                                {u"recentDays"_s, 90},
                                                {u"selectedIds"_s, QJsonArray{}}}},
                     {u"announcements"_s, QJsonArray{}}};

    ContentHost()
    {
        listen(QHostAddress::LocalHost);
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (auto *socket = nextPendingConnection()) {
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket]() {
                    const auto request =
                        socket->property("request").toByteArray() + socket->readAll();
                    socket->setProperty("request", request);
                    if (!request.contains("\r\n\r\n") || socket->property("answered").toBool())
                        return;
                    socket->setProperty("answered", true);
                    const auto path = QString::fromLatin1(request.split(' ').value(1));
                    ++requests[path];
                    if (held.contains(path)) {
                        waiting.append(socket);
                        return;
                    }
                    const auto bytes = files.value(path);
                    const auto etag = '"' + digest(bytes) + '"';
                    const bool unchanged = request.contains("If-None-Match: " + etag);
                    const auto status = !files.contains(path) ? "404 Not Found"
                                        : unchanged           ? "304 Not Modified"
                                                              : "200 OK";
                    const auto body = unchanged ? QByteArray{} : bytes;
                    if (!body.isEmpty())
                        ++bodies[path];
                    socket->write(QByteArray("HTTP/1.1 ") + status + "\r\nETag: " + etag +
                                  "\r\nContent-Length: " + QByteArray::number(body.size()) +
                                  "\r\nConnection: close\r\n\r\n" + body);
                    socket->disconnectFromHost();
                });
            }
        });
    }

    QStringList sources() const
    {
        return {u"http://127.0.0.1:%1/index.json"_s.arg(serverPort())};
    }

    void publish(int revision)
    {
        QJsonObject index{{u"schemaVersion"_s, 1}, {u"revision"_s, revision}};
        for (const auto &kind : {u"sponsors"_s, u"announcements"_s}) {
            const auto document = kind == u"sponsors"_s ? sponsors : news;
            const auto bytes = json(document);
            const auto path = kind + u".json"_s;
            files[u'/' + path] = bytes;
            index[kind] = QJsonObject{{u"revision"_s, document.value(u"revision"_s)},
                                      {u"path"_s, path},
                                      {u"sha256"_s, QString::fromLatin1(digest(bytes))}};
        }
        files[u"/index.json"_s] = json(index);
    }

    QJsonObject sponsor(const QString &id, bool withAvatar = true)
    {
        QJsonObject entry{{u"id"_s, id},
                          {u"name"_s, id},
                          {u"tier"_s, u"ragavan"_s},
                          {u"profileUrl"_s, u"https://example.com/supporter"_s}};
        if (withAvatar) {
            QImage image(16, 16, QImage::Format_RGB32);
            image.fill(Qt::green);
            QBuffer buffer;
            buffer.open(QIODevice::WriteOnly);
            image.save(&buffer, "PNG");
            files[u"/avatars/shared.png"_s] = buffer.data();
            entry[u"avatar"_s] =
                QJsonObject{{u"path"_s, u"avatars/shared.png"_s},
                            {u"sha256"_s, QString::fromLatin1(digest(buffer.data()))}};
        }
        return entry;
    }
};

QJsonObject announcement(const QString &id, int daysAgo = 0)
{
    return {{u"id"_s, id},
            {u"notificationRevision"_s, 1},
            {u"publishedAt"_s,
             QDateTime::currentDateTimeUtc().addDays(-daysAgo).addSecs(-60).toString(Qt::ISODate)},
            {u"title"_s, QJsonObject{{u"en"_s, id}, {u"zh"_s, u"公告："_s + id}}},
            {u"body"_s,
             QJsonObject{{u"en"_s, u"Full announcement body"_s}, {u"zh"_s, u"完整公告正文"_s}}}};
}

QStringList cachedFiles(const QString &root, const QString &pattern)
{
    QStringList result;
    QDirIterator iterator(root, {pattern}, QDir::Files, QDirIterator::Subdirectories);
    while (iterator.hasNext())
        result.append(iterator.next());
    return result;
}

bool write(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}
} // namespace

class TestPublicContent : public QObject
{
    Q_OBJECT
  private slots:
    void snapshotCacheAndConditionalRefresh()
    {
        ContentHost host;
        QTemporaryDir root;
        host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"alice"_s)};
        host.news[u"announcements"_s] = QJsonArray{announcement(u"maintenance"_s)};
        host.publish(1);
        {
            PublicContentService service(root.path(), host.sources());
            service.start();
            QTRY_VERIFY(!service.refreshing());
            QVERIFY(!service.refreshFailed());
            QTRY_VERIFY(service.sponsors()
                            .first()
                            .toMap()
                            .value(u"avatarSource"_s)
                            .toString()
                            .startsWith(u"file:"_s));
            QCOMPARE(service.sponsors().size(), 1);
            QCOMPARE(service.takeSponsorAnnouncement(), QStringList{u"alice"_s});
            QVERIFY(service.takeSponsorAnnouncement().isEmpty());
            QVERIFY(service.acknowledgeSponsors({u"alice"_s}));
            QCOMPARE(service.unreadCount(), 1);
            QVERIFY(service.markRead(u"maintenance"_s));
            service.refresh(true);
            QTRY_VERIFY(!service.refreshing());
            QCOMPARE(host.requests.value(u"/index.json"_s), 2);
            QCOMPARE(host.bodies.value(u"/index.json"_s), 1);
            QCOMPARE(host.requests.value(u"/sponsors.json"_s), 1);
            QCOMPARE(host.requests.value(u"/announcements.json"_s), 1);
            QCOMPARE(host.requests.value(u"/avatars/shared.png"_s), 1);
        }
        PublicContentService restarted(root.path(), host.sources());
        QCOMPARE(restarted.sponsors().size(), 1);
        QCOMPARE(restarted.unreadCount(), 0);
        QVERIFY(restarted.newSponsorIds().isEmpty());
        restarted.start();
        QTRY_VERIFY(!restarted.refreshing());
        QVERIFY(restarted.takeSponsorAnnouncement().isEmpty());
        QCOMPARE(host.requests.value(u"/sponsors.json"_s), 1);
        QCOMPARE(host.requests.value(u"/avatars/shared.png"_s), 1);
    }

    void removesExpiredSponsorsAndOnlyUnusedAvatars()
    {
        ContentHost host;
        QTemporaryDir root;
        host.sponsors[u"sponsors"_s] =
            QJsonArray{host.sponsor(u"expired"_s), host.sponsor(u"active"_s)};
        host.publish(1);
        {
            PublicContentService service(root.path(), host.sources());
            service.start();
            QTRY_COMPARE(cachedFiles(root.path(), u"*.image"_s).size(), 1);
            host.sponsors[u"revision"_s] = 3;
            host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"active"_s)};
            host.publish(2);
            service.refresh(true);
            QTRY_VERIFY(!service.refreshing());
            QCOMPARE(service.sponsors().size(), 1);
            QCOMPARE(service.sponsors().first().toMap().value(u"id"_s).toString(), u"active"_s);
            QCOMPARE(cachedFiles(root.path(), u"*.image"_s).size(), 1);
            QFile cached(cachedFiles(root.path(), u"sponsors.json"_s).first());
            QVERIFY(cached.open(QIODevice::ReadOnly));
            const auto stored = QJsonDocument::fromJson(cached.readAll()).object();
            QVERIFY(!QByteArray::fromBase64(stored.value(u"payload"_s).toString().toLatin1())
                         .contains("expired"));
            cached.close();
            host.sponsors[u"revision"_s] = 4;
            host.sponsors[u"sponsors"_s] = QJsonArray{};
            host.publish(3);
            service.refresh(true);
            QTRY_VERIFY(!service.refreshing());
            QVERIFY(service.sponsors().isEmpty());
            QVERIFY(service.newSponsorIds().isEmpty());
            QVERIFY(cachedFiles(root.path(), u"*.image"_s).isEmpty());
        }
        PublicContentService restarted(root.path(), host.sources());
        QVERIFY(restarted.sponsors().isEmpty());
        QVERIFY(cachedFiles(root.path(), u"*.image"_s).isEmpty());
    }

    void offlineDeletionAndDamagedCacheRecovery()
    {
        ContentHost host;
        const auto sources = host.sources();
        QTemporaryDir root;
        host.publish(1);
        {
            PublicContentService service(root.path(), sources);
            service.start();
            QTRY_VERIFY(!service.refreshing());
            QVERIFY(service.sponsors().isEmpty());
        }
        {
            PublicContentService restarted(root.path(), sources);
            QVERIFY(restarted.sponsors().isEmpty());
            QVERIFY(write(cachedFiles(root.path(), u"sponsors.json"_s).first(), "broken"));
        }
        PublicContentService repaired(root.path(), sources);
        QVERIFY(repaired.sponsors().isEmpty());
        repaired.start();
        QTRY_VERIFY(!repaired.refreshing());
        QVERIFY(!repaired.refreshFailed());
        QCOMPARE(host.requests.value(u"/sponsors.json"_s), 2);
        QCOMPARE(host.bodies.value(u"/index.json"_s), 1);
        host.close();
        PublicContentService offline(root.path(), sources);
        offline.start();
        QTRY_VERIFY(!offline.refreshing());
        QVERIFY(offline.refreshFailed());
        QVERIFY(offline.sponsors().isEmpty());
    }

    void failedDownloadKeepsRosterAndRetriesUninstalledRevision()
    {
        ContentHost host;
        QTemporaryDir root;
        host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"retained"_s, false)};
        host.publish(1);
        PublicContentService service(root.path(), host.sources());
        service.start();
        QTRY_VERIFY(!service.refreshing());
        host.sponsors[u"sponsors"_s] = QJsonArray{};
        host.sponsors[u"revision"_s] = 3;
        host.publish(2);
        const auto correct = host.files.take(u"/sponsors.json"_s);
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QVERIFY(service.refreshFailed());
        QCOMPARE(service.sponsors().size(), 1);
        host.files[u"/sponsors.json"_s] = correct;
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QVERIFY(!service.refreshFailed());
        QVERIFY(service.sponsors().isEmpty());
        QCOMPARE(host.bodies.value(u"/index.json"_s), 2);
        // Same-revision edits and stale catalogs cannot restore a retired entry.
        host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"retained"_s, false)};
        host.publish(3);
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QVERIFY(service.refreshFailed());
        QVERIFY(service.sponsors().isEmpty());
    }

    void restoredOldCacheCannotResurrectRetiredSponsors()
    {
        ContentHost host;
        const auto sources = host.sources();
        QTemporaryDir root;
        host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"retired"_s, false)};
        host.publish(1);
        QString cache;
        QByteArray oldCache;
        {
            PublicContentService service(root.path(), sources);
            service.start();
            QTRY_VERIFY(!service.refreshing());
            cache = cachedFiles(root.path(), u"sponsors.json"_s).first();
            QFile file(cache);
            QVERIFY(file.open(QIODevice::ReadOnly));
            oldCache = file.readAll();
            file.close();
            host.sponsors[u"revision"_s] = 3;
            host.sponsors[u"sponsors"_s] = QJsonArray{};
            host.publish(2);
            service.refresh(true);
            QTRY_VERIFY(!service.refreshing());
            QVERIFY(service.sponsors().isEmpty());
        }
        QVERIFY(write(cache, oldCache));
        host.close();
        PublicContentService offline(root.path(), sources);
        QVERIFY(offline.sponsors().isEmpty());
        offline.start();
        QTRY_VERIFY(!offline.refreshing());
        QVERIFY(offline.sponsors().isEmpty());
    }

    void removalCancelsPendingAvatar()
    {
        ContentHost host;
        QTemporaryDir root;
        host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"expired"_s)};
        host.held.insert(u"/avatars/shared.png"_s);
        host.publish(1);
        PublicContentService service(root.path(), host.sources());
        service.start();
        QTRY_COMPARE(host.waiting.size(), 1);
        QCOMPARE(service.takeSponsorAnnouncement(), QStringList{u"expired"_s});
        host.sponsors[u"sponsors"_s] = QJsonArray{};
        host.sponsors[u"revision"_s] = 3;
        host.publish(2);
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QVERIFY(service.sponsors().isEmpty());
        QVERIFY(cachedFiles(root.path(), u"*.image"_s).isEmpty());
        QCOMPARE(host.requests.value(u"/avatars/shared.png"_s), 1);
        // Closing a popup after its roster changed still acknowledges the IDs it showed.
        QVERIFY(service.acknowledgeSponsors({u"expired"_s}));
        host.sponsors[u"revision"_s] = 4;
        host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"expired"_s, false)};
        host.publish(3);
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QVERIFY(service.newSponsorIds().isEmpty());
    }

    void newsHistoryVisibilityAndReadRevisions()
    {
        ContentHost host;
        QTemporaryDir root;
        auto current = announcement(u"current"_s);
        auto old = announcement(u"old"_s, 200);
        auto withdrawn = announcement(u"withdrawn"_s);
        withdrawn[u"withdrawn"_s] = true;
        host.news[u"announcements"_s] =
            QJsonArray{current, old, withdrawn, announcement(u"future"_s, -1)};
        host.publish(1);
        PublicContentService service(root.path(), host.sources());
        service.start();
        QTRY_VERIFY(!service.refreshing());
        QCOMPARE(service.currentAnnouncements().size(), 1);
        QCOMPARE(service.historicalAnnouncements().size(), 1);
        QCOMPARE(service.unreadCount(), 1);
        service.setLanguage(u"zh"_s);
        QCOMPARE(service.latestUnreadTitle(), u"公告：current"_s);
        QVERIFY(service.markRead(u"current"_s));
        QCOMPARE(service.unreadCount(), 0);
        current[u"body"_s] = QJsonObject{{u"en"_s, u"Corrected spelling"_s}};
        host.news[u"revision"_s] = 3;
        host.news[u"announcements"_s] = QJsonArray{current, old};
        host.publish(2);
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QCOMPARE(service.unreadCount(), 0);
        current[u"notificationRevision"_s] = 2;
        host.news[u"revision"_s] = 4;
        host.news[u"announcements"_s] = QJsonArray{current, old};
        host.publish(3);
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QCOMPARE(service.unreadCount(), 1);
        QVERIFY(service.markAllRead());
        host.news[u"revision"_s] = 5;
        host.news[u"announcements"_s] = QJsonArray{old};
        host.news[u"display"_s] = QJsonObject{{u"mode"_s, u"selected"_s},
                                              {u"recentDays"_s, 90},
                                              {u"selectedIds"_s, QJsonArray{u"old"_s}}};
        host.publish(4);
        service.refresh(true);
        QTRY_VERIFY(!service.refreshing());
        QCOMPARE(service.currentAnnouncements().first().toMap().value(u"id"_s).toString(),
                 u"old"_s);
        QCOMPARE(service.historicalAnnouncements().size(), 1);
        QVERIFY(service.markAllRead());
        PublicContentService restarted(root.path(), host.sources());
        QCOMPARE(restarted.historicalAnnouncements().size(), 1);
        QCOMPARE(restarted.unreadCount(), 0);
        old[u"withdrawn"_s] = true;
        host.news[u"revision"_s] = 6;
        host.news[u"announcements"_s] = QJsonArray{old};
        host.publish(5);
        restarted.refresh(true);
        QTRY_VERIFY(!restarted.refreshing());
        QVERIFY(restarted.currentAnnouncements().isEmpty());
        QCOMPARE(restarted.historicalAnnouncements().size(), 1);
    }

    void migratesAcknowledgementsAndKeepsLaterNewcomersPending()
    {
        QTemporaryDir root;
        QVERIFY(write(root.filePath(u"settings.json"_s),
                      "{\"sponsorAnnouncementId\":\"sponsors:2.0.5\"}"));
        ContentHost host;
        host.sponsors[u"sponsors"_s] = QJsonArray{host.sponsor(u"newcomer"_s, false)};
        host.publish(1);
        {
            PublicContentService service(root.path(), host.sources());
            QVERIFY(service.newSponsorIds().isEmpty());
            service.start();
            QTRY_VERIFY(!service.refreshing());
            QCOMPARE(service.takeSponsorAnnouncement(), QStringList{u"newcomer"_s});
            host.sponsors[u"revision"_s] = 3;
            host.sponsors[u"sponsors"_s] =
                QJsonArray{host.sponsor(u"newcomer"_s, false), host.sponsor(u"later"_s, false)};
            host.publish(2);
            service.refresh(true);
            QTRY_VERIFY(!service.refreshing());
            QVERIFY(service.acknowledgeSponsors({u"newcomer"_s}));
            QCOMPARE(service.newSponsorIds(), QStringList{u"later"_s});
            QVERIFY(service.takeSponsorAnnouncement().isEmpty());
        }
        PublicContentService restarted(root.path(), host.sources());
        restarted.start();
        QTRY_VERIFY(!restarted.refreshing());
        QCOMPARE(restarted.takeSponsorAnnouncement(), QStringList{u"later"_s});
    }

    void rejectsUnsafeData()
    {
        ContentHost host;
        auto entry = host.sponsor(u"valid"_s, false);
        host.sponsors[u"sponsors"_s] = QJsonArray{entry};
        QVERIFY(validDocument(u"sponsors"_s, host.sponsors));
        entry[u"profileUrl"_s] = u"file:///tmp/unsafe"_s;
        host.sponsors[u"sponsors"_s] = QJsonArray{entry};
        QVERIFY(!validDocument(u"sponsors"_s, host.sponsors));
        for (const auto &path : {u"../private"_s, u"/absolute"_s, u"https://elsewhere/a"_s,
                                 u"images/%2e%2e/file"_s, u"images//file"_s, u"image?x"_s})
            QVERIFY(!validPath(path));
        QVERIFY(!validSource(QUrl(u"http://example.com/index.json"_s)));
        QVERIFY(!validSource(QUrl(u"https://user:pass@example.com/index.json"_s)));
        auto invalid = announcement(u"date"_s);
        invalid[u"publishedAt"_s] = u"2026-09-23T12:00:00"_s;
        QVERIFY(!validAnnouncement(invalid));
    }
};

QTEST_GUILESS_MAIN(TestPublicContent)
#include "publiccontent_test.moc"
