# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2025-12-16

### Added
- **Glow Opacity Settings**: Dedicated sliders for Proc Glow (Yellow) and Assist Glow (Blue) opacity (0-100%).
- **How to Use Guide**: Detailed setup instructions in README.

### Changed
- **Visual Polish**: Refined Glows to coexist. Proc Glow is now 1px (Outer/Top), Assist Glow is 2px (Inner/Bottom).
- **Settings Clarity**: Opacity sliders now display as clean 0-100% integers.
- **Cooldown Logic**: "Gold Spark" removed for GCD and short lockouts (<1.5s) to reduce visual noise; retained for real cooldowns and charge refills.
- **Documentation**: Complete rewrite of AGENTS.md and README.md for accuracy.

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
