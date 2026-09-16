// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Substitute only X server reads/event delivery. The production identity and
// keyboard guards run unchanged, without opening or focusing desktop windows.
#define XGetWindowProperty fixtureProperty
#define XGetWindowAttributes fixtureAttributes
#define XGetTransientForHint fixtureTransient
#define XQueryTree fixtureTree
#define XDisplayKeycodes fixtureKeycodes
#define XGetKeyboardMapping fixtureMapping
#define XTestFakeKeyEvent fixtureSend
#define XSendEvent fixtureDirectedSend
#define XGetInputFocus fixtureFocus
#define XGrabServer fixtureGrab
#define XUngrabServer fixtureUngrab
#define XFlush fixtureFlush
#define XSync fixtureSync
#define XDefaultRootWindow fixtureRoot
#define main xfileDialogMain
#include "xfile-dialog.c"
#undef main

typedef struct
{
    Window id;
    unsigned long pid;
    const char *title;
    Window parent;
    bool dialog;
    bool visible;
    Window treeParent;
} FixtureWindow;

static FixtureWindow windows[4];
static unsigned int sent;
static Window sentTo;
static Window inputFocus;
static bool grabbed;
static int failures;
static unsigned int checks;

static FixtureWindow *windowFor(Window id)
{
    for (size_t index = 0; index < sizeof(windows) / sizeof(windows[0]); ++index)
        if (windows[index].id == id)
            return &windows[index];
    return NULL;
}

int fixtureProperty(Display *display, Window window, Atom property, long offset, long length,
                    Bool deleteProperty, Atom requestedType, Atom *actualType, int *format,
                    unsigned long *count, unsigned long *remaining, unsigned char **value)
{
    (void)display;
    (void)offset;
    (void)length;
    (void)deleteProperty;
    FixtureWindow *fixture = windowFor(window);
    *actualType = None;
    *format = 0;
    *count = 0;
    *remaining = 0;
    *value = NULL;
    if (fixture == NULL)
        return Success;
    *actualType = requestedType;
    if (property == 101) {
        *format = 8;
        *count = strlen(fixture->title);
        *value = (unsigned char *)strdup(fixture->title);
    } else {
        *format = 32;
        *count = 1;
        *value = malloc(sizeof(unsigned long));
        *(unsigned long *)*value = property == 100 ? fixture->pid : fixture->dialog ? 104 : 105;
    }
    return Success;
}

Status fixtureAttributes(Display *display, Window window, XWindowAttributes *attributes)
{
    (void)display;
    const FixtureWindow *fixture = windowFor(window);
    if (fixture == NULL)
        return 0;
    attributes->map_state = fixture->visible ? IsViewable : IsUnmapped;
    return 1;
}

Status fixtureTransient(Display *display, Window window, Window *parent)
{
    (void)display;
    const FixtureWindow *fixture = windowFor(window);
    *parent = fixture ? fixture->parent : None;
    return *parent != None;
}

Status fixtureTree(Display *display, Window window, Window *root, Window *parent, Window **children,
                   unsigned int *count)
{
    (void)display;
    *root = 1;
    const FixtureWindow *fixture = windowFor(window);
    *parent = fixture && fixture->treeParent ? fixture->treeParent : 1;
    *count = window == 1 ? 4 : 0;
    *children = *count ? malloc(*count * sizeof(Window)) : NULL;
    for (unsigned int index = 0; index < *count; ++index)
        (*children)[index] = windows[index].id;
    return 1;
}

int fixtureKeycodes(Display *display, int *minimum, int *maximum)
{
    (void)display;
    *minimum = 8;
    *maximum = 10;
    return 1;
}

KeySym *fixtureMapping(Display *display, KeyCode first, int count, int *perCode)
{
    (void)display;
    (void)first;
    (void)count;
    *perCode = 2;
    KeySym *mapping = calloc(6, sizeof(KeySym));
    mapping[0] = XK_l;
    mapping[1] = XK_L;
    mapping[2] = XK_Control_L;
    mapping[4] = XK_Shift_L;
    return mapping;
}

Bool fixtureSend(Display *display, unsigned int code, Bool pressed, unsigned long delay)
{
    (void)display;
    (void)code;
    (void)pressed;
    (void)delay;
    if (!grabbed)
        return 0;
    ++sent;
    sentTo = inputFocus;
    return 1;
}

