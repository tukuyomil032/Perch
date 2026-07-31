#!/usr/bin/env python3
"""
resolve-release.py - Resolve Perch release metadata from version.env.

The script is intentionally strict: release workflows should fail when the
release intent is ambiguous instead of publishing the wrong channel.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


STABLE_KEYS = ("STABLE_MARKETING_VERSION", "STABLE_BUILD_NUMBER")
BETA_KEYS = ("BETA_MARKETING_VERSION", "BETA_PRERELEASE_NUMBER", "BETA_BUILD_NUMBER")
LEGACY_KEYS = ("MARKETING_VERSION", "BUILD_NUMBER")
SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
BETA_DISPLAY_VERSION_RE = re.compile(
    r"^((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))-beta\.([1-9]\d*)$"
)


class ReleaseError(Exception):
    """Raised when release metadata cannot be resolved safely."""

    pass


def parse_env(path: Path) -> dict[str, str]:
    """Parse a KEY=VALUE env file.

    Args:
        path: Path to the env file. Missing files return an empty mapping.

    Returns:
        A dictionary of parsed key/value pairs.

    Raises:
        ReleaseError: If a non-comment line is malformed, a key is empty, a key
            appears more than once, or the file cannot be read.
    """
    values: dict[str, str] = {}
    if not path.exists():
        return values

    try:
        content = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ReleaseError(f"failed to read {path}: {error}") from error

    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ReleaseError(f"{path}:{line_number}: expected KEY=VALUE")

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if not key:
            raise ReleaseError(f"{path}:{line_number}: key is empty")
        if key in values:
            raise ReleaseError(f"{path}:{line_number}: duplicate key {key}")
        values[key] = value

    return values


def require(values: dict[str, str], key: str) -> str:
    """Return a required release field.

    Args:
        values: Parsed version.env values.
        key: Name of the required key.

    Returns:
        The non-empty value for key.

    Raises:
        ReleaseError: If the key is missing or empty.
    """
    value = values.get(key, "")
    if not value:
        raise ReleaseError(f"version.env is missing {key}")
    return value


def parse_positive_int(value: str, key: str) -> int:
    """Parse a positive integer release field.

    Args:
        value: Raw field value.
        key: Field name used in error messages.

    Returns:
        The parsed positive integer.

    Raises:
        ReleaseError: If value is not a positive integer.
    """
    if not re.fullmatch(r"[1-9]\d*", value):
        raise ReleaseError(f"{key} must be a positive integer")
    return int(value)


def parse_semver(value: str, key: str) -> str:
    """Validate a plain semantic version.

    Args:
        value: Raw field value.
        key: Field name used in error messages.

    Returns:
        The validated semver string.

    Raises:
        ReleaseError: If value is not MAJOR.MINOR.PATCH semver.
    """
    if not SEMVER_RE.fullmatch(value):
        raise ReleaseError(f"{key} must be plain semver like 0.3.1")
    return value


def changed(keys: tuple[str, ...], current: dict[str, str], previous: dict[str, str]) -> bool:
    """Check whether any release key changed between env snapshots.

    Args:
        keys: Keys to compare.
        current: Current version.env values.
        previous: Previous version.env values.

    Returns:
        True when at least one key has a different value.
    """
    return any(current.get(key) != previous.get(key) for key in keys)


def infer_channel(event_name: str, current: dict[str, str], previous: dict[str, str], requested: str) -> str | None:
    """Infer the release channel for the current workflow event.

    Args:
        event_name: GitHub event name, such as push or workflow_dispatch.
        current: Current version.env values.
        previous: Previous version.env values for push events.
        requested: Channel passed for workflow_dispatch.

    Returns:
        stable, beta, preview, or None when the workflow should skip publishing.

    Raises:
        ReleaseError: If the requested channel is invalid or the changed release
            block is ambiguous.
    """
    if event_name == "workflow_dispatch":
        if requested not in {"stable", "beta", "preview"}:
            raise ReleaseError("workflow_dispatch requires --channel stable, --channel beta, or --channel preview")
        return requested

    stable_changed = changed(STABLE_KEYS, current, previous)
    beta_changed = changed(BETA_KEYS, current, previous)

    if stable_changed and beta_changed:
        previous_has_current_keys = any(key in previous for key in STABLE_KEYS + BETA_KEYS)
        previous_has_legacy_keys = any(key in previous for key in LEGACY_KEYS)
        if previous_has_legacy_keys and not previous_has_current_keys:
            return None
        raise ReleaseError("Change either STABLE_* or BETA_* in one release commit, not both")
    if stable_changed:
        return "stable"
    if beta_changed:
        return "beta"
    return None


def appcast_max_build(path: Path) -> int:
    """Read the largest Sparkle build number from appcast.xml.

    Args:
        path: Path to the appcast XML file. Missing files return 0.

    Returns:
        The largest sparkle:version value found, or 0.

    Raises:
        ReleaseError: If the file cannot be read.
    """
    if not path.exists():
        return 0

    max_build = 0
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ReleaseError(f"failed to read {path}: {error}") from error

    for match in re.finditer(r"<sparkle:version>\s*([0-9]+)\s*</sparkle:version>", content):
        max_build = max(max_build, int(match.group(1)))
    return max_build


def resolve_metadata(
    channel: str,
    values: dict[str, str],
    beta_display_version: str = "",
) -> dict[str, str]:
    """Build GitHub Actions outputs for a release channel.

    Args:
        channel: Release channel, stable or beta.
        values: Parsed version.env values.

    Returns:
        Output values for downstream workflow steps.

    Raises:
        ReleaseError: If required values are missing, invalid, or the channel is
            unsupported.
    """
    if channel == "stable":
        base_version = parse_semver(require(values, "STABLE_MARKETING_VERSION"), "STABLE_MARKETING_VERSION")
        build_number = parse_positive_int(require(values, "STABLE_BUILD_NUMBER"), "STABLE_BUILD_NUMBER")
        version = base_version
        is_beta = "false"
    elif channel == "beta":
        if beta_display_version:
            match = BETA_DISPLAY_VERSION_RE.fullmatch(beta_display_version)
            if match is None:
                raise ReleaseError(
                    "beta display version must be MAJOR.MINOR.PATCH-beta.N like 0.3.1-beta.1"
                )
            base_version, prerelease_number = match.groups()
        else:
            base_version = parse_semver(require(values, "BETA_MARKETING_VERSION"), "BETA_MARKETING_VERSION")
            prerelease_number = str(
                parse_positive_int(
                    require(values, "BETA_PRERELEASE_NUMBER"),
                    "BETA_PRERELEASE_NUMBER",
                )
            )
        build_number = parse_positive_int(require(values, "BETA_BUILD_NUMBER"), "BETA_BUILD_NUMBER")
        version = f"{base_version}-beta.{prerelease_number}"
        is_beta = "true"
    else:
        raise ReleaseError(f"unsupported release channel: {channel}")

    return {
        "skip": "false",
        "channel": channel,
        "version": version,
        "base_version": base_version,
        "build_number": str(build_number),
        "tag": f"v{version}",
        "is_beta": is_beta,
    }


def resolve_preview_metadata(base_version: str, branch_slug: str, run_number: str) -> dict[str, str]:
    """Build GitHub Actions outputs for a preview build off a non-main branch.

    Preview builds never touch version.env's STABLE_*/BETA_* fields - the
    version string is derived from the branch and run number instead, so
    branch experiments can never collide with the real stable/beta channels.

    Args:
        base_version: Marketing version to prefix the preview suffix with.
        branch_slug: Source branch name with slashes replaced by dashes.
        run_number: GitHub Actions run number, used as the build number.

    Returns:
        Output values for downstream workflow steps.

    Raises:
        ReleaseError: If base_version is not plain semver or run_number is not
            a positive integer.
    """
    base_version = parse_semver(base_version, "preview base version")
    build_number = parse_positive_int(run_number, "preview run number")
    version = f"{base_version}-preview.{branch_slug}.{build_number}"

    return {
        "skip": "false",
        "channel": "preview",
        "version": version,
        "base_version": base_version,
        "build_number": str(build_number),
        "tag": f"v{version}",
        "is_beta": "true",
    }


def write_outputs(outputs: dict[str, str], github_output: str) -> None:
    """Write release metadata to GitHub Actions and stdout.

    Args:
        outputs: Key/value pairs to emit.
        github_output: Path from GITHUB_OUTPUT. Empty string disables file output.

    Raises:
        ReleaseError: If GITHUB_OUTPUT cannot be opened or written.
    """
    if github_output:
        try:
            with open(github_output, "a", encoding="utf-8") as output_file:
                for key, value in outputs.items():
                    output_file.write(f"{key}={value}\n")
        except OSError as error:
            raise ReleaseError(f"failed to write {github_output}: {error}") from error

    for key, value in outputs.items():
        print(f"{key}={value}")


def main() -> int:
    """Run the release metadata resolver CLI.

    Returns:
        Process exit code, where 0 means success and 1 means ReleaseError.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--channel", default="")
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--preview-branch", default="")
    parser.add_argument("--preview-run", default="")
    parser.add_argument("--preview-base-version", default="")
    parser.add_argument("--beta-display-version", default="")
    parser.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT", ""))
    args = parser.parse_args()

    try:
        current = parse_env(args.current)
        previous = parse_env(args.previous) if args.previous else {}
        channel = infer_channel(args.event_name, current, previous, args.channel)

        if channel is None:
            write_outputs({"skip": "true"}, args.github_output)
            return 0

        if channel == "preview":
            base_version = args.preview_base_version or require(current, "STABLE_MARKETING_VERSION")
            outputs = resolve_preview_metadata(base_version, args.preview_branch, args.preview_run)
            write_outputs(outputs, args.github_output)
            return 0

        if args.event_name == "workflow_dispatch" and channel == "beta" and not args.beta_display_version:
            raise ReleaseError("beta display version is required for a manual beta release")

        outputs = resolve_metadata(channel, current, args.beta_display_version)
        max_build = appcast_max_build(args.appcast)
        build_number = int(outputs["build_number"])
        if build_number <= max_build:
            raise ReleaseError(
                f"{outputs['channel']} build number {build_number} must be greater than appcast max {max_build}"
            )

        write_outputs(outputs, args.github_output)
        return 0
    except ReleaseError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
