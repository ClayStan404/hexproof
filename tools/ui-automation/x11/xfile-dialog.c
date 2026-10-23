// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#define _POSIX_C_SOURCE 200809L

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XTest.h>
#include <X11/keysym.h>

#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

typedef struct
{
    Display *display;
    unsigned long pid;
    const char *title;
    Window dialog;
    Window owner;
    unsigned int matches;
    unsigned int visited;
    unsigned int keys;
    bool save;
    bool directed;
    const char *failure;
    const char *step;
    KeySym lastSymbol;
    Window focus;
    Window checkedOwner;
    bool focusInDialog;
    bool dialogEligible;
    Atom pidAtom;
    Atom titleAtom;
    Atom utf8Atom;
    Atom typeAtom;
    Atom dialogAtom;
} Context;

static int xError;
static unsigned char xRequest;
static unsigned char xMinor;
static XID xResource;

static int handleXError(Display *display, XErrorEvent *event)
{
    (void)display;
    xError = event->error_code;
    xRequest = event->request_code;
    xMinor = event->minor_code;
    xResource = event->resourceid;
    return 0;
}

static void pauseMs(long milliseconds)
{
    struct timespec delay = {milliseconds / 1000, (milliseconds % 1000) * 1000000};
    while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {
    }
}

static bool propertyContains(Context *context, Window window, Atom property, Atom type,
                             unsigned long expected)
{
    Atom actualType = None;
    int format = 0;
    unsigned long count = 0;
    unsigned long remaining = 0;
    unsigned char *value = NULL;
    bool found = false;
    if (XGetWindowProperty(context->display, window, property, 0, 32, False, type, &actualType,
                           &format, &count, &remaining, &value) == Success &&
        actualType == type && format == 32 && remaining == 0) {
        for (unsigned long index = 0; index < count; ++index)
            found = found || ((unsigned long *)value)[index] == expected;
    }
    if (value != NULL)
        XFree(value);
    return found;
}

static bool ownedWindow(Context *context, Window window)
{
    return propertyContains(context, window, context->pidAtom, XA_CARDINAL, context->pid);
}

static bool visibleWindow(Context *context, Window window)
{
    XWindowAttributes attributes;
    return XGetWindowAttributes(context->display, window, &attributes) &&
           attributes.map_state == IsViewable;
}

static char *windowTitle(Context *context, Window window)
{
    Atom actualType = None;
    int format = 0;
    unsigned long count = 0;
    unsigned long remaining = 0;
    unsigned char *value = NULL;
    if (XGetWindowProperty(context->display, window, context->titleAtom, 0, 1024, False,
                           context->utf8Atom, &actualType, &format, &count, &remaining,
                           &value) == Success &&
        actualType == context->utf8Atom && format == 8 && remaining == 0 && count > 0)
        return (char *)value;
    if (value != NULL)
        XFree(value);
    char *legacy = NULL;
    XFetchName(context->display, window, &legacy);
    return legacy;
}

static Window transientOwner(Context *context, Window dialog)
{
    Window current = dialog;
    for (int depth = 0; depth < 8; ++depth) {
        Window parent = None;
        if (!XGetTransientForHint(context->display, current, &parent))
            return current == dialog ? None : current;
        if (parent == current || parent == dialog || parent == None ||
            !ownedWindow(context, parent) || !visibleWindow(context, parent))
            return None;
        current = parent;
    }
    return None;
}

static bool eligibleDialog(Context *context, Window window, Window *owner)
{
    if (!ownedWindow(context, window) || !visibleWindow(context, window) ||
        !propertyContains(context, window, context->typeAtom, XA_ATOM, context->dialogAtom))
        return false;
    char *title = windowTitle(context, window);
    const bool matches = title != NULL && strcmp(title, context->title) == 0;
    if (title != NULL)
        XFree(title);
    if (!matches)
        return false;
    *owner = transientOwner(context, window);
    return *owner != None;
}

