# Changelog
## [2.13.0] - 2026-02-10

### Added
- Added "Hide Out of Combat" toggle for Action Bars (fades bars when not in combat)
- Added "Hide Out of Combat" toggle for Resource Bars (same behavior)

### Fixed
- Fixed action bar range tint (red) getting permanently stuck by resolving state desync between push events and range ticker
- Fixed combat visibility not triggering on combat start due to `InCombatLockdown()` timing race

## [2.12.0] - 2026-02-08

### Added
- Added Target of Target unit frame with configurable health/power bars, name/level text, and class-colored icons
- Added "Copy Settings From" dropdown in unit frame settings for quick configuration between player/target/targettarget/focus frames
- Added Hide Blizzard Target of Target frame toggle

## [2.11.0] - 2026-02-08

### Added
- Added Midnight 12.0 push-based event handlers for ACTION_USABLE_CHANGED and ACTION_RANGE_CHECK_UPDATE
- Added 0.2s range ticker for real-time out-of-range detection with C_ActionBar.IsActionInRange

### Fixed
- Fixed ADDON_ACTION_FORBIDDEN taint errors caused by other addons hooking LoadAddOn (AceEvent-3.0 v9)
- Restored action bar usability states: grey/desaturated for unavailable, blue tint for no mana, red tint for out of range

## [2.10.0] - 2026-01-24

### Fixed
- **Midnight M+ Charge Display**: Fixed action bar charges not showing in M+ combat by using `C_ActionBar.GetActionDisplayCount` pattern (from LibActionButton-1.0)
- **M+ Instance Layout**: Fixed action bars switching from 1 row to 2 rows when entering instances by pre-caching Edit Mode settings in safe zones
- **Secret Value Detection**: Improved `Utils.IsValueSecret` to use `issecretvalue()` global as primary detection method

### Changed
- **Charge Display Logic**: Simplified count/charge display code - removed manual secret checks in favor of Blizzard's display-ready API

## [2.9.1] - 2026-01-19

### Fixed
- Fixed unit frames staying visible when custom frames disabled

## [2.9.1] - 2026-01-19

### Fixed
- Fixed combat taint error when resetting profile during combat

## [0.5.0] - 2026-01-19

### Changed
- Reduced icon offset slider range to ±25px

## [0.5.0] - 2026-01-19

### Fixed
- Fixed X/Y offset slider property name mismatch

## [0.5.0] - 2026-01-19

### Changed
- Set default background opacity to 40% for all unit frames

## [0.5.0] - 2026-01-19

### Fixed
- Fixed combat taint error with InCombatLockdown protection

## [0.5.0] - 2026-01-19

### Added
- Enhanced summon icon with Pending/Accepted/Declined states

## [0.5.0] - 2026-01-19

### Fixed
- Fixed role icon texcoords (0.3 crop) for proper centering

## [0.5.0] - 2026-01-19

### Changed
- Set default icon positions and offsets for all unit frames

## [0.5.0] - 2026-01-19

### Fixed
- Fixed all 12 status icon textures with proper Blizzard paths


All notable changes to this project will be documented in this file.




## [2.8.0] - 2025-12-23

### Changed
- - Implemented Midnight Capability & Standby System
- Added /ah testapi diagnostic tool
- Defensive guards for Royal API transition (Beta 5+)
- Refined version detection (Threshold 120001)
- Added @midnight-cleanup tags for future API restoration

## [2.7.4] - 2025-12-22

### Changed
- Fixed critical 'Error loading' bug in packaged versions by wrapping DevMarker.lua in debug blocks. Added preventative checks to TOCValidator.

## [2.7.3] - 2025-12-21

### Changed
- **CurseForge Deployment**: Re-release to address metadata issues.

## [2.7.2] - 2025-12-21

### Changed
- **CurseForge Deployment**: Re-release to trigger updated CurseForge packaging.

## [2.7.1] - 2025-12-21

### Fixed
- **Trinket Logic**: Fixed an issue where trinkets were not showing on Retail 11.2.7+ and Midnight 12.0.0+.
- **Midnight Readiness**: Added `Utils.GetInventoryItemCooldownSafe` to handle table-based return signatures and secret values for item cooldowns.
- **Improved Trinket Initialization**: Added a safety delay on enable to ensure item data is loaded from the server before rendering.

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
- **Action Bar Mirroring (Edit Mode Sync)**: New feature to synchronize the HUD's Action Bar layout with Blizzard's native Edit Mode settings (Bars 1 and 2).
    - Automatically mirrors row and column counts from WoW settings.
    - Added **Top Bar Priority** setting to swap stacking order of Bar 1 and Bar 2.
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
