# Changelog

All notable changes to this project will be documented in this file.

## [2.2.1] - 2025-12-16
### Added
- **Cooldown Spacing**: Added "Icon Spacing" setting to control the gap between cooldown icons.
- **Documentation**: Added "Prerequisites" section to README.

### Changed
- **Defaults**: Updated default Cooldown Manager Icon Size to 20x20 and spacing to 0px for a more compact look.
- **Settings UI**: Added requirement notes for Cooldown Manager features.

### Fixed
- **Action Bars**: Fixed the Enable/Disable toggle in settings not correctly hiding/showing the grid.

## [2.2.0] - 2025-12-16
### Added
- **Modular Action Bars**: Moved action bar logic to a dedicated `ActionBars` module.
- **Cooldown Fonts**: Added "Stack Font Size" setting to Cooldown Manager for styling charge counts.
- **Credits**: Added credits to README for referenced works.

### Changed
- **Settings UI**: Restructured settings into "General", "Action Bars", and "Cooldowns" tabs.
- **Cooldown Visuals**: Implemented aggressive hiding of native borders/shadows and Aspect Ratio cropping for non-square icons.
- **Defaults**: Updated default font sizes and gap settings.

### Fixed
- **Cooldown Layout**: Fixed sizing issues for Essential/Utility bars and resolved icon stretching.
- **Charge Counts**: Fixed unstyled charge numbers on deeply nested frames (e.g., Bear Form).

## [2.1.0] - 2025-12-16

### Added
- **Class Resource Bars**: Universal support for secondary power bars (Combo Points, Holy Power, Chi, Arcane Charges, Soul Shards, Essence).
- **Smart Visibility**: Class bars only appear when you have active charges/points. They auto-hide in forms/stances that don't satisfy this (e.g., Bear Form with 0 CP).
- **Dynamic Layout**: The gap between Player and Target HUDs now automatically expands/collapses based on Class Bar visibility to maintain symmetry.
- **Settings**:
    - **Class Resource Height**: Configurable height for the new bar.
    - **Player-Target Gap**: Adjustable spacing between the two main resource clusters.
    - **Defaults**: Updated default profile for a tighter, cleaner look 20x17 icons, 0px spacing).

### Changed
- **Visuals**: Desaturated all resource bars by ~15-25% to reduce visual prominence and "neon" effect. Custom matte pallete added for Class Resources.
- **Positioning**: Improved "Top" vs "Bottom" logic. Class bars now anchor to the "outside" edge of the stack (Above Health if Top, Below Power if Bottom).
- **Responsiveness**: Resource layout now updates instantly on power changes, removing previous 5-10s delay.

## [2.0.0] - 2025-12-16

### Major Rewrite: Ace3 Integration
- **Framework**: Migrated to AceAddon-3.0, AceDB-3.0, and AceConfig-3.0 for robust architecture.
- **Profiles**: Added full Profile support (AceDB). Settings are now saved per-profile and can be copied/reset.
- **Libs**: Proper library management via `embeds.xml`. Fixed dependencies blocking other addons (CallbackHandler issue resolved).

### Added
- **Resource Bars**: New module displaying Health and Power (Energy/Mana/Rage) bars attached to the HUD. Configurable position, size, and coloring.
- **SharedMedia**: Added LibSharedMedia support for proper font selection.
- **Automation**: Created `ADDON_DEV` environment with Git managed libraries and auto-updater script.

### Changed
- **Config UI**: Completely replaced custom config frame with AceConfigDialog for a native, standarized options menu.
- **Commands**: `/ah` now opens the config window.
- **Stability**: Fixed initialization ordering issues that prevented the HUD from showing on first load under certain conditions.

### Removed
- **Manual Library Imports**: Replaced with clean `Embeds.xml` referencing standard Ace3 libs.

## [1.1.0] - 2025-12-16

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
