// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "NativeGtkInput.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFileInfo>
#include <QThread>

// GTK public headers have fields named signals. Keep Qt's keyword macro out
// of this audit-only implementation without changing other translation units.
#undef signals
#include <gdk/gdkx.h>
#include <gtk/gtk.h>

#include <X11/Xatom.h>

namespace hexproof::client {
namespace {

void dispatchPending(int milliseconds)
{
    QElapsedTimer elapsed;
    elapsed.start();
    do {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
        if (elapsed.elapsed() < milliseconds)
            QThread::msleep(1);
    } while (elapsed.elapsed() < milliseconds);
}

bool sameProcessWindow(Display *display, Window window)
{
    Atom type = None;
    int format = 0;
    unsigned long count = 0;
    unsigned long remaining = 0;
    unsigned char *value = nullptr;
    const Atom pidAtom = XInternAtom(display, "_NET_WM_PID", False);
    const bool read = XGetWindowProperty(display, window, pidAtom, 0, 1, False, XA_CARDINAL, &type,
                                         &format, &count, &remaining, &value) == Success;
    const bool owned = read && type == XA_CARDINAL && format == 32 && count == 1 &&
                       remaining == 0 &&
                       *reinterpret_cast<unsigned long *>(value) ==
                           static_cast<unsigned long>(QCoreApplication::applicationPid());
    if (value)
        XFree(value);
    return owned;
}

bool matchesOwner(GtkWidget *widget, quintptr expectedOwnerWindow)
{
    GdkWindow *window = gtk_widget_get_window(widget);
    if (!window || !GDK_IS_X11_WINDOW(window) || expectedOwnerWindow == 0)
        return false;
    GdkDisplay *gdkDisplay = gdk_window_get_display(window);
    Display *display = gdk_x11_display_get_xdisplay(gdkDisplay);
    gdk_x11_display_error_trap_push(gdkDisplay);
    Window current = gdk_x11_window_get_xid(window);
    bool matches = false;
    for (int depth = 0; depth < 8 && sameProcessWindow(display, current); ++depth) {
        if (current == static_cast<Window>(expectedOwnerWindow)) {
            matches = depth > 0;
            break;
        }
        Window parent = None;
        if (!XGetTransientForHint(display, current, &parent) || parent == None || parent == current)
            break;
        current = parent;
    }
    return gdk_x11_display_error_trap_pop(gdkDisplay) == 0 && matches;
}

bool shown(GtkWidget *widget)
{
    return gtk_widget_get_visible(widget) && gtk_widget_get_mapped(widget) &&
           gtk_widget_get_realized(widget) && !gtk_widget_in_destruction(widget);
}

bool eligible(GtkWidget *widget, const QString &title, quintptr owner, bool save)
{
    return GTK_IS_FILE_CHOOSER_DIALOG(widget) && shown(widget) &&
           QString::fromUtf8(gtk_window_get_title(GTK_WINDOW(widget))) == title &&
           gtk_file_chooser_get_action(GTK_FILE_CHOOSER(widget)) ==
               (save ? GTK_FILE_CHOOSER_ACTION_SAVE : GTK_FILE_CHOOSER_ACTION_OPEN) &&
           matchesOwner(widget, owner);
}

QString focusName(GtkWidget *dialog)
{
    GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(dialog));
    return focus ? QString::fromUtf8(G_OBJECT_TYPE_NAME(focus)) : QString{};
}

GtkWidget *locationEntry(GtkWidget *dialog)
{
    GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(dialog));
    return focus && GTK_IS_ENTRY(focus) && gtk_widget_is_ancestor(focus, dialog) &&
                   QString::fromUtf8(G_OBJECT_TYPE_NAME(focus)) ==
                       QStringLiteral("GtkFileChooserEntry")
               ? focus
               : nullptr;
}

