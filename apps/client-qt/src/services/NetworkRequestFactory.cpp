// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "NetworkRequestFactory.h"

namespace hexproof::client {

bool hostRequiresHttp11(const QUrl &url)
{
    const QString host = url.host();
    return host.compare(QLatin1String("cards.scryfall.io"), Qt::CaseInsensitive) == 0 ||
           host.compare(QLatin1String("api.scryfall.com"), Qt::CaseInsensitive) == 0;
}

void applyHttpVersionPolicy(QNetworkRequest &request)
{
    if (!hostRequiresHttp11(request.url()))
        return;
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
}

QNetworkRequest makeNetworkRequest(const QUrl &url, const QByteArray &accept, int transferTimeoutMs)
{
    QNetworkRequest request(url);
    request.setRawHeader(QByteArrayLiteral("User-Agent"),
                         QByteArrayLiteral("Hexproof/") + QByteArrayLiteral(HEXPROOF_VERSION) +
                             QByteArrayLiteral(" (+https://github.com/ClayStan404/hexproof)"));
    request.setRawHeader(QByteArrayLiteral("Accept"), accept);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    applyHttpVersionPolicy(request);
    request.setTransferTimeout(transferTimeoutMs);
    return request;
}

} // namespace hexproof::client
