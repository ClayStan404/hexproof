// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ServerDirectory.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

#include <algorithm>
#include <functional>

using namespace Qt::StringLiterals;
using hexproof::client::ServerDirectory;

namespace {

void clearServerOverrides()
{
    for (int index = 1; index <= 32; ++index)
        qunsetenv(qPrintable(u"HEXPROOF_SERVER_%1_URL"_s.arg(index)));
    qunsetenv("HEXPROOF_SERVER_DIRECTORY_FILE");
    qunsetenv("HEXPROOF_SERVER_DIRECTORY_URL");
    qunsetenv("HEXPROOF_SERVER_DIRECTORY_CACHE");
}

// A loopback HTTP fixture exercises the real network, mirror and disk-cache paths.
class DirectoryHost : public QTcpServer
{
  public:
    QByteArray primary = "unavailable";
    QByteArray mirror;
    QByteArray healthCapabilities;
    std::function<void()> beforeHealthResponse;
    QStringList requests;

    DirectoryHost()
    {
        listen(QHostAddress::LocalHost, 0);
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (QTcpSocket *socket = nextPendingConnection()) {
                socket->setParent(this);
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket]() {
                    QByteArray request =
                        socket->property("request").toByteArray() + socket->readAll();
                    socket->setProperty("request", request);
                    if (!request.contains("\r\n\r\n") || socket->property("answered").toBool())
                        return;
                    socket->setProperty("answered", true);
                    const QString path = QString::fromLatin1(request.split(' ').value(1));
                    requests.append(path);
                    const QByteArray body = path == u"/catalog"_s  ? primary
                                            : path == u"/mirror"_s ? mirror
                                                                   : QByteArray{};
                    QByteArray headers;
                    if (path.endsWith(u"/healthz"_s)) {
                        if (beforeHealthResponse)
                            beforeHealthResponse();
                        if (!healthCapabilities.isEmpty())
                            headers = "X-Hexproof-Capabilities: " + healthCapabilities + "\r\n";
                    }
                    socket->write(
                        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " +
                        QByteArray::number(body.size()) + "\r\n" + headers +
                        "Connection: close\r\n\r\n" + body);
                    socket->disconnectFromHost();
                });
            }
        });
    }

    QString url(const QString &path) const
    {
        return u"http://127.0.0.1:%1%2"_s.arg(serverPort()).arg(path);
    }

    QJsonObject entry(const QString &id, bool forge = true) const
    {
        return {{u"id"_s, id},
                {u"name"_s, id},
                {u"forge"_s, forge},
                {u"url"_s, u"ws://127.0.0.1:%1/%2/ws"_s.arg(serverPort()).arg(id)}};
    }
};

QJsonObject catalog(int revision, const QJsonArray &entries, const QJsonArray &sources = {})
{
    return {{u"schemaVersion"_s, 2},
            {u"revision"_s, revision},
            {u"directoryUrls"_s, sources},
            {u"servers"_s, entries}};
}

bool writeCatalog(const QString &path, const QJsonObject &document)
{
    QFile file(path);
    const QByteArray bytes = QJsonDocument(document).toJson();
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

void isolateCatalog(const QTemporaryDir &directory)
{
    qputenv("HEXPROOF_SERVER_DIRECTORY_FILE", directory.filePath(u"bootstrap.json"_s).toUtf8());
    qputenv("HEXPROOF_SERVER_DIRECTORY_CACHE", directory.filePath(u"cache.json"_s).toUtf8());
}

// The embedded production fleet can shrink at any time, so tests that assume
// the retired five-slot bootstrap shape must isolate their own catalog.
QJsonArray fiveSlotEntries()
{
    QJsonArray entries;
    const QStringList urls = {u"wss://primary.example/ws"_s, u"wss://secondary.example/ws"_s,
                              u"wss://tertiary.example/ws"_s, u"wss://quaternary.example/ws"_s,
                              u"wss://test.example/test/ws"_s};
    for (int index = 0; index < urls.size(); ++index) {
        entries.append(QJsonObject{{u"id"_s, u"server-%1"_s.arg(index + 1)},
                                   {u"name"_s, u"Server %1"_s.arg(index + 1)},
                                   {u"forge"_s, true},
                                   {u"url"_s, urls[index]}});
    }
    return entries;
}

bool isolateFiveSlotCatalog(const QTemporaryDir &directory)
{
    return writeCatalog(directory.filePath(u"bootstrap.json"_s), catalog(1, fiveSlotEntries()));
}

QJsonObject capabilities(bool forge, bool hosting)
{
    return {{u"forge"_s, forge},
            {u"playerHosting"_s, hosting},
            {u"directPeer"_s, hosting},
            {u"hostMigration"_s, hosting}};
}

} // namespace