bool key(GtkWidget *dialog, guint keyval, guint modifiers, const QString &title, quintptr owner,
         bool save, QVariantList *events, QString *error)
{
    if (!eligible(dialog, title, owner, save)) {
        *error = QStringLiteral("The GTK chooser no longer matches the owned dialog");
        return false;
    }
    GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(dialog));
    if (!focus || !gtk_widget_is_ancestor(focus, dialog) || !gtk_widget_get_sensitive(focus)) {
        *error = QStringLiteral("The GTK chooser has no enabled focus widget in its own hierarchy");
        return false;
    }
    GdkWindow *window = gtk_widget_get_window(dialog);
    GdkDisplay *display = gdk_window_get_display(window);
    GdkSeat *seat = gdk_display_get_default_seat(display);
    GdkDevice *keyboard = seat ? gdk_seat_get_keyboard(seat) : nullptr;
    if (!keyboard) {
        *error = QStringLiteral("The GTK display has no keyboard device");
        return false;
    }
    GdkKeymapKey *mapping = nullptr;
    int mappingCount = 0;
    guint16 code = 0;
    guint8 group = 0;
    if (gdk_keymap_get_entries_for_keyval(gdk_keymap_get_for_display(display), keyval, &mapping,
                                          &mappingCount)) {
        for (int index = 0; index < mappingCount; ++index) {
            if (mapping[index].group == 0 && mapping[index].level <= 1) {
                code = static_cast<guint16>(mapping[index].keycode);
                group = static_cast<guint8>(mapping[index].group);
                if (mapping[index].level == 1)
                    modifiers |= GDK_SHIFT_MASK;
                break;
            }
        }
    }
    g_free(mapping);
    const QString before = focusName(dialog);
    for (const GdkEventType type : {GDK_KEY_PRESS, GDK_KEY_RELEASE}) {
        // Return can close/destroy the chooser during KeyPress. No hardware
        // modifier is held by these widget events, so no release is then needed.
        if (!shown(dialog))
            break;
        // Ctrl+L creates a new location entry during KeyPress. GTK forwards
        // KeyRelease to the new focus widget, which must first be realized.
        QElapsedTimer focusReady;
        focusReady.start();
        while (eligible(dialog, title, owner, save)) {
            focus = gtk_window_get_focus(GTK_WINDOW(dialog));
            if (focus && gtk_widget_is_ancestor(focus, dialog) && shown(focus) &&
                gtk_widget_is_sensitive(focus))
                break;
            if (focusReady.elapsed() >= 1000) {
                *error = QStringLiteral("The GTK focus widget did not become ready for input");
                return false;
            }
            dispatchPending(5);
        }
        if (!eligible(dialog, title, owner, save)) {
            *error = QStringLiteral("The GTK chooser changed while waiting for its focus widget");
            return false;
        }
        GdkEvent *event = gdk_event_new(type);
        event->key.window = GDK_WINDOW(g_object_ref(window));
        event->key.send_event = TRUE;
        event->key.time = GDK_CURRENT_TIME;
        event->key.state = modifiers;
        event->key.keyval = keyval;
        event->key.hardware_keycode = code;
        event->key.group = group;
        gdk_event_set_device(event, keyboard);
        gdk_event_set_source_device(event, keyboard);
        gtk_widget_event(dialog, event);
        gdk_event_free(event);
    }
    events->append(
        QVariantMap{{QStringLiteral("keyval"), keyval},
                    {QStringLiteral("modifiers"), modifiers},
                    {QStringLiteral("focusBefore"), before},
                    {QStringLiteral("focusAfter"),
                     gtk_widget_in_destruction(dialog) ? QString{} : focusName(dialog)}});
    return true;
}

GdkWindow *eventWindowFor(GtkWidget *widget, GdkWindow *window, int depth = 0)
{
    if (depth > 12)
        return nullptr;
    gpointer owner = nullptr;
    gdk_window_get_user_data(window, &owner);
    if (owner == widget && gdk_window_is_visible(window))
        return window;
    GList *children = gdk_window_get_children(window);
    GdkWindow *found = nullptr;
    for (GList *entry = children; entry && !found; entry = entry->next)
        found = eventWindowFor(widget, GDK_WINDOW(entry->data), depth + 1);
    g_list_free(children);
    return found;
}

