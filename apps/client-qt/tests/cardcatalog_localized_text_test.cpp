// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

#include "services/CardArtCache.h"
#include "services/CardResolver.h"

using namespace hexproof::client;

namespace {

const QByteArray kRulesTestPng = QByteArray::fromBase64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");

class RulesNetwork final : public QNetworkAccessManager
{
  public:
    QString name = u"Test Emblem"_s;
    QString chineseText = u"由你操控的生物具有飞行。\n每当你抓一张牌时，你获得1点生命。"_s;
    QString englishText = u"Creatures you control have flying."_s;
    bool failEveryImage = false;
    bool serveScryfallChinese = false;
    bool missMtgch = false;
    bool transientMtgchFailure = false;
    int requestedImages = 0;
    QList<QUrl> requests;
    QJsonObject sourceCard;

  protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override
    {
        const QUrl url = request.url();
        requests.append(url);
        if (url.host() == u"mtgch.com"_s && transientMtgchFailure)
            return new StaticNetworkReply(request, "{}", "application/json", this, 503,
                                          QNetworkReply::UnknownServerError);
        if (url.host() == u"rules-images.test"_s) {
            ++requestedImages;
            if (!failEveryImage &&
                (url.path() == u"/english.png"_s || url.path() == u"/scryfall-chinese.png"_s))
                return new StaticNetworkReply(request, kRulesTestPng, "image/png", this);
        } else if ((url.host() == u"mtgch.com"_s && !missMtgch) ||
                   (url.host() == u"api.scryfall.com"_s &&
                    (serveScryfallChinese || !url.path().endsWith(u"/zhs"_s)) &&
                    url.path() != u"/cards/search"_s)) {
            QJsonObject card{
                {u"name"_s, name},
                {u"oracle_id"_s, u"rules-oracle-"_s + name},
                {u"set"_s, u"TST"_s},
                {u"collector_number"_s, u"1"_s},
                {u"type_line"_s, u"Emblem"_s},
                {u"oracle_text"_s, englishText},
                {u"image_uris"_s,
                 QJsonObject{{u"normal"_s, u"https://rules-images.test/english.png"_s}}},
            };
            if (url.path().endsWith(u"/zhs"_s)) {
                card.insert(u"lang"_s, u"zhs"_s);
                card.insert(u"image_uris"_s,
                            QJsonObject{{u"normal"_s,
                                         u"https://rules-images.test/scryfall-chinese.png"_s}});
            }
            if (url.host() == u"mtgch.com"_s && !chineseText.isEmpty()) {
                card.insert(u"zhs_name"_s, u"测试徽记"_s);
                card.insert(u"zhs_type_line"_s, u"徽记"_s);
                card.insert(u"zhs_text"_s, chineseText);
                card.insert(u"zhs_image_uris"_s,
                            QJsonObject{{u"normal"_s, u"https://rules-images.test/chinese.png"_s}});
            }
            if (!sourceCard.isEmpty())
                card = sourceCard;
            return new StaticNetworkReply(request, QJsonDocument(card).toJson(), "application/json",
                                          this);
        }
        return new StaticNetworkReply(request, "{}", "application/json", this, 404,
                                      QNetworkReply::ContentNotFoundError);
    }
};

} // namespace

