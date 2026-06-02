# Perch: macOS Dynamic Island-Style Live Hub

**Date**: 2026-06-02
**Status**: Approved
**Author**: tukuyomil032 + Claude

---

## Overview

Perch is a macOS menubar-level overlay app inspired by iOS Dynamic Island. It provides a compact pill UI anchored to the top-center of the screen (or aligned with the MacBook notch) that expands into rich information cards for music playback, AI usage tracking, file staging, and developer status monitoring.

### Design Philosophy

- **Native-first**: NSVisualEffectView ultraDark material, SF Pro/SF Mono typography, macOS HIG spacing
- **Anti-AI-Slop**: All UI must pass hallmark review. No generic gradients, no card-heavy dashboards, no LLM-generated aesthetic
- **Dynamic Island heritage**: Compact pill morphs into expanded cards via `matchedGeometryEffect` with Spring animations

### Tech Stack

- Swift 6, macOS 14+ (Sonoma), Xcode 16+
- SwiftUI + AppKit hybrid (NSWindow for window control, SwiftUI for content)
- `@Observable` + `@MainActor` (NOT ObservableObject/@Published)
- Xcode .xcodeproj base (NOT Swift Package Manager project)
- Bundle ID: `com.tukuyomi032.perch`

---

## Architecture

### Three-Layer Model

```
┌─────────────────────────────────────────┐
│  Island Layer (AppKit)                  │
│  NSWindow, NSPanel, mouse events        │
├─────────────────────────────────────────┤
│  UI Layer (SwiftUI)                     │
│  CompactPill, ExpandedCard, Settings    │
├─────────────────────────────────────────┤
│  Data Layer (Swift Concurrency)         │
│  Providers, Stores, Schedulers          │
└─────────────────────────────────────────┘
```

### Module Structure

```
perch/
  App/          — Entry point, AppDelegate, MenuBarController
  Core/         — AppState, IslandCard, EventBus, Preferences, RefreshScheduler, NotificationService
  Island/       — IslandWindow, IslandWindowController, NotchDetector, IslandMode, IslandGeometry, MouseEventMonitor
  UI/           — DesignSystem, RootIslandView, CompactPillView, ExpandedIslandView, IslandCardContainer, SettingsView, Cards/
  Features/     — NowPlaying/, FileShelf/, AIUsage/, DevStatus/, HUD/
  Providers/    — Claude/, Codex/, OpenAI/, GitHub/
  Resources/    — Assets.xcassets, Info.plist, Perch.entitlements
```

---

## Phase 1: Core Island UI (v0.1)

### IslandWindow

- `NSWindow` subclass, `styleMask: [.borderless, .fullSizeContentView]`
- `backgroundColor: .clear`, `isOpaque: false`
- `level: .statusBar + 1` (configurable)
- `collectionBehavior: [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`
- `hasShadow`: false in compact, subtle shadow in expanded
- `canBecomeKey: true`, `canBecomeMain: false`
- Mouse passthrough: hitTest returns nil outside pill region in compact mode

### NotchDetector

- `NSScreen` extension: `perchNotchSize` (CGSize), `isBuiltInDisplay` (Bool)
- Detection: `safeAreaInsets.top > 0` + `auxiliaryTopLeftArea/RightArea` for notch width
- Notch width > 0 → `.physicalNotch`, otherwise → `.floatingPill`
- Display selection: `isBuiltInDisplay` priority → `NSScreen.main` fallback

### IslandGeometry

| Mode | Compact Size | Expanded Size | Top Offset |
|------|-------------|---------------|------------|
| `.floatingPill` | 150×34 | 420×180 | 8pt |
| `.physicalNotch` | max(notchWidth, 150) × max(notchHeight, 32) | 460×190 | 0pt |

All sizes configurable in Settings.

### CompactPillView

- Background: NSVisualEffectView ultraDark material Capsule
- Left: 6pt status indicator circle
- Center: context-dependent label
- Height: 34pt, width: variable (min 150pt)
- Hover: scale 1.03 + subtle glow, 0.3s delay before expand trigger
- Click: immediate expand
- Animation: `.spring(response: 0.32, dampingFraction: 0.82)`

### ExpandedIslandView

- RoundedRectangle (cornerRadius: 28, .continuous)
- NSVisualEffectView ultraDark material background
- Header: left "Perch" + right card name
- Center: active card content
- Width: 420pt, height: variable by card content
- Card switching: swipe or page indicator
- Auto-collapse: 3s after mouse leaves, reset on interaction

### RootIslandView