bool clickAccept(GtkWidget *dialog, const QString &title, const QString &path, quintptr owner,
                 bool save, QVariantList *events, QVariantMap *state, QString *error)
{
    if (!eligible(dialog, title, owner, save)) {
        *error = QStringLiteral("The GTK chooser changed before its button could be clicked");
        return false;
    }
    GtkWidget *button = nullptr;
    QElapsedTimer ready;
    ready.start();
    do {
        int response = GTK_RESPONSE_ACCEPT;
        button = gtk_dialog_get_widget_for_response(GTK_DIALOG(dialog), response);
        if (!button) {
            response = GTK_RESPONSE_OK;
            button = gtk_dialog_get_widget_for_response(GTK_DIALOG(dialog), response);
        }
        *state = {{QStringLiteral("response"), response},
                  {QStringLiteral("found"), button != nullptr},
                  {QStringLiteral("waitMs"), ready.elapsed()}};
        if (button) {
            state->insert(QStringLiteral("class"), QString::fromUtf8(G_OBJECT_TYPE_NAME(button)));
            state->insert(QStringLiteral("visible"), bool(gtk_widget_get_visible(button)));
            state->insert(QStringLiteral("mapped"), bool(gtk_widget_get_mapped(button)));
            state->insert(QStringLiteral("realized"), bool(gtk_widget_get_realized(button)));
            state->insert(QStringLiteral("sensitive"), bool(gtk_widget_is_sensitive(button)));
            state->insert(QStringLiteral("inDialog"), bool(gtk_widget_is_ancestor(button, dialog)));
        }
        if (button && GTK_IS_BUTTON(button) && shown(button) && gtk_widget_is_sensitive(button) &&
            gtk_widget_is_ancestor(button, dialog))
            break;
        if (ready.elapsed() >= 3000)
            break;
        dispatchPending(10);
        if (!eligible(dialog, title, owner, save)) {
            *error = QStringLiteral("The GTK chooser changed while waiting for its accept button");
            return false;
        }
    } while (true);
    if (!button || !GTK_IS_BUTTON(button) || !shown(button) || !gtk_widget_is_sensitive(button) ||
        !gtk_widget_is_ancestor(button, dialog)) {
        *error = QStringLiteral("The owned GTK chooser has no visible enabled accept button");
        return false;
    }
    if (save && (QFileInfo(path).exists() || QFileInfo(path).isSymLink())) {
        *error = QStringLiteral("The save target appeared while waiting for the accept button");
        return false;
    }
    GdkWindow *window = eventWindowFor(button, gtk_widget_get_window(dialog));
    GdkDisplay *display = gtk_widget_get_display(dialog);
    GdkSeat *seat = gdk_display_get_default_seat(display);
    GdkDevice *pointer = seat ? gdk_seat_get_pointer(seat) : nullptr;
    if (!window || !pointer) {
        *error =
            QStringLiteral("Cannot resolve the accept button's own GDK event window and pointer");
        return false;
    }
    g_object_ref(button);
    g_object_ref(window);
    const QString label = QString::fromUtf8(gtk_button_get_label(GTK_BUTTON(button)));
    const double x = gdk_window_get_width(window) / 2.0;
    const double y = gdk_window_get_height(window) / 2.0;
    int rootX = 0;
    int rootY = 0;
    gdk_window_get_origin(window, &rootX, &rootY);
    for (const GdkEventType type : {GDK_BUTTON_PRESS, GDK_BUTTON_RELEASE}) {
        if (!shown(button))
            break;
        GdkEvent *event = gdk_event_new(type);
        event->button.window = GDK_WINDOW(g_object_ref(window));
        event->button.send_event = TRUE;
        event->button.time = GDK_CURRENT_TIME;
        event->button.state = type == GDK_BUTTON_RELEASE ? GDK_BUTTON1_MASK : 0;
        event->button.button = 1;
        event->button.x = x;
        event->button.y = y;
        event->button.x_root = rootX + x;
        event->button.y_root = rootY + y;
        gdk_event_set_device(event, pointer);
        gdk_event_set_source_device(event, pointer);
        gtk_widget_event(button, event);
        gdk_event_free(event);
        events->append(QVariantMap{
            {QStringLiteral("type"), type == GDK_BUTTON_PRESS ? QStringLiteral("button-press")
                                                              : QStringLiteral("button-release")},
            {QStringLiteral("target"), label},
            {QStringLiteral("x"), x},
            {QStringLiteral("y"), y},
            {QStringLiteral("window"),
             QStringLiteral("0x%1").arg(gdk_x11_window_get_xid(window), 0, 16)}});
    }
    g_object_unref(window);
    g_object_unref(button);
    return events->size() == 2;
}

} // namespace