static void findDialog(Context *context, Window window, int depth)
{
    if (++context->visited > 16384 || depth > 16)
        return;
    Window owner = None;
    if (eligibleDialog(context, window, &owner)) {
        context->dialog = window;
        context->owner = owner;
        ++context->matches;
    }
    Window root = None;
    Window parent = None;
    Window *children = NULL;
    unsigned int count = 0;
    if (XQueryTree(context->display, window, &root, &parent, &children, &count)) {
        for (unsigned int index = 0; index < count; ++index)
            findDialog(context, children[index], depth + 1);
    }
    if (children != NULL)
        XFree(children);
}

static bool keyCode(Context *context, KeySym symbol, KeyCode *code, unsigned int *modifiers)
{
    int minimum = 0;
    int maximum = 0;
    int perCode = 0;
    XDisplayKeycodes(context->display, &minimum, &maximum);
    KeySym *mapping =
        XGetKeyboardMapping(context->display, (KeyCode)minimum, maximum - minimum + 1, &perCode);
    if (mapping == NULL)
        return false;
    bool found = false;
    for (int key = minimum; key <= maximum && !found; ++key) {
        for (int level = 0; level < 2 && level < perCode; ++level) {
            if (mapping[(key - minimum) * perCode + level] == symbol) {
                *code = (KeyCode)key;
                *modifiers = level == 1 ? ShiftMask : 0;
                found = true;
                break;
            }
        }
    }
    XFree(mapping);
    return found;
}

static bool sendKey(Context *context, KeySym symbol, unsigned int modifiers)
{
    context->lastSymbol = symbol;
    KeyCode code = 0;
    unsigned int keyModifiers = 0;
    if (!keyCode(context, symbol, &code, &keyModifiers)) {
        context->failure = "Requested key is absent from the current keyboard map";
        return false;
    }
    const unsigned int required = modifiers | keyModifiers;
    KeyCode control = 0;
    KeyCode shift = 0;
    unsigned int unused = 0;
    if ((required & ControlMask) && !keyCode(context, XK_Control_L, &control, &unused)) {
        context->failure = "Control modifier is absent from the current keyboard map";
        return false;
    }
    if ((required & ShiftMask) && !keyCode(context, XK_Shift_L, &shift, &unused)) {
        context->failure = "Shift modifier is absent from the current keyboard map";
        return false;
    }

    // GTK ignores directed XSendEvent keyboard input. XTest follows real input
    // focus, so verify the exact owned dialog under a short server grab. Queue
    // each complete chord, including modifier releases, before allowing another
    // client's focus request to run. Never leave a modifier held on an abort.
    XGrabServer(context->display);
    Window owner = None;
    Window focus = None;
    int revert = 0;
    XGetInputFocus(context->display, &focus, &revert);
    context->focus = focus;
    bool focused = false;
    for (int depth = 0; depth < 32 && focus != None && focus != PointerRoot; ++depth) {
        if (focus == context->dialog) {
            focused = true;
            break;
        }
        Window root = None;
        Window parent = None;
        Window *children = NULL;
        unsigned int count = 0;
        const bool queried = XQueryTree(context->display, focus, &root, &parent, &children, &count);
        if (children != NULL)
            XFree(children);
        if (!queried || parent == focus)
            break;
        focus = parent;
    }
    context->focusInDialog = focused;
    context->dialogEligible = eligibleDialog(context, context->dialog, &owner);
    context->checkedOwner = owner;
    bool ok = focused && context->dialogEligible && owner == context->owner;
    if (!focused)
        context->failure = "Input focus left the selected dialog's X window subtree";
    else if (!context->dialogEligible)
        context->failure =
            "Selected dialog no longer matches PID, title, visibility or transient ownership";
    else if (owner != context->owner)
        context->failure = "Selected dialog's transient owner changed";
    if (ok) {
        if (context->directed) {
            XEvent event = {0};
            event.xkey.display = context->display;
            event.xkey.window = context->focus;
            event.xkey.root = XDefaultRootWindow(context->display);
            event.xkey.same_screen = True;
            event.xkey.keycode = code;
            event.xkey.state = required;
            event.xkey.type = KeyPress;
            // XI2 clients need not select core KeyPressMask. An empty mask
            // routes this core event directly to the creator of the validated
            // focus window, which GTK explicitly supports for synthetic input.
            ok = XSendEvent(context->display, context->focus, False, NoEventMask, &event) && ok;
            event.xkey.type = KeyRelease;
            ok = XSendEvent(context->display, context->focus, False, NoEventMask, &event) && ok;
        } else {
            if (control)
                ok = XTestFakeKeyEvent(context->display, control, True, CurrentTime) && ok;
            if (shift)
                ok = XTestFakeKeyEvent(context->display, shift, True, CurrentTime) && ok;
            ok = XTestFakeKeyEvent(context->display, code, True, CurrentTime) && ok;
            ok = XTestFakeKeyEvent(context->display, code, False, CurrentTime) && ok;
            if (shift)
                ok = XTestFakeKeyEvent(context->display, shift, False, CurrentTime) && ok;
            if (control)
                ok = XTestFakeKeyEvent(context->display, control, False, CurrentTime) && ok;
        }
        ++context->keys;
        if (!ok)
            context->failure = "X11 rejected a key press or release";
    }
    XSync(context->display, False);
    XUngrabServer(context->display);
    XFlush(context->display);
    if (xError != 0)
        context->failure = "X server reported an error while validating or sending input";
    return ok && xError == 0;
}

