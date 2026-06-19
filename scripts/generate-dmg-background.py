#!/usr/bin/env python3
"""
generate-dmg-background.py
Generates assets/dmg/background.png for the Perch DMG installer.

Output: 1320x800 px (2x retina for a 660x400 pt window)
Style: Solid #f5f5f5 — light neutral (matches Claude.app installer style)
Dependencies: stdlib only (no pip/uv required)

Run:
    python3 scripts/generate-dmg-background.py
"""

import os
import struct
import zlib

OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "..", "assets", "dmg", "background.png")
WIDTH = 1320
HEIGHT = 800
R, G, B = 0xF5, 0xF5, 0xF5


def write_png_solid(path: str, width: int, height: int, r: int, g: int, b: int) -> None:
    def chunk(name: bytes, data: bytes) -> bytes:
        c = name + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    # Filter byte 0 (None) + RGB pixels for one row, repeated height times
    row = bytes([0]) + bytes([r, g, b] * width)
    idat = zlib.compress(row * height, level=6)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def main() -> None:
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    write_png_solid(OUTPUT_PATH, WIDTH, HEIGHT, R, G, B)
    print(f"Written: {OUTPUT_PATH} ({WIDTH}x{HEIGHT}, #{R:02X}{G:02X}{B:02X})")


if __name__ == "__main__":
    main()
