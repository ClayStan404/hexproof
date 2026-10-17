// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "ForgeCrashReportService.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <cmath>

namespace hexproof::client {
namespace {
using namespace Qt::StringLiterals;

// Hub diagnostics are already public-safe. This second projection never copies
// unknown fields, messages, paths, credentials or arbitrary nested objects.
class Projection
{
  public:
    bool valid = true;
    QString text(const QJsonObject &source, const QString &key, int limit = 128,
                 const QString &pattern = {})
    {
        if (!source.contains(key))
            return {};
        const auto value = source.value(key);
        const auto text = value.toString();
        if (!value.isString() || text.size() > limit) {
            valid = false;
            return {};
        }
        for (const auto ch : text)
            if (ch.category() == QChar::Other_Control || ch.category() == QChar::Other_Format ||
                ch == QChar::LineSeparator || ch == QChar::ParagraphSeparator)
                valid = false;
        if (!text.isEmpty() && !pattern.isEmpty() &&
            !QRegularExpression(pattern).match(text).hasMatch())
            valid = false;
        return text;
    }
    QString token(const QJsonObject &source, const QString &key, int limit = 128)
    {
        return text(source, key, limit, u"^[A-Za-z0-9_.$<>:-]+$"_s);
    }
    double number(const QJsonObject &source, const QString &key, double min = 0,
                  double max = 9007199254740991.0)
    {
        if (!source.contains(key))
            return min < 0 ? 0 : min;
        const auto value = source.value(key);
        const auto number = value.toDouble();
        if (!value.isDouble() || !std::isfinite(number) || std::floor(number) != number ||
            number < min || number > max)
            valid = false;
        return number;
    }
    bool boolean(const QJsonObject &source, const QString &key)
    {
        if (source.contains(key) && !source.value(key).isBool())
            valid = false;
        return source.value(key).toBool();
    }
    QJsonObject object(const QJsonObject &source, const QString &key)
    {
        if (!source.value(key).isObject())
            valid = false;
        return source.value(key).toObject();
    }
    QJsonArray array(const QJsonObject &source, const QString &key, int limit)
    {
        const auto value = source.value(key);
        if ((!value.isArray() && !value.isNull() && !value.isUndefined()) ||
            value.toArray().size() > limit)
            valid = false;
        const auto result = value.toArray();
        return result.size() <= limit ? result : QJsonArray{};
    }
    void optionalNumber(QJsonObject &result, const QJsonObject &source, const QString &key,
                        double min = 0, double max = 9007199254740991.0)
    {
        if (source.contains(key))
            result.insert(key, number(source, key, min, max));
    }
    QJsonObject failure(const QJsonObject &source)
    {
        const auto kind = token(source, u"kind"_s);
        if (!QStringList{u"engine_exception"_s, u"resource_exhausted"_s, u"execution_timeout"_s,
                         u"protocol_failure"_s, u"process_exit"_s, u"host_connection_lost"_s}
                 .contains(kind))
            valid = false;
        QJsonObject result{{u"kind"_s, kind},
                           {u"code"_s, token(source, u"code"_s)},
                           {u"stage"_s, token(source, u"stage"_s)}};
        for (const auto &key : {u"requestFamily"_s, u"exitSignal"_s})
            if (source.contains(key))
                result.insert(key, token(source, key));
        optionalNumber(result, source, u"exitCode"_s, -2147483648.0, 2147483647);
        QJsonArray causes;
        int frameCount = 0;
        for (const auto &item : array(source, u"causes"_s, 4)) {
            if (!item.isObject())
                valid = false;
            const auto cause = item.toObject();
            QJsonArray frames;
            for (const auto &frameItem : array(cause, u"frames"_s, 32)) {
                if (!frameItem.isObject() || ++frameCount > 32)
                    valid = false;
                const auto frame = frameItem.toObject();
                frames.append(QJsonObject{{u"className"_s, token(frame, u"className"_s, 256)},
                                          {u"methodName"_s, token(frame, u"methodName"_s, 256)},
                                          {u"line"_s, number(frame, u"line"_s, -2, 10000000)}});
            }
            causes.append(QJsonObject{{u"className"_s, token(cause, u"className"_s, 256)},
                                      {u"frames"_s, frames}});
        }
        result.insert(u"causes"_s, causes);
        return result;
    }
};
} // namespace

QJsonObject normalizedForgeCrashReport(const QJsonObject &source)
{
    if (QJsonDocument(source).toJson(QJsonDocument::Compact).size() > 64 * 1024)
        return {};
    if (!source.value(u"revision"_s).isDouble())
        return {};
    Projection p;
    const auto id = p.text(source, u"reportId"_s, 64, u"^(?:[a-f0-9]{32}|[a-f0-9]{64})$"_s);
    const auto fingerprint = p.text(source, u"fingerprint"_s, 64, u"^[a-f0-9]{64}$"_s);
    const auto occurrence = p.text(source, u"occurredAt"_s, 40);
    const auto time = QDateTime::fromString(occurrence, Qt::ISODateWithMs);
    const auto state = p.token(source, u"collectionState"_s);
    if (p.number(source, u"schemaVersion"_s) != 1 ||
        p.number(source, u"fingerprintVersion"_s) != 1 || id.isEmpty() || fingerprint.isEmpty() ||
        !time.isValid() || !occurrence.endsWith(u'Z') ||
        !QStringList{u"collecting"_s, u"complete"_s, u"partial"_s}.contains(state))
        return {};
    if (source.value(u"revision"_s).toInt() == 2 && state == u"collecting"_s)
        return {};
    QJsonObject result{{u"schemaVersion"_s, 1},
                       {u"reportId"_s, id},
                       {u"revision"_s, p.number(source, u"revision"_s, 1, 2)},
                       {u"collectionState"_s, state},
                       {u"occurredAt"_s, occurrence},
                       {u"fingerprintVersion"_s, 1},
                       {u"fingerprint"_s, fingerprint}};
    const auto versions = p.object(source, u"versions"_s);
    result.insert(u"versions"_s,
                  QJsonObject{{u"hexproof"_s, p.token(versions, u"hexproof"_s)},
                              {u"runtime"_s, p.token(versions, u"runtime"_s, 256)},
                              {u"forge"_s, p.token(versions, u"forge"_s)},
                              {u"adapter"_s, p.number(versions, u"adapter"_s, 0, 1000000)}});
    const auto environment = p.object(source, u"environment"_s);
    result.insert(
        u"environment"_s,
        QJsonObject{{u"hostingMode"_s, p.token(environment, u"hostingMode"_s)},
                    {u"format"_s, p.token(environment, u"format"_s)},
                    {u"participants"_s, p.number(environment, u"participants"_s, 1, 16)},
                    {u"gameNumber"_s, p.number(environment, u"gameNumber"_s, 0, 1000000)}});
    result.insert(u"failure"_s, p.failure(p.object(source, u"failure"_s)));
    if (source.contains(u"recoveryFailure"_s))
        result.insert(u"recoveryFailure"_s, p.failure(p.object(source, u"recoveryFailure"_s)));
    const auto context = p.object(source, u"context"_s);
    const auto attribution = p.token(context, u"attribution"_s);
    if (!QStringList{u"execution_site"_s, u"resolution_context"_s, u"recent_context"_s,
                     u"unknown"_s}
             .contains(attribution))
        return {};
    QJsonObject safeContext{{u"attribution"_s, attribution},
                            {u"turn"_s, p.number(context, u"turn"_s, 0, 10000000)},
                            {u"step"_s, p.token(context, u"step"_s)},
                            {u"publicSequence"_s, p.number(context, u"publicSequence"_s)}};
    p.optionalNumber(safeContext, context, u"activeSeat"_s, -1, 15);
    p.optionalNumber(safeContext, context, u"observationAgeMs"_s);
    QJsonArray spans;
    for (const auto &item : p.array(context, u"spans"_s, 8)) {
        if (!item.isObject())
            p.valid = false;
        const auto span = item.toObject();
        QJsonObject safe{{u"id"_s, p.number(span, u"id"_s)},
                         {u"parentId"_s, p.number(span, u"parentId"_s)},
                         {u"stage"_s, p.token(span, u"stage"_s)}};
        for (const auto &key : {u"api"_s, u"sourceId"_s})
            if (span.contains(key))
                safe.insert(key, p.token(span, key));
        spans.append(safe);
    }
    safeContext.insert(u"spans"_s, spans);
    QJsonArray sources;
    for (const auto &item : p.array(context, u"sources"_s, 4)) {
        if (!item.isObject())
            p.valid = false;
        const auto card = item.toObject();
        const auto zone = p.token(card, u"zone"_s);
        if (!QStringList{u"battlefield"_s, u"graveyard"_s, u"exile"_s, u"command"_s, u"stack"_s,
                         u"ante"_s}
                 .contains(zone))
            p.valid = false;
        const auto identity = p.object(card, u"identity"_s);
        QJsonObject safeIdentity{
            {u"name"_s, p.text(identity, u"name"_s, 256)},
            {u"setCode"_s, p.text(identity, u"setCode"_s, 32)},
            {u"collectorNumber"_s, p.text(identity, u"collectorNumber"_s, 64)}};
        if (identity.contains(u"token"_s))
            safeIdentity.insert(u"token"_s, p.boolean(identity, u"token"_s));
        sources.append(QJsonObject{
            {u"id"_s, p.token(card, u"id"_s)}, {u"zone"_s, zone}, {u"identity"_s, safeIdentity}});
    }
    safeContext.insert(u"sources"_s, sources);
    QJsonArray events;
    for (const auto &item : p.array(context, u"events"_s, 32)) {
        if (!item.isObject())
            p.valid = false;
        const auto event = item.toObject();
        QJsonObject safe{{u"sequence"_s, p.number(event, u"sequence"_s)},
                         {u"kind"_s, p.token(event, u"kind"_s)},
                         {u"origin"_s, p.token(event, u"origin"_s)}};
        if (!QStringList{u"native"_s, u"hub"_s}.contains(safe.value(u"origin"_s).toString()))
            p.valid = false;
        for (const auto &key : {u"stage"_s, u"api"_s, u"step"_s})
            if (event.contains(key))
                safe.insert(key, p.token(event, key));
        for (const auto &key : {u"spanId"_s, u"turn"_s})
            p.optionalNumber(safe, event, key);
        p.optionalNumber(safe, event, u"seat"_s, -1, 15);
        if (event.contains(u"automatic"_s))
            safe.insert(u"automatic"_s, p.boolean(event, u"automatic"_s));
        events.append(safe);
    }
    safeContext.insert(u"events"_s, events);
    result.insert(u"context"_s, safeContext);
    const auto completeness = p.object(source, u"completeness"_s);
    QJsonObject safeCompleteness;
    for (const auto &key : {u"nativeEvidence"_s, u"exitEvidence"_s})
        safeCompleteness.insert(key, p.boolean(completeness, key));
    for (const auto &key : {u"omittedFrames"_s, u"omittedCauses"_s, u"omittedSpans"_s,
                            u"omittedSources"_s, u"droppedEvents"_s})
        safeCompleteness.insert(key, p.number(completeness, key, 0, 2147483647));
    QJsonArray missing;
    for (const auto &item : p.array(completeness, u"missing"_s, 16))
        missing.append(p.token(QJsonObject{{u"item"_s, item}}, u"item"_s));
    safeCompleteness.insert(u"missing"_s, missing);
    result.insert(u"completeness"_s, safeCompleteness);
    return p.valid ? result : QJsonObject{};
}
} // namespace hexproof::client