class TestServerDirectory : public QObject
{
    Q_OBJECT

  private slots:
    void init();
    void cleanup();
    void exposesDefaultEndpoints() const;
    void loadsExternalDirectory() const;
    void appliesEnvironmentOverrides() const;
    void mapsConfiguredAndCustomUrls() const;
    void exposesInitialLatencyState() const;
    void probesConfiguredHealthEndpoints() const;
    void editingCustomEndpointPreservesConfiguredProbes() const;
    void refreshesViaMirrorAndRecoversCache() const;
    void rejectsInvalidUpdates_data() const;
    void rejectsInvalidUpdates() const;
    void preservesCustomEndpointAndObservedCapabilities() const;
    void discoversIndependentHostingCapabilities() const;
    void welcomeOverridesAnOlderProbe() const;
};

void TestServerDirectory::init()
{
    clearServerOverrides();
}

void TestServerDirectory::cleanup()
{
    clearServerOverrides();
}

void TestServerDirectory::exposesDefaultEndpoints() const
{
    ServerDirectory directory;
    QSet<QString> endpoints;
    for (int index = 0; index < directory.configuredServerCount(); ++index) {
        const QUrl url(directory.serverUrl(index));
        QVERIFY(url.isValid());
        QVERIFY(!url.host().isEmpty());
        QVERIFY(url.scheme() == u"ws"_s || url.scheme() == u"wss"_s);
        endpoints.insert(url.toString());
    }
    QCOMPARE(endpoints.size(), directory.configuredServerCount());
}

void TestServerDirectory::loadsExternalDirectory() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = directory.filePath(u"servers.json"_s);
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    const QByteArray payload = R"({
  "schemaVersion": 1,
  "servers": [
    {
      "url": "ws://127.0.0.1:10001",
      "legacyUrls": ["ws://retired-primary.example:10001/ws"]
    },
    {"url": "wss://secondary.example/ws"},
    {"url": "wss://tertiary.example/ws"},
    {"url": "wss://quaternary.example/ws"},
    {"url": "wss://test.example/test/ws"}
  ]
})";
    QCOMPARE(file.write(payload), payload.size());
    file.close();
    qputenv("HEXPROOF_SERVER_DIRECTORY_FILE", path.toUtf8());

    ServerDirectory serverDirectory;
    QCOMPARE(serverDirectory.serverUrl(0), u"ws://127.0.0.1:10001/ws"_s);
    QCOMPARE(serverDirectory.serverUrl(1), u"wss://secondary.example/ws"_s);
    QCOMPARE(serverDirectory.serverUrl(2), u"wss://tertiary.example/ws"_s);
    QCOMPARE(serverDirectory.serverUrl(3), u"wss://quaternary.example/ws"_s);
    QCOMPARE(serverDirectory.serverUrl(4), u"wss://test.example/test/ws"_s);
    QCOMPARE(serverDirectory.normalizePersistedUrl(u"ws://retired-primary.example:10001/ws"_s),
             serverDirectory.serverUrl(0));
}

