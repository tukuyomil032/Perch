# NookSurface (vendored)

Copied from [OpenNook](https://github.com/athledev-labs/opennook) **0.4.0**,
`Sources/NookSurface/`. MIT, no external dependencies.

## Why this is vendored instead of a SwiftPM dependency

The synthetic notch width — the box drawn on Macs with no physical notch — is a
private constant (`arbitraryWidth = 300`) with no public seam. It cannot be reached
through `screenProvider`, `configureWindow`, or `NookStyle`. Perch draws the notch
layout on every Mac, so a 300pt shape sitting next to a real 185–208pt notch is a
visible defect rather than a tuning preference.

Swapping NookSurface underneath an upstream `NookKit` is also not possible: NookKit
constructs the concrete `Nook<AnyView, AnyView, AnyView>` directly and keeps
`NookSurfaceDriving` internal. Since Perch writes its own chrome anyway (NookKit's
top bar is internal and structurally fixed), taking only NookSurface is the smaller
commitment.

## Rules for this directory

- **Keep files byte-identical to upstream unless there is a reason not to.**
  `swift-format` is excluded here in both `lefthook.yml` and the CI lint job so that
  `diff -rq` against an upstream checkout stays meaningful.
- Every intentional change carries a `// Modified for Perch:` comment at the point of
  change, plus a summary in the file header.
- The `/ThirdPartyLicenses/...` and `/LICENSE-MIT-NOOKSURFACE` paths in the SPDX
  headers refer to the **upstream** repository layout. In Perch, both notices live in
  `THIRD_PARTY_NOTICES.md` at the repository root. The header lines are left untouched
  so the files stay comparable to upstream.

## Current modifications

| File | Change |
|---|---|
| `Internal/NSScreen+Extensions.swift` | `notchFrameWithMenubarAsBackup` takes a `syntheticWidth` parameter instead of hardcoding 300pt |
| `Nook.swift` | Adds `syntheticNotchWidth` (default 195); publishes `notchSize` / `menubarHeight`; gates hover-driven expand/compact on `.expandsOnHover` |
| `NookHoverBehavior.swift` | Adds `.expandsOnHover`, included in `.all` so upstream defaults behave the same |
| `NookStyle.swift` | Adds `compactTopCornerRadius`/`compactBottomCornerRadius` (default 6/14, matching the previous hardcoded values) so a host can tune the compact pill's roundedness |
| `Internal/NookView.swift` | `compactCornerRadii` reads the two new `NookStyle` properties instead of a hardcoded `(6, 14)` |

## Verifying against upstream

```bash
git clone --depth 1 --branch v0.4.0 https://github.com/athledev-labs/opennook /tmp/opennook
diff -rq /tmp/opennook/Sources/NookSurface perch/Vendor/NookSurface
```

Only the five files above should differ (plus this README).
