"""Tests for the signed Sparkle appcast updater."""

from __future__ import annotations

import importlib.util
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
_MODULE_PATH = Path(__file__).parent / "update-appcast.py"
_SPEC = importlib.util.spec_from_file_location("update_appcast", _MODULE_PATH)
update_appcast = importlib.util.module_from_spec(_SPEC)
sys.modules["update_appcast"] = update_appcast
_SPEC.loader.exec_module(update_appcast)


def qname(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def write_appcast(path: Path) -> None:
    path.write_text(
        """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\" version=\"2.0\">
  <channel>
    <title>Perch</title>
    <item><title>0.3.0</title><description>Keep this item intact</description>
      <enclosure url=\"https://example.test/old.dmg\" length=\"7\"
        sparkle:version=\"1\" sparkle:edSignature=\"old-signature\" />
    </item>
  </channel>
</rss>
""",
        encoding="utf-8",
    )


def test_update_appcast_inserts_signed_stable_item_and_preserves_existing_item(tmp_path):
    appcast = tmp_path / "appcast.xml"
    write_appcast(appcast)

    update_appcast.update_appcast(
        str(appcast),
        "0.4.0",
        "8",
        "https://example.test/perch-0.4.0.dmg",
        "123456",
        "new-signature",
    )

    items = ET.parse(appcast).getroot().find("channel").findall("item")
    new_enclosure = items[0].find("enclosure")
    old_enclosure = items[1].find("enclosure")

    assert items[0].findtext("title") == "0.4.0"
    assert items[0].findtext(qname("minimumSystemVersion")) == "15.0"
    assert items[0].find(qname("channel")) is None
    assert new_enclosure.attrib[qname("version")] == "8"
    assert new_enclosure.attrib[qname("shortVersionString")] == "0.4.0"
    assert new_enclosure.attrib[qname("edSignature")] == "new-signature"
    assert items[1].findtext("description") == "Keep this item intact"
    assert old_enclosure.attrib[qname("edSignature")] == "old-signature"


def test_update_appcast_marks_beta_item_with_beta_channel(tmp_path):
    appcast = tmp_path / "appcast.xml"
    write_appcast(appcast)

    update_appcast.update_appcast(
        str(appcast),
        "0.4.0-beta.2",
        "9",
        "https://example.test/perch-0.4.0-beta.2.dmg",
        "234567",
        "beta-signature",
        "beta",
    )

    item = ET.parse(appcast).getroot().find("channel").find("item")
    enclosure = item.find("enclosure")

    assert item.findtext(qname("channel")) == "beta"
    assert enclosure.attrib[qname("shortVersionString")] == "0.4.0-beta.2"
    assert enclosure.attrib[qname("edSignature")] == "beta-signature"


def test_update_appcast_rejects_an_empty_signature(tmp_path):
    appcast = tmp_path / "appcast.xml"
    write_appcast(appcast)

    with pytest.raises(ValueError, match="ed_signature must not be empty"):
        update_appcast.update_appcast(
            str(appcast), "0.4.0", "8", "https://example.test/perch.dmg", "123", ""
        )


def test_main_rejects_extra_arguments(monkeypatch, capsys):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "update-appcast.py",
            "0.4.0",
            "8",
            "https://example.test/perch.dmg",
            "123",
            "signature",
            "beta",
            "unexpected",
        ],
    )

    with pytest.raises(SystemExit) as error:
        update_appcast.main()

    assert error.value.code == 1
    assert "Usage:" in capsys.readouterr().err