Status fixtureDirectedSend(Display *display, Window window, Bool propagate, long mask,
                           XEvent *event)
{
    (void)display;
    if (!grabbed || propagate || window != event->xkey.window || mask != NoEventMask ||
        (event->xkey.type != KeyPress && event->xkey.type != KeyRelease))
        return 0;
    ++sent;
    sentTo = window;
    return 1;
}

int fixtureFocus(Display *display, Window *window, int *revert)
{
    (void)display;
    *window = inputFocus;
    *revert = RevertToParent;
    return 1;
}

int fixtureGrab(Display *display)
{
    (void)display;
    grabbed = true;
    return 1;
}

int fixtureUngrab(Display *display)
{
    (void)display;
    grabbed = false;
    return 1;
}

int fixtureFlush(Display *display)
{
    (void)display;
    return 1;
}

int fixtureSync(Display *display, Bool discard)
{
    (void)display;
    (void)discard;
    return 0;
}

Window fixtureRoot(Display *display)
{
    (void)display;
    return 1;
}

static Context resetFixture(void)
{
    windows[0] = (FixtureWindow){10, 1234, "Hexproof test", None, false, true, 1};
    windows[1] = (FixtureWindow){11, 1234, "Import card database", 10, true, true, 1};
    windows[2] = (FixtureWindow){12, 9876, "Import card database", 10, true, true, 1};
    windows[3] = (FixtureWindow){13, 1234, "Import card database", 10, true, false, 1};
    sent = 0;
    sentTo = None;
    inputFocus = 11;
    grabbed = false;
    xError = 0;
    return (Context){.pid = 1234,
                     .title = "Import card database",
                     .pidAtom = 100,
                     .titleAtom = 101,
                     .utf8Atom = 102,
                     .typeAtom = 103,
                     .dialogAtom = 104};
}

static void check(bool condition, const char *name)
{
    ++checks;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", name);
        ++failures;
    }
}

static void checkSelectionPaths(void)
{
    char directory[] = "/tmp/hexproof-file-dialog-XXXXXX";
    const bool created = mkdtemp(directory) != NULL;
    check(created, "create an isolated path-validation directory");
    if (!created)
        return;
    char fresh[4096];
    char missingParent[4096];
    char dangling[4096];
    char childOfFile[4096];
    char trailingSlash[4096];
    snprintf(fresh, sizeof(fresh), "%s/new-deck.txt", directory);
    snprintf(missingParent, sizeof(missingParent), "%s/missing/deck.txt", directory);
    snprintf(dangling, sizeof(dangling), "%s/dangling.txt", directory);
    snprintf(childOfFile, sizeof(childOfFile), "%s/new-deck.txt/child.txt", directory);
    snprintf(trailingSlash, sizeof(trailingSlash), "%s/new-directory/", directory);
    struct stat attributes;
    check(validateSelectionPath(fresh, true) == NULL,
          "save accepts a new file in an existing writable directory");
    check(lstat(fresh, &attributes) != 0 && errno == ENOENT,
          "save validation does not pre-create the target");
    check(validateSelectionPath(fresh, false) != NULL, "open still rejects a missing file");
    check(validateSelectionPath(missingParent, true) != NULL,
          "save rejects a missing parent directory");
    check(validateSelectionPath(trailingSlash, true) != NULL,
          "save requires a file name rather than a trailing slash");
    check(validateSelectionPath("relative.txt", true) != NULL,
          "save rejects a relative destination");
    check(validateSelectionPath("/tmp/deck\n.txt", true) != NULL,
          "save rejects keyboard control characters");
    check(validateSelectionPath(directory, true) != NULL,
          "save rejects an existing directory destination");
    check(validateSelectionPath(directory, false) != NULL,
          "open still rejects directory destinations");
    check(symlink(fresh, dangling) == 0, "create a dangling symlink fixture");
    check(validateSelectionPath(dangling, true) != NULL,
          "save rejects a dangling symlink instead of following it to a new target");
    check(validateSelectionPath(dangling, false) != NULL,
          "open rejects a dangling symlink to a missing file");
    if (geteuid() != 0) {
        check(chmod(directory, 0500) == 0, "remove write permission from the fixture directory");
        check(validateSelectionPath(fresh, true) != NULL,
              "save rejects a parent directory that the caller cannot write");
        check(chmod(directory, 0700) == 0, "restore fixture directory permissions");
    }
    FILE *existing = fopen(fresh, "wx");
    check(existing != NULL, "create an existing deck fixture");
    if (existing) {
        fputs("Deck\n1 Island (LEA) 291\n", existing);
        check(fclose(existing) == 0, "close the existing deck fixture");
        check(validateSelectionPath(fresh, false) == NULL,
              "open accepts an existing readable regular file");
        check(validateSelectionPath(fresh, true) != NULL,
              "save revalidation rejects a target created after the first check");
        check(validateSelectionPath(childOfFile, true) != NULL,
              "save rejects a regular file used as a parent directory");
        existing = fopen(fresh, "r");
        char content[64] = {0};
        const size_t length = existing ? fread(content, 1, sizeof(content) - 1, existing) : 0;
        check(length > 0 && strcmp(content, "Deck\n1 Island (LEA) 291\n") == 0,
              "rejected save leaves the existing file unchanged");
        if (existing)
            fclose(existing);
    }
    check(unlink(dangling) == 0, "remove only the isolated symlink fixture");
    check(unlink(fresh) == 0, "remove only the isolated deck fixture");
    check(rmdir(directory) == 0, "remove the empty isolated directory");
}

