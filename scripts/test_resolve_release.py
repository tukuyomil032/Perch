"""Tests for scripts/resolve-release.py, focused on the preview channel."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

_MODULE_PATH = Path(__file__).parent / "resolve-release.py"
_SPEC = importlib.util.spec_from_file_location("resolve_release", _MODULE_PATH)
resolve_release = importlib.util.module_from_spec(_SPEC)
sys.modules["resolve_release"] = resolve_release
_SPEC.loader.exec_module(resolve_release)


def test_infer_channel_accepts_preview_for_workflow_dispatch():
    channel = resolve_release.infer_channel("workflow_dispatch", {}, {}, "preview")
    assert channel == "preview"


def test_infer_channel_still_accepts_stable_and_beta():
    assert resolve_release.infer_channel("workflow_dispatch", {}, {}, "stable") == "stable"
    assert resolve_release.infer_channel("workflow_dispatch", {}, {}, "beta") == "beta"


def test_infer_channel_rejects_unknown_channel():
    with pytest.raises(resolve_release.ReleaseError):
        resolve_release.infer_channel("workflow_dispatch", {}, {}, "nightly")


def test_resolve_preview_metadata_builds_expected_version_and_tag():
    outputs = resolve_release.resolve_preview_metadata("0.4.0", "feature-foo", "5")

    assert outputs["channel"] == "preview"
    assert outputs["version"] == "0.4.0-preview.feature-foo.5"
    assert outputs["tag"] == "v0.4.0-preview.feature-foo.5"
    assert outputs["base_version"] == "0.4.0"
    assert outputs["build_number"] == "5"
    assert outputs["is_beta"] == "true"
    assert outputs["skip"] == "false"


def test_resolve_preview_metadata_rejects_non_semver_base_version():
    with pytest.raises(resolve_release.ReleaseError):
        resolve_release.resolve_preview_metadata("not-a-version", "feature-foo", "5")


def test_resolve_preview_metadata_rejects_non_positive_run_number():
    with pytest.raises(resolve_release.ReleaseError):
        resolve_release.resolve_preview_metadata("0.4.0", "feature-foo", "0")


def test_resolve_manual_beta_display_version_keeps_numeric_base_version_and_build():
    outputs = resolve_release.resolve_metadata(
        "beta",
        {"BETA_BUILD_NUMBER": "12"},
        "0.4.0-beta.2",
    )

    assert outputs["version"] == "0.4.0-beta.2"
    assert outputs["base_version"] == "0.4.0"
    assert outputs["build_number"] == "12"


def test_resolve_manual_beta_display_version_rejects_non_beta_semver():
    with pytest.raises(resolve_release.ReleaseError, match="beta display version"):
        resolve_release.resolve_metadata(
            "beta",
            {"BETA_BUILD_NUMBER": "12"},
            "0.4.0",
        )


def test_main_manual_beta_requires_display_version(tmp_path, monkeypatch, capsys):
    version_env = tmp_path / "version.env"
    version_env.write_text("BETA_MARKETING_VERSION=0.4.0\nBETA_PRERELEASE_NUMBER=2\nBETA_BUILD_NUMBER=12\n")
    appcast = tmp_path / "appcast.xml"
    appcast.write_text("<xml></xml>")

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "resolve-release.py",
            "--current",
            str(version_env),
            "--event-name",
            "workflow_dispatch",
            "--channel",
            "beta",
            "--appcast",
            str(appcast),
            "--github-output",
            "",
        ],
    )

    exit_code = resolve_release.main()
    captured = capsys.readouterr()

    assert exit_code == 1
    assert "beta display version is required" in captured.err


def test_main_preview_falls_back_to_stable_marketing_version(tmp_path, monkeypatch, capsys):
    version_env = tmp_path / "version.env"
    version_env.write_text(
        "STABLE_MARKETING_VERSION=0.3.0\n"
        "STABLE_BUILD_NUMBER=1\n"
        "BETA_MARKETING_VERSION=0.3.1\n"
        "BETA_PRERELEASE_NUMBER=6\n"
        "BETA_BUILD_NUMBER=3\n"
    )
    appcast = tmp_path / "appcast.xml"
    appcast.write_text("<xml></xml>")

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "resolve-release.py",
            "--current",
            str(version_env),
            "--event-name",
            "workflow_dispatch",
            "--channel",
            "preview",
            "--preview-branch",
            "feature-foo",
            "--preview-run",
            "5",
            "--preview-base-version",
            "",
            "--appcast",
            str(appcast),
            "--github-output",
            "",
        ],
    )

    exit_code = resolve_release.main()
    captured = capsys.readouterr()

    assert exit_code == 0
    assert "tag=v0.3.0-preview.feature-foo.5" in captured.out


def test_main_preview_ignores_appcast_max_build(tmp_path, monkeypatch, capsys):
    version_env = tmp_path / "version.env"
    version_env.write_text("STABLE_MARKETING_VERSION=0.3.0\nSTABLE_BUILD_NUMBER=1\n")
    appcast = tmp_path / "appcast.xml"
    appcast.write_text("<sparkle:version>999999</sparkle:version>")

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "resolve-release.py",
            "--current",
            str(version_env),
            "--event-name",
            "workflow_dispatch",
            "--channel",
            "preview",
            "--preview-branch",
            "feature-foo",
            "--preview-run",
            "1",
            "--preview-base-version",
            "0.4.0",
            "--appcast",
            str(appcast),
            "--github-output",
            "",
        ],
    )

    exit_code = resolve_release.main()
    captured = capsys.readouterr()

    assert exit_code == 0
    assert "tag=v0.4.0-preview.feature-foo.1" in captured.out


def test_main_stable_channel_still_enforces_appcast_max_build(tmp_path, monkeypatch, capsys):
    version_env = tmp_path / "version.env"
    version_env.write_text("STABLE_MARKETING_VERSION=0.3.0\nSTABLE_BUILD_NUMBER=1\n")
    appcast = tmp_path / "appcast.xml"
    appcast.write_text("<sparkle:version>5</sparkle:version>")

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "resolve-release.py",
            "--current",
            str(version_env),
            "--event-name",
            "workflow_dispatch",
            "--channel",
            "stable",
            "--appcast",
            str(appcast),
            "--github-output",
            "",
        ],
    )

    exit_code = resolve_release.main()
    captured = capsys.readouterr()

    assert exit_code == 1
    assert "must be greater than appcast max" in captured.err