void TestServerDirectory::appliesEnvironmentOverrides() const
{
    QTemporaryDir files;
    QVERIFY(files.isValid());
    isolateCatalog(files);
    QVERIFY(isolateFiveSlotCatalog(files));
    qputenv("HEXPROOF_SERVER_1_URL", " ws://127.0.0.1:10001/ws ");
    qputenv("HEXPROOF_SERVER_2_URL", "wss://secondary.example/ws");
    qputenv("HEXPROOF_SERVER_3_URL", "wss://tertiary.example/ws");
    qputenv("HEXPROOF_SERVER_4_URL", "wss://quaternary.example/ws");
    qputenv("HEXPROOF_SERVER_5_URL", "wss://test.example/test/ws");

    ServerDirectory directory;
    QCOMPARE(directory.serverUrl(0), u"ws://127.0.0.1:10001/ws"_s);
    QCOMPARE(directory.serverUrl(1), u"wss://secondary.example/ws"_s);
    QCOMPARE(directory.serverUrl(2), u"wss://tertiary.example/ws"_s);
}

void TestServerDirectory::mapsConfiguredAndCustomUrls() const
{
    QTemporaryDir files;
    QVERIFY(files.isValid());
    isolateCatalog(files);
    QVERIFY(isolateFiveSlotCatalog(files));
    ServerDirectory directory;
    QCOMPARE(directory.indexForUrl(directory.serverUrl(0)), 0);
    QCOMPARE(directory.indexForUrl(directory.serverUrl(1)), 1);
    QCOMPARE(directory.indexForUrl(directory.serverUrl(2)), 2);
    QVERIFY(directory.setCustomServerUrl(u" ws://127.0.0.1:57320 "_s));
    QCOMPARE(directory.customServerUrl(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(directory.serverUrl(directory.customServerIndex()), directory.customServerUrl());
    QCOMPARE(directory.indexForUrl(directory.customServerUrl()), directory.customServerIndex());
    QCOMPARE(directory.indexForUrl(u"wss://another.example/ws"_s), directory.customServerIndex());
    QVERIFY(!directory.setCustomServerUrl(u"https://invalid.example/ws"_s));
    QCOMPARE(directory.customServerUrl(), u"ws://127.0.0.1:57320/ws"_s);
}

void TestServerDirectory::exposesInitialLatencyState() const
{
    QTemporaryDir files;
    QVERIFY(files.isValid());
    isolateCatalog(files);
    QVERIFY(isolateFiveSlotCatalog(files));
    ServerDirectory directory;
    const QVariantList latencies = directory.latencies();
    QCOMPARE(latencies.size(), (directory.configuredServerCount() + 1));
    QCOMPARE(latencies[0].toInt(), -2);
    QCOMPARE(latencies[1].toInt(), -2);
    QCOMPARE(latencies[2].toInt(), -2);
    QCOMPARE(latencies[3].toInt(), -2);
}

void TestServerDirectory::probesConfiguredHealthEndpoints() const
{
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QStringList requestTargets;
    connect(&server, &QTcpServer::newConnection, &server, [&server, &requestTargets]() {
        while (QTcpSocket *socket = server.nextPendingConnection()) {
            socket->setParent(&server);
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &requestTargets]() {
                const QList<QByteArray> requestParts = socket->readAll().split(' ');
                if (requestParts.size() >= 2)
                    requestTargets.push_back(QString::fromLatin1(requestParts[1]));
                socket->write("HTTP/1.1 204 No Content\r\n"
                              "Content-Length: 0\r\n"
                              "Connection: close\r\n\r\n");
                socket->disconnectFromHost();
            });
        }
    });

    const QByteArray endpoint =
        "ws://127.0.0.1:" + QByteArray::number(server.serverPort()) + "/test/ws";
    QTemporaryDir files;
    QVERIFY(files.isValid());
    isolateCatalog(files);
    QVERIFY(isolateFiveSlotCatalog(files));
    qputenv("HEXPROOF_SERVER_1_URL", endpoint);
    qputenv("HEXPROOF_SERVER_2_URL", endpoint);
    qputenv("HEXPROOF_SERVER_3_URL", endpoint);
    qputenv("HEXPROOF_SERVER_4_URL", endpoint);
    qputenv("HEXPROOF_SERVER_5_URL", endpoint);

    ServerDirectory directory;
    QVERIFY(directory.setCustomServerUrl(QString::fromUtf8(endpoint)));
    QSignalSpy changed(&directory, &ServerDirectory::latenciesChanged);
    directory.refreshLatencies();

    QElapsedTimer deadline;
    deadline.start();
    QVariantList latencies;
    do {
        QCoreApplication::processEvents();
        latencies = directory.latencies();
        if (latencies.size() == (directory.configuredServerCount() + 1) &&
            latencies[0].toInt() >= 0 &&
            std::all_of(latencies.cbegin(), latencies.cend(),
                        [](const QVariant &value) { return value.toInt() >= 0; })) {
            break;
        }
        QTest::qWait(10);
    } while (deadline.elapsed() < 5000);

    QCOMPARE(latencies.size(), (directory.configuredServerCount() + 1));
    QVERIFY(latencies[0].toInt() >= 0);
    QVERIFY(latencies[1].toInt() >= 0);
    QVERIFY(latencies[2].toInt() >= 0);
    QVERIFY(latencies[3].toInt() >= 0);
    QCOMPARE(requestTargets.size(), (directory.configuredServerCount() + 1));
    for (const QString &target : requestTargets)
        QCOMPARE(target, u"/test/healthz"_s);
    QCOMPARE(changed.count(), directory.configuredServerCount() + 2);
}

