// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QString>

namespace hexproof::client {

struct AccountVaultResult
{
    bool available = false;
    QString token;
};

// Called on a worker thread. Empty writes delete a session. Login/recovery
// codes never enter the vault; its key includes the local profile and realm.
AccountVaultResult readAccountVault(const QString &key);
bool writeAccountVault(const QString &key, const QString &token);

} // namespace hexproof::client
