// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/AccountSessionState.h"
#include <QJsonArray>
#include <QScopeGuard>
#include <QSemaphore>
#include <QSignalSpy>
#include <QTest>
#include <QUuid>
#include <atomic>

using namespace Qt::StringLiterals;
using hexproof::client::AccountSessionState;
using hexproof::client::AccountVaultResult;

namespace {
QJsonObject state(const QString &operation, const QString &token = {})
{
    QJsonObject result{
        {u"operation"_s, operation},
        {u"accountId"_s, u"account-a"_s},
        {u"displayName"_s, u"Alice"_s},
        {u"sessionId"_s, u"device-a"_s},
        {u"devices"_s, QJsonArray{QJsonObject{{u"id"_s, u"device-a"_s}, {u"current"_s, true}}}},
        {u"resources"_s, QJsonArray{}}};
    if (!token.isEmpty())
        result.insert(u"sessionToken"_s, token);
    return result;
}
} // namespace

class TestAccountSession : public QObject
{
    Q_OBJECT
  private slots:
    void nativeVaultRoundTrip()
    {
        if (qEnvironmentVariableIntValue("HEXPROOF_TEST_ACCOUNT_VAULT") != 1)
            QSKIP("Native credential vault verification requires explicit opt-in.");
        const QString key =
            u"hexproof-test-"_s + QUuid::createUuid().toString(QUuid::WithoutBraces);
        const auto cleanup =
            qScopeGuard([&key]() { hexproof::client::writeAccountVault(key, {}); });
        const auto empty = hexproof::client::readAccountVault(key);
        QVERIFY2(empty.available, "The native credential vault is unavailable");
        QVERIFY(empty.token.isEmpty());
        QVERIFY(hexproof::client::writeAccountVault(key, u"disposable-session-one"_s));
        const auto first = hexproof::client::readAccountVault(key);
        QVERIFY(first.available);
        QCOMPARE(first.token, u"disposable-session-one"_s);
        QVERIFY(hexproof::client::writeAccountVault(key, u"disposable-session-two"_s));
        QCOMPARE(hexproof::client::readAccountVault(key).token, u"disposable-session-two"_s);
        QVERIFY(hexproof::client::writeAccountVault(key, {}));
        const auto removed = hexproof::client::readAccountVault(key);
        QVERIFY(removed.available);
        QVERIFY(removed.token.isEmpty());
    }

    void globalRecoveryChoosesOnlyOneRoom_data()
    {
        QTest::addColumn<int>("rooms");
        QTest::newRow("unique") << 1;
        QTest::newRow("multiple") << 2;
    }

    void globalRecoveryChoosesOnlyOneRoom()
    {
        QFETCH(int, rooms);
        AccountSessionState service(
            u"cluster-profile"_s,
            [](const QString &) { return AccountVaultResult{true, u"cached-token"_s}; },
            [](const QString &, const QString &) { return true; });
        QSignalSpy commands(&service, &AccountSessionState::commandRequested);
        QSignalSpy chooser(&service, &AccountSessionState::accountPageRequested);
        service.prepareRealm(u"test"_s);
        QTRY_COMPARE(service.helloToken(u"test"_s), u"cached-token"_s);
        service.welcome(u"test"_s, u"account-a"_s, u"Alice"_s, true);
        service.setTransportReady(true);
        QCOMPARE(commands.size(), 1);
        QCOMPARE(commands[0][0].toJsonObject().value(u"operation"_s).toString(), u"status"_s);
        service.commandQueued(u"status"_s);
        auto response = state(u"status"_s);
        QJsonArray resources;
        for (int i = 1; i <= rooms; ++i)
            resources.append(
                QJsonObject{{u"kind"_s, u"room"_s}, {u"id"_s, u"N%1:ABCDEF"_s.arg(i)}});
        response.insert(u"resources"_s, resources);
        service.acceptState(u"status"_s, response);
        if (rooms == 1) {
            QCOMPARE(commands.size(), 2);
            QCOMPARE(commands[1][0].toJsonObject().value(u"resourceId"_s).toString(),
                     u"N1:ABCDEF"_s);
        } else {
            QCOMPARE(commands.size(), 1);
            QCOMPARE(chooser.size(), 1);
        }
    }

    void lateVaultLoadsOnlyIntoMatchingRealm()
    {
        AccountSessionState service(
            u"isolated"_s,
            [](const QString &) { return AccountVaultResult{true, u"saved-token"_s}; },
            [](const QString &, const QString &) { return true; });
        QSignalSpy commands(&service, &AccountSessionState::commandRequested);
        service.prepareRealm(u"test"_s);
        service.welcome(u"test"_s, {}, {});
        service.setTransportReady(true);
        QTRY_COMPARE(commands.size(), 1);
        const auto command = commands[0][0].toJsonObject();
        QCOMPARE(command.value(u"operation"_s).toString(), u"attach"_s);
        QCOMPARE(command.value(u"credential"_s).toString(), u"saved-token"_s);
        service.commandQueued(u"1"_s);
        service.acceptState(u"1"_s, state(u"attach"_s, u"saved-token"_s));
        QVERIFY(service.authenticated());
        QCOMPARE(service.helloToken(u"test"_s), u"saved-token"_s);
        QVERIFY(service.helloToken(u"other"_s).isEmpty());
        service.setTransportReady(false);
        service.prepareRealm({});
        service.welcome(u"test"_s, {}, {});
        service.setTransportReady(true);
        QVERIFY(!service.supported());
        QVERIFY(!service.authenticated());
        QVERIFY(service.helloToken({}).isEmpty());
        QCOMPARE(commands.size(), 1);
    }

