#!/usr/bin/env python3
"""
update-appcast.py — Insert a new release entry into appcast.xml.

Dependencies: stdlib only (xml.etree.ElementTree, email.utils)
              No pip/uv required.

Usage:
    python3 scripts/update-appcast.py <version> <build> <dmg_url> <dmg_size> <ed_signature> [channel]

Arguments:
    version   Marketing version string (e.g. 0.3.1)
    build     Build number from version.env (e.g. 2)
    dmg_url   GitHub Releases direct download URL of the DMG
    dmg_size  File size in bytes (from stat -f%z)
    ed_signature  EdDSA signature emitted by Sparkle's sign_update
    channel       Optional: "beta" for pre-release channel (omit for stable)
"""

import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
APPCAST_PATH = "appcast.xml"


def s(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def update_appcast(
    appcast_path: str,
    version: str,
    build: str,
    dmg_url: str,
    dmg_size: str,
    ed_signature: str,
    channel: str = "",
) -> None:
    """Insert a signed item while retaining every existing appcast item."""
    if not ed_signature:
        raise ValueError("ed_signature must not be empty")

    ET.register_namespace("sparkle", SPARKLE_NS)
    tree = ET.parse(appcast_path)
    root = tree.getroot()
    ch = root.find("channel")
    if ch is None:
        raise ValueError("<channel> not found in appcast.xml")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = version
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(tz=timezone.utc))
    ET.SubElement(item, s("minimumSystemVersion")).text = "15.0"
    if channel:
        ET.SubElement(item, s("channel")).text = channel

    enc = ET.SubElement(item, "enclosure")
    enc.set("url", dmg_url)
    enc.set("length", dmg_size)
    enc.set("type", "application/x-apple-diskimage")
    enc.set(s("version"), build)
    enc.set(s("shortVersionString"), version)
    enc.set(s("edSignature"), ed_signature)

    existing = ch.findall("item")
    if existing:
        ch.insert(list(ch).index(existing[0]), item)
    else:
        ch.append(item)

    ET.indent(tree, space="    ")
    tree.write(appcast_path, encoding="unicode", xml_declaration=True)


def main() -> None:
    if len(sys.argv) not in {6, 7}:
        print(f"Usage: {sys.argv[0]} <version> <build> <dmg_url> <dmg_size> <ed_signature> [channel]",
              file=sys.stderr)
        sys.exit(1)

    version  = sys.argv[1]
    build    = sys.argv[2]
    dmg_url  = sys.argv[3]
    dmg_size = sys.argv[4]
    ed_signature = sys.argv[5]
    channel = sys.argv[6] if len(sys.argv) > 6 else ""
    try:
        update_appcast(APPCAST_PATH, version, build, dmg_url, dmg_size, ed_signature, channel)
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"Updated {APPCAST_PATH}: inserted entry for v{version} (build {build})")


if __name__ == "__main__":
    main()
