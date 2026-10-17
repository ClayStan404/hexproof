// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QQmlScriptString>
#include <QQuickItem>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <memory>

class QQmlExpression;

namespace hexproof::client {

// Coalesce geometry notifications until Qt Quick polishes the next frame.
// An optional expression observes its dependencies without evaluating on every
// notification; value is published at polish, including synchronous captures.
class FramePolish : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(
        QQmlScriptString expression READ expression WRITE setExpression NOTIFY expressionChanged)
    Q_PROPERTY(QVariant value READ value NOTIFY valueChanged)

  public:
    explicit FramePolish(QQuickItem *parent = nullptr);
    ~FramePolish() override;
    QQmlScriptString expression() const;
    void setExpression(const QQmlScriptString &expression);
    QVariant value() const;
    Q_INVOKABLE void request();

  signals:
    void expressionChanged();
    void valueChanged();
    void ready();

  protected:
    void updatePolish() override;

  private:
    bool m_pending = false;
    QQmlScriptString m_script;
    std::shared_ptr<QQmlExpression> m_expression;
    QVariant m_value;
};

} // namespace hexproof::client
