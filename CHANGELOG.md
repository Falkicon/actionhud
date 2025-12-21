# Changelog

All notable changes to this project will be documented in this file.


## [2.7.0] - 2025-12-21

### Added
- **API Deprecation Scanner Support**: Integrated with the new `ADDON_DEV/Tools/DeprecationScanner` tool.
- **Scoped Ignore Tags**: Implemented `-- @scan-ignore: midnight` tags across the codebase to silence verified "passthrough" warnings for Midnight (12.0.0).

### Changed
- **Midnight Compatibility Layer**: Major refactor of `Utils.lua` to include bulletproof "Safe" API wrappers for `C_ActionBar` and `C_Spell` namespaces.
- **Robust Secret Value Handling**: Updated `Utils.IsValueSecret` and `Utils.SafeCompare` with `pcall` protection to prevent runtime crashes during instanced combat in Midnight.
- **Action Bar Normalization**: Refactored `ActionBars.lua` to handle the new table-based return signatures of `C_ActionBar` functions automatically.

### Fixed
- **Action Bar Count/Timer Display**: Resolved an issue where secret values caused action counts to display as `...` inappropriately; now leverages native UI passthrough for correct rendering.
- **Type Mismatch Errors**: Fixed Lua errors when comparing numeric counts/durations that could potentially be strings (secret values).

## [2.6.2] - 2025-12-21

### Added
- **Trinkets Module**: New sidecar module for tracking equipped on-use trinket cooldowns.
    - Synchronizes with Blizzard's native cooldown numbers.
    - Adjustable icon sizing and font typography settings.
    - Automatically hides passive trinkets and empty slots.
    - Defensive API wrappers to prevent crashes with new Blizzard item APIs on PTR.

### Fixed
- **Settings Panel Combat Block**: Resolved an `ADDON_ACTION_BLOCKED` error when attempting to open settings while in combat or via secure macros.
- **Trinket Logic Crash**: Fixed a Lua error on the PTR where `C_Item.GetItemSpell` was called with invalid arguments.
- **Trinket Timer Text**: Switched to native Blizzard countdown numbers for trinket icons to ensure accurate timers that work in combat and respond to HUD scaling.

## [2.6.1] - 2025-12-21

### Added
- **Layout Visualization Outlines**: New configuration tool to see the bounds of every HUD module.
    - Shows semi-transparent boxes with identifying labels for all components.
    - Forces a minimum size for empty/inactive modules so they can be positioned out of combat.
    - Controlled via a new toggle at the top of the **Layout** settings tab.
- **Debugging System Overhaul**: Complete rewrite of the logging and troubleshooting tools for better performance and insight.
    - **Integrated Log Field**: Replaced the export popup with a selectable, multi-line text field directly in the settings panel.
    - **Debug Events**: Added event tracking for Action Bars, Resource Bars, and Cooldowns.
    - **Debug Containers**: Solid color-coded backgrounds for troubleshooting rendering issues.
- **In-Game Help**: Added a new **Help & Slash Commands** section to the main settings page.

### Changed
- **Slash Commands**: 
    - `/ah debug` now immediately toggles debug recording on/off with chat confirmation.
    - `/ah log` has been removed (logs are now integrated into the main settings).
    - `/ah clear` remains for clearing the buffer.
- **Settings UI Reliability**: Improved the module's ability to find correct numeric category IDs in the modern WoW settings panel, resolving potential crashes and navigation issues.
- **Debugging Panel Layout**: Reordered for better workflow: Tools at the top, Troubleshooting Filters in the middle, and Recording/Logs at the bottom.

## [2.6.0] - 2025-12-20

### Added
- **Action Bar Mirroring (Edit Mode Sync)**: New feature to synchronize the HUD's Action Bar layout with Blizzard's native Edit Mode settings (Bars 1 and 6).
    - Automatically mirrors row and column counts from WoW settings.
    - Added **Top Bar Priority** setting to swap stacking order of Bar 1 and Bar 6.
    - Added **Row Alignment** settings (Left, Center, Right) for custom horizontal positioning.
- **Enhanced Resource Bar Control**: Complete refactor of the Resources module settings.
    - Added individual visibility toggles for Health, Power, and Class bars.
    - HUD now dynamically restacks bars and updates its total height when bars are toggled off.
    - Reorganized Resource Bar settings into logical "Common" and "Per-Bar" sections for better UX.

### Fixed
- **Row Inversion Bug**: Corrected layout logic where action bar rows within a block were appearing upside down compared to the Blizzard UI.
- **Midnight API Taint**: Implemented a layout cache and combat-lockdown checks for Edit Mode APIs to prevent "secret value" errors and UI taint in WoW 12.0+.
- **Paging Logic**: Fixed action bar paging (stance changes, bonus bars) to safely handle secret values in instances.