void TestCardCatalog::parsesLocalizedRulesIndependentlyOfArtwork() const
{
    QJsonObject card{
        {u"name"_s, u"Test Emblem"_s},
        {u"zhs_name"_s, u"测试徽记"_s},
        {u"type_line"_s, u"Emblem"_s},
        {u"zhs_text"_s, u"由你操控的生物具有飞行。\n它们得+1/+1。"_s},
        {u"oracle_text"_s, u"Creatures you control have flying.\nThey get +1/+1."_s},
    };
    CardRecord record = CardCatalog::parseCardObject(card, u"zh"_s, u"Test Emblem"_s);
    QCOMPARE(record.oracleText, card.value(u"zhs_text"_s).toString());
    QCOMPARE(record.oracleTextLanguage, u"zh"_s);
    QVERIFY(record.localizedRulesChecked);
    QVERIFY(record.imageUrl.isEmpty());
    QVERIFY(record.imageLanguage.isEmpty());

    record = CardCatalog::parseCardObject(card, u"en"_s, u"Test Emblem"_s);
    QCOMPARE(record.oracleText, card.value(u"oracle_text"_s).toString());
    QCOMPARE(record.oracleTextLanguage, u"en"_s);
    QVERIFY(!record.localizedRulesChecked);

    card.remove(u"zhs_text"_s);
    card.insert(u"printed_text"_s, u"由你操控的生物具有飞行。"_s);
    card.insert(u"lang"_s, u"zhs"_s);
    record = CardCatalog::parseCardObject(card, u"zh"_s, u"Test Emblem"_s);
    QCOMPARE(record.oracleText, card.value(u"printed_text"_s).toString());
    QCOMPARE(record.oracleTextLanguage, u"zh"_s);

    // An English placeholder in a translated field is not Chinese rules.
    card.insert(u"printed_text"_s, u"Creatures you control have flying."_s);
    card.insert(u"zhs_text"_s, u"Creatures you control have flying."_s);
    record = CardCatalog::parseCardObject(card, u"zh"_s, u"Test Emblem"_s);
    QCOMPARE(record.oracleText, card.value(u"oracle_text"_s).toString());
    QCOMPARE(record.oracleTextLanguage, u"en"_s);

    card.remove(u"oracle_text"_s);
    card.remove(u"zhs_text"_s);
    card.remove(u"printed_text"_s);
    card.insert(u"text"_s, u"Flying"_s);
    record = CardCatalog::parseCardObject(card, u"zh"_s, u"Test Emblem"_s);
    QCOMPARE(record.oracleText, u"Flying"_s);
    QCOMPARE(record.oracleTextLanguage, u"en"_s);
    card.insert(u"text"_s, QString{});
    record = CardCatalog::parseCardObject(card, u"zh"_s, u"Test Emblem"_s);
    QVERIFY(record.oracleText.isEmpty());
    QCOMPARE(record.oracleTextLanguage, u"en"_s);
}

void TestCardCatalog::localizedRulesRespectFaceAndLanguage() const
{
    QJsonObject card{
        {u"name"_s, u"Soldier // Spirit"_s},
        {u"layout"_s, u"double_faced_token"_s},
        {u"oracle_text"_s, u"Front-only text"_s},
        {u"zhs_text"_s, u"正面规则"_s},
        {u"card_faces"_s, QJsonArray{QJsonObject{{u"name"_s, u"Soldier"_s},
                                                 {u"oracle_text"_s, u"Vigilance"_s},
                                                 {u"printed_text"_s, u"警戒"_s}},
                                     QJsonObject{{u"name"_s, u"Spirit"_s},
                                                 {u"oracle_text"_s, u"Flying"_s},
                                                 {u"printed_text"_s, u"飞行"_s}}}},
    };
    const CardRecord back = CardCatalog::parseCardObject(card, u"zh"_s, u"Spirit"_s);
    QCOMPARE(back.oracleText, u"飞行"_s);
    QCOMPARE(back.oracleTextLanguage, u"zh"_s);
    QCOMPARE(back.faceName, u"Spirit"_s);
    const CardRecord english = CardCatalog::parseCardObject(card, u"en"_s, u"Spirit"_s);
    QCOMPARE(english.oracleText, u"Flying"_s);
    QCOMPARE(english.oracleTextLanguage, u"en"_s);

    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    RulesNetwork network;
    network.sourceCard = card;
    QJsonArray faces = card.value(u"card_faces"_s).toArray();
    QJsonObject spirit = faces.at(1).toObject();
    spirit.insert(u"image_uris"_s,
                  QJsonObject{{u"normal"_s, u"https://rules-images.test/english.png"_s}});
    faces[1] = spirit;
    network.sourceCard.insert(u"card_faces"_s, faces);
    CardRecord resolved;
    bool completed = false;
    CardResolver::Callbacks callbacks;
    callbacks.lookupCatalog = [&card](const CardRequest &) {
        CardRecord record;
        record.name = card.value(u"name"_s).toString();
        record.oracleText = u"Front-only text"_s;
        record.oracleTextLanguage = u"en"_s;
        return record;
    };
    callbacks.imagePathFor = [&directory](const CardRequest &, const CardRecord &) {
        return directory.filePath(u"spirit.png"_s);
    };
    callbacks.completed = [&resolved, &completed](const CardRequest &, CardRecord record,
                                                  bool success, bool, const QString &) {
        QVERIFY(success);
        resolved = record;
        completed = true;
    };
    CardResolver resolver(&network, callbacks);
    resolver.resolve(CardRequest{u"Spirit"_s, u"TST"_s, u"1"_s, u"en"_s});
    QTRY_VERIFY(completed);
    QCOMPARE(resolved.oracleText, u"Flying"_s);
    QCOMPARE(resolved.oracleTextLanguage, u"en"_s);
    card.remove(u"card_faces"_s);
    const CardRecord missing = CardCatalog::parseCardObject(card, u"zh"_s, u"Spirit"_s);
    QVERIFY(missing.oracleText.isEmpty());
    QVERIFY(missing.oracleTextLanguage.isEmpty());
}

