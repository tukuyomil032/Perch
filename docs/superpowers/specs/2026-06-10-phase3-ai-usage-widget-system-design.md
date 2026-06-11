# Perch Phase 3: AI Usage + Widget Preset System Design

**Date**: 2026-06-10
**Status**: Approved
**Author**: tukuyomil032 + Claude
**Phase**: 3 (v0.3)

## Overview

Phase 3 introduces two interlocking systems:
1. **Widget Preset System** — browser-tab-like presets for arranging named widget collections
2. **AI Usage Feature** — per-provider usage tracking (Claude, Codex, Gemini, Copilot, OpenRouter)

Backward compatibility: all Phase 2 Now Playing features continue unchanged. Widgets wrap existing views.

## Design Decisions

### Widget Preset System
- `PerchWidget` protocol — 4 sizes: mini/compact/standard/full
- `PresetLayout` — named widget arrangements, persisted via Defaults
- `PresetTabBar` — switching via click, Cmd+1/2/3, wheel scroll, trackpad swipe
- Expanded UI height is dynamic based on widget content

### Compact Pill — Dual Activity
- iPhone Dynamic Island-style split: main pill + secondary bubble (32pt circle)
- Each preset configures `pillPrimary` / `pillSecondary` widget IDs
- Secondary bubble tap expands to that widget's card

### AI Usage (CodexBar-inspired)
- `AIProvider` protocol with multi-strategy data fetching
- Claude/Codex: local JSONL log parsing
- Gemini/Copilot/OpenRouter: API-based
- Display: Session/Weekly bars, $ cost, daily chart, model breakdown
- `RefreshScheduler` actor for periodic updates (default 5 min)

### Built-in Default Presets
| Preset | Widgets |
|---|---|
| Daily | Now Playing (standard) + AI Usage mini (compact) |
| Dev | AI Usage (full) + Now Playing mini (compact, bottom) |

## Architecture

### New Files
```
perch/Core/
  WidgetTypes.swift          — WidgetSize, WidgetPosition enums
  WidgetProtocol.swift       — PerchWidget protocol
  WidgetLayout.swift         — PresetLayout, WidgetPlacement structs
  PresetStore.swift          — Preset CRUD + persistence
  WidgetRegistry.swift       — Widget registration

perch/Features/AIUsage/
  AIProvider.swift           — Protocol + data types
  AIUsageStore.swift         — Store + refresh orchestration
  CostCalculator.swift       — Model pricing, token-to-USD
  Providers/
    ClaudeProvider.swift     — JSONL log parsing
    CodexProvider.swift      — JSONL log parsing
    GeminiProvider.swift     — OAuth + REST API
    CopilotProvider.swift    — API token
    OpenRouterProvider.swift — API key

perch/UI/
  PresetTabBar.swift         — Preset switching tabs
  WidgetContainer.swift      — Multi-widget layout engine
  SecondaryBubbleView.swift  — Dual-activity bubble
```

### Modified Files
- `AppState.swift` — Add PresetStore, AIUsageStore
- `ExpandedIslandView.swift` — Replace cardContent with WidgetContainer
- `RootIslandView.swift` — Add SecondaryBubbleView + gestures
- `CompactPillView.swift` — Preset-based pill content
- `IslandGeometry.swift` — Dynamic height
- `IslandWindowController.swift` — Dynamic resize
- `SettingsView.swift` — AI Providers + Presets tabs

## Implementation Phases

### Sub-phase 1 (Step 1-3): Foundation [COMPLETE]
- WidgetProtocol, WidgetRegistry, PresetStore
- RefreshScheduler implementation
- AIProvider protocol, AIUsageStore, CostCalculator

### Sub-phase 2 (Step 4-6): AI Providers + Widget Views
- Claude Provider (log parsing)
- Remaining providers (Codex, Gemini, Copilot, OpenRouter)
- AI Usage Widget views (4 sizes)

### Sub-phase 3 (Step 7-10): UI Integration
- NowPlayingWidget wrapper
- WidgetContainer + PresetTabBar
- ExpandedIslandView integration
- Dynamic window resize

### Sub-phase 4 (Step 11-15): Polish
- Compact pill dual activity
- Preset switching (all 4 methods)
- AppState integration + default presets
- Settings UI
- Threshold alerts

## Technical Constraints
- No App Sandbox (already disabled for window level control)
- Keychain for API keys (`com.tukuyomi032.perch`)
- All cost calculations on-device (no external data sent)
- Swift 6 strict concurrency throughout

## References
- CodexBar: https://github.com/steipete/CodexBar
- Boring Notch: https://github.com/TheBoredTeam/boring.notch
- Progress: `docs/progress.md`
