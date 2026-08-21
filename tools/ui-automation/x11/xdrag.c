// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static int parseWindow(const char *text, Window *window)
{
    char *end = NULL;
    errno = 0;
    const unsigned long value = strtoul(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0')
        return 0;
    *window = (Window)value;
    return 1;
}

static int parseCoordinate(const char *text, int *coordinate)
{
    char *end = NULL;
    errno = 0;
    const long value = strtol(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || value < INT_MIN || value > INT_MAX) {
        return 0;
    }
    *coordinate = (int)value;
    return 1;
}

static int sendButton(Display *display, Window window, Window root, int rootX, int rootY, int x,
                      int y, int type)
{
    XEvent event = {0};
    event.xbutton.type = type;
    event.xbutton.display = display;
    event.xbutton.window = window;
    event.xbutton.root = root;
    event.xbutton.x = x;
    event.xbutton.y = y;
    event.xbutton.x_root = rootX + x;
    event.xbutton.y_root = rootY + y;
    event.xbutton.state = type == ButtonRelease ? Button1Mask : 0;
    event.xbutton.button = Button1;
    event.xbutton.same_screen = True;
    return XSendEvent(display, window, True,
                      type == ButtonPress ? ButtonPressMask : ButtonReleaseMask, &event);
}

static int sendMotion(Display *display, Window window, Window root, int rootX, int rootY, int x,
                      int y)
{
    XEvent event = {0};
    event.xmotion.type = MotionNotify;
    event.xmotion.display = display;
    event.xmotion.window = window;
    event.xmotion.root = root;
    event.xmotion.x = x;
    event.xmotion.y = y;
    event.xmotion.x_root = rootX + x;
    event.xmotion.y_root = rootY + y;
    event.xmotion.state = Button1Mask;
    event.xmotion.same_screen = True;
    return XSendEvent(display, window, True, PointerMotionMask, &event);
}

int main(int argc, char **argv)
{
    if (argc != 6) {
        fprintf(stderr, "usage: xdrag WINDOW_ID START_X START_Y END_X END_Y\n");
        return 2;
    }

    Window window = None;
    int startX = 0;
    int startY = 0;
    int endX = 0;
    int endY = 0;
    if (!parseWindow(argv[1], &window) || !parseCoordinate(argv[2], &startX) ||
        !parseCoordinate(argv[3], &startY) || !parseCoordinate(argv[4], &endX) ||
        !parseCoordinate(argv[5], &endY)) {
        fprintf(stderr, "xdrag: invalid window ID or coordinate\n");
        return 2;
    }

    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "xdrag: could not open the X11 display\n");
        return 1;
    }

    const Window root = DefaultRootWindow(display);
    Window child = None;
    int rootX = 0;
    int rootY = 0;
    if (!XTranslateCoordinates(display, window, root, 0, 0, &rootX, &rootY, &child)) {
        fprintf(stderr, "xdrag: could not resolve window 0x%lx\n", window);
        XCloseDisplay(display);
        return 1;
    }

    if (!sendButton(display, window, root, rootX, rootY, startX, startY, ButtonPress)) {
        fprintf(stderr, "xdrag: the target rejected the button press\n");
        XCloseDisplay(display);
        return 1;
    }

    const struct timespec delay = {.tv_sec = 0, .tv_nsec = 15L * 1000L * 1000L};
    for (int step = 1; step <= 20; ++step) {
        const int x = startX + (endX - startX) * step / 20;
        const int y = startY + (endY - startY) * step / 20;
        if (!sendMotion(display, window, root, rootX, rootY, x, y)) {
            fprintf(stderr, "xdrag: the target rejected pointer motion\n");
            XCloseDisplay(display);
            return 1;
        }
        XFlush(display);
        nanosleep(&delay, NULL);
    }

    if (!sendButton(display, window, root, rootX, rootY, endX, endY, ButtonRelease)) {
        fprintf(stderr, "xdrag: the target rejected the button release\n");
        XCloseDisplay(display);
        return 1;
    }

    XFlush(display);
    XCloseDisplay(display);
    return 0;
}
