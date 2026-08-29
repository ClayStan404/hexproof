// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardCatalog.h"
#include "services/CatalogStorage.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTextStream>

using hexproof::client::CardCatalog;
namespace catalogstorage = hexproof::client::catalogstorage;

namespace {

bool importLimitedProducts(const QString &path, const QString &databasePath, QString *error)
{
    if (path.isEmpty())
        return true;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("Could not open the limited product catalog.");
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = document.object();
    if (parseError.error != QJsonParseError::NoError || !document.isObject() ||
        root.value(QStringLiteral("schemaVersion")).toInt() != 1 ||
        !root.value(QStringLiteral("products")).isArray()) {
        *error = QStringLiteral("The limited product catalog is invalid.");
        return false;
    }
    const QString connectionName = QStringLiteral("hexproof-limited-product-builder");
    bool ok = false;
    {
        QSqlDatabase database =
            QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setDatabaseName(databasePath);
        if (!database.open()) {
            *error = database.lastError().text();
        } else if (!database.transaction()) {
            *error = database.lastError().text();
        } else {
            QSqlQuery insert(database);
            ok = insert.prepare(
                QStringLiteral("INSERT INTO limited_products "
                               "(id, name, set_code, product_type, authentic, definition_json) "
                               "VALUES (?, ?, ?, ?, ?, ?)"));
            int count = 0;
            for (const QJsonValue &value : root.value(QStringLiteral("products")).toArray()) {
                const QJsonObject product = value.toObject();
                const QString id = product.value(QStringLiteral("id")).toString();
                const QString name = product.value(QStringLiteral("name")).toString();
                const QString setCode = product.value(QStringLiteral("setCode")).toString();
                const QString type = product.value(QStringLiteral("productType")).toString();
                if (!ok || id.isEmpty() || name.isEmpty() || setCode.isEmpty() || type.isEmpty() ||
                    !product.value(QStringLiteral("sheets")).isArray() ||
                    !product.value(QStringLiteral("variants")).isArray()) {
                    ok = false;
                    *error =
                        QStringLiteral("The limited product catalog contains an invalid product.");
                    break;
                }
                insert.bindValue(0, id);
                insert.bindValue(1, name);
                insert.bindValue(2, setCode);
                insert.bindValue(3, type);
                insert.bindValue(4, product.value(QStringLiteral("authentic")).toBool() ? 1 : 0);
                insert.bindValue(5, QJsonDocument(product).toJson(QJsonDocument::Compact));
                if (!insert.exec()) {
                    ok = false;
                    *error = insert.lastError().text();
                    break;
                }
                ++count;
            }
            if (ok && count == 0) {
                ok = false;
                *error = QStringLiteral("The limited product catalog is empty.");
            }
            if (ok) {
                QSqlQuery metadata(database);
                metadata.prepare(
                    QStringLiteral("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)"));
                metadata.addBindValue(QStringLiteral("limited_product_count"));
                metadata.addBindValue(count);
                ok = metadata.exec();
                if (!ok)
                    *error = metadata.lastError().text();
            }
            if (ok)
                ok = database.commit();
            else
                database.rollback();
            if (!ok && error->isEmpty())
                *error = database.lastError().text();
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return ok;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("hexproof-card-database-builder"));

    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("Build a ready-to-import Hexproof SQLite card database."));
    parser.addHelpOption();
    parser.addOption({QStringList{QStringLiteral("s"), QStringLiteral("source")},
                      QStringLiteral("Scryfall JSON, JSONL, or gzip source file."),
                      QStringLiteral("path")});
    parser.addOption({QStringList{QStringLiteral("c"), QStringLiteral("chinese-index")},
                      QStringLiteral("magic-cards-zhs tar.gz archive."), QStringLiteral("path")});
    parser.addOption(
        {QStringList{QStringLiteral("l"), QStringLiteral("localized-source")},
         QStringLiteral("Optional Scryfall All Cards source for the compact zhs printing index."),
         QStringLiteral("path")});
    parser.addOption({QStringList{QStringLiteral("limited-products")},
                      QStringLiteral("Optional generated MTGJSON limited-product definitions."),
                      QStringLiteral("path")});
    parser.addOption({QStringList{QStringLiteral("o"), QStringLiteral("output")},
                      QStringLiteral("Destination SQLite file."), QStringLiteral("path")});
    parser.process(application);

    const QString sourcePath = parser.value(QStringLiteral("source"));
    const QString chinesePath = parser.value(QStringLiteral("chinese-index"));
    const QString localizedPath = parser.value(QStringLiteral("localized-source"));
    const QString limitedProductsPath = parser.value(QStringLiteral("limited-products"));
    const QString outputPath = parser.value(QStringLiteral("output"));
    if (!QFileInfo(sourcePath).isReadable() || !QFileInfo(chinesePath).isReadable() ||
        (!localizedPath.isEmpty() && !QFileInfo(localizedPath).isReadable()) ||
        (!limitedProductsPath.isEmpty() && !QFileInfo(limitedProductsPath).isReadable()) ||
        outputPath.isEmpty()) {
        parser.showHelp(2);
    }

    const QString outputDirectory = QFileInfo(outputPath).absolutePath();
    if (!QDir().mkpath(outputDirectory)) {
        QTextStream(stderr) << "Could not create the output directory." << Qt::endl;
        return 1;
    }
    QTemporaryDir stagingDirectory(
        QDir(outputDirectory).filePath(QStringLiteral(".hexproof-database-build-XXXXXX")));
    if (!stagingDirectory.isValid()) {
        QTextStream(stderr) << "Could not create the database staging directory." << Qt::endl;
        return 1;
    }
    const QString stagingPath = stagingDirectory.filePath(QStringLiteral("database.sqlite"));
    const CardCatalog::ImportResult result = CardCatalog::importBulkFile(
        sourcePath, stagingPath, QStringLiteral("default_cards"), chinesePath, localizedPath);
    if (!result.ok) {
        QTextStream(stderr) << result.error << Qt::endl;
        return 1;
    }
    QString limitedError;
    if (!importLimitedProducts(limitedProductsPath, stagingPath, &limitedError)) {
        QTextStream(stderr) << limitedError << Qt::endl;
        return 1;
    }
    if (!catalogstorage::installDatabase(stagingPath, outputPath, &limitedError)) {
        QTextStream(stderr) << limitedError << Qt::endl;
        return 1;
    }

    const QJsonObject summary{
        {QStringLiteral("path"), outputPath},
        {QStringLiteral("package"), result.packageType},
        {QStringLiteral("card_count"), result.cardCount},
        {QStringLiteral("alias_count"), result.aliasCount},
        {QStringLiteral("token_count"), result.tokenCount},
        {QStringLiteral("localized_printing_count"), result.localizedPrintingCount},
    };
    QTextStream(stdout) << QJsonDocument(summary).toJson(QJsonDocument::Compact) << Qt::endl;
    return 0;
}
