# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-12-16

### Added
- **Core HUD**: 6x4 Grid System mapping Action Bar 1 (1-12) and Action Bar 2 (61-72).
- **Stance Support**: Native handling of Druid forms, Stealth, and Vehicle bars.
- **Assisted Highlight**: "Blue Glow" rotation support via `AssistedCombatManager` hook.
- **Charge Tracking**: "Cold Line" swipe indication for charge cooldowns and deep stack tracking.
- **Settings UI**: Native Blizzard Options panel for:
    - Drag & Drop (Lock toggle).
    - Icon Size (Width/Height) with correct aspect ratio cropping.
    - Font Sizing (Cooldowns/Counts).
    - Background Opacity.
- **Performance**: Event-driven architecture with 0ms idle CPU usage.
