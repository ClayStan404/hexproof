// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "deck/DeckFormat.h"
#include "deck/DeckListFileIO.h"
#include "deck/DeckParser.h"
#include "models/DeckLibraryQueries.h"
#include "services/BackgroundTaskPools.h"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QTimer>
#include <QUuid>
#include <QtConcurrent>

#include <utility>

namespace hexproof::client {

bool DeckLibraryModel::importDeck(const QString &name, const QString &format, const QString &text)
{
    clearLastError();
    setLastImportWarnings({});
    QString deckName;
    QString deckFormat;
    if (!validateDeckImport(name, format, &deckName, &deckFormat))
        return false;

    const DeckParseProfile parseProfile =
        isCubeDeckFormat(deckFormat) ? DeckParseProfile::Cube : DeckParseProfile::Constructed;
    return commitDeckImport(
        deckName, deckFormat,
        DeckParser::parse(text, isCommanderTableMode(tableModeForDeckFormat(deckFormat)),
                          parseProfile));
}

bool DeckLibraryModel::importDeckAsync(const QString &name, const QString &format,
                                       const QString &text)
{
    if (m_importingDeck)
        return false;

    clearLastError();
    setLastImportWarnings({});
    QString deckName;
    QString deckFormat;
    if (!validateDeckImport(name, format, &deckName, &deckFormat))
        return false;

    m_pendingImportName = deckName;
    m_pendingImportFormat = deckFormat;
    m_importingDeck = true;
    setImportStage(QStringLiteral("parsing"));
    emit importingDeckChanged();
    const bool commander = isCommanderTableMode(tableModeForDeckFormat(deckFormat));
    const DeckParseProfile parseProfile =
        isCubeDeckFormat(deckFormat) ? DeckParseProfile::Cube : DeckParseProfile::Constructed;
    m_importWatcher.setFuture(
        QtConcurrent::run(BackgroundTaskPools::deckParsing(), [text, commander, parseProfile]() {
            return DeckParser::parse(text, commander, parseProfile);
        }));
    return true;
}

QVariantMap DeckLibraryModel::loadDeckTextFile(const QUrl &fileUrl)
{
    clearLastError();
    const DeckListFileData loaded = loadDeckListFile(fileUrl);
    if (!loaded.error.isEmpty()) {
        setLastError(loaded.error);
        return {};
    }
    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("text"), loaded.text},
        {QStringLiteral("suggestedName"), loaded.suggestedName},
    };
}

bool DeckLibraryModel::validateDeckImport(const QString &name, const QString &format,
                                          QString *deckName, QString *deckFormat)
{
    *deckName = name.simplified();
    *deckFormat = normalizedDeckFormat(format);
    if (deckName->isEmpty()) {
        setLastError(QStringLiteral("Give the deck a name before importing."));
        return false;
    }
    if (!supportedDeckFormat(*deckFormat)) {
        setLastError(QStringLiteral("Choose a supported deck format."));
        return false;
    }
    return true;
}

bool DeckLibraryModel::commitDeckImport(const QString &deckName, const QString &deckFormat,
                                        const DeckParseResult &parsed)
{
    if (!parsed.ok()) {
        setLastError(parsed.error);
        return false;
    }

    Deck deck = parsed.deck;
    deck.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    deck.name = deckName;
    deck.deckFormat = deckFormat;
    deck.format = tableModeForDeckFormat(deckFormat);
    if (isCubeDeckFormat(deckFormat)) {
        mergeSideboardIntoMain(deck);
        deck.commanders.clear();
    }
    deck.createdAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    deck.updatedAt = deck.createdAt;

    m_decks.prepend(deck);
    if (!save()) {
        m_decks.removeFirst();
        return false;
    }
    beginResetModel();
    rebuildVisibleRows();
    rebuildCardDeckIndex();
    endResetModel();
    scheduleDeckValidation(deck.id);
    emit countChanged();
    requestCatalogMetadata(m_decks.constFirst(), false);
    emit cardsNeedCachedArtLookup(
        DeckLibraryQueries::cacheRequestsForDeck(m_decks.constFirst(), true));

    setLastImportWarnings(parsed.warnings);
    return true;
}

void DeckLibraryModel::finishAsyncDeckImport()
{
    m_pendingParsedImport = m_importWatcher.result();
    setImportStage(QStringLiteral("finalizing"));
    QTimer::singleShot(16, this, &DeckLibraryModel::commitPendingAsyncDeckImport);
}

void DeckLibraryModel::commitPendingAsyncDeckImport()
{
    const DeckParseResult parsed = std::exchange(m_pendingParsedImport, {});
    const QString deckName = std::exchange(m_pendingImportName, {});
    const QString deckFormat = std::exchange(m_pendingImportFormat, {});
    const bool success = commitDeckImport(deckName, deckFormat, parsed);
    m_importingDeck = false;
    setImportStage({});
    emit importingDeckChanged();
    emit deckImportFinished(success);
}

QString DeckLibraryModel::exportDeckText(const QString &id) const
{
    const Deck *deck = deckById(id);
    return deck ? DeckParser::format(*deck) : QString{};
}

QString DeckLibraryModel::exportCurrentDeckText() const
{
    return exportDeckText(m_currentDeckId);
}

QString DeckLibraryModel::suggestedExportFileName(const QString &id) const
{
    const Deck *deck = deckById(id);
    return deck ? exportFileNameForDeck(*deck) : QString{};
}

QUrl DeckLibraryModel::suggestedExportUrl(const QString &id) const
{
    const QString fileName = suggestedExportFileName(id);
    if (fileName.isEmpty())
        return {};
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return QUrl::fromLocalFile(QDir(folder).filePath(fileName));
}

bool DeckLibraryModel::copyDeckText(const QString &id)
{
    const QString text = exportDeckText(id);
    if (text.isEmpty()) {
        setLastError(QStringLiteral("Deck not found."));
        return false;
    }
    QGuiApplication *app = qGuiApp;
    if (!app || !app->clipboard()) {
        setLastError(QStringLiteral("The clipboard is not available."));
        return false;
    }
    app->clipboard()->setText(text);
    return true;
}

bool DeckLibraryModel::copyCurrentDeckText()
{
    return copyDeckText(m_currentDeckId);
}

bool DeckLibraryModel::saveDeckText(const QString &id, const QUrl &fileUrl)
{
    const QString text = exportDeckText(id);
    if (text.isEmpty()) {
        setLastError(QStringLiteral("Deck not found."));
        return false;
    }
    if (!fileUrl.isLocalFile()) {
        setLastError(QStringLiteral("Choose a local file to export the deck list."));
        return false;
    }
    const QString path = fileUrl.toLocalFile();
    if (path.isEmpty()) {
        setLastError(QStringLiteral("Choose a file to export the deck list."));
        return false;
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setLastError(QStringLiteral("The deck list could not be saved."));
        return false;
    }
    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);
    stream << text;
    if (stream.status() != QTextStream::Ok) {
        file.cancelWriting();
        setLastError(QStringLiteral("The deck list could not be saved."));
        return false;
    }
    if (!file.commit()) {
        setLastError(QStringLiteral("The deck list could not be saved."));
        return false;
    }
    return true;
}

bool DeckLibraryModel::saveCurrentDeckText(const QUrl &fileUrl)
{
    return saveDeckText(m_currentDeckId, fileUrl);
}

} // namespace hexproof::client