static void jsonString(FILE *output, const char *value)
{
    fputc('"', output);
    for (const unsigned char *next = (const unsigned char *)value; *next; ++next) {
        if (*next == '"' || *next == '\\')
            fprintf(output, "\\%c", *next);
        else if (*next < 32)
            fprintf(output, "\\u%04x", *next);
        else
            fputc(*next, output);
    }
    fputc('"', output);
}

static unsigned long windowPid(Context *context, Window window)
{
    Atom type = None;
    int format = 0;
    unsigned long count = 0;
    unsigned long remaining = 0;
    unsigned char *value = NULL;
    unsigned long pid = 0;
    if (window != None && window != PointerRoot &&
        XGetWindowProperty(context->display, window, context->pidAtom, 0, 1, False, XA_CARDINAL,
                           &type, &format, &count, &remaining, &value) == Success &&
        type == XA_CARDINAL && format == 32 && count == 1 && remaining == 0) {
        pid = *(unsigned long *)value;
    }
    if (value)
        XFree(value);
    return pid;
}

static void reportWindow(FILE *output, Context *context, Window window)
{
    const unsigned long pid = windowPid(context, window);
    Window transient = None;
    const bool exists = window != None && window != PointerRoot;
    if (exists)
        XGetTransientForHint(context->display, window, &transient);
    XWindowAttributes attributes = {0};
    if (exists)
        XGetWindowAttributes(context->display, window, &attributes);
    fprintf(output, "{\"window\":\"0x%lx\",\"pid\":%lu,\"transient\":\"0x%lx\",\"visible\":%s",
            window, pid, transient, exists && visibleWindow(context, window) ? "true" : "false");
    fprintf(output, ",\"coreEventMask\":%ld,\"width\":%d,\"height\":%d", attributes.all_event_masks,
            attributes.width, attributes.height);
    if (pid == context->pid) {
        char *title = windowTitle(context, window);
        fprintf(output, ",\"title\":");
        jsonString(output, title ? title : "");
        if (title)
            XFree(title);
        fprintf(output, ",\"dialogType\":%s",
                propertyContains(context, window, context->typeAtom, XA_ATOM, context->dialogAtom)
                    ? "true"
                    : "false");
    }
    fputs("}", output);
}

