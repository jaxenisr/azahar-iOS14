#!/usr/bin/env python3
"""Draw the 1024 px app icon as a PNG, with no third-party modules.

The icon is a dark tile carrying the two screens of the hardware: the lit upper
screen, the dimmer lower one and the hinge between them. Keeping the generator in
the repository instead of the binary keeps the tree text-only and lets the icon be
reproduced exactly on any machine with python3.
"""

import struct
import sys
import zlib

SIZE = 1024
BACKGROUND = (14, 17, 22)
UPPER = (236, 240, 247)
LOWER = (150, 160, 176)
HINGE = (70, 78, 92)

MARGIN = 164
SCREEN_H = 307
GAP = 77
RADIUS = 40
TOP = 194


def inside_rounded(x, y, left, top, right, bottom, radius):
    if not (left <= x < right and top <= y < bottom):
        return False
    if left + radius <= x < right - radius or top + radius <= y < bottom - radius:
        return True
    cx = min(max(x, left + radius), right - 1 - radius)
    cy = min(max(y, top + radius), bottom - 1 - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def render():
    left, right = MARGIN, SIZE - MARGIN
    width = right - left
    # Rows are counted from the top of the image: the lit screen sits above the
    # dim one, the way the hardware opens.
    upper_top = TOP
    upper_bottom = upper_top + SCREEN_H
    lower_top = upper_bottom + GAP
    lower_bottom = lower_top + SCREEN_H
    hinge_top = upper_bottom + (GAP - 16) // 2
    hinge_bottom = hinge_top + 16
    hinge_left = (SIZE - width) // 2 + 60
    hinge_right = SIZE - hinge_left

    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            if inside_rounded(x, y, left, upper_top, right, upper_bottom, RADIUS):
                colour = UPPER
            elif inside_rounded(x, y, left, lower_top, right, lower_bottom, RADIUS):
                colour = LOWER
            elif hinge_left <= x < hinge_right and hinge_top <= y < hinge_bottom:
                colour = HINGE
            else:
                colour = BACKGROUND
            row.extend(colour)
        rows.append(bytes(row))
    return b"".join(rows)


def chunk(kind, payload):
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path, raw):
    stride = SIZE * 3
    # Filter type 0 (none) in front of every scanline.
    filtered = b"".join(b"\x00" + raw[i:i + stride] for i in range(0, len(raw), stride))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(filtered, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png"
    write_png(path, render())
    print("wrote {}".format(path))


if __name__ == "__main__":
    main()
