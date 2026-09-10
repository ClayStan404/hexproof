// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include <X11/Xlib.h>

#include <stdio.h>

static char *windowName(Display *display, Window window, Atom utf8Name, Atom utf8String)
{
    Atom actualType = None;
    int format = 0;
    unsigned long count = 0;
    unsigned long remaining = 0;
    unsigned char *value = NULL;
    // Qt uses the UTF-8 title property for labels that contain non-Latin text.
    // XFetchName alone only reads the legacy WM_NAME property.
    if (XGetWindowProperty(display, window, utf8Name, 0, 1024, False, utf8String, &actualType,
                           &format, &count, &remaining, &value) == Success &&
        actualType == utf8String && format == 8 && count > 0) {
        return (char *)value;
    }
    if (value != NULL)
        XFree(value);
    char *name = NULL;
    XFetchName(display, window, &name);
    return name;
}

static void visitWindow(Display *display, Window window, Atom utf8Name, Atom utf8String)
{
    char *name = windowName(display, window, utf8Name, utf8String);
    if (name != NULL) {
        XWindowAttributes attributes;
        if (XGetWindowAttributes(display, window, &attributes)) {
            printf("0x%lx %dx%d depth=%d class=%d map=%d %s\n", window, attributes.width,
                   attributes.height, attributes.depth, attributes.class, attributes.map_state,
                   name);
        }
        XFree(name);
    }

    Window root = None;
    Window parent = None;
    Window *children = NULL;
    unsigned int childCount = 0;
    if (!XQueryTree(display, window, &root, &parent, &children, &childCount))
        return;

    for (unsigned int index = 0; index < childCount; ++index)
        visitWindow(display, children[index], utf8Name, utf8String);
    if (children != NULL)
        XFree(children);
}

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "xwindow-list: could not open the X11 display\n");
        return 1;
    }

    visitWindow(display, DefaultRootWindow(display), XInternAtom(display, "_NET_WM_NAME", False),
                XInternAtom(display, "UTF8_STRING", False));
    XCloseDisplay(display);
    return 0;
}
