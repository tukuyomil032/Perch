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

### Manual beta release

For `workflow_dispatch`, select `beta` and enter the complete **Beta display
version** separately, such as `0.3.2-beta.1`. The workflow uses that exact
display version for the tag, release, DMG, and appcast's
`sparkle:shortVersionString`; it passes only the numeric base version (`0.3.2`)
to Xcode as `MARKETING_VERSION`. `BETA_BUILD_NUMBER` remains a positive integer
and is passed unchanged as `CURRENT_PROJECT_VERSION` / `sparkle:version`.

## Sparkle appcast signing

Stable and beta releases must have the GitHub Actions `SPARKLE_PRIVATE_KEY`
secret. The workflow writes it only to a `mktemp` file under `RUNNER_TEMP`,
restricts that file to mode `0600`, signs the DMG with
`sign_update --ed-key-file`, then removes the file with an exit trap. It never
prints the key or its value. Preview releases neither read this secret nor
change the shared appcast.

The generated item includes the resulting `sparkle:edSignature`, uses
`sparkle:minimumSystemVersion` `15.0`, and is inserted before existing items;
the workflow obtains the current `appcast.xml` from `main` and commits the
updated feed directly to `main` through the GitHub Contents API.

The generated public key is configured in `perch/Resources/Info.plist` as
`SUPublicEDKey`; the feed URL is `SUFeedURL`. The private key belongs only in
the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.

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
UV_CACHE_DIR=.uv-cache uv run pytest scripts/test_resolve_release.py scripts/test_update_appcast.py
bash -n scripts/build-dmg.sh
```