static bool report(FILE *output, Context *context, const char *status, const char *error,
                   const char *path)
{
    const int savedError = xError;
    const unsigned char savedRequest = xRequest;
    const unsigned char savedMinor = xMinor;
    const XID savedResource = xResource;
    fprintf(output, "{\"status\":");
    jsonString(output, status);
    fprintf(output, ",\"error\":");
    jsonString(output, error);
    fprintf(output,
            ",\"pid\":%lu,\"window\":\"0x%lx\",\"transientOwner\":\"0x%lx\","
            "\"matches\":%u,\"keys\":%u,\"evidence\":\"%s\",\"title\":",
            context->pid, context->dialog, context->owner, context->matches, context->keys,
            context->directed ? "x11-directed-focus-input" : "x11-focus-verified-xtest");
    jsonString(output, context->title);
    fprintf(output, ",\"path\":");
    jsonString(output, path);
    fprintf(output, ",\"mode\":\"%s\"", context->save ? "save" : "open");
    fprintf(output, ",\"step\":");
    jsonString(output, context->step ? context->step : "inspect");
    fprintf(output,
            ",\"lastSymbol\":%lu,\"xError\":%d,\"xRequest\":%u,\"xMinor\":%u,"
            "\"xResource\":\"0x%lx\",\"focusInDialog\":%s,\"dialogEligible\":%s,"
            "\"checkedOwner\":\"0x%lx\"",
            context->lastSymbol, xError, xRequest, xMinor, xResource,
            context->focusInDialog ? "true" : "false", context->dialogEligible ? "true" : "false",
            context->checkedOwner);
    if (context->display) {
        fprintf(output, ",\"focus\":");
        reportWindow(output, context, context->focus);
        fprintf(output, ",\"currentDialog\":");
        reportWindow(output, context, context->dialog);
        fprintf(output, ",\"currentOwner\":");
        reportWindow(output, context, context->owner);
    }
    fputs("}\n", output);
    // The dialog may already be destroyed after successful selection. Reads
    // for diagnostic output must not replace the actual input failure details.
    xError = savedError;
    xRequest = savedRequest;
    xMinor = savedMinor;
    xResource = savedResource;
    return !ferror(output);
}

static const char *validateSelectionPath(const char *path, bool save)
{
    if (*path != '/' || strlen(path) > 4096)
        return "select a bounded absolute path";
    for (const unsigned char *next = (const unsigned char *)path; *next; ++next) {
        if (*next < 32 || *next > 126)
            return "this helper requires a printable ASCII path";
    }

    struct stat attributes;
    if (!save) {
        if (stat(path, &attributes) != 0 || !S_ISREG(attributes.st_mode) || access(path, R_OK) != 0)
            return "select a readable absolute regular file";
        return NULL;
    }

    // lstat also rejects dangling symlinks. Never pre-create a save target or
    // approve an overwrite confirmation on behalf of the caller.
    if (lstat(path, &attributes) == 0 || errno != ENOENT)
        return "save requires a new target; existing paths cannot be overwritten";
    const char *separator = strrchr(path, '/');
    if (separator[1] == '\0')
        return "save requires a file name";
    char parent[4097];
    const size_t length = separator == path ? 1 : (size_t)(separator - path);
    memcpy(parent, path, length);
    parent[length] = '\0';
    if (stat(parent, &attributes) != 0 || !S_ISDIR(attributes.st_mode) ||
        access(parent, W_OK | X_OK) != 0)
        return "save requires an existing writable parent directory";
    return NULL;
}