- `matchedGeometryEffect` for compact→expanded continuous morphing
- Pill expands horizontally while growing downward (Dynamic Island style)
- `@Namespace private var animation`
- Spring: response 0.32, dampingFraction 0.82

### AppState

```swift
@MainActor @Observable
final class AppState {
    var isExpanded = false
    var activeCard: IslandCard = .idle
    var aiSnapshots: [AIUsageSnapshot] = []
    var nowPlaying: NowPlayingState?
    var shelfItems: [ShelfItem] = []
    var devStatuses: [DevStatus] = []
    var latestError: PerchError?
}
```

### Additional Phase 1 Components

- **MouseEventMonitor**: `NSEvent.addLocalMonitorForEvents` + `addGlobalMonitorForEvents` + `NSTrackingArea`
- **MenuBarController**: `NSStatusBar.system.statusItem`, NSMenu with Settings / Check for Updates / Quit
- **Settings**: SwiftUI Settings scene with General, Island, Display tabs. `Defaults` library for typed persistence
- **Login at launch**: `SMAppService.mainApp` (macOS 13+)

---

## Phase 2: Now Playing (v0.2)

### MRMediaRemote (Private Framework)

- Dynamic loading via `CFBundleCreate` → `"/System/Library/PrivateFrameworks/MediaRemote.framework"`
- Supported apps: **Spotify, YouTube Music, Apple Music**
- Functions: `MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteRegisterForNowPlayingNotifications`, `MRMediaRemoteSendCommand`
- Commands: `.play`, `.pause`, `.togglePlayPause`, `.nextTrack`, `.previousTrack`

### NowPlayingState

```swift
struct NowPlayingState: Equatable {
    var title: String
    var artist: String
    var album: String?
    var artwork: NSImage?
    var isPlaying: Bool
    var duration: TimeInterval?
    var elapsedTime: TimeInterval?
    var appBundleIdentifier: String?
}
```

### NowPlayingCard

- **Expanded**: album art (80×80, rounded) + title (bold) + artist + controls (prev/play-pause/next) + progress bar
- **Compact**: mini thumbnail (20×20, Capsule clip) + marquee-scrolling title
- **Color extraction**: dominant color from artwork → subtle gradient on expanded background
- **Waveform**: 3 thin bars with random up/down animation during playback

### Animations

- Playback start: pill micro-bounce
- Track change: artwork crossfade
- Compact→expanded: `matchedGeometryEffect` morphs artwork 20×20 → 80×80
- `NSHapticFeedbackManager` tactile feedback (MacBook only)

---

## Phase 3: AI Usage (v0.3)

### AIProvider Protocol

```swift
protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }
    func refresh() async throws -> AIUsageSnapshot
    func isConfigured() -> Bool
}
```

### Authentication Priority

1. API key → Settings input → Keychain (`Security.framework`, service: `com.tukuyomi032.perch.<provider>`)
2. CLI config (`~/.claude/`, `~/.codex/`)
3. Environment variables (`ANTHROPIC_API_KEY`, etc.)

### Providers

- **Claude**: `~/.claude/` config + Anthropic API usage endpoint
- **Codex**: `~/.codex/` config (CodexBar pattern)
- **OpenAI** (Phase 6): `/v1/organization/usage`
- **OpenRouter** (Phase 6): `/api/v1/auth/key`

### AIUsageStore + RefreshScheduler

- `actor RefreshScheduler`: configurable interval (1min/5min/15min/manual) via `Task.sleep(for:)`
- `@MainActor @Observable AIUsageStore`: parallel refresh with `withTaskGroup`, sorted snapshots

### AIUsageCard

- **Expanded**: per-provider usage bars + session/weekly detail + reset countdown
- **Compact**: lowest-remaining provider (e.g., "Claude 72%")
- **Threshold alert**: ≤20% remaining → red pill glow + OS notification

---

## Phase 4: File Shelf (v0.4)

### Drag & Drop

- AppKit `NSDraggingDestination` on IslandWindow/contentView
- `registerForDraggedTypes([.fileURL])`
- Visual feedback: pill expands upward during drag + drop icon
- `draggingEntered` → `.copy` + pill expansion trigger
- `performDragOperation` → URL → `ShelfStore.addFiles`

### ShelfItem

```swift
struct ShelfItem: Identifiable, Sendable, Equatable, Codable {
    var id: UUID
    var originalURL: URL
    var storedURL: URL
    var bookmarkData: Data?
    var displayName: String
    var fileSize: Int64
    var fileType: UTType?
    var addedAt: Date
    var expiresAt: Date?
    var accessCount: Int = 0
}
```