void TestCardCatalog::localizedRulesSurviveEnglishFallbackAndNextRequest() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    RulesNetwork network;
    QList<CardRecord> completed;
    QList<CardRecord> metadata;
    CardResolver::Callbacks callbacks;
    callbacks.imagePathFor = [&directory](const CardRequest &request, const CardRecord &) {
        return directory.filePath(request.name + u".png"_s);
    };
    callbacks.metadataAvailable = [&metadata](const CardRequest &, const CardRecord &record) {
        metadata.append(record);
        QVERIFY(record.imagePath.isEmpty());
        QVERIFY(record.imageUrl.isEmpty());
        QVERIFY(record.imageLanguage.isEmpty());
    };
    callbacks.completed = [&completed](const CardRequest &, CardRecord record, bool success, bool,
                                       const QString &) {
        QVERIFY(success);
        completed.append(record);
    };
    CardResolver resolver(&network, callbacks);
    resolver.resolve(CardRequest{network.name, u"TST"_s, u"1"_s, u"zh"_s});
    QTRY_COMPARE(completed.size(), 1);
    QVERIFY(!metadata.isEmpty());
    QCOMPARE(completed.first().oracleText, network.chineseText);
    QCOMPARE(completed.first().oracleTextLanguage, u"zh"_s);
    QCOMPARE(completed.first().imageLanguage, u"en"_s);
    QCOMPARE(completed.first().localizedName, u"测试徽记"_s);
    QCOMPARE(completed.first().typeLine, u"徽记"_s);
    QVERIFY(QFileInfo::exists(completed.first().imagePath));

    network.name = u"Other Token"_s;
    network.chineseText.clear();
    network.englishText = u"Vigilance"_s;
    resolver.resolve(CardRequest{network.name, u"TST"_s, u"2"_s, u"en"_s});
    QTRY_COMPARE(completed.size(), 2);
    QCOMPARE(completed.last().oracleText, u"Vigilance"_s);
    QCOMPARE(completed.last().oracleTextLanguage, u"en"_s);
    QCOMPARE(completed.last().localizedName, network.name);
    QVERIFY(!resolver.active());
}