void TestServerDirectory::editingCustomEndpointPreservesConfiguredProbes() const
{
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QList<QTcpSocket *> pending;
    connect(&server, &QTcpServer::newConnection, &server, [&]() {
        while (QTcpSocket *socket = server.nextPendingConnection()) {
            socket->setParent(&server);
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket]() {
                socket->readAll();
                if (!pending.contains(socket))
                    pending.append(socket);
            });
        }
    });
    const QByteArray endpoint = "ws://127.0.0.1:" + QByteArray::number(server.serverPort()) + "/ws";
    QTemporaryDir files;
    QVERIFY(files.isValid());
    isolateCatalog(files);
    QVERIFY(isolateFiveSlotCatalog(files));
    for (int index = 1; index <= 32; ++index)
        qputenv(qPrintable(u"HEXPROOF_SERVER_%1_URL"_s.arg(index)), endpoint);
    ServerDirectory directory;
    QVERIFY(directory.setCustomServerUrl(QString::fromUtf8(endpoint)));
    directory.refreshLatencies();
    QTRY_COMPARE(pending.size(), (directory.configuredServerCount() + 1));
    QVERIFY(directory.setCustomServerUrl(QString::fromUtf8(endpoint) + u"/changed"_s));
    for (QTcpSocket *socket : pending) {
        socket->write("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        socket->disconnectFromHost();
    }
    QTRY_VERIFY_WITH_TIMEOUT(directory.latencies()[0].toInt() >= 0, 1'000);
    for (int index = 0; index < directory.configuredServerCount(); ++index)
        QTRY_VERIFY(directory.latencies()[index].toInt() >= 0);
    QCOMPARE(directory.latencies()[directory.customServerIndex()].toInt(), -2);
}

void TestServerDirectory::refreshesViaMirrorAndRecoversCache() const
{
    QTemporaryDir files;
    DirectoryHost host;
    QVERIFY(host.isListening());
    isolateCatalog(files);
    QVERIFY(writeCatalog(files.filePath(u"bootstrap.json"_s),
                         catalog(1, {}, {host.url(u"/catalog"_s), host.url(u"/mirror"_s)})));
    host.mirror = QJsonDocument(catalog(2, {host.entry(u"new-node"_s)})).toJson();
    {
        ServerDirectory directory;
        directory.refreshDirectory();
        QTRY_COMPARE(directory.source(), u"online"_s);
        QVERIFY(!directory.refreshFailed());
        QCOMPARE(directory.configuredServerCount(), 1);
        QCOMPARE(directory.entries()[0].toMap()[u"id"_s].toString(), u"new-node"_s);
        QCOMPARE(host.requests.mid(0, 2), QStringList({u"/catalog"_s, u"/mirror"_s}));
        const auto requestCount = host.requests.count(u"/catalog"_s);
        directory.refreshDirectory(); // Automatic refresh is throttled.
        QTest::qWait(20);
        QCOMPARE(host.requests.count(u"/catalog"_s), requestCount);
    }
    // Restart while both origins are unavailable: keep the last accepted catalog.
    host.mirror = "invalid";
    ServerDirectory restored;
    QCOMPARE(restored.source(), u"cache"_s);
    QCOMPARE(restored.configuredServerCount(), 1);
    restored.refreshDirectory(true);
    QTRY_VERIFY(!restored.refreshing());
    QVERIFY(restored.refreshFailed());
    QCOMPARE(restored.source(), u"cache"_s);
    // A stale mirror must not bring retired nodes back after a newer revision.
    host.primary = QJsonDocument(catalog(1, {host.entry(u"retired"_s)})).toJson();
    restored.refreshDirectory(true);
    QTRY_VERIFY(!restored.refreshing());
    QVERIFY(restored.refreshFailed());
    QCOMPARE(restored.entries()[0].toMap()[u"id"_s].toString(), u"new-node"_s);
}

void TestServerDirectory::rejectsInvalidUpdates_data() const
{
    QTest::addColumn<QByteArray>("payload");
    DirectoryHost host;
    const auto validEntry = host.entry(u"node"_s);
    auto add = [&](const char *name, QJsonObject document) {
        QTest::newRow(name) << QJsonDocument(document).toJson();
    };
    add("duplicate-ids", catalog(2, {validEntry, validEntry}));
    auto changed = validEntry;
    changed[u"forge"_s] = "yes";
    add("invalid-capability", catalog(2, {changed}));
    changed = validEntry;
    changed[u"url"_s] = "ws://public.example/ws";
    add("insecure-public-endpoint", catalog(2, {changed}));
    changed[u"url"_s] = "wss://user:password@public.example/ws";
    add("endpoint-credentials", catalog(2, {changed}));
    changed[u"url"_s] = "wss://public.example/ws?token=secret";
    add("endpoint-query", catalog(2, {changed}));
    changed[u"url"_s] = "wss://public.example/ws#fragment";
    add("endpoint-fragment", catalog(2, {changed}));
    changed = validEntry;
    changed[u"id"_s] = "custom";
    add("reserved-id", catalog(2, {changed}));
    add("same-revision-changed-entries", catalog(1, {validEntry}));
    add("invalid-directory-source", catalog(2, {}, {u"http://public.example/catalog"_s}));
    QTest::newRow("oversized-body") << QByteArray(65537, ' ');
    QTest::newRow("malformed-json") << QByteArray("{");
}

void TestServerDirectory::rejectsInvalidUpdates() const
{
    QFETCH(QByteArray, payload);
    QTemporaryDir files;
    DirectoryHost host;
    isolateCatalog(files);
    QVERIFY(writeCatalog(files.filePath(u"bootstrap.json"_s),
                         catalog(1, {}, {host.url(u"/catalog"_s)})));
    host.primary = payload;
    ServerDirectory directory;
    directory.refreshDirectory(true);
    QTRY_VERIFY(!directory.refreshing());
    QVERIFY(directory.refreshFailed());
    QCOMPARE(directory.configuredServerCount(), 0);
    QVERIFY(!QFile::exists(files.filePath(u"cache.json"_s)));
}

void TestServerDirectory::preservesCustomEndpointAndObservedCapabilities() const
{
    QTemporaryDir files;
    DirectoryHost host;
    isolateCatalog(files);
    qputenv("HEXPROOF_SERVER_DIRECTORY_CACHE", "");
    const auto first = host.entry(u"first"_s, false);
    const auto second = host.entry(u"second"_s, true);
    QVERIFY(writeCatalog(files.filePath(u"bootstrap.json"_s),
                         catalog(1, {first, second}, {host.url(u"/catalog"_s)})));
    ServerDirectory directory;
    QVERIFY(directory.setCustomServerUrl(u"ws://127.0.0.1:57321/ws"_s));
    directory.recordCapabilities(first[u"url"_s].toString(), capabilities(true, true));
    QCOMPARE(directory.entries()[0].toMap()[u"forge"_s].toInt(), 1);
    host.primary = QJsonDocument(catalog(2, {second, first})).toJson();
    directory.refreshDirectory(true);
    QTRY_COMPARE(directory.source(), u"online"_s);
    QCOMPARE(directory.entries()[1].toMap()[u"forge"_s].toInt(), 1);
    QCOMPARE(directory.entries()[1].toMap()[u"playerHosting"_s].toInt(), 1);
    QCOMPARE(directory.customServerUrl(), u"ws://127.0.0.1:57321/ws"_s);
    host.primary = QJsonDocument(catalog(3, {})).toJson();
    directory.refreshDirectory(true);
    QTRY_VERIFY(!directory.refreshing());
    QCOMPARE(directory.configuredServerCount(), 0);
    QCOMPARE(directory.customServerIndex(), 0);
    QCOMPARE(directory.entries().size(), 1);
    QCOMPARE(directory.serverUrl(0), u"ws://127.0.0.1:57321/ws"_s);
}

void TestServerDirectory::discoversIndependentHostingCapabilities() const
{
    QTemporaryDir files;
    DirectoryHost host;
    isolateCatalog(files);
    QVERIFY(writeCatalog(files.filePath(u"bootstrap.json"_s),
                         catalog(1, {host.entry(u"relay"_s, false)})));
    ServerDirectory directory;
    QCOMPARE(directory.entries()[0].toMap()[u"playerHosting"_s].toInt(), -1);
    const auto refresh = [&]() {
        directory.refreshLatencies();
        QTRY_VERIFY(directory.latencies()[0].toInt() >= 0);
    };
    refresh(); // Older servers retain unknown hosting support.
    QCOMPARE(directory.entries()[0].toMap()[u"playerHosting"_s].toInt(), -1);
    host.healthCapabilities =
        QJsonDocument(capabilities(false, true)).toJson(QJsonDocument::Compact);
    refresh();
    QCOMPARE(directory.entries()[0].toMap()[u"forge"_s].toInt(), 0);
    for (const auto &key : {u"playerHosting"_s, u"directPeer"_s, u"hostMigration"_s})
        QCOMPARE(directory.entries()[0].toMap()[key].toInt(), 1);
    auto oversized = capabilities(true, false);
    oversized.insert(u"padding"_s, QString(1100, u'x'));
    for (const QByteArray &invalid :
         {QByteArray("{broken"), QByteArray("{\"forge\":false}"),
          QJsonDocument(oversized).toJson(QJsonDocument::Compact),
          QByteArray("{\"forge\":false,\"playerHosting\":\"yes\",\"directPeer\":true,"
                     "\"hostMigration\":true}")}) {
        host.healthCapabilities = invalid;
        refresh();
        QCOMPARE(directory.entries()[0].toMap()[u"playerHosting"_s].toInt(), 1);
    }
    host.healthCapabilities =
        QJsonDocument(capabilities(true, false)).toJson(QJsonDocument::Compact);
    refresh();
    QCOMPARE(directory.entries()[0].toMap()[u"forge"_s].toInt(), 1);
    QCOMPARE(directory.entries()[0].toMap()[u"playerHosting"_s].toInt(), 0);
}

void TestServerDirectory::welcomeOverridesAnOlderProbe() const
{
    QTemporaryDir files;
    DirectoryHost host;
    isolateCatalog(files);
    const auto entry = host.entry(u"relay"_s, false);
    QVERIFY(writeCatalog(files.filePath(u"bootstrap.json"_s), catalog(1, {entry})));
    ServerDirectory directory;
    host.healthCapabilities =
        QJsonDocument(capabilities(true, false)).toJson(QJsonDocument::Compact);
    host.beforeHealthResponse = [&]() {
        directory.recordCapabilities(entry[u"url"_s].toString(), capabilities(false, true));
    };
    directory.refreshLatencies();
    QTRY_VERIFY(directory.latencies()[0].toInt() >= 0);
    QCOMPARE(directory.entries()[0].toMap()[u"forge"_s].toInt(), 0);
    QCOMPARE(directory.entries()[0].toMap()[u"playerHosting"_s].toInt(), 1);
}

QTEST_MAIN(TestServerDirectory)
#include "serverdirectory_test.moc"