### Storage

- Path: `~/Library/Application Support/Perch/Shelf/{uuid}-{filename}`
- **Copy mode**: file copied, safe from deletion. Disk usage
- **Reference mode**: security-scoped bookmark only. No disk usage, invalid if source deleted
- Capacity: 500MB default, oldest files auto-deleted on overflow
- Max items: 50

### Auto-Delete Policy

Options: 1h / 6h / 24h (default) / 7d / manual only

### FileShelfCard

- Expanded: file list with `NSWorkspace.shared.icon(forFile:)` + name + size + date
- Actions: Open / Quick Look / AirDrop / Reveal in Finder / Delete
- Context menu (right-click)
- Drag-out support (Shelf → Finder/other apps)
- Empty state: "Drop files here" + dashed border

### Quick Look & AirDrop

- `QLPreviewPanel.shared()` with `QLPreviewPanelDataSource`/`Delegate`
- `NSSharingService(named: .sendViaAirDrop)` with `canPerform(withItems:)` check

---

## Phase 5: Dev Status (v0.5)

### GitHubClient

- `actor GitHubClient`: URLSession-based, REST API v3
- Auth: Fine-grained PAT → Keychain `com.tukuyomi032.perch.github`
- Rate limit: `X-RateLimit-Remaining`/`Reset` monitoring. Low remaining → extend polling
- 5,000 req/hr authenticated, 60 req/hr unauthenticated

### GitHubActionsProvider

- `GET /repos/{owner}/{repo}/actions/runs?per_page=5`
- Monitoring config per repo: owner, repo, displayName, branch filter, workflow filter, enabled toggle
- Settings: add/remove repos in `{owner}/{repo}` format

### ProcessWatcher

- `pgrep -x claude` / `pgrep -x codex` for running CLI detection
- 10s polling interval (lightweight)

### DevStatusCard

- Per-repo workflow status: icon + repo name + branch + status
- Repo tap → browser to GitHub Actions
- Claude Code / Codex CLI running status section

### Notifications

- New failure detected: red pill glow + bounce → "Build failed" compact text → 3s revert
- macOS notification via `UNUserNotificationCenter`
- Sound: macOS default or user-specified MP3 (`UNNotificationSound(named:)`)
- Priority: failure > running > success (success not shown in pill)

---

## Phase 6: Stabilization & Distribution (v1.0)

### NotificationService

```swift
@MainActor
final class NotificationService {
    func requestPermission() async -> Bool
    func send(title:, body:, category:, sound:) async
}
enum NotificationCategory: String { case ciFailure, aiUsageWarning, fileShelfFull, generalError }
enum NotificationSound { case system; case custom(URL); case none }
```

- Custom sounds: MP3/WAV/AIFF → `~/Library/Application Support/Perch/Sounds/`
- 30s max (UNNotificationSound limit)

### DesignSystem

- Colors: perchBackground (.black.opacity(0.85)), perchSuccess/Failure/Warning/Running/Idle
- Typography: SF Pro / SF Mono only
  - Compact pill: `.system(size: 12, weight: .semibold)`
  - Card title: `.system(size: 15, weight: .bold)`
  - Card body: `.system(size: 13, weight: .regular)`
  - Caption: `.system(size: 11, weight: .medium)`
- Spacing: 4pt grid: 8/12/16/20/24
- Components: unified cornerRadius(28), padding(16), header layout
- Animations: `perchSpring` (0.32/0.82), `perchExpand` (0.35/0.86), `perchSubtle` (0.2s easeInOut)

### Sparkle

- SPM `Sparkle 2.9.1+`
- `SPUStandardUpdaterController` in MenuBarController
- EdDSA signing, appcast via GitHub Pages or homebrew-tap

### Homebrew Cask

- Existing `tukuyomil032/homebrew-tap` repository
- `cask "perch"`: GitHub Releases dmg download
- zap: Application Support/Perch, Preferences plist, Caches

### HUD (Info Display)

- Battery: `IOPSCopyPowerSourcesInfo()`, charge state/percentage/estimated time
- Volume: `AudioObjectGetPropertyData` + `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`
- Charge start/complete → pill notification (Dynamic Island style)
- Standard HUD replacement deferred (private API/SIP issues)

---

## Design References

- Apple Dynamic Island (iOS 16+)
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch) — macOS notch UI
- [NotchDrop](https://github.com/Lakr233/NotchDrop) — file drop via notch
- CodexBar — AI usage tracking menubar app
- macOS Human Interface Guidelines — vibrancy, materials, SF Symbols