void TestCardCatalog::localizedRulesAvailableWhenEveryImageFails() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    RulesNetwork network;
    network.failEveryImage = true;
    bool completed = false;
    CardRecord lastMetadata;
    CardRecord finalRecord;
    CardResolver::Callbacks callbacks;
    callbacks.imagePathFor = [&directory](const CardRequest &, const CardRecord &) {
        return directory.filePath(u"missing.png"_s);
    };
    callbacks.metadataAvailable = [&lastMetadata](const CardRequest &, const CardRecord &record) {
        lastMetadata = record;
    };
    callbacks.completed = [&completed, &finalRecord](const CardRequest &, CardRecord record,
                                                     bool success, bool, const QString &) {
        QVERIFY(!success);
        finalRecord = record;
        completed = true;
    };
    CardResolver resolver(&network, callbacks);
    resolver.resolve(CardRequest{network.name, u"TST"_s, u"1"_s, u"zh"_s});
    QTRY_VERIFY(completed);
    QVERIFY(network.requestedImages > 1);
    QCOMPARE(lastMetadata.oracleText, network.chineseText);
    QCOMPARE(lastMetadata.oracleTextLanguage, u"zh"_s);
    QCOMPARE(finalRecord.oracleText, network.chineseText);
    QVERIFY(lastMetadata.imagePath.isEmpty());
    QVERIFY(finalRecord.imagePath.isEmpty());
    QVERIFY(!resolver.active());
}

void TestCardCatalog::localizedRulesCacheRoundTrip() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardRecord record;
    record.name = u"Test Emblem"_s;
    record.requestedName = record.name;
    record.oracleText = u"由你操控的生物具有飞行。\n它们得+1/+1。"_s;
    record.oracleTextLanguage = u"zh"_s;
    record.imageLanguage = u"en"_s;
    record.imageUrl = u"https://cards.scryfall.io/normal/front/test.png"_s;
    record.resolutionVersion = kCardResolutionVersion;
    record.localizedRulesChecked = true;
    QString key;
    {
        CardArtCache cache(directory.path());
        key = cache.key(record.name, u"zh"_s, {}, {});
        cache.rememberSuccess(key, record);
        QVERIFY(cache.save());
    }
    CardArtCache reopened(directory.path());
    reopened.load();
    const CardRecord restored = reopened.exactRecord(key);
    QCOMPARE(restored.oracleText, record.oracleText);
    QCOMPARE(restored.oracleTextLanguage, u"zh"_s);
    QCOMPARE(restored.imageLanguage, u"en"_s);
    QVERIFY(restored.localizedRulesChecked);
    QVERIFY(restored.imagePath.isEmpty());
    QJsonObject legacy = catalog_internal::recordToJson(record);
    legacy.remove(u"oracleText"_s);
    legacy.remove(u"oracleTextLanguage"_s);
    legacy.remove(u"localizedRulesChecked"_s);
    const CardRecord old = catalog_internal::recordFromJson(legacy);
    QVERIFY(old.oracleText.isEmpty());
    QVERIFY(old.oracleTextLanguage.isEmpty());
    QVERIFY(!old.localizedRulesChecked);
}