QVariantMap selectNativeGtkFile(const QString &title, const QString &path,
                                quintptr expectedOwnerWindow, bool save)
{
    QVariantMap result{
        {QStringLiteral("status"), QStringLiteral("failed")},
        {QStringLiteral("evidence"), QStringLiteral("native-gtk-input")},
        {QStringLiteral("osInputRoutingVerified"), false},
        {QStringLiteral("pid"), QCoreApplication::applicationPid()},
        {QStringLiteral("title"), title},
        {QStringLiteral("path"), path},
        {QStringLiteral("mode"), save ? QStringLiteral("save") : QStringLiteral("open")},
        {QStringLiteral("keys"), 0}};
    const auto failure = [&result](const QString &message) {
        result.insert(QStringLiteral("error"), message);
        return result;
    };
    const QFileInfo file(path);
    if (title.isEmpty() || path.size() > 4096 || !QDir::isAbsolutePath(path) ||
        path.contains(u'\n') || path.contains(u'\r') || path.contains(QChar(0)) ||
        (!save && (!file.isFile() || !file.isReadable())) ||
        (save && (file.exists() || file.isSymLink() || !QFileInfo(file.absolutePath()).isDir() ||
                  !QFileInfo(file.absolutePath()).isWritable()))) {
        return failure(
            QStringLiteral("The requested file is not a valid isolated open/save target"));
    }
    GdkDisplay *display = gdk_display_get_default();
    if (!display || !GDK_IS_X11_DISPLAY(display))
        return failure(QStringLiteral("There is no current-process GTK X11 display to inspect"));
    GtkWidget *dialog = nullptr;
    int matches = 0;
    GList *windows = gtk_window_list_toplevels();
    for (GList *entry = windows; entry; entry = entry->next) {
        auto *candidate = GTK_WIDGET(entry->data);
        if (eligible(candidate, title, expectedOwnerWindow, save)) {
            dialog = candidate;
            ++matches;
        }
    }
    g_list_free(windows);
    result.insert(QStringLiteral("matches"), matches);
    if (matches != 1)
        return failure(
            QStringLiteral("Expected one visible GTK file chooser belonging to this test window"));
    g_object_ref(dialog);
    result.insert(
        QStringLiteral("window"),
        QStringLiteral("0x%1").arg(gdk_x11_window_get_xid(gtk_widget_get_window(dialog)), 0, 16));
    result.insert(QStringLiteral("transientOwner"),
                  QStringLiteral("0x%1").arg(expectedOwnerWindow, 0, 16));
    QVariantList events;
    QVariantList pointerEvents;
    QVariantMap buttonState;
    QString error;
    // An open chooser can retain its location field on subsequent openings.
    // Ctrl+L would toggle it off and send the path to the file-list search.
    const bool reuseLocation = locationEntry(dialog) != nullptr;
    result.insert(QStringLiteral("reusedLocationEntry"), reuseLocation);
    bool ok = reuseLocation || key(dialog, GDK_KEY_l, GDK_CONTROL_MASK, title, expectedOwnerWindow,
                                   save, &events, &error);
    QElapsedTimer locationReady;
    locationReady.start();
    while (ok && eligible(dialog, title, expectedOwnerWindow, save) &&
           (!locationEntry(dialog) || !shown(locationEntry(dialog))) &&
           locationReady.elapsed() < 1000)
        dispatchPending(5);
    if (ok && (!eligible(dialog, title, expectedOwnerWindow, save) || !locationEntry(dialog) ||
               !shown(locationEntry(dialog)))) {
        error = QStringLiteral("The GTK chooser did not focus its location entry");
        ok = false;
    }
    if (ok)
        ok = key(dialog, GDK_KEY_a, GDK_CONTROL_MASK, title, expectedOwnerWindow, save, &events,
                 &error);
    for (const char32_t point : path.toUcs4()) {
        if (!ok)
            break;
        ok = key(dialog, gdk_unicode_to_keyval(point), 0, title, expectedOwnerWindow, save, &events,
                 &error);
    }
    dispatchPending(40);
    // File creation between typing and acceptance must not trigger an overwrite
    // prompt that this helper could accidentally approve on a later invocation.
    if (ok && save && (QFileInfo(path).exists() || QFileInfo(path).isSymLink())) {
        error = QStringLiteral("The save target appeared before acceptance");
        ok = false;
    }
    GtkWidget *location = locationEntry(dialog);
    if (ok && (!location || QString::fromUtf8(gtk_entry_get_text(GTK_ENTRY(location))) != path)) {
        error = QStringLiteral("The GTK location entry does not contain the requested path");
        ok = false;
    }
    if (ok)
        ok = clickAccept(dialog, title, path, expectedOwnerWindow, save, &pointerEvents,
                         &buttonState, &error);
    QElapsedTimer closing;
    closing.start();
    while (ok && shown(dialog) && closing.elapsed() < 5000)
        dispatchPending(10);
    result.insert(QStringLiteral("keys"), events.size());
    result.insert(QStringLiteral("events"), events);
    result.insert(QStringLiteral("pointerEvents"), pointerEvents);
    result.insert(QStringLiteral("acceptButton"), buttonState);
    result.insert(QStringLiteral("mappedAfter"), static_cast<bool>(gtk_widget_get_mapped(dialog)));
    result.insert(QStringLiteral("realizedAfter"),
                  static_cast<bool>(gtk_widget_get_realized(dialog)));
    if (ok && shown(dialog)) {
        error = QStringLiteral("GTK processed the key events but the chooser did not close");
        ok = false;
    }
    g_object_unref(dialog);
    if (!ok)
        return failure(error);
    result.insert(QStringLiteral("status"), QStringLiteral("passed"));
    result.insert(QStringLiteral("error"), QString{});
    return result;
}

} // namespace hexproof::client
