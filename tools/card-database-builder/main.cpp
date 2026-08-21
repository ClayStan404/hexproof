// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardCatalog.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

using hexproof::client::CardCatalog;

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
    parser.addOption({QStringList{QStringLiteral("o"), QStringLiteral("output")},
                      QStringLiteral("Destination SQLite file."), QStringLiteral("path")});
    parser.process(application);

    const QString sourcePath = parser.value(QStringLiteral("source"));
    const QString chinesePath = parser.value(QStringLiteral("chinese-index"));
    const QString localizedPath = parser.value(QStringLiteral("localized-source"));
    const QString outputPath = parser.value(QStringLiteral("output"));
    if (!QFileInfo(sourcePath).isReadable() || !QFileInfo(chinesePath).isReadable() ||
        (!localizedPath.isEmpty() && !QFileInfo(localizedPath).isReadable()) ||
        outputPath.isEmpty()) {
        parser.showHelp(2);
    }

    const CardCatalog::ImportResult result = CardCatalog::importBulkFile(
        sourcePath, outputPath, QStringLiteral("default_cards"), chinesePath, localizedPath);
    if (!result.ok) {
        QTextStream(stderr) << result.error << Qt::endl;
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
