// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#pragma once

#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>

inline QJsonObject crashReportFixture(const QDateTime &occurred,
                                      const QString &id = QString(32, u'a'), int revision = 1)
{
    using namespace Qt::StringLiterals;
    const QJsonObject frame{{u"className"_s, u"forge.game.ability.effects.DrawEffect"_s},
                            {u"methodName"_s, u"resolve"_s},
                            {u"line"_s, 42}};
    const QJsonObject cause{{u"className"_s, u"java.lang.IllegalStateException"_s},
                            {u"frames"_s, QJsonArray{frame}}};
    return {
        {u"schemaVersion"_s, 1},
        {u"reportId"_s, id},
        {u"revision"_s, revision},
        {u"collectionState"_s, revision == 1 ? u"collecting"_s : u"complete"_s},
        {u"occurredAt"_s, occurred.toUTC().toString(Qt::ISODateWithMs)},
        {u"fingerprintVersion"_s, 1},
        {u"fingerprint"_s, QString(64, u'f')},
        {u"versions"_s, QJsonObject{{u"hexproof"_s, u"2.5.0"_s},
                                    {u"runtime"_s, u"native-test"_s},
                                    {u"forge"_s, QString(40, u'c')},
                                    {u"adapter"_s, 1}}},
        {u"environment"_s, QJsonObject{{u"hostingMode"_s, u"server"_s},
                                       {u"format"_s, u"commander"_s},
                                       {u"participants"_s, 4},
                                       {u"gameNumber"_s, 1}}},
        {u"failure"_s, QJsonObject{{u"kind"_s, u"engine_exception"_s},
                                   {u"code"_s, u"native_failure"_s},
                                   {u"stage"_s, u"effect"_s},
                                   {u"causes"_s, QJsonArray{cause}}}},
        {u"context"_s,
         QJsonObject{
             {u"attribution"_s, u"execution_site"_s},
             {u"turn"_s, 5},
             {u"step"_s, u"main1"_s},
             {u"publicSequence"_s, 12},
             {u"activeSeat"_s, 2},
             {u"observationAgeMs"_s, 7},
             {u"spans"_s, QJsonArray{QJsonObject{{u"id"_s, 2},
                                                 {u"parentId"_s, 1},
                                                 {u"stage"_s, u"effect"_s},
                                                 {u"api"_s, u"Draw"_s},
                                                 {u"sourceId"_s, u"public-1"_s}}}},
             {u"sources"_s, QJsonArray{QJsonObject{
                                {u"id"_s, u"public-1"_s},
                                {u"zone"_s, u"stack"_s},
                                {u"identity"_s, QJsonObject{{u"name"_s, u"Divination"_s},
                                                            {u"setCode"_s, u"M19"_s},
                                                            {u"collectorNumber"_s, u"51"_s}}}}}},
             {u"events"_s, QJsonArray{QJsonObject{{u"sequence"_s, 1},
                                                  {u"origin"_s, u"native"_s},
                                                  {u"kind"_s, u"effect_enter"_s},
                                                  {u"spanId"_s, 2},
                                                  {u"automatic"_s, true}}}}}},
        {u"completeness"_s, QJsonObject{{u"nativeEvidence"_s, true},
                                        {u"exitEvidence"_s, revision > 1},
                                        {u"omittedFrames"_s, 0},
                                        {u"omittedCauses"_s, 0},
                                        {u"omittedSpans"_s, 0},
                                        {u"omittedSources"_s, 0},
                                        {u"droppedEvents"_s, 0},
                                        {u"missing"_s, revision == 1 ? QJsonArray{u"exit_pending"_s}
                                                                     : QJsonArray{}}}}};
}