## [2.5.5] - 2025-12-19

### Changed
- **Documentation**: Consolidated shared documentation to central `ADDON_DEV/AGENTS.md`; trimmed addon-specific AGENTS.md
- **Deep-Dive Docs**: Moved detailed proxy system and performance docs to `Docs/` folder

### Added
- **CurseForge Metadata**: Added `## X-License: GPL-3.0` to .toc file
- **CurseForge Integration**: Added project ID and webhook info to AGENTS.md
- **Cursor Ignore**: Added `.cursorignore` to reduce indexing overhead

## [Unreleased - Midnight Branch (Archived Changes)]
### Added
- **Dynamic Layout Refresh**: HUD now automatically refreshes and reposition modules when shared dimensions (like Icon Width) or module enable states are toggled.
- **Resource Bar Scaling**: Resource bars now automatically match the width of the Action Bar grid.
- **Unit Frames Module**: New reskin module for Player, Target, and Focus frames.
    - Hide circular portraits, borders, and decorations for a cleaner look.
    - Flat solid bar textures with desaturated class/power coloring.
    - Adjustable health and mana bar heights and width scaling.
    - Always-show text option with safe numeric transforms for Midnight secret values.
- **Nameplates Module**: New reskin module for Blizzard's default nameplates.
    - Hide borders and apply flat solid bar textures.
    - Adjustable health bar height and width scale.
    - Class resource bar (mana, runes) styling.
- **Tracked Bars Compact Mode**: New option to hide cooldown bars and show icons only for a more compact display.
- **Timer on Icon**: New option to display the countdown timer centered on the icon instead of on the bar.
    - Stack count automatically repositions to bottom-right when enabled.

### Changed
- **Layout Manager Refinement**: 
    - Disabled modules are now hidden from the "HUD Stack Order" settings list.
    - Gaps between modules now automatically close when an intervening module is disabled.
- **TrackedBuffs/TrackedBars Style-Only**: Simplified to style-only approach for Midnight (12.0) compatibility.
    - Hooks into Blizzard's native `BuffIconCooldownViewer` and `BuffBarCooldownViewer` frames.
    - Blizzard handles all protected API calls and positioning (via EditMode).
    - ActionHud applies visual styling only: strips decorations, custom fonts.
    - Resolves "secret value" errors during combat in instanced content.
- **Settings Consolidation**: Combined separate Tracked Buffs and Tracked Bars tabs into single "Tracked Abilities" tab.
    - "Enable" toggles renamed to "Style Tracked Buffs/Bars" for clarity.
    - Shared font settings (Stack Count Font Size, Timer Font Size).
    - Removed sizing/positioning settings – use EditMode instead.

### Fixed
- **Taint Reduction**: Removed several protected API calls (`ClearAllPoints`, `SetAllPoints`, `StatusBar:SetStatusBarTexture` hooks) in Unit Frame styling that were causing "Action blocked" errors and combat taint.
- **Anchor Alignment**: Fixed Target and Focus frame anchoring to ensure bars grow in the correct direction and maintain proper spacing.
- **Secret Value Safety**: Implemented `SafeNumericTransform` and `lockShow` assignment fixes to prevent Lua errors when encountering Midnight secret values.
- **Reputation Bar**: Fixed unit-type indicators (blue/green bars) showing through on styled Target/Focus frames.

### Technical
- Added `ActionHud:RefreshLayout()` central refresh point.
- Implemented `EnsureBarLayout` helper for uniform anchoring across all unit frames.
- Added hook points on `RefreshLayout` and `OnAcquireItemFrame` for Blizzard frame restyling.
- Strips MaskTexture and overlay Texture regions for cleaner icon appearance.

## [2.5.4] - 2025-12-19
### Fixed
- **Cooldown Manager Real-time Detection**: Fixed a bug where cooldown-related modules would not display until after a UI reload if Blizzard's "Enable Cooldown Manager" setting was turned on during the session.

## [2.5.3] - 2025-12-19
### Added
- **Death Knight Support**: Added support for Rune tracking in the class resource bar.

## [2.5.2] - 2025-12-18
### Performance
- **CPU Optimization**: Reduced CPU usage by ~16%.
- **Memory Optimization**: Reduced baseline memory by ~60% (5.8MB → 2.2MB).

## [2.5.1] - 2025-12-18
### Fixed
- **Cooldown Manager**: Fixed GCD detection misreporting for certain spells (e.g. Demoralizing Shout).

## [2.5.0] - 2025-12-18
### Added
- **Layout Manager**: New unified layout system for arranging HUD modules.
