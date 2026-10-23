// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

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

static unsigned char channelValue(unsigned long pixel, unsigned long mask)
{
    if (mask == 0)
        return 0;

    unsigned int shift = 0;
    while ((mask & 1UL) == 0) {
        mask >>= 1;
        ++shift;
    }
    const unsigned long maximum = mask;
    const unsigned long value = (pixel >> shift) & maximum;
    return (unsigned char)((value * UCHAR_MAX + maximum / 2) / maximum);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: xshot WINDOW_ID OUTPUT.ppm\n");
        return 2;
    }

    Window window = None;
    if (!parseWindow(argv[1], &window)) {
        fprintf(stderr, "xshot: invalid window ID: %s\n", argv[1]);
        return 2;
    }

    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "xshot: could not open the X11 display\n");
        return 1;
    }

    XWindowAttributes attributes;
    if (!XGetWindowAttributes(display, window, &attributes) || attributes.width <= 0 ||
        attributes.height <= 0) {
        fprintf(stderr, "xshot: could not inspect window 0x%lx\n", window);
        XCloseDisplay(display);
        return 1;
    }

    XImage *image = XGetImage(display, window, 0, 0, (unsigned int)attributes.width,
                              (unsigned int)attributes.height, AllPlanes, ZPixmap);
    if (image == NULL) {
        fprintf(stderr, "xshot: could not capture window 0x%lx\n", window);
        XCloseDisplay(display);
        return 1;
    }

    FILE *output = fopen(argv[2], "wb");
    if (output == NULL) {
        fprintf(stderr, "xshot: could not open %s for writing\n", argv[2]);
        XDestroyImage(image);
        XCloseDisplay(display);
        return 1;
    }

    int failed = fprintf(output, "P6\n%d %d\n255\n", attributes.width, attributes.height) < 0;
    for (int y = 0; y < attributes.height && !failed; ++y) {
        for (int x = 0; x < attributes.width; ++x) {
            const unsigned long pixel = XGetPixel(image, x, y);
            const unsigned char rgb[3] = {
                channelValue(pixel, image->red_mask),
                channelValue(pixel, image->green_mask),
                channelValue(pixel, image->blue_mask),
            };
            if (fwrite(rgb, sizeof(rgb), 1, output) != 1) {
                failed = 1;
                break;
            }
        }
    }
    if (fclose(output) != 0)
        failed = 1;

    XDestroyImage(image);
    XCloseDisplay(display);
    if (failed) {
        fprintf(stderr, "xshot: could not finish writing %s\n", argv[2]);
        return 1;
    }
    return 0;
}