void TestCardCatalog::localizedRulesProbePreservesScryfallArtwork() const
{
    // Both an available translation and a failed metadata probe must keep the
    // already selected Scryfall image, including when that image is on disk.
    for (const bool missingTranslation : {false, true}) {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        RulesNetwork network;
        network.serveScryfallChinese = true;
        network.missMtgch = missingTranslation;
        CardRecord finalRecord;
        bool completed = false;
        CardResolver::Callbacks callbacks;
        callbacks.lookupCatalog = [&network](const CardRequest &) {
            CardRecord record;
            record.name = network.name;
            record.setCode = u"TST"_s;
            record.collectorNumber = u"1"_s;
            record.imageLanguage = u"zh"_s;
            record.imageUrl = u"https://rules-images.test/scryfall-chinese.png"_s;
            record.oracleText = network.englishText;
            record.oracleTextLanguage = u"en"_s;
            return record;
        };
        callbacks.imagePathFor = [&directory](const CardRequest &, const CardRecord &) {
            return directory.filePath(u"chosen.png"_s);
        };
        callbacks.completed = [&completed, &finalRecord](const CardRequest &, CardRecord record,
                                                         bool success, bool, const QString &) {
            QVERIFY(success);
            finalRecord = record;
            completed = true;
        };
        CardResolver resolver(&network, callbacks);
        resolver.setPreferredProvider(CardResolver::ArtProvider::Scryfall);
        CardRequest request{network.name, u"TST"_s, u"1"_s, u"zh"_s};
        request.supportCard = true;
        resolver.resolve(request);
        QTRY_VERIFY(completed);
        QCOMPARE(finalRecord.imageLanguage, u"zh"_s);
        QCOMPARE(finalRecord.imageUrl, u"https://rules-images.test/scryfall-chinese.png"_s);
        QCOMPARE(finalRecord.oracleTextLanguage, missingTranslation ? u"en"_s : u"zh"_s);
        QCOMPARE(finalRecord.oracleText,
                 missingTranslation ? network.englishText : network.chineseText);
        QVERIFY(finalRecord.localizedRulesChecked);
        QCOMPARE(network.requests.size(), 3);
        QCOMPARE(network.requests.at(0).host(), u"api.scryfall.com"_s);
        QVERIFY(network.requests.at(0).path().endsWith(u"/zhs"_s));
        QCOMPARE(network.requests.at(1).host(), u"mtgch.com"_s);
        QCOMPARE(network.requests.at(2).host(), u"rules-images.test"_s);
    }
}

void TestCardCatalog::localizedRulesRetryAfterTransientMetadataFailure() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    RulesNetwork network;
    network.serveScryfallChinese = true;
    network.transientMtgchFailure = true;
    QList<CardRecord> completed;
    CardResolver::Callbacks callbacks;
    callbacks.imagePathFor = [&directory](const CardRequest &, const CardRecord &) {
        return directory.filePath(u"chosen.png"_s);
    };
    callbacks.completed = [&completed](const CardRequest &, CardRecord record, bool success, bool,
                                       const QString &) {
        QVERIFY(success);
        completed.append(record);
    };
    CardResolver resolver(&network, callbacks);
    resolver.setPreferredProvider(CardResolver::ArtProvider::Scryfall);
    CardRequest request{network.name, u"TST"_s, u"1"_s, u"zh"_s};
    request.supportCard = true;
    resolver.resolve(request);
    QTRY_COMPARE(completed.size(), 1);
    QVERIFY(!completed.last().localizedRulesChecked);
    QCOMPARE(completed.last().oracleTextLanguage, u"en"_s);
    QCOMPARE(completed.last().imageLanguage, u"zh"_s);
    QVERIFY(QFileInfo::exists(completed.last().imagePath));
    QCOMPARE(network.requestedImages, 1);

    // The provider cooldown avoids another network probe, but it must not
    // permanently declare the missing translation resolved.
    network.transientMtgchFailure = false;
    const qsizetype beforeCooldown = network.requests.size();
    resolver.resolve(request);
    QTRY_COMPARE(completed.size(), 2);
    QVERIFY(!completed.last().localizedRulesChecked);
    QCOMPARE(network.requests.size(), beforeCooldown + 1);
    QCOMPARE(network.requestedImages, 1);

    // Explicit retry clears the existing cooldown and reuses the good image.
    resolver.clearCooldowns();
    resolver.resolve(request);
    QTRY_COMPARE(completed.size(), 3);
    QVERIFY(completed.last().localizedRulesChecked);
    QCOMPARE(completed.last().oracleTextLanguage, u"zh"_s);
    QCOMPARE(completed.last().oracleText, network.chineseText);
    QCOMPARE(completed.last().imageUrl, u"https://rules-images.test/scryfall-chinese.png"_s);
    QCOMPARE(network.requestedImages, 1);
}
