// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CatalogSearchController.h"
#include "BackgroundTaskPools.h"
#include "CatalogRepository.h"
#include <QFutureWatcher>
#include <QtConcurrent>

namespace hexproof::client {

CatalogSearchController::CatalogSearchController(QObject *parent)
    : QObject(parent)
{
}

bool CatalogSearchController::Query::empty() const
{
    return text.isEmpty() && type.isEmpty() && set.isEmpty() && language.isEmpty() &&
           color.isEmpty() && rarity.isEmpty() && legality.isEmpty() && mana.isEmpty();
}

void CatalogSearchController::setContext(const QString &databasePath, const QString &language,
                                         bool cardsAvailable, bool tokensAvailable)
{
    m_databasePath = databasePath;
    m_language = language;
    m_cardsAvailable = cardsAvailable;
    m_tokensAvailable = tokensAvailable;
}

void CatalogSearchController::search(Query query)
{
    m_query = {query.text.simplified(),
               query.type.simplified(),
               query.set.simplified().toUpper(),
               query.language.toLower(),
               query.color.simplified().toUpper(),
               query.rarity.simplified().toLower(),
               query.legality.simplified().toLower(),
               query.mana.simplified()};
    m_cards.requested = true;
    request(false, m_cardsAvailable && !m_query.empty());
}

void CatalogSearchController::searchTokens(const QString &text, const QString &kind,
                                           const QStringList &sets)
{
    m_tokenText = text.simplified();
    m_tokenKind = kind == QStringLiteral("token") || kind == QStringLiteral("emblem")
                      ? kind
                      : QStringLiteral("all");
    m_tokenSets = sets;
    m_tokens.requested = true;
    request(true, m_tokensAvailable);
}

void CatalogSearchController::refresh()
{
    if (m_cards.requested)
        request(false, m_cardsAvailable && !m_query.empty());
    if (m_tokens.requested)
        request(true, m_tokensAvailable);
}

void CatalogSearchController::notifySearching(bool tokens)
{
    if (tokens)
        emit tokenSearchingChanged();
    else
        emit searchingChanged();
}

void CatalogSearchController::notifyResults(bool tokens)
{
    if (tokens)
        emit tokensChanged();
    else
        emit cardsChanged();
}

void CatalogSearchController::request(bool tokens, bool enabled)
{
    Channel &channel = tokens ? m_tokens : m_cards;
    const quint64 generation = ++channel.generation;
    const bool hadResults = !channel.results.isEmpty();
    const bool searchingChanged = channel.searching != enabled;
    channel.results.clear();
    channel.searching = enabled;
    if (hadResults)
        notifyResults(tokens);
    if (generation != channel.generation)
        return;
    if (searchingChanged)
        notifySearching(tokens);
    if (generation == channel.generation)
        startLatest(tokens);
}

void CatalogSearchController::startLatest(bool tokens)
{
    Channel &channel = tokens ? m_tokens : m_cards;
    if (channel.running || !channel.searching)
        return;
    channel.running = true;
    const quint64 generation = channel.generation;
    auto *watcher = new QFutureWatcher<CatalogSearchResult>(this);
    connect(watcher, &QFutureWatcher<CatalogSearchResult>::finished, this,
            [this, watcher, tokens, generation]() {
                const CatalogSearchResult result = watcher->result();
                watcher->deleteLater();
                Channel &current = tokens ? m_tokens : m_cards;
                current.running = false;
                if (generation != current.generation) {
                    startLatest(tokens);
                    return;
                }
                const bool changed = current.results != result.cards;
                current.results = result.cards;
                current.searching = false;
                notifySearching(tokens);
                // A signal handler may synchronously issue a new query.
                if (generation != current.generation)
                    return;
                if (tokens)
                    emit tokenSearchFinished(result.error);
                else
                    emit cardSearchFinished(result.error);
                if (generation == current.generation && changed) {
                    notifyResults(tokens);
                }
            });
    const QString database = m_databasePath;
    const QString language = m_language;
    const Query query = m_query;
    const QString tokenText = m_tokenText;
    const QString tokenKind = m_tokenKind;
    const QStringList tokenSets = m_tokenSets;
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::catalogSearch(),
        [database, language, query, tokens, tokenText, tokenKind, tokenSets]() {
            const CatalogRepository repository(database);
            if (tokens)
                return repository.searchTokens(tokenText, language, tokenKind, tokenSets);
            return repository.search(query.text, language, query.type, query.set, query.language,
                                     query.color, query.rarity, query.legality, query.mana);
        }));
}

} // namespace hexproof::client
