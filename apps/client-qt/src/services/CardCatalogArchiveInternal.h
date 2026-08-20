// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#pragma once
#include "CardCatalogCommon.h"
namespace hexproof::client::catalog_internal {

inline bool readGzipExactly(gzFile file, char *target, qint64 size,
                            CatalogImportStopToken stopToken = {})
{
    qint64 offset = 0;
    while (offset < size) {
        if (stopToken.stopRequested())
            return false;
        const int request =
            static_cast<int>(qMin<qint64>(size - offset, std::numeric_limits<int>::max()));
        const int received = gzread(file, target + offset, request);
        if (received <= 0)
            return false;
        offset += received;
    }
    return true;
}

inline QByteArray tarField(const char *data, int size)
{
    QByteArray value(data, size);
    const qsizetype nul = value.indexOf('\0');
    if (nul >= 0)
        value.truncate(nul);
    return value;
}

inline bool tarOctal(const char *data, int size, qint64 *value)
{
    QByteArray field(data, size);
    field.replace('\0', ' ');
    field = field.trimmed();
    if (field.isEmpty()) {
        *value = 0;
        return true;
    }
    bool ok = false;
    const qulonglong parsed = field.toULongLong(&ok, 8);
    if (!ok || parsed > static_cast<qulonglong>(std::numeric_limits<qint64>::max()))
        return false;
    *value = static_cast<qint64>(parsed);
    return true;
}

inline bool validTarChecksum(const QByteArray &header)
{
    qint64 expected = 0;
    if (!tarOctal(header.constData() + 148, 8, &expected))
        return false;
    qint64 actual = 0;
    for (int index = 0; index < header.size(); ++index) {
        actual += index >= 148 && index < 156 ? static_cast<unsigned char>(' ')
                                              : static_cast<unsigned char>(header.at(index));
    }
    return actual == expected;
}

inline bool extractChineseNameFile(const QString &archivePath, const QString &outputPath,
                                   QString *error, CatalogImportStopToken stopToken = {},
                                   CatalogImportResult *result = nullptr)
{
    if (stopToken.stopRequested()) {
        if (result)
            cancelCatalogImportIfRequested(stopToken, result);
        return false;
    }
#ifdef Q_OS_WIN
    gzFile archive = gzopen_w(reinterpret_cast<const wchar_t *>(archivePath.utf16()), "rb");
#else
    gzFile archive = gzopen(QFile::encodeName(archivePath).constData(), "rb");
#endif
    if (!archive) {
        *error = QStringLiteral("Could not open the downloaded Chinese name index.");
        return false;
    }

    QSaveFile output(outputPath);
    bool found = false;
    std::array<char, 64 * 1024> buffer{};
    while (!found) {
        if (stopToken.stopRequested()) {
            if (result)
                cancelCatalogImportIfRequested(stopToken, result);
            if (output.isOpen())
                output.cancelWriting();
            break;
        }
        QByteArray header(512, Qt::Uninitialized);
        if (!readGzipExactly(archive, header.data(), header.size(), stopToken)) {
            if (stopToken.stopRequested() && result)
                cancelCatalogImportIfRequested(stopToken, result);
            break;
        }
        bool allZero = true;
        for (const char byte : header) {
            if (byte != '\0') {
                allZero = false;
                break;
            }
        }
        if (allZero)
            break;
        if (!validTarChecksum(header)) {
            *error = QStringLiteral("The Chinese name index archive is damaged.");
            break;
        }

        const QByteArray name = tarField(header.constData(), 100);
        const QByteArray prefix = tarField(header.constData() + 345, 155);
        const QByteArray path = prefix.isEmpty() ? name : prefix + '/' + name;
        qint64 entrySize = 0;
        if (!tarOctal(header.constData() + 124, 12, &entrySize) || entrySize < 0 ||
            entrySize > kMaximumChineseNameFileBytes) {
            *error = QStringLiteral("The Chinese name index archive contains an invalid file.");
            break;
        }
        const bool wanted = (path == QByteArrayLiteral("zhs_oracle.json") ||
                             path == QByteArrayLiteral("./zhs_oracle.json")) &&
                            (header.at(156) == '\0' || header.at(156) == '0');
        if (wanted && !output.open(QIODevice::WriteOnly)) {
            *error = QStringLiteral("Could not create the Chinese name index file.");
            break;
        }

        qint64 remaining = entrySize;
        while (remaining > 0) {
            if (stopToken.stopRequested()) {
                if (result)
                    cancelCatalogImportIfRequested(stopToken, result);
                if (output.isOpen())
                    output.cancelWriting();
                remaining = -1;
                break;
            }
            const qint64 amount = qMin<qint64>(remaining, buffer.size());
            if (!readGzipExactly(archive, buffer.data(), amount, stopToken)) {
                if (stopToken.stopRequested()) {
                    if (result)
                        cancelCatalogImportIfRequested(stopToken, result);
                    if (output.isOpen())
                        output.cancelWriting();
                    remaining = -1;
                    break;
                }
                *error = QStringLiteral("The Chinese name index archive ended unexpectedly.");
                remaining = -1;
                break;
            }
            if (wanted && output.write(buffer.data(), amount) != amount) {
                *error = QStringLiteral("Could not write the Chinese name index file.");
                remaining = -1;
                break;
            }
            remaining -= amount;
        }
        if (remaining < 0)
            break;

        const qint64 padding = (512 - (entrySize % 512)) % 512;
        if (padding > 0 && !readGzipExactly(archive, buffer.data(), padding, stopToken)) {
            if (stopToken.stopRequested()) {
                if (result)
                    cancelCatalogImportIfRequested(stopToken, result);
                if (output.isOpen())
                    output.cancelWriting();
                break;
            }
            *error = QStringLiteral("The Chinese name index archive ended unexpectedly.");
            break;
        }
        if (wanted) {
            if (!output.commit()) {
                *error = QStringLiteral("Could not write the Chinese name index file.");
                break;
            }
            found = true;
        }
    }
    gzclose(archive);
    if (!found && error->isEmpty() && !(result && result->cancelled))
        *error = QStringLiteral("The Chinese name index archive did not contain card names.");
    return found;
}

inline gzFile openGzipFile(const QString &path)
{
#ifdef Q_OS_WIN
    return gzopen_w(reinterpret_cast<const wchar_t *>(path.utf16()), "rb");
#else
    return gzopen(QFile::encodeName(path).constData(), "rb");
#endif
}

} // namespace hexproof::client::catalog_internal