    void creationStoresOnlySessionAndLogoutClearsVault()
    {
        std::atomic_int writes{0};
        QStringList written;
        AccountSessionState service(
            u"new-device"_s, [](const QString &) { return AccountVaultResult{false, {}}; },
            [&written, &writes](const QString &, const QString &token) {
                written.append(token);
                ++writes;
                return true;
            });
        QSignalSpy commands(&service, &AccountSessionState::commandRequested);
        QSignalSpy loggedOut(&service, &AccountSessionState::loggedOut);
        service.setLoginIntent(u"create"_s, u"Alice"_s);
        service.prepareRealm(u"test"_s);
        service.welcome(u"test"_s, {}, {});
        service.setTransportReady(true);
        QCOMPARE(commands.size(), 1);
        QCOMPARE(commands[0][0].toJsonObject().value(u"operation"_s).toString(), u"create"_s);
        service.commandQueued(u"create"_s);
        auto response = state(u"create"_s, u"session-only"_s);
        response.insert(u"loginCode"_s, u"private-login"_s);
        response.insert(u"recoveryCode"_s, u"private-recovery"_s);
        service.acceptState(u"unrelated"_s, response);
        QVERIFY(!service.authenticated());
        service.acceptState(u"create"_s, response);
        QCOMPARE(service.loginCode(), u"private-login"_s);
        QCOMPARE(service.recoveryCode(), u"private-recovery"_s);
        QTRY_COMPARE(writes.load(), 1);
        QCOMPARE(written, QStringList{u"session-only"_s});
        service.acknowledgeBackup();
        QVERIFY(service.loginCode().isEmpty());
        QVERIFY(service.recoveryCode().isEmpty());
        service.logout();
        service.commandQueued(u"logout"_s);
        response = state(u"logout"_s);
        response.insert(u"devices"_s, QJsonArray{});
        service.acceptState(u"logout"_s, response);
        QCOMPARE(loggedOut.size(), 1);
        QVERIFY(!service.authenticated());
        QVERIFY(service.helloToken(u"test"_s).isEmpty());
        QTRY_COMPARE(writes.load(), 2);
        QCOMPARE(written, QStringList({u"session-only"_s, QString{}}));
    }

    void guestChoiceSurvivesLateVaultAndRevocationClearsIdentity()
    {
        AccountSessionState service(
            u"test"_s, [](const QString &) { return AccountVaultResult{true, u"token"_s}; },
            [](const QString &, const QString &) { return true; });
        QSignalSpy commands(&service, &AccountSessionState::commandRequested);
        service.setLoginIntent(u"guest"_s, {});
        service.prepareRealm(u"test"_s);
        QVERIFY(service.helloToken(u"test"_s).isEmpty());
        service.welcome(u"test"_s, {}, {});
        service.setTransportReady(true);
        QTest::qWait(50);
        QCOMPARE(commands.size(), 0);
        service.login(u"login"_s);
        service.commandQueued(u"login"_s);
        service.acceptState(u"login"_s, state(u"login"_s, u"new-token"_s));
        service.acceptError(u"unsolicited"_s, u"account_invalid"_s, u"Session expired"_s);
        QVERIFY(!service.authenticated());
        QVERIFY(service.helloToken(u"test"_s).isEmpty());
        QCOMPARE(service.lastError(), u"Session expired"_s);
    }

    void loginRecoversRoomAndFailedClaimKeepsAccount()
    {
        AccountSessionState service(
            u"test"_s, [](const QString &) { return AccountVaultResult{true, {}}; },
            [](const QString &, const QString &) { return true; });
        QSignalSpy commands(&service, &AccountSessionState::commandRequested);
        service.prepareRealm(u"test"_s);
        service.welcome(u"test"_s, {}, {});
        service.setTransportReady(true);
        service.login(u"private-login"_s);
        service.commandQueued(u"login"_s);
        auto response = state(u"login"_s, u"session"_s);
        response.insert(u"resources"_s,
                        QJsonArray{QJsonObject{{u"kind"_s, u"room"_s}, {u"id"_s, u"ABCDEF"_s}}});
        service.acceptState(u"login"_s, response);
        QCOMPARE(commands.last()[0].toJsonObject().value(u"operation"_s).toString(), u"resume"_s);
        QCOMPARE(commands.last()[0].toJsonObject().value(u"resourceId"_s).toString(), u"ABCDEF"_s);
        service.commandQueued(u"resume"_s);
        service.acceptState(u"resume"_s, state(u"resume"_s));
        service.claim(u"tournament"_s, u"EVENT1"_s, u"saved-bearer"_s);
        service.commandQueued(u"claim"_s);
        service.acceptError(u"claim"_s, u"account_conflict"_s, u"Unavailable"_s);
        QVERIFY(service.authenticated());
        QCOMPARE(service.helloToken(u"test"_s), u"session"_s);
    }
};

QTEST_GUILESS_MAIN(TestAccountSession)
#include "accountsession_test.moc"
