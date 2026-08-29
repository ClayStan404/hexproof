// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include <X11/Xlib.h>

#include <stdio.h>

static void visitWindow(Display *display, Window window)
{
    char *name = NULL;
    if (XFetchName(display, window, &name) && name != NULL) {
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
        visitWindow(display, children[index]);
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

    visitWindow(display, DefaultRootWindow(display));
    XCloseDisplay(display);
    return 0;
}
