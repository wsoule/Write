#!/usr/bin/env python3
"""Draws Write's app icon and packs it into Resources/AppIcon.icns.

No image libraries: the shapes are signed-distance fields sampled once per
pixel, which is enough for the rounded rectangles this icon is made of, and
the PNG/ICNS containers are written by hand.
"""

import os
import struct
import zlib

BODY_RATIO = 0.824          # icon body inside its canvas, per Apple's grid
CORNER_RATIO = 0.2237       # Big Sur squircle corner radius
PAGE = (0x10, 0x10, 0x10)
LINE = (0xEE, 0xEE, 0xEE)
ACCENT = (0x55, 0x84, 0xAA)
MUTED = (0x4F, 0x52, 0x5A)

# Lines of "writing": (x0, y0, x1, y1, colour) in unit body coordinates.
LINES = [
    (0.16, 0.20, 0.62, 0.26, LINE),
    (0.16, 0.36, 0.84, 0.42, MUTED),
    (0.16, 0.50, 0.78, 0.56, MUTED),
    (0.16, 0.64, 0.84, 0.70, MUTED),
    (0.16, 0.78, 0.46, 0.84, ACCENT),
]


def rounded_rect_distance(px, py, cx, cy, half_w, half_h, radius):
    """Signed distance to a rounded rectangle; negative inside."""
    radius = min(radius, half_w, half_h)
    dx = abs(px - cx) - (half_w - radius)
    dy = abs(py - cy) - (half_h - radius)
    outside_x = max(dx, 0.0)
    outside_y = max(dy, 0.0)
    outside = (outside_x * outside_x + outside_y * outside_y) ** 0.5
    return outside + min(max(dx, dy), 0.0) - radius


def coverage(distance):
    """Antialiased coverage from a distance in pixels."""
    return min(1.0, max(0.0, 0.5 - distance))


def render(size):
    body = size * BODY_RATIO
    margin = (size - body) / 2.0
    centre = size / 2.0
    corner = body * CORNER_RATIO
    half = body / 2.0

    shapes = []
    for x0, y0, x1, y1, colour in LINES:
        left = margin + x0 * body
        top = margin + y0 * body
        right = margin + x1 * body
        bottom = margin + y1 * body
        shapes.append((
            (left + right) / 2.0, (top + bottom) / 2.0,
            (right - left) / 2.0, (bottom - top) / 2.0,
            (bottom - top) / 2.0, colour,
        ))

    rows = []
    for y in range(size):
        py = y + 0.5
        row = bytearray()
        for x in range(size):
            px = x + 0.5
            alpha = coverage(rounded_rect_distance(px, py, centre, centre, half, half, corner))
            if alpha <= 0.0:
                row += b"\x00\x00\x00\x00"
                continue

            red, green, blue = PAGE
            for cx, cy, hw, hh, radius, colour in shapes:
                mark = coverage(rounded_rect_distance(px, py, cx, cy, hw, hh, radius))
                if mark > 0.0:
                    red = round(red + (colour[0] - red) * mark)
                    green = round(green + (colour[1] - green) * mark)
                    blue = round(blue + (colour[2] - blue) * mark)
            row += bytes((red, green, blue, round(alpha * 255)))
        rows.append(bytes(row))
    return rows


def png(size, rows):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


# ICNS slot -> pixel size. Retina slots repeat a size at a different key.
SLOTS = [
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
    (b"ic07", 128), (b"ic13", 256), (b"ic08", 256),
    (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024),
]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    destination = os.path.join(root, "Resources", "AppIcon.icns")

    images = {}
    for size in sorted({size for _, size in SLOTS}):
        print(f"rendering {size}x{size}")
        images[size] = png(size, render(size))

    entries = b""
    for slot, size in SLOTS:
        data = images[size]
        entries += slot + struct.pack(">I", len(data) + 8) + data

    with open(destination, "wb") as icns:
        icns.write(b"icns" + struct.pack(">I", len(entries) + 8) + entries)
    print(f"wrote {destination} ({len(entries) + 8} bytes)")


if __name__ == "__main__":
    main()
