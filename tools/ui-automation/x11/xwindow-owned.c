// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int xError;
static int ignoreXError(Display *display, XErrorEvent *event)
{
    (void)display;
    (void)event;
    xError = 1;
    return 0;
}

static unsigned long windowPid(Display *display, Window window)
{
    Atom actual = None;
    int format = 0;
    unsigned long count = 0, remaining = 0;
    unsigned char *bytes = NULL;
    unsigned long pid = 0;
    if (XGetWindowProperty(display, window, XInternAtom(display, "_NET_WM_PID", False), 0, 1, False,
                           XA_CARDINAL, &actual, &format, &count, &remaining, &bytes) == Success &&
        actual == XA_CARDINAL && format == 32 && count == 1)
        pid = *(unsigned long *)bytes;
    if (bytes)
        XFree(bytes);
    return pid;
}

static void findOwned(Display *display, Window parent, unsigned long pid, int depth, Window *match,
                      int *matches)
{
    if (depth > 8 || *matches > 1)
        return;
    XWindowAttributes attributes;
    Window transient = None;
    if (windowPid(display, parent) == pid && XGetWindowAttributes(display, parent, &attributes) &&
        attributes.map_state == IsViewable && attributes.class == InputOutput &&
        attributes.width >= 640 && attributes.height >= 400 &&
        !XGetTransientForHint(display, parent, &transient)) {
        *match = parent;
        ++*matches;
        return;
    }
    Window root = None, ancestor = None, *children = NULL;
    unsigned int count = 0;
    if (!XQueryTree(display, parent, &root, &ancestor, &children, &count))
        return;
    for (unsigned int index = 0; index < count; ++index)
        findOwned(display, children[index], pid, depth + 1, match, matches);
    if (children)
        XFree(children);
}

static unsigned char channel(unsigned long pixel, unsigned long mask)
{
    if (!mask)
        return 0;
    unsigned int shift = 0;
    while (!(mask & 1UL)) {
        mask >>= 1;
        ++shift;
    }
    return (unsigned char)((((pixel >> shift) & mask) * UCHAR_MAX + mask / 2) / mask);
}

static int capture(Display *display, Window window, const XWindowAttributes *attributes,
                   const char *path)
{
    XImage *image = XGetImage(display, window, 0, 0, (unsigned int)attributes->width,
                              (unsigned int)attributes->height, AllPlanes, ZPixmap);
    if (!image)
        return 0;
    FILE *file = fopen(path, "wbx");
    if (!file) {
        XDestroyImage(image);
        return 0;
    }
    int ok = fprintf(file, "P6\n%d %d\n255\n", attributes->width, attributes->height) > 0;
    for (int y = 0; y < attributes->height && ok; ++y) {
        for (int x = 0; x < attributes->width; ++x) {
            const unsigned long pixel = XGetPixel(image, x, y);
            const unsigned char rgb[] = {channel(pixel, image->red_mask),
                                         channel(pixel, image->green_mask),
                                         channel(pixel, image->blue_mask)};
            if (fwrite(rgb, 1, sizeof(rgb), file) != sizeof(rgb)) {
                ok = 0;
                break;
            }
        }
    }
    if (fclose(file))
        ok = 0;
    XDestroyImage(image);
    return ok;
}

static int closeWindow(Display *display, Window window)
{
    Atom *protocols = NULL;
    int count = 0, supported = 0;
    const Atom deletion = XInternAtom(display, "WM_DELETE_WINDOW", False);
    if (XGetWMProtocols(display, window, &protocols, &count)) {
        for (int index = 0; index < count; ++index)
            if (protocols[index] == deletion)
                supported = 1;
        XFree(protocols);
    }
    if (!supported)
        return 0;
    XEvent event;
    memset(&event, 0, sizeof(event));
    event.xclient.type = ClientMessage;
    event.xclient.window = window;
    event.xclient.message_type = XInternAtom(display, "WM_PROTOCOLS", False);
    event.xclient.format = 32;
    event.xclient.data.l[0] = (long)deletion;
    event.xclient.data.l[1] = CurrentTime;
    return XSendEvent(display, window, False, NoEventMask, &event) != 0;
}

int main(int argc, char **argv)
{
    if (argc < 3 || argc > 4 ||
        (strcmp(argv[1], "--inspect") && strcmp(argv[1], "--capture") &&
         strcmp(argv[1], "--close")))
        return fprintf(stderr,
                       "usage: xwindow-owned --inspect|--close PID; --capture PID OUTPUT.ppm\n"),
               2;
    if ((!strcmp(argv[1], "--capture")) != (argc == 4))
        return 2;
    errno = 0;
    char *end = NULL;
    const unsigned long pid = strtoul(argv[2], &end, 10);
    if (errno || !end || *end || pid <= 1 || pid > INT_MAX)
        return 2;
    Display *display = XOpenDisplay(NULL);
    if (!display)
        return fprintf(stderr, "No X11 display\n"), 1;
    XSetErrorHandler(ignoreXError);
    XGrabServer(display);
    Window window = None;
    int matches = 0;
    findOwned(display, DefaultRootWindow(display), pid, 0, &window, &matches);
    XWindowAttributes attributes;
    int ok = matches == 1 && windowPid(display, window) == pid &&
             XGetWindowAttributes(display, window, &attributes) &&
             attributes.map_state == IsViewable;
    if (ok && !strcmp(argv[1], "--capture"))
        ok = capture(display, window, &attributes, argv[3]);
    if (ok && !strcmp(argv[1], "--close"))
        ok = closeWindow(display, window);
    XSync(display, False);
    ok = ok && !xError;
    XUngrabServer(display);
    XFlush(display);
    if (ok)
        printf("{\"status\":\"passed\",\"pid\":%lu,\"window\":\"0x%lx\",\"width\":%d,\"height\":%d,"
               "\"visible\":true,\"action\":\"%s\"}\n",
               pid, window, attributes.width, attributes.height, argv[1]);
    else
        printf("{\"status\":\"failed\",\"pid\":%lu,\"matchingWindows\":%d,\"xError\":%d}\n", pid,
               matches, xError);
    XCloseDisplay(display);
    return ok ? 0 : 1;
}
