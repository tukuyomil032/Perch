#!/usr/bin/env python3
"""
update-appcast.py — Insert a new release entry into appcast.xml.

Dependencies: stdlib only (xml.etree.ElementTree, email.utils)
              No pip/uv required.

Usage:
    python3 scripts/update-appcast.py <version> <build> <dmg_url> <dmg_size> [channel]

Arguments:
    version   Marketing version string (e.g. 0.3.1)
    build     Build number from version.env (e.g. 2)
    dmg_url   GitHub Releases direct download URL of the DMG
    dmg_size  File size in bytes (from stat -f%z)
    channel   Optional: "beta" for pre-release channel (omit for stable)

Note on edSignature:
    Set to PLACEHOLDER_PHASE6 until EdDSA keys are generated in Phase 6.
    After Phase 6: generate keys with `generate_keys`, sign each DMG with
    `sign_update`, and replace PLACEHOLDER_PHASE6 in each entry.
"""

import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
APPCAST_PATH = "appcast.xml"


def s(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def main() -> None:
    if len(sys.argv) < 5:
        print(f"Usage: {sys.argv[0]} <version> <build> <dmg_url> <dmg_size> [channel]",
              file=sys.stderr)
        sys.exit(1)

    version  = sys.argv[1]
    build    = sys.argv[2]
    dmg_url  = sys.argv[3]
    dmg_size = sys.argv[4]
    channel  = sys.argv[5] if len(sys.argv) > 5 else ""
    pub_date = format_datetime(datetime.now(tz=timezone.utc))

    ET.register_namespace("sparkle", SPARKLE_NS)

    tree = ET.parse(APPCAST_PATH)
    root = tree.getroot()
    ch = root.find("channel")
    if ch is None:
        print("Error: <channel> not found in appcast.xml", file=sys.stderr)
        sys.exit(1)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = version
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, s("version")).text = build
    ET.SubElement(item, s("shortVersionString")).text = version
    ET.SubElement(item, s("minimumSystemVersion")).text = "14.0"
    if channel:
        ET.SubElement(item, s("channel")).text = channel

    enc = ET.SubElement(item, "enclosure")
    enc.set("url", dmg_url)
    enc.set("length", dmg_size)
    enc.set("type", "application/x-apple-diskimage")
    enc.set(s("edSignature"), "PLACEHOLDER_PHASE6")

    existing = ch.findall("item")
    if existing:
        ch.insert(list(ch).index(existing[0]), item)
    else:
        ch.append(item)

    ET.indent(tree, space="    ")
    tree.write(APPCAST_PATH, encoding="unicode", xml_declaration=True)
    print(f"Updated {APPCAST_PATH}: inserted entry for v{version} (build {build})")


if __name__ == "__main__":
    main()