int main(int argc, char **argv)
{
    bool inspect = false;
    bool save = false;
    bool directed = false;
    int offset = 0;
    while (argc > offset + 1) {
        const char *option = argv[offset + 1];
        if (strcmp(option, "--inspect") == 0 && !inspect)
            inspect = true;
        else if (strcmp(option, "--save") == 0 && !save)
            save = true;
        else if (strcmp(option, "--directed") == 0 && !directed)
            directed = true;
        else
            break;
        ++offset;
    }
    if ((!inspect && argc != 4 + offset && argc != 5 + offset) ||
        (inspect && (argc != 3 + offset || save || directed))) {
        fprintf(stderr, "usage: xfile-dialog PID EXACT_TITLE ABSOLUTE_PATH [ARTIFACT_BASE]\n"
                        "       xfile-dialog --save PID EXACT_TITLE ABSOLUTE_PATH [ARTIFACT_BASE]\n"
                        "       xfile-dialog --directed [--save] PID EXACT_TITLE ABSOLUTE_PATH "
                        "[ARTIFACT_BASE]\n"
                        "       xfile-dialog --inspect PID EXACT_TITLE\n");
        return 2;
    }
    char *end = NULL;
    errno = 0;
    const unsigned long pid = strtoul(argv[1 + offset], &end, 10);
    if (errno != 0 || *end != '\0' || pid == 0 || pid > INT_MAX) {
        fprintf(stderr, "xfile-dialog: invalid client PID\n");
        return 2;
    }
    const char *title = argv[2 + offset];
    const char *path = inspect ? "" : argv[3 + offset];
    const char *artifactBase = !inspect && argc == 5 + offset ? argv[4 + offset] : NULL;
    if (!*title || strlen(title) > 4096) {
        fprintf(stderr, "xfile-dialog: an exact dialog title is required\n");
        return 2;
    }
    if (!inspect) {
        const char *pathError = validateSelectionPath(path, save);
        if (pathError) {
            fprintf(stderr, "xfile-dialog: %s\n", pathError);
            return 2;
        }
    }
    Context context = {.pid = pid, .title = title, .save = save, .directed = directed};
    context.display = XOpenDisplay(NULL);
    if (context.display == NULL) {
        report(stdout, &context, "failed", "Could not open the X11 display", path);
        return 1;
    }
    XSetErrorHandler(handleXError);
    context.pidAtom = XInternAtom(context.display, "_NET_WM_PID", False);
    context.titleAtom = XInternAtom(context.display, "_NET_WM_NAME", False);
    context.utf8Atom = XInternAtom(context.display, "UTF8_STRING", False);
    context.typeAtom = XInternAtom(context.display, "_NET_WM_WINDOW_TYPE", False);
    context.dialogAtom = XInternAtom(context.display, "_NET_WM_WINDOW_TYPE_DIALOG", False);
    findDialog(&context, XDefaultRootWindow(context.display), 0);
    // Windows can disappear during the read-only tree walk; selected identity
    // is checked again immediately before every directed keyboard event.
    XSync(context.display, False);
    xError = 0;
    int revert = 0;
    XGetInputFocus(context.display, &context.focus, &revert);
    const char *error = "";
    bool ok = context.matches == 1;
    if (!ok)
        error = "Expected exactly one visible PID/title/transient-owned dialog";
    if (ok && !inspect) {
        context.step = "open-location";
        ok = sendKey(&context, XK_l, ControlMask);
        pauseMs(150);
        if (ok) {
            context.step = "select-location";
            ok = sendKey(&context, XK_a, ControlMask);
        }
        for (const unsigned char *next = (const unsigned char *)path; ok && *next; ++next) {
            context.step = "type-location";
            ok = sendKey(&context, (KeySym)*next, 0);
        }
        pauseMs(150);
        if (ok && save) {
            const char *pathError = validateSelectionPath(path, true);
            if (pathError) {
                ok = false;
                error = pathError;
            }
        }
        if (ok) {
            context.step = "accept-location";
            ok = sendKey(&context, XK_Return, 0);
        }
        if (ok) {
            context.step = "wait-for-close";
            for (int attempt = 0; attempt < 100 && visibleWindow(&context, context.dialog);
                 ++attempt)
                pauseMs(100);
            ok = !visibleWindow(&context, context.dialog);
        }
        if (!ok && !*error)
            error = context.failure ? context.failure
                                    : "Selected dialog did not close within ten seconds";
    }
    if (artifactBase) {
        char *destination = malloc(strlen(artifactBase) + 6);
        if (destination == NULL) {
            ok = false;
            error = "Could not allocate artifact path";
        } else {
            sprintf(destination, "%s.json", artifactBase);
            FILE *output = fopen(destination, "wx");
            const bool written =
                output != NULL && report(output, &context, ok ? "passed" : "failed", error, path);
            const bool closed = output != NULL && fclose(output) == 0;
            if (!written || !closed) {
                ok = false;
                error = "Could not create the exclusive identity artifact";
            }
            free(destination);
        }
    }
    report(stdout, &context, ok ? "passed" : "failed", error, path);
    XCloseDisplay(context.display);
    return ok ? 0 : 1;
}
