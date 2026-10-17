// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "FramePolish.h"

#include <QPointer>
#include <QQmlExpression>
#include <QQmlInfo>

namespace hexproof::client {

FramePolish::FramePolish(QQuickItem *parent)
    : QQuickItem(parent)
{
    connect(this, &QQuickItem::enabledChanged, this, [this] {
        if (m_expression)
            m_expression->setNotifyOnValueChanged(isEnabled());
        if (isEnabled())
            request();
        else
            m_pending = false;
    });
}

FramePolish::~FramePolish() = default;

QQmlScriptString FramePolish::expression() const
{
    return m_script;
}

void FramePolish::setExpression(const QQmlScriptString &expression)
{
    if (m_script == expression)
        return;
    m_script = expression;
    m_expression.reset();
    if (!m_script.isEmpty()) {
        m_expression = std::make_shared<QQmlExpression>(m_script);
        m_expression->setNotifyOnValueChanged(isEnabled());
        // QQmlExpression observes the properties read by evaluate(), but a
        // dependency change only emits valueChanged; it does not re-evaluate.
        connect(m_expression.get(), &QQmlExpression::valueChanged, this, &FramePolish::request);
    }
    request();
    emit expressionChanged();
}

QVariant FramePolish::value() const
{
    return m_value;
}

void FramePolish::request()
{
    if (!isEnabled())
        return;
    m_pending = true;
    polish();
}

void FramePolish::updatePolish()
{
    if (!m_pending)
        return;
    // A geometry change caused by publication may request another polish.
    m_pending = false;
    QPointer<FramePolish> guard(this);
    const auto expression = m_expression;
    if (expression) {
        const QVariant next = expression->evaluate();
        // QML evaluation can invoke callbacks that replace the expression,
        // disable the publisher, or destroy it. Never publish that stale result.
        if (!guard || m_expression != expression || !isEnabled())
            return;
        if (expression->hasError()) {
            qmlWarning(this) << expression->error().toString();
        } else if (next != m_value) {
            m_value = next;
            emit valueChanged();
        }
    } else if (m_value.isValid()) {
        m_value.clear();
        emit valueChanged();
    }
    if (guard)
        emit ready();
}

} // namespace hexproof::client
