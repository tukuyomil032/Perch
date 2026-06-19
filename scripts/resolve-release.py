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
SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


class ReleaseError(Exception):
    pass


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
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
        values[key] = value

    return values


def require(values: dict[str, str], key: str) -> str:
    value = values.get(key, "")
    if not value:
        raise ReleaseError(f"version.env is missing {key}")
    return value


def parse_positive_int(value: str, key: str) -> int:
    if not re.fullmatch(r"[1-9]\d*", value):
        raise ReleaseError(f"{key} must be a positive integer")
    return int(value)


def parse_semver(value: str, key: str) -> str:
    if not SEMVER_RE.fullmatch(value):
        raise ReleaseError(f"{key} must be plain semver like 0.3.1")
    return value


def changed(keys: tuple[str, ...], current: dict[str, str], previous: dict[str, str]) -> bool:
    return any(current.get(key) != previous.get(key) for key in keys)


def infer_channel(event_name: str, current: dict[str, str], previous: dict[str, str], requested: str) -> str | None:
    if event_name == "workflow_dispatch":
        if requested not in {"stable", "beta"}:
            raise ReleaseError("workflow_dispatch requires --channel stable or --channel beta")
        return requested

    stable_changed = changed(STABLE_KEYS, current, previous)
    beta_changed = changed(BETA_KEYS, current, previous)

    if stable_changed and beta_changed:
        raise ReleaseError("Change either STABLE_* or BETA_* in one release commit, not both")
    if stable_changed:
        return "stable"
    if beta_changed:
        return "beta"
    return None


def appcast_max_build(path: Path) -> int:
    if not path.exists():
        return 0

    max_build = 0
    content = path.read_text(encoding="utf-8")
    for match in re.finditer(r"<sparkle:version>\s*([0-9]+)\s*</sparkle:version>", content):
        max_build = max(max_build, int(match.group(1)))
    return max_build


def resolve_metadata(channel: str, values: dict[str, str]) -> dict[str, str]:
    if channel == "stable":
        base_version = parse_semver(require(values, "STABLE_MARKETING_VERSION"), "STABLE_MARKETING_VERSION")
        build_number = parse_positive_int(require(values, "STABLE_BUILD_NUMBER"), "STABLE_BUILD_NUMBER")
        version = base_version
        is_beta = "false"
    elif channel == "beta":
        base_version = parse_semver(require(values, "BETA_MARKETING_VERSION"), "BETA_MARKETING_VERSION")
        prerelease_number = parse_positive_int(
            require(values, "BETA_PRERELEASE_NUMBER"),
            "BETA_PRERELEASE_NUMBER",
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


def write_outputs(outputs: dict[str, str], github_output: str) -> None:
    if github_output:
        with open(github_output, "a", encoding="utf-8") as output_file:
            for key, value in outputs.items():
                output_file.write(f"{key}={value}\n")

    for key, value in outputs.items():
        print(f"{key}={value}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--channel", default="")
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT", ""))
    args = parser.parse_args()

    try:
        current = parse_env(args.current)
        previous = parse_env(args.previous) if args.previous else {}
        channel = infer_channel(args.event_name, current, previous, args.channel)

        if channel is None:
            write_outputs({"skip": "true"}, args.github_output)
            return 0

        outputs = resolve_metadata(channel, current)
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
