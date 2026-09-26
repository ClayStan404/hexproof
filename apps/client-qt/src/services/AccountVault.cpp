// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "AccountVault.h"

#if defined(Q_OS_WIN)
#include <windows.h>

#include <wincred.h>
#elif defined(Q_OS_MACOS)
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#elif defined(HEXPROOF_HAVE_LIBSECRET)
#pragma push_macro("signals")
#undef signals
#include <chrono>
#include <condition_variable>
#include <libsecret/secret.h>
#include <mutex>
#include <thread>
#pragma pop_macro("signals")
#endif

namespace hexproof::client {

#if defined(HEXPROOF_HAVE_LIBSECRET)
// A locked or absent desktop vault must not keep application shutdown waiting
// for an unattended prompt. Cancellation also bounds serialized read/write work.
class VaultDeadline final
{
  public:
    GCancellable *cancel = g_cancellable_new();
    std::jthread timer{[this](std::stop_token stop) {
        std::mutex mutex;
        std::condition_variable_any wake;
        std::unique_lock lock(mutex);
        wake.wait_for(lock, stop, std::chrono::seconds(5), [] { return false; });
        if (!stop.stop_requested())
            g_cancellable_cancel(cancel);
    }};
    ~VaultDeadline()
    {
        timer.request_stop();
        timer.join();
        g_object_unref(cancel);
    }
};

static const SecretSchema *accountSchema()
{
    static const SecretSchema schema = [] {
        SecretSchema value{};
        value.name = "io.github.claystan404.hexproof.account";
        value.flags = SECRET_SCHEMA_NONE;
        value.attributes[0] = {"key", SECRET_SCHEMA_ATTRIBUTE_STRING};
        return value;
    }();
    return &schema;
}
#endif

#if defined(Q_OS_MACOS)
static CFMutableDictionaryRef accountQuery(const QString &key)
{
    auto query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                           &kCFTypeDictionaryValueCallBacks);
    const auto bytes = key.toUtf8();
    auto account = CFStringCreateWithBytes(kCFAllocatorDefault,
                                           reinterpret_cast<const UInt8 *>(bytes.constData()),
                                           bytes.size(), kCFStringEncodingUTF8, false);
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, CFSTR("io.github.claystan404.hexproof.account"));
    CFDictionarySetValue(query, kSecAttrAccount, account);
    CFRelease(account);
    return query;
}
#endif

AccountVaultResult readAccountVault(const QString &key)
{
#if defined(Q_OS_WIN)
    const auto name = (QStringLiteral("Hexproof/account/") + key).toStdWString();
    PCREDENTIALW credential = nullptr;
    if (!CredReadW(name.c_str(), CRED_TYPE_GENERIC, 0, &credential))
        return {GetLastError() == ERROR_NOT_FOUND, {}};
    const QString token = QString::fromUtf8(
        reinterpret_cast<const char *>(credential->CredentialBlob), credential->CredentialBlobSize);
    CredFree(credential);
    return {true, token};
#elif defined(Q_OS_MACOS)
    auto query = accountQuery(key);
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFTypeRef result = nullptr;
    const OSStatus status = SecItemCopyMatching(query, &result);
    CFRelease(query);
    QString token;
    if (status == errSecSuccess && result && CFGetTypeID(result) == CFDataGetTypeID()) {
        auto data = static_cast<CFDataRef>(result);
        token = QString::fromUtf8(reinterpret_cast<const char *>(CFDataGetBytePtr(data)),
                                  CFDataGetLength(data));
    }
    if (result)
        CFRelease(result);
    return {status == errSecSuccess || status == errSecItemNotFound, token};
#elif defined(HEXPROOF_HAVE_LIBSECRET)
    VaultDeadline deadline;
    GError *error = nullptr;
    const auto encoded = key.toUtf8();
    gchar *secret = secret_password_lookup_sync(accountSchema(), deadline.cancel, &error, "key",
                                                encoded.constData(), nullptr);
    const bool available = error == nullptr;
    QString token = secret ? QString::fromUtf8(secret) : QString{};
    if (secret)
        secret_password_free(secret);
    if (error)
        g_error_free(error);
    return {available, token};
#else
    Q_UNUSED(key);
    return {};
#endif
}

bool writeAccountVault(const QString &key, const QString &token)
{
#if defined(Q_OS_WIN)
    auto name = (QStringLiteral("Hexproof/account/") + key).toStdWString();
    if (token.isEmpty())
        return CredDeleteW(name.c_str(), CRED_TYPE_GENERIC, 0) || GetLastError() == ERROR_NOT_FOUND;
    const auto bytes = token.toUtf8();
    CREDENTIALW credential{};
    credential.Type = CRED_TYPE_GENERIC;
    credential.TargetName = name.data();
    credential.CredentialBlobSize = static_cast<DWORD>(bytes.size());
    credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char *>(bytes.constData()));
    credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
    return CredWriteW(&credential, 0);
#elif defined(Q_OS_MACOS)
    auto query = accountQuery(key);
    OSStatus status;
    if (token.isEmpty()) {
        status = SecItemDelete(query);
    } else {
        const auto bytes = token.toUtf8();
        auto data = CFDataCreate(kCFAllocatorDefault,
                                 reinterpret_cast<const UInt8 *>(bytes.constData()), bytes.size());
        auto attributes =
            CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                      &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(attributes, kSecValueData, data);
        status = SecItemUpdate(query, attributes);
        if (status == errSecItemNotFound) {
            CFDictionarySetValue(query, kSecValueData, data);
            status = SecItemAdd(query, nullptr);
        }
        CFRelease(attributes);
        CFRelease(data);
    }
    CFRelease(query);
    return status == errSecSuccess || (token.isEmpty() && status == errSecItemNotFound);
#elif defined(HEXPROOF_HAVE_LIBSECRET)
    VaultDeadline deadline;
    GError *error = nullptr;
    const auto encoded = key.toUtf8();
    const auto bytes = token.toUtf8();
    bool ok;
    if (token.isEmpty())
        ok = secret_password_clear_sync(accountSchema(), deadline.cancel, &error, "key",
                                        encoded.constData(), nullptr);
    else
        ok = secret_password_store_sync(
            accountSchema(), SECRET_COLLECTION_DEFAULT, "Hexproof official account session",
            bytes.constData(), deadline.cancel, &error, "key", encoded.constData(), nullptr);
    if (token.isEmpty() && error == nullptr)
        ok = true;
    if (error)
        g_error_free(error);
    return ok;
#else
    Q_UNUSED(key);
    Q_UNUSED(token);
    return false;
#endif
}

} // namespace hexproof::client
