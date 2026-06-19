# Release Flow

Perch releases are driven by `version.env` on the `main` branch. Do not create
or push release tags manually for the normal flow.

## Stable Release

Update only the stable fields:

```env
STABLE_MARKETING_VERSION=0.3.1
STABLE_BUILD_NUMBER=3

BETA_MARKETING_VERSION=0.3.1
BETA_PRERELEASE_NUMBER=1
BETA_BUILD_NUMBER=2
```

Commit and push to `main`. The Release workflow creates:

- tag: `v0.3.1`
- GitHub Release: `Perch 0.3.1`
- DMG: `perch-0.3.1.dmg`
- appcast entry without a beta channel

## Beta Release

Update only the beta fields:

```env
STABLE_MARKETING_VERSION=0.3.1
STABLE_BUILD_NUMBER=3

BETA_MARKETING_VERSION=0.3.2
BETA_PRERELEASE_NUMBER=1
BETA_BUILD_NUMBER=4
```

Commit and push to `main`. The Release workflow creates:

- tag: `v0.3.2-beta.1`
- GitHub pre-release: `Perch 0.3.2-beta.1`
- DMG: `perch-0.3.2-beta.1.dmg`
- appcast entry with `sparkle:channel` set to `beta`

## Rules

- Change either `STABLE_*` or `BETA_*` in one release commit, not both.
- `STABLE_BUILD_NUMBER` and `BETA_BUILD_NUMBER` are separate fields, but the
  selected build number must be greater than the largest build already in
  `appcast.xml`.
- If the target tag or GitHub Release already exists, the workflow fails.
- `workflow_dispatch` remains available for manual stable or beta publishing
  from the current `version.env` values, but it must be run from `main`.
- The one-time migration from the legacy `MARKETING_VERSION` / `BUILD_NUMBER`
  format to the split stable/beta fields is treated as a schema update and does
  not publish a release by itself.

## Local Checks

Python release tooling is managed with `uv` and pinned to Python 3.12.

```bash
UV_CACHE_DIR=.uv-cache uv run python -m py_compile scripts/resolve-release.py scripts/update-appcast.py
bash -n scripts/build-dmg.sh
```
