// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "NativeAudit.h"
#include "services/ForgeHostService.h"
#include "services/WsClient.h"
#ifdef HEXPROOF_NATIVE_AUDIT_GTK
#include "NativeGtkInput.h"
#endif

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHostAddress>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSaveFile>
#include <QScreen>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>
#include <QWheelEvent>

#include <algorithm>
#include <functional>
#include <memory>

namespace hexproof::client {
namespace {

QString auditEnvironment(const QString &name)
{
    const QString suffix = name.startsWith(QStringLiteral("AUDIT_")) ? name.mid(6) : name;
    const QString preferred = name.startsWith(QStringLiteral("AUDIT_"))
                                  ? QStringLiteral("HEXPROOF_AUDIT_") + suffix
                                  : name;
    const QByteArray value = qgetenv(preferred.toUtf8().constData());
    return QString::fromUtf8(value.isEmpty() ? qgetenv(name.toUtf8().constData()) : value);
}

QVariantMap windowGeometry(QQuickWindow *window)
{
    if (!window)
        return {};
    const auto visibility = window->visibility();
    const QString mode = visibility == QWindow::Maximized    ? QStringLiteral("maximized")
                         : visibility == QWindow::FullScreen ? QStringLiteral("fullscreen")
                         : visibility == QWindow::Windowed   ? QStringLiteral("windowed")
                         : visibility == QWindow::Minimized  ? QStringLiteral("minimized")
                                                             : QStringLiteral("hidden");
    QVariantMap result{{QStringLiteral("width"), window->width()},
                       {QStringLiteral("height"), window->height()},
                       {QStringLiteral("dpr"), window->devicePixelRatio()},
                       {QStringLiteral("visible"), window->isVisible()},
                       {QStringLiteral("exposed"), window->isExposed()},
                       {QStringLiteral("active"), window->isActive()},
                       {QStringLiteral("visibility"), visibility},
                       {QStringLiteral("windowMode"), mode},
                       {QStringLiteral("platform"), QGuiApplication::platformName()}};
    if (const QScreen *screen = window->screen()) {
        const QRect geometry = screen->geometry();
        const QRect available = screen->availableGeometry();
        result.insert(QStringLiteral("screenName"), screen->name());
        result.insert(
            QStringLiteral("screenGeometry"),
            QVariantList{geometry.x(), geometry.y(), geometry.width(), geometry.height()});
        result.insert(
            QStringLiteral("screenAvailableGeometry"),
            QVariantList{available.x(), available.y(), available.width(), available.height()});
    }
    return result;
}

QVariant plainVariant(const QVariant &value)
{
    return value.metaType() == QMetaType::fromType<QJSValue>() ? value.value<QJSValue>().toVariant()
                                                               : value;
}

QVariant field(QObject *object, const QString &path)
{
    const auto parts = path.split(u'.');
    QVariant value = object->property(parts.first().toUtf8().constData());
    for (qsizetype i = 1; i < parts.size(); ++i) {
        value = plainVariant(value);
        if (value.canConvert<QObject *>()) {
            QObject *nested = value.value<QObject *>();
            value = nested ? nested->property(parts[i].toUtf8().constData()) : QVariant{};
        } else {
            value = value.toMap().value(parts[i]);
        }
    }
    return plainVariant(value);
}

bool containsItem(QQuickItem *ancestor, QQuickItem *item)
{
    for (; item; item = item->parentItem())
        if (item == ancestor)
            return true;
    return false;
}

QRectF visibleRect(QQuickItem *item)
{
    if (!item || !item->window() || !item->isVisible() || !item->isEnabled() ||
        item->width() <= 0 || item->height() <= 0)
        return {};
    // Text inputs can override boundingRect() with glyph/cursor bounds. Input
    // geometry and ancestor clipping use the item's layout rectangle.
    QRectF rect = item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
    rect &= QRectF(0, 0, item->window()->width(), item->window()->height());
    for (QQuickItem *ancestor = item; ancestor; ancestor = ancestor->parentItem()) {
        if (!ancestor->isVisible() || !ancestor->isEnabled() || ancestor->opacity() <= 0)
            return {};
        if (ancestor->clip())
            rect &= ancestor->mapRectToScene(QRectF(0, 0, ancestor->width(), ancestor->height()));
    }
    return rect;
}

bool pointerReceiver(QQuickItem *item)
{
    if (item->inherits("QQuickOverlay")) {
        // Overlay remains allocated after popups close and may retain mouse
        // buttons. Its event filter blocks the background only for a visible
        // modal popup; popup children are still tested in visual order.
        for (QObject *object : item->window()->findChildren<QObject *>()) {
            if (object->inherits("QQuickPopup") && object->property("visible").toBool() &&
                object->property("modal").toBool())
                return true;
        }
        return false;
    }
    if (item->acceptedMouseButtons() != Qt::NoButton)
        return true;
    for (QObject *child : item->children()) {
        // Pointer handlers are not QQuickItems. Inspect their public QML
        // properties without depending on Qt Quick private headers.
        if (child->inherits("QQuickPointerHandler") && child->property("enabled").toBool() &&
            child->property("acceptedButtons").toInt() != 0)
            return true;
    }
    return false;
}

QQuickItem *receiverAt(QQuickItem *root, const QPointF &point)
{
    if (!root->isVisible() || !root->isEnabled() || root->opacity() <= 0)
        return nullptr;
    const QPointF local = root->mapFromScene(point);
    if (root->clip() && !root->contains(local))
        return nullptr;
    auto children = root->childItems();
    std::stable_sort(children.begin(), children.end(),
                     [](QQuickItem *a, QQuickItem *b) { return a->z() < b->z(); });
    for (auto it = children.crbegin(); it != children.crend(); ++it)
        if (QQuickItem *hit = receiverAt(*it, point))
            return hit;
    return root->contains(local) && pointerReceiver(root) ? root : nullptr;
}

void visitItems(QQuickItem *root, const std::function<void(QQuickItem *)> &visitor)
{
    visitor(root);
    for (QQuickItem *child : root->childItems())
        visitItems(child, visitor);
}

QVariantMap itemDescription(QQuickItem *item)
{
    const QRectF rect = visibleRect(item);
    QVariantMap description{
        {QStringLiteral("objectName"), item->objectName()},
        {QStringLiteral("class"), QString::fromLatin1(item->metaObject()->className())},
        {QStringLiteral("visible"), item->isVisible()},
        {QStringLiteral("enabled"), item->isEnabled()},
        {QStringLiteral("inViewport"), !rect.isEmpty()},
        {QStringLiteral("focus"), item->hasActiveFocus()},
        {QStringLiteral("rect"), QVariantMap{{QStringLiteral("x"), rect.x()},
                                             {QStringLiteral("y"), rect.y()},
                                             {QStringLiteral("width"), rect.width()},
                                             {QStringLiteral("height"), rect.height()}}}};
    for (const char *property : {"text", "checked", "currentIndex", "count", "atYEnd"}) {
        const QVariant value = item->property(property);
        if (value.isValid())
            description.insert(QString::fromLatin1(property), plainVariant(value));
    }
    // Only report identities belonging to rendered items, not hidden model
    // cards or another seat's private state.
    if (!rect.isEmpty()) {
        QVariantMap identity;
        for (const QString &property :
             {QStringLiteral("card.instanceId"), QStringLiteral("card.name"),
              QStringLiteral("card.setCode"), QStringLiteral("card.collectorNumber")}) {
            const QVariant value = field(item, property);
            if (value.isValid())
                identity.insert(property, value);
        }
        description.insert(QStringLiteral("identity"), identity);
    }
    return description;
}

bool artifactName(const QString &name)
{
    static const QRegularExpression valid(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$"));
    return valid.match(name).hasMatch();
}

} // namespace

QString NativeAudit::profileStorageRoot()
{
    const QFileInfo profile(auditEnvironment(QStringLiteral("HEXPROOF_TEST_PROFILE_ROOT")));
    if (!profile.isAbsolute() || !profile.isDir())
        return {};
    const QString root = profile.canonicalFilePath();
    if (root.isEmpty() || root == QDir::rootPath())
        return {};
    return QDir(root).filePath(QStringLiteral("data/Hexproof/Hexproof"));
}

bool NativeAudit::validateEnvironment(const QString &storageRoot)
{
    const QFileInfo driver(auditEnvironment(QStringLiteral("AUDIT_DRIVER")));
    const QString output = auditEnvironment(QStringLiteral("AUDIT_OUTPUT"));
    const QString profile =
        QFileInfo(auditEnvironment(QStringLiteral("HEXPROOF_TEST_PROFILE_ROOT")))
            .canonicalFilePath();
    const QString storage = QDir::cleanPath(QFileInfo(storageRoot).absoluteFilePath());
    const QString platform = QGuiApplication::platformName();
    const QString widthText = auditEnvironment(QStringLiteral("AUDIT_WIDTH"));
    const QString heightText = auditEnvironment(QStringLiteral("AUDIT_HEIGHT"));
    if ((!widthText.isEmpty() || !heightText.isEmpty()) &&
        (widthText.toInt() < 900 || widthText.toInt() > 7680 || heightText.toInt() < 620 ||
         heightText.toInt() > 4320)) {
        qCritical() << "Native audit window fixture requires WIDTH 900..7680 and HEIGHT 620..4320.";
        return false;
    }
    if (!driver.isAbsolute() || !driver.isFile() || !QDir::isAbsolutePath(output) ||
        storageRoot.isEmpty() || profile.isEmpty() || profile == QDir::rootPath() ||
        !storage.startsWith(profile + u'/') || platform == QStringLiteral("offscreen") ||
        platform == QStringLiteral("minimal")) {
        qCritical() << "Native audit requires an absolute existing HEXPROOF_AUDIT_DRIVER, absolute"
                       " HEXPROOF_AUDIT_OUTPUT, isolated HEXPROOF_TEST_PROFILE_ROOT containing"
                       " the application data directory, and a native Qt display platform.";
        return false;
    }
    if (!QDir().mkpath(output)) {
        qCritical() << "Cannot create native audit output directory:" << output;
        return false;
    }
    return true;
}

NativeAudit::NativeAudit(QQmlApplicationEngine *engine)
    : QObject(engine),
      m_engine(engine),
      m_output(environment(QStringLiteral("AUDIT_OUTPUT"))),
      m_shared(environment(QStringLiteral("AUDIT_SHARED")))
{
    m_elapsed.start();
    m_requestedWidth = environment(QStringLiteral("AUDIT_WIDTH")).toInt();
    m_requestedHeight = environment(QStringLiteral("AUDIT_HEIGHT")).toInt();
    engine->rootContext()->setContextProperty(QStringLiteral("auditProbe"), this);
    connect(engine, &QQmlApplicationEngine::warnings, this,
            [this](const QList<QQmlError> &warnings) {
                for (const auto &warning : warnings)
                    m_warnings.append(warning.toString());
                record(QStringLiteral("qml-warnings"), m_warnings);
            });
    connect(engine, &QQmlApplicationEngine::objectCreated, this, [this](QObject *object) {
        if (m_window)
            return;
        m_window = qobject_cast<QQuickWindow *>(object);
        if (m_window) {
            m_engine->rootContext()->setContextProperty(QStringLiteral("auditWindow"),
                                                        m_window.data());
            if (m_requestedWidth > 0 && m_requestedHeight > 0) {
                m_window->setVisibility(QWindow::Windowed);
                m_window->resize(m_requestedWidth, m_requestedHeight);
            } else {
                m_window->setVisibility(QWindow::Maximized);
            }
        }
    });
    m_heartbeat.setInterval(250);
    connect(&m_heartbeat, &QTimer::timeout, this, &NativeAudit::heartbeat);
    m_heartbeat.start();
}

QString NativeAudit::lastError() const
{
    return m_lastError;
}
QString NativeAudit::environment(const QString &name) const
{
    return auditEnvironment(name);
}

QString NativeAudit::readText(const QString &path)
{
    QFile file(path);
    if (!QDir::isAbsolutePath(path) || !QFileInfo(path).isFile() ||
        !file.open(QIODevice::ReadOnly) || file.isSequential() || file.size() > 16 * 1024 * 1024) {
        fail(QStringLiteral("Cannot read a bounded absolute fixture file: %1").arg(path));
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

QObject *NativeAudit::fileDialogObject(const QString &name) const
{
    if (!m_engine || name.isEmpty())
        return {};
    QObject *dialog = nullptr;
    for (QObject *root : m_engine->rootObjects()) {
        for (QObject *candidate : root->findChildren<QObject *>(name)) {
            if (!candidate->inherits("QQuickFileDialog"))
                continue;
            if (dialog)
                return {};
            dialog = candidate;
        }
    }
    return dialog;
}

QVariantMap NativeAudit::fileDialogState(const QString &name) const
{
    QObject *dialog = fileDialogObject(name);
    if (!dialog)
        return {};
    return {{QStringLiteral("visible"), dialog->property("visible")},
            {QStringLiteral("fileMode"), dialog->property("fileMode")},
            {QStringLiteral("selectedFile"), dialog->property("selectedFile")},
            {QStringLiteral("title"), dialog->property("title")}};
}

bool NativeAudit::chooseFile(const QString &name, const QString &path)
{
    const auto started = m_elapsed.elapsed();
    const auto dialog = fileDialogState(name);
    QObject *dialogObject = fileDialogObject(name);
    auto accepted =
        dialogObject ? std::make_unique<QSignalSpy>(dialogObject, SIGNAL(accepted())) : nullptr;
    QString selectedFile;
    bool dialogAccepted = false;
    bool dialogClosed = false;
    const auto verifyCompletion = [&]() {
        QElapsedTimer waiting;
        waiting.start();
        do {
            const auto after = fileDialogState(name);
            const auto selected = after.value(QStringLiteral("selectedFile")).toUrl();
            selectedFile = selected.toString();
            dialogAccepted = accepted && accepted->isValid() && !accepted->isEmpty();
            dialogClosed = after.value(QStringLiteral("visible")).isValid() &&
                           !after.value(QStringLiteral("visible")).toBool();
            if (dialogAccepted && dialogClosed && selected.toLocalFile() == path)
                return true;
            QTest::qWait(10);
        } while (waiting.elapsed() < 1000);
        return false;
    };
    bool ok = QDir::isAbsolutePath(path) && !path.contains(u'\n') && !path.contains(u'\r') &&
              dialog.value(QStringLiteral("visible")).toBool();
    QQuickWindow *window = nullptr;
    QQuickItem *fileName = nullptr;
    if (ok) {
        // The platform's Qt Quick file chooser may have its own popup window.
        // Never send input to an unrelated window or an external portal.
        for (QWindow *candidate : QGuiApplication::allWindows()) {
            auto *quick = qobject_cast<QQuickWindow *>(candidate);
            QWindow *owner = candidate;
            while (owner && owner != m_window)
                owner = owner->transientParent();
            if (!quick || !owner || !quick->isExposed() || !quick->isVisible())
                continue;
            visitItems(quick->contentItem(), [&](QQuickItem *item) {
                if (visibleRect(item).isEmpty())
                    return;
                if (item->objectName() == QStringLiteral("fileDialogListView"))
                    window = quick;
                if (item->objectName() == QStringLiteral("fileNameTextField"))
                    fileName = item;
            });
        }
        if (!window) {
#ifdef HEXPROOF_NATIVE_AUDIT_GTK
            if (environment(QStringLiteral("AUDIT_GTK_FILE_DIALOG")) == QStringLiteral("1")) {
                const auto detail = selectNativeGtkFile(
                    dialog.value(QStringLiteral("title")).toString(), path, m_window->winId(),
                    dialog.value(QStringLiteral("fileMode")).toInt() == 2);
                ok =
                    detail.value(QStringLiteral("status")).toString() == QStringLiteral("passed") &&
                    verifyCompletion();
                if (!ok)
                    fail(QStringLiteral("GTK chooser input failed or selected a different file: %1")
                             .arg(detail.value(QStringLiteral("error")).toString()));
                trace(QStringLiteral("chooseFile"),
                      {{QStringLiteral("accepted"), ok},
                       {QStringLiteral("dialog"), name},
                       {QStringLiteral("path"), path},
                       {QStringLiteral("selectedFile"), selectedFile},
                       {QStringLiteral("dialogAccepted"), dialogAccepted},
                       {QStringLiteral("dialogClosed"), dialogClosed},
                       {QStringLiteral("dialogBackend"), QStringLiteral("native-gtk")},
                       {QStringLiteral("evidence"), QStringLiteral("native-gtk-input")},
                       {QStringLiteral("nativeDialog"), detail}},
                      started);
                return ok;
            }
#endif
            const QFileInfo helper(environment(QStringLiteral("AUDIT_FILE_DIALOG_HELPER")));
            QVariantMap detail;
            if (helper.isAbsolute() && helper.isExecutable()) {
                QProcess process;
                QStringList arguments{QString::number(QCoreApplication::applicationPid()),
                                      dialog.value(QStringLiteral("title")).toString(), path,
                                      QDir(m_output).filePath(
                                          QStringLiteral("file-dialog-%1").arg(m_inputCount + 1))};
                if (dialog.value(QStringLiteral("fileMode")).toInt() == 2)
                    arguments.prepend(QStringLiteral("--save"));
                process.start(helper.absoluteFilePath(), arguments);
                // GTK native choosers share this process's event loop. Keep
                // dispatching while the PID-scoped X11 helper sends input.
                while (process.state() != QProcess::NotRunning &&
                       m_elapsed.elapsed() - started < 12'000)
                    QTest::qWait(10);
                if (process.state() != QProcess::NotRunning) {
                    process.kill();
                    process.waitForFinished(1'000);
                }
                detail = QJsonDocument::fromJson(process.readAllStandardOutput())
                             .object()
                             .toVariantMap();
                ok =
                    process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0 &&
                    detail.value(QStringLiteral("status")).toString() == QStringLiteral("passed") &&
                    verifyCompletion();
                if (!ok)
                    fail(QStringLiteral("Native file chooser input failed: %1 %2")
                             .arg(QString::fromUtf8(process.readAllStandardError()),
                                  QString::fromUtf8(QJsonDocument::fromVariant(detail).toJson(
                                      QJsonDocument::Compact))));
            } else {
                ok = fail(QStringLiteral("The native file chooser needs an executable absolute "
                                         "HEXPROOF_AUDIT_FILE_DIALOG_HELPER."));
            }
            trace(QStringLiteral("chooseFile"),
                  {{QStringLiteral("accepted"), ok},
                   {QStringLiteral("dialog"), name},
                   {QStringLiteral("path"), path},
                   {QStringLiteral("selectedFile"), selectedFile},
                   {QStringLiteral("dialogAccepted"), dialogAccepted},
                   {QStringLiteral("dialogClosed"), dialogClosed},
                   {QStringLiteral("dialogBackend"), QStringLiteral("native-x11")},
                   {QStringLiteral("evidence"), QStringLiteral("native-x11-input")},
                   {QStringLiteral("nativeDialog"), detail}},
                  started);
            return ok;
        }
    }
    if (ok) {
        window->requestActivate();
        ok = QTest::qWaitForWindowActive(window, 1'000);
    }
    if (ok) {
        if (fileName && fileName->window() == window)
            QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier,
                              visibleRect(fileName).center().toPoint());
        else
            QTest::keyClick(window, Qt::Key_L, Qt::ControlModifier);
        QTest::keyClick(window, Qt::Key_A, Qt::ControlModifier);
        QQuickItem *focus = window->activeFocusItem();
        ok = focus && !visibleRect(focus).isEmpty() && focus->inherits("QQuickTextInput");
        if (ok) {
            for (char32_t codePoint : path.toUcs4())
                QTest::sendKeyEvent(QTest::Click, window, Qt::Key_unknown,
                                    QString::fromUcs4(&codePoint, 1), Qt::NoModifier);
            ok = focus->property("text").toString() == path;
            if (ok)
                QTest::keyClick(window, Qt::Key_Return);
        }
    }
    if (ok)
        ok = verifyCompletion();
    if (!ok)
        fail(QStringLiteral("The named file chooser must accept and close with the requested "
                            "path after input."));
    trace(QStringLiteral("chooseFile"),
          {{QStringLiteral("accepted"), ok},
           {QStringLiteral("dialog"), name},
           {QStringLiteral("path"), path},
           {QStringLiteral("selectedFile"), selectedFile},
           {QStringLiteral("dialogAccepted"), dialogAccepted},
           {QStringLiteral("dialogClosed"), dialogClosed},
           {QStringLiteral("dialogBackend"), QStringLiteral("qt-quick")}},
          started);
    return ok;
}

bool NativeAudit::fail(const QString &message)
{
    m_lastError = message;
    emit lastErrorChanged();
    return false;
}

bool NativeAudit::artifactFailure(const QString &message)
{
    ++m_artifactFailures;
    return fail(message);
}

QQuickItem *NativeAudit::find(QObject *scope, const QString &name, const QVariantMap &identity)
{
    auto *root = qobject_cast<QQuickItem *>(scope);
    if (auto *window = qobject_cast<QQuickWindow *>(scope))
        root = window->contentItem();
    if (!root || root->window() != m_window || name.isEmpty()) {
        fail(QStringLiteral("Selector scope is not in the audit window."));
        return nullptr;
    }
    QList<QQuickItem *> matches;
    QStringList rejected;
    visitItems(root, [&](QQuickItem *item) {
        if (item->objectName() != name || visibleRect(item).isEmpty())
            return;
        for (auto it = identity.cbegin(); it != identity.cend(); ++it)
            if (field(item, it.key()) != plainVariant(it.value()))
                return;
        QPointF point;
        if (targetPoint(item, &point))
            matches.append(item);
        else
            rejected.append(m_lastError);
    });
    if (matches.size() != 1) {
        fail(QStringLiteral("Selector '%1' matched %2 usable items; require one. %3")
                 .arg(name)
                 .arg(matches.size())
                 .arg(rejected.join(QStringLiteral("; "))));
        return nullptr;
    }
    m_lastError.clear();
    emit lastErrorChanged();
    return matches.first();
}

bool NativeAudit::targetPoint(QQuickItem *item, QPointF *point, qreal x, qreal y)
{
    if (!m_window || !m_window->isExposed() || !m_window->isVisible() || !item ||
        item->window() != m_window)
        return fail(QStringLiteral("Input target has no exposed audit window."));
    const QRectF rect = visibleRect(item);
    if (rect.isEmpty())
        return fail(QStringLiteral("Input target is hidden, disabled, or outside its viewport."));
    for (QQuickItem *ancestor = item; ancestor; ancestor = ancestor->parentItem()) {
        if (ancestor->inherits("QQuickStackView") && ancestor->property("busy").toBool())
            return fail(QStringLiteral("Input target is in an active page transition."));
    }
    *point = x < 0 || y < 0 ? rect.center() : item->mapToScene(QPointF(x, y));
    if (!rect.contains(*point) || !item->contains(item->mapFromScene(*point)))
        return fail(QStringLiteral("Input point is outside the target's visible area."));
    QQuickItem *receiver = receiverAt(m_window->contentItem(), *point);
    if (receiver && !containsItem(item, receiver) && !containsItem(receiver, item))
        return fail(QStringLiteral("Input target is covered by another pointer receiver: %1 (%2)")
                        .arg(receiver->objectName(),
                             QString::fromLatin1(receiver->metaObject()->className())));
    return true;
}

void NativeAudit::trace(const QString &action, const QVariantMap &detail, qint64 started)
{
    QVariantMap row = detail;
    row.insert(QStringLiteral("action"), action);
    row.insert(QStringLiteral("monotonicMs"), started);
    row.insert(QStringLiteral("dispatchDurationMs"), m_elapsed.elapsed() - started);
    row.insert(QStringLiteral("window"), windowGeometry(m_window));
    if (!row.contains(QStringLiteral("evidence")))
        row.insert(QStringLiteral("evidence"), QStringLiteral("native-qt-input"));
    row.insert(QStringLiteral("sequence"), ++m_inputCount);
    if (row.value(QStringLiteral("accepted")) == false) {
        ++m_failedActions;
        row.insert(QStringLiteral("error"), m_lastError);
    }
    QFile file(QDir(m_output).filePath(QStringLiteral("actions.jsonl")));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append) ||
        file.write(QJsonDocument::fromVariant(row).toJson(QJsonDocument::Compact) + '\n') < 0) {
        ++m_failedActions;
        fail(QStringLiteral("Could not write input evidence."));
    }
}

bool NativeAudit::click(QQuickItem *item, qreal x, qreal y)
{
    const auto started = m_elapsed.elapsed();
    QPointF point;
    const bool ok = targetPoint(item, &point, x, y);
    QVariantMap detail{{QStringLiteral("accepted"), ok},
                       {QStringLiteral("target"), item ? itemDescription(item) : QVariantMap{}},
                       {QStringLiteral("x"), point.x()},
                       {QStringLiteral("y"), point.y()}};
    if (ok)
        QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    else
        detail.insert(QStringLiteral("error"), m_lastError);
    trace(QStringLiteral("click"), detail, started);
    return ok;
}

bool NativeAudit::hover(QQuickItem *item)
{
    const auto started = m_elapsed.elapsed();
    QPointF point;
    const bool ok = targetPoint(item, &point);
    const QVariantMap target = item ? itemDescription(item) : QVariantMap{};
    if (ok)
        QTest::mouseMove(m_window, point.toPoint());
    trace(QStringLiteral("hover"),
          {{QStringLiteral("accepted"), ok}, {QStringLiteral("target"), target}}, started);
    return ok;
}

bool NativeAudit::doubleClick(QQuickItem *item)
{
    const auto started = m_elapsed.elapsed();
    QPointF point;
    const bool ok = targetPoint(item, &point);
    const QVariantMap target = item ? itemDescription(item) : QVariantMap{};
    if (ok)
        QTest::mouseDClick(m_window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    trace(QStringLiteral("doubleClick"),
          {{QStringLiteral("accepted"), ok}, {QStringLiteral("target"), target}}, started);
    return ok;
}

bool NativeAudit::inputFocus()
{
    if (!m_window || !m_window->isExposed() || !m_window->isVisible())
        return fail(QStringLiteral("Keyboard input requires the exposed audit window."));
    if (!activate())
        return false;
    QQuickItem *focus = m_window->activeFocusItem();
    if (!focus || visibleRect(focus).isEmpty())
        return fail(QStringLiteral("Keyboard input requires a visible, enabled focus item."));
    for (QQuickItem *ancestor = focus; ancestor; ancestor = ancestor->parentItem()) {
        if (ancestor->inherits("QQuickStackView") && ancestor->property("busy").toBool())
            return fail(QStringLiteral("Keyboard focus is in an active page transition."));
    }
    // A popup can retain keyboard focus on its opening control while covering
    // that control with its list. Pointer hit testing does not describe key
    // delivery; Qt's activeFocusItem is the authoritative keyboard target.
    return true;
}

bool NativeAudit::activate()
{
    if (m_window && m_window->isActive())
        return true;
    const auto started = m_elapsed.elapsed();
    bool ok = m_window && m_window->isExposed() && m_window->isVisible();
    if (ok) {
        m_window->requestActivate();
        ok = QTest::qWaitForWindowActive(m_window, 1'000);
    }
    if (!ok)
        fail(QStringLiteral("The native window manager did not activate the audit window; keyboard "
                            "input was not sent."));
    trace(QStringLiteral("activate"), {{QStringLiteral("accepted"), ok}}, started);
    return ok;
}

bool NativeAudit::rightClick(QQuickItem *item)
{
    const auto started = m_elapsed.elapsed();
    QPointF point;
    const bool ok = targetPoint(item, &point);
    const QVariantMap target = item ? itemDescription(item) : QVariantMap{};
    if (ok)
        QTest::mouseClick(m_window, Qt::RightButton, Qt::NoModifier, point.toPoint());
    trace(QStringLiteral("rightClick"),
          {{QStringLiteral("accepted"), ok}, {QStringLiteral("target"), target}}, started);
    return ok;
}

bool NativeAudit::key(int keyCode, int modifiers)
{
    const auto started = m_elapsed.elapsed();
    const bool ok = inputFocus();
    if (ok)
        QTest::keyClick(m_window, static_cast<Qt::Key>(keyCode), Qt::KeyboardModifiers(modifiers));
    trace(QStringLiteral("key"),
          {{QStringLiteral("accepted"), ok},
           {QStringLiteral("key"), keyCode},
           {QStringLiteral("modifiers"), modifiers}},
          started);
    return ok;
}

bool NativeAudit::type(const QString &value)
{
    const auto started = m_elapsed.elapsed();
    const bool ok = inputFocus();
    if (ok) {
        // Qt window keyboard events, including Unicode; never modify a text
        // property's value or borrow the user's system clipboard.
        for (char32_t codePoint : value.toUcs4()) {
            if (codePoint == U'\n')
                QTest::keyClick(m_window, Qt::Key_Return);
            else
                QTest::sendKeyEvent(QTest::Click, m_window, Qt::Key_unknown,
                                    QString::fromUcs4(&codePoint, 1), Qt::NoModifier);
        }
    }
    trace(QStringLiteral("type"),
          {{QStringLiteral("accepted"), ok}, {QStringLiteral("characters"), value.size()}},
          started);
    return ok;
}

bool NativeAudit::text(const QString &value)
{
    return type(value);
}
bool NativeAudit::wheel(QQuickItem *item, int delta)
{
    return wheel(item, -1, -1, delta);
}

bool NativeAudit::wheel(QQuickItem *item, qreal x, qreal y, int delta)
{
    const auto started = m_elapsed.elapsed();
    QPointF point;
    const bool ok = targetPoint(item, &point, x, y);
    const QVariantMap target = item ? itemDescription(item) : QVariantMap{};
    if (ok) {
        QTest::mouseMove(m_window, point.toPoint());
        QWheelEvent event(point, m_window->mapToGlobal(point), QPoint(), QPoint(0, delta),
                          Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        event.setTimestamp(static_cast<quint64>(m_elapsed.elapsed()));
        QCoreApplication::sendEvent(m_window, &event);
    }
    trace(QStringLiteral("wheel"),
          {{QStringLiteral("accepted"), ok},
           {QStringLiteral("target"), target},
           {QStringLiteral("delta"), delta}},
          started);
    return ok;
}

bool NativeAudit::drag(QQuickItem *source, QQuickItem *target)
{
    return drag(source, target, -1, -1);
}

bool NativeAudit::drag(QQuickItem *source, QQuickItem *target, qreal sourceX, qreal sourceY)
{
    const auto started = m_elapsed.elapsed();
    QPointF start, end;
    const bool ok = targetPoint(source, &start, sourceX, sourceY) && targetPoint(target, &end);
    if (ok) {
        QTest::mousePress(m_window, Qt::LeftButton, Qt::NoModifier, start.toPoint());
        QTest::qWait(20);
        for (int i = 1; i <= 12; ++i) {
            QTest::mouseMove(m_window, (start + (end - start) * i / 12).toPoint(), 20);
            // QWindow mouseMove's delay advances only event timestamps. Real
            // frames must run too, so drag/reorder handlers can settle between
            // pointer positions just as they do during a person's gesture.
            QTest::qWait(20);
        }
        QTest::mouseRelease(m_window, Qt::LeftButton, Qt::NoModifier, end.toPoint());
    }
    trace(QStringLiteral("drag"),
          {{QStringLiteral("accepted"), ok},
           {QStringLiteral("startX"), start.x()},
           {QStringLiteral("startY"), start.y()},
           {QStringLiteral("endX"), end.x()},
           {QStringLiteral("endY"), end.y()}},
          started);
    return ok;
}

QVariantMap NativeAudit::observe(QQuickWindow *window) const
{
    if (!window || window != m_window)
        return {};
    QVariantList items;
    visitItems(window->contentItem(), [&](QQuickItem *item) {
        if (!item->objectName().isEmpty())
            items.append(itemDescription(item));
    });
    QVariantMap result = windowGeometry(window);
    result.insert(QStringLiteral("monotonicMs"), m_elapsed.elapsed());
    result.insert(QStringLiteral("requestedWindowMode"),
                  m_requestedWidth > 0 ? QStringLiteral("windowed") : QStringLiteral("maximized"));
    result.insert(QStringLiteral("requestedWidth"), m_requestedWidth);
    result.insert(QStringLiteral("requestedHeight"), m_requestedHeight);
    result.insert(QStringLiteral("artifactFailures"), m_artifactFailures);
    result.insert(QStringLiteral("items"), items);
    return result;
}

bool NativeAudit::capture(QQuickWindow *window, const QString &name)
{
    if (!window || window != m_window || !window->isExposed() || !artifactName(name))
        return artifactFailure(QStringLiteral(
            "Screenshot requires the exposed audit window and a safe artifact name."));
    const QImage image = window->grabWindow();
    if (image.isNull() || !image.save(QDir(m_output).filePath(name + QStringLiteral(".png"))))
        return artifactFailure(QStringLiteral("Could not save screenshot: %1").arg(name));
    return true;
}

bool NativeAudit::writeJson(const QString &directory, const QString &name, const QVariant &value)
{
    if (!QDir::isAbsolutePath(directory) || !artifactName(name))
        return artifactFailure(
            QStringLiteral("JSON output requires an absolute directory and a safe artifact name."));
    QSaveFile file(QDir(directory).filePath(name + QStringLiteral(".json")));
    if (!file.open(QIODevice::WriteOnly))
        return artifactFailure(file.errorString());
    const QJsonDocument document = QJsonDocument::fromVariant(plainVariant(value));
    if (document.isNull())
        return artifactFailure(QStringLiteral("JSON artifacts must contain an object or array."));
    const QByteArray bytes = document.toJson();
    if (file.write(bytes) != bytes.size() || !file.commit())
        return artifactFailure(file.errorString());
    return true;
}

bool NativeAudit::record(const QString &name, const QVariant &value)
{
    return writeJson(m_output, name, value);
}
bool NativeAudit::share(const QString &name, const QVariant &value)
{
    return writeJson(m_shared, name, value);
}

QVariant NativeAudit::readShared(const QString &name)
{
    if (!QDir::isAbsolutePath(m_shared) || !artifactName(name))
        return {};
    QFile file(QDir(m_shared).filePath(name + QStringLiteral(".json")));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).toVariant();
}

bool NativeAudit::interruptTransport(QObject *client)
{
    auto *transport = qobject_cast<WsClient *>(client);
    if (!transport || !transport->connected() ||
        !QHostAddress(QUrl(transport->serverUrl()).host()).isLoopback())
        return artifactFailure(
            QStringLiteral("Transport fault requires a connected loopback test client"));
    fixture(QStringLiteral("interrupt-loopback-transport"));
    transport->m_ws.abort();
    return true;
}

bool NativeAudit::crashHostingHelper(QObject *client)
{
    auto *transport = qobject_cast<WsClient *>(client);
    if (!transport || !transport->connected() ||
        !QHostAddress(QUrl(transport->serverUrl()).host()).isLoopback() ||
        !transport->m_forgeHost->hosting())
        return artifactFailure(QStringLiteral("Hosting fault requires an owned loopback helper"));
    fixture(QStringLiteral("crash-loopback-host-helper"));
    transport->m_forgeHost->m_process.kill();
    return true;
}

void NativeAudit::fixture(const QString &name, const QVariantMap &detail)
{
    ++m_fixtureCount;
    record(QStringLiteral("fixture-%1").arg(m_fixtureCount),
           QVariantMap{{QStringLiteral("name"), name},
                       {QStringLiteral("detail"), detail},
                       {QStringLiteral("evidence"), QStringLiteral("fixture-setup")},
                       {QStringLiteral("monotonicMs"), m_elapsed.elapsed()}});
}

bool NativeAudit::applyRulesTableFixture(const QVariantMap &room, const QVariantMap &rules)
{
    auto *transport = qobject_cast<WsClient *>(
        m_engine->rootContext()->contextProperty(QStringLiteral("ws")).value<QObject *>());
    if (!transport)
        return artifactFailure(
            QStringLiteral("Rules table fixture requires the production client"));
    QString roomId = room.value(QStringLiteral("roomId")).toString();
    if (roomId.isEmpty())
        roomId = QStringLiteral("LAND01");
    QString role = room.value(QStringLiteral("role")).toString();
    if (role.isEmpty())
        role = QStringLiteral("player");
    const int seat = room.value(QStringLiteral("seatIndex")).toInt();
    const bool host =
        !room.contains(QStringLiteral("host")) || room.value(QStringLiteral("host")).toBool();
    transport->m_roomSession->enter(roomId, role, seat, host);
    transport->m_roomSession->applySnapshot(QJsonObject::fromVariantMap(room));
    if (!transport->m_rulesSession->applySnapshot(QJsonObject::fromVariantMap(rules)))
        return artifactFailure(QStringLiteral("Rules snapshot was rejected"));
    transport->setState(WsClient::InRoom);
    emit transport->inRoomChanged();
    fixture(QStringLiteral("rules-table-snapshot"),
            {{QStringLiteral("description"),
              QStringLiteral("Deterministic Forge table snapshot; not a live engine game.")},
             {QStringLiteral("roomId"), roomId},
             {QStringLiteral("gameId"), rules.value(QStringLiteral("gameId"))}});
    return true;
}

void NativeAudit::startDriver()
{
    m_driverStarted = true;
    // Save the settled fixture before Component.onCompleted can take input or
    // change any application state. Requested dimensions are never evidence
    // of the actual geometry by themselves.
    record(QStringLiteral("startup"),
           QVariantMap{{QStringLiteral("pid"), QCoreApplication::applicationPid()},
                       {QStringLiteral("runId"), environment(QStringLiteral("AUDIT_RUN_ID"))},
                       {QStringLiteral("seat"), environment(QStringLiteral("AUDIT_SEAT"))},
                       {QStringLiteral("driver"), environment(QStringLiteral("AUDIT_DRIVER"))},
                       {QStringLiteral("startupServices"),
                        environment(QStringLiteral("AUDIT_STARTUP_SERVICES")) == "1"},
                       {QStringLiteral("downloadDirectory"),
                        QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)},
                       {QStringLiteral("evidence"), QStringLiteral("native-qt-input")},
                       {QStringLiteral("window"), observe(m_window)}});
    QQmlComponent component(m_engine,
                            QUrl::fromLocalFile(environment(QStringLiteral("AUDIT_DRIVER"))));
    m_driver = component.create(m_engine->rootContext());
    if (!m_driver) {
        for (const auto &error : component.errors())
            m_warnings.append(error.toString());
        record(QStringLiteral("driver-errors"), m_warnings);
        finish(3);
        return;
    }
    m_driver->setParent(this);
}

void NativeAudit::heartbeat()
{
    record(QStringLiteral("heartbeat"),
           QVariantMap{
               {QStringLiteral("monotonicMs"), m_elapsed.elapsed()},
               {QStringLiteral("inputs"), m_inputCount},
               {QStringLiteral("driverStage"), m_driver ? m_driver->property("stage") : QVariant{}},
               {QStringLiteral("driverBusy"), m_driver ? m_driver->property("busy") : QVariant{}},
               {QStringLiteral("finished"), m_finished}});
    if (!m_driverStarted && !m_finished) {
        const bool sizeMatches =
            m_window && (m_requestedWidth == 0 ? m_window->visibility() == QWindow::Maximized
                                               : (m_window->visibility() == QWindow::Windowed &&
                                                  m_window->width() == m_requestedWidth &&
                                                  m_window->height() == m_requestedHeight));
        if (m_window && m_window->isExposed() && sizeMatches) {
            m_geometryStableTicks =
                m_window->size() == m_lastWindowSize ? m_geometryStableTicks + 1 : 1;
            m_lastWindowSize = m_window->size();
            if (m_geometryStableTicks >= 2)
                startDriver();
        } else {
            m_geometryStableTicks = 0;
        }
        if (!m_driverStarted && m_elapsed.elapsed() > 10'000) {
            fail(QStringLiteral("Window fixture did not settle at its requested visible geometry "
                                "within ten seconds."));
            record(QStringLiteral("window-fixture-failure"), observe(m_window));
            finish(3);
        }
    }
    // Audit scheduling must continue when the scene's animation clock stalls.
    // The driver still checks visible controls, transitions and its watchdog.
    if (m_driver && !m_finished)
        emit stepRequested();
}

void NativeAudit::finish(int code)
{
    if (m_finished)
        return;
    m_finished = true;
    m_heartbeat.stop();
    if (code == 0 && (!m_warnings.isEmpty() || m_failedActions > 0 || m_artifactFailures > 0))
        code = 4;
    const bool saved =
        record(QStringLiteral("audit-summary"),
               QVariantMap{{QStringLiteral("exitCode"), code},
                           {QStringLiteral("inputs"), m_inputCount},
                           {QStringLiteral("fixtures"), m_fixtureCount},
                           {QStringLiteral("failedInputs"), m_failedActions},
                           {QStringLiteral("artifactFailures"), m_artifactFailures},
                           {QStringLiteral("qmlWarnings"), m_warnings},
                           {QStringLiteral("lastError"), m_lastError},
                           {QStringLiteral("durationMs"), m_elapsed.elapsed()},
                           {QStringLiteral("evidence"), QStringLiteral("native-qt-input")},
                           {QStringLiteral("osInputVerified"), false}});
    if (!saved && code == 0)
        code = 5;
    QCoreApplication::exit(code);
}

} // namespace hexproof::client