int main(void)
{
    Context context = resetFixture();
    findDialog(&context, 1, 0);
    check(context.matches == 1 && context.dialog == 11 && context.owner == 10,
          "unique visible PID/title/transient match excludes other processes and hidden windows");
    check(sendKey(&context, XK_l, ControlMask) && sent == 4 && sentTo == 11 && !grabbed,
          "validated input sends a complete chord to the focused owned dialog and releases the "
          "server");
    windows[1].pid = 9876;
    check(!sendKey(&context, XK_l, ControlMask) && sent == 4 && !grabbed,
          "PID changes before input must prevent every event");
    check(context.failure && strstr(context.failure, "PID") && context.focus == 11 &&
              context.focusInDialog && !context.dialogEligible,
          "ownership failure identifies the failed guard and focused window");
    context = resetFixture();
    findDialog(&context, 1, 0);
    inputFocus = 12;
    check(!sendKey(&context, XK_l, ControlMask) && sent == 0 && !grabbed,
          "foreign focus aborts without input and releases the server");
    check(context.failure && strstr(context.failure, "focus") && context.focus == 12 &&
              !context.focusInDialog && context.dialogEligible,
          "focus failure is distinct from an otherwise eligible owned dialog");
    context = resetFixture();
    context.directed = true;
    findDialog(&context, 1, 0);
    check(sendKey(&context, XK_l, ControlMask) && sent == 2 && sentTo == 11 && !grabbed,
          "directed backend sends key press and release only to the validated focus window");
    windows[3] = (FixtureWindow){14, 0, "", None, false, true, 11};
    inputFocus = 14;
    check(sendKey(&context, XK_l, ControlMask) && sent == 4 && sentTo == 14 && !grabbed,
          "GTK focus child receives directed events instead of its outer dialog window");
    context = resetFixture();
    Window owner = None;
    windows[1].title = "Different dialog";
    check(!eligibleDialog(&context, 11, &owner), "title match is exact");
    context = resetFixture();
    windows[1].parent = None;
    check(!eligibleDialog(&context, 11, &owner),
          "a same-PID standalone window is not a dialog owner");
    context = resetFixture();
    windows[0].pid = 9876;
    check(!eligibleDialog(&context, 11, &owner), "a foreign transient parent is rejected");
    context = resetFixture();
    windows[0].parent = 11;
    check(!eligibleDialog(&context, 11, &owner), "a transient cycle is rejected");
    context = resetFixture();
    windows[1].dialog = false;
    check(!eligibleDialog(&context, 11, &owner),
          "normal windows are rejected even with matching title");
    context = resetFixture();
    windows[3].visible = true;
    findDialog(&context, 1, 0);
    check(context.matches == 2,
          "ambiguous same-PID matching dialogs cannot select one arbitrarily");
    context = resetFixture();
    KeyCode code = 0;
    unsigned int modifiers = 0;
    check(keyCode(&context, XK_L, &code, &modifiers) && code == 8 && modifiers == ShiftMask,
          "typing resolves required shift from the current keyboard map");
    check(!keyCode(&context, XK_F12, &code, &modifiers), "unmapped keys fail before sending input");
    checkSelectionPaths();
    if (!failures)
        printf("%u ownership, focus, keyboard-map and file-selection checks passed without an X "
               "server\n",
               checks);
    return failures ? 1 : 0;
}
