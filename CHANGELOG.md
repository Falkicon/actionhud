# Changelog

All notable changes to this project will be documented in this file.


## [Unreleased - Midnight Branch]

### Added
- **Tracked Bars Compact Mode**: New option to hide cooldown bars and show icons only for a more compact display.
- **Timer on Icon**: New option to display the countdown timer centered on the icon instead of on the bar.
    - Stack count automatically repositions to bottom-right when enabled.

### Changed
- **TrackedBuffs/TrackedBars Style-Only**: Simplified to style-only approach for Midnight (12.0) compatibility.
    - Hooks into Blizzard's native `BuffIconCooldownViewer` and `BuffBarCooldownViewer` frames.
    - Blizzard handles all protected API calls and positioning (via EditMode).
    - ActionHud applies visual styling only: strips decorations, custom fonts.
    - Resolves "secret value" errors during combat in instanced content.
- **Settings Consolidation**: Combined separate Tracked Buffs and Tracked Bars tabs into single "Tracked Abilities" tab.
    - "Enable" toggles renamed to "Style Tracked Buffs/Bars" for clarity.
    - Shared font settings (Stack Count Font Size, Timer Font Size).
    - Removed sizing/positioning settings – use EditMode instead.
- **Layout Stack**: Removed `trackedBuffs` from the HUD layout stack (now positioned via EditMode).

### Removed
- **PopulateBuffProxy**: Removed ~140 lines of dead code from Manager.lua (no longer needed).
- **Tracked Bars Sidecar**: Removed X/Y offset settings from Layout tab (use EditMode).
- **Obsolete Settings**: Removed buffsEnabled, tbEnabled, sizing, spacing, hide inactive settings.

### Technical
- Added hook points on `RefreshLayout` and `OnAcquireItemFrame` for Blizzard frame restyling.
- Strips MaskTexture and overlay Texture regions for cleaner icon appearance.
- Migration code cleans up trackedBuffs from existing layout stacks.

---

## [2.5.5] - 2025-12-19

### Changed
- **Documentation**: Consolidated shared documentation to central `ADDON_DEV/AGENTS.md`; trimmed addon-specific AGENTS.md
- **Deep-Dive Docs**: Moved detailed proxy system and performance docs to `Docs/` folder

### Added
- **CurseForge Metadata**: Added `## X-License: GPL-3.0` to .toc file
- **CurseForge Integration**: Added project ID and webhook info to AGENTS.md
- **Cursor Ignore**: Added `.cursorignore` to reduce indexing overhead

## [2.5.4] - 2025-12-19
### Fixed
- **Cooldown Manager Real-time Detection**: Fixed a bug where cooldown-related modules (Essential, Utility, Tracked Buffs, Tracked Bars) would not display until after a UI reload if Blizzard's "Enable Cooldown Manager" setting was turned on during the session.
    - Added `CVAR_UPDATE` event and `CVarCallbackRegistry` monitoring for `cooldownViewerEnabled`.
    - HUD now instantly populates or clears cooldown modules when the setting is toggled in Blizzard's Gameplay Enhancements options.
    - Triggers full layout recalculation via LayoutManager on state change.

## [2.5.3] - 2025-12-19
### Added
- **Death Knight Support**: Added support for Rune tracking in the class resource bar.
    - Runes now display as segments in the class resource bar for Death Knights.
    - Matches Rogue combo point behavior: hides when no runes are ready.
    - Added spec-based coloring (Blood: Red, Frost: Blue, Unholy: Green).
    - Added `RUNE_POWER_UPDATE` event handling for instant UI updates.
    - Fixed an issue where runes would always show as full and not deplete.
    - Fixed Rune segments appearing as small dashes on initial load by ensuring layout calculation happens after frame sizing.

## [2.5.2] - 2025-12-18
### Performance
- **CPU Optimization**: Reduced CPU usage by ~16% (3.47 → 2.9 ms/s).
    - Removed redundant 20Hz OnUpdate polling from Cooldowns module.
    - Added frame-level API caching for spell cooldown/charge queries.
    - Added early-exit checks in ActionBars event handlers for empty slots.
    - Added local upvalues for hot-path globals.
    - Consolidated initialization timers.
    - Cached module references in Manager to avoid GetModule lookups on UNIT_AURA.
    - Removed duplicate GetSpellChargesSafe call in UpdateState.
- **Memory Optimization**: Reduced baseline memory by ~60% (5.8MB → 2.2MB).
    - Eliminated table garbage creation in render functions (reusable cache tables).
    - Fixed unbounded textureCache growth (now wiped every 60 seconds).
    - Removed string.format calls from hot paths (allocated even when logging disabled).
    - Moved legacyFontMap to module level (was recreated every call).
    - Return shared EMPTY_TABLE instead of `{}` on API failures.
    - Reuse totemDataCache table instead of creating new one per call.
- **Memory Management**: Memory now properly garbage collected (cycles between 2.2-6.6MB, returns to baseline after GC).

## [2.5.1] - 2025-12-18
### Fixed
- **Cooldown Manager**: Fixed Demoralizing Shout (and similar abilities) taking 2-3 seconds to show cooldown.
    - **Root Cause**: WoW API incorrectly reports `activeCategory = 133` (GCD category) for these spells for 1-2 seconds after cast, despite having long cooldowns.
    - **Solution**: Changed GCD detection to check both category AND duration. Only treat as GCD if category matches AND duration ≤ 1.5 seconds.

### Added
- **Development Mode**: Added `DevMarker.lua` and `.pkgmeta` for CurseForge packaging.
    - Debugging panel only visible in dev mode (git clones).
    - `[DEV MODE]` indicator shown on addon load.
- **Cooldown Manager Dump**: Extended `/ah dump` to include all cooldown categories (Essential, Utility, TrackedBuff, TrackedBar).

### Technical
- **API Documentation**: Added "GCD Category Misreporting" section to AGENTS.md documenting the API quirk and solution.

## [2.5.0] - 2025-12-18
### Added
- **Layout Manager**: New unified layout system for arranging HUD modules.
    - **Reorderable Stack**: All modules (Tracked Buffs, Resources, Action Bars, Cooldowns) can now be reordered in any order via the new "Layout" settings panel.
    - **Configurable Gaps**: Set spacing between each adjacent module independently.
    - **Migration**: Existing settings are automatically migrated to the new system on first load.
- **Layout Settings Panel**: New "Layout" sub-panel in settings:
    - Tracked Bars (sidecar) X/Y offset controls at top.
    - Visual list of HUD modules with Move Up/Down buttons.
    - Gap sliders between each module pair.
    - Reset to Default Order button.

### Changed
- **Module Positioning**: Modules now use centralized LayoutManager instead of individual position/gap settings.
- **Simplified Settings**: Removed redundant "Position" and "Gap from HUD" settings from Resource Bars, Cooldown Manager, and Tracked Buffs panels (now managed via Layout panel).

### Technical
- **LayoutManager.lua**: New module that coordinates vertical stacking of all HUD components.
- **Module API**: Each module now implements `CalculateHeight()`, `GetLayoutWidth()`, and `ApplyLayoutPosition()` for integration with LayoutManager.

## [2.4.1] - 2025-12-18
### Fixed
- **Proxy Pool Collision Bug**: Fixed TrackedBuffs and TrackedBars not displaying correctly after refactor.
    - **Root Cause**: `Manager:GetProxy()` was returning hidden proxies that were still logically owned by another cooldownID, causing multiple IDs to share the same frame.
    - **Solution**: Added lease tracking (`leasedTo` property) to prevent proxy reuse while still assigned to an active item.
    - **Render Loop Restructure**: Changed from single-pass to multi-pass rendering to prevent proxies from being "stolen" mid-render.

## [2.4.0] - 2025-12-18
### Changed
- **Major Proxy System Rewrite**: Simplified visibility model for better compatibility.
    - **Hide-Only Model**: Now uses simple `SetShown(false)` to hide Blizzard frames instead of reparenting and alpha manipulation.
    - **Direct API Queries**: Proxies now query spell data directly from `C_Spell` APIs and `CooldownViewerSettings:GetDataProvider()` instead of scraping from hidden frames.
    - **Event-Driven Updates**: Uses `SPELL_UPDATE_COOLDOWN`, `UNIT_AURA`, `PLAYER_TOTEM_UPDATE` events instead of 20Hz OnUpdate polling.
    - **Clean Restoration**: Disabling features now instantly restores Blizzard's native UI with a single `SetShown(true)` call.
- **Settings UX**: Settings now dynamically show status of Blizzard's Cooldown Manager.
    - Green message when enabled, red warning when disabled.
    - All cooldown-related settings are greyed out when Blizzard's feature is disabled.

### Fixed
- **Tracked Buffs/Bars responsiveness**: Activation tracking now uses an event-driven `UNIT_AURA` cache (Blizzard-style `unitAuraUpdateInfo`) instead of relying on repeated `C_UnitAuras.GetPlayerAuraBySpellID` polling, fixing slow/late activations (e.g. Shield Block, Ignore Pain, Demoralizing Shout).

### Removed
- **Legacy Code**: Removed `ahOriginalParent`, `ahOriginalAlpha`, `EnableMouse(false)` complexity.
- **OnUpdate Polling**: Eliminated the 20Hz sync loop in favor of event-driven updates.
- **Frame Sync Logic**: Removed heuristic texture/fontstring scraping from Blizzard frame children.


## [2.3.1] - 2025-12-18
### Added
- **Midnight (12.0) Compatibility**: Full support for secret values that will be introduced in WoW 12.0.
    - Cooldown displays use passthrough pattern for `Cooldown:SetCooldown()`.
    - Charge counts gracefully degrade to "..." when values are secret during combat.
    - Resource bars use passthrough for `StatusBar:SetValue()` and `SetMinMaxValues()`.
- **API Resilience**: Added `pcall` wrappers for critical spell APIs (`C_Spell.GetSpellCooldown`, `C_Spell.GetSpellCharges`, `IsSpellOverlayed`).

### Changed
- **Performance**: Implemented adaptive throttling for OnUpdate handler (20 Hz when visible, 2 Hz when hidden).
- **Performance**: Global namespace scan for debug mode now rate-limited to once per 5 seconds.
- **Performance**: Reusable table pool eliminates per-frame allocations in hot paths.
- **Performance**: O(1) lookup for known target frames instead of O(n) iteration.

### Fixed
- **Settings**: Added missing `minimap` default table to prevent nil reference errors.
- **Settings**: Minimap icon toggle now safely handles missing LibDBIcon.

## [2.3.0] - 2025-12-18
### Added
- **Proxy System**: Complete rewrite of the Cooldown Manager's frame handling.
    - **Shadow Mode**: Original Blizzard frames are now hidden but kept active to preserve game logic/tooltips.
    - **Proxies**: Custom, stable "Proxy Frames" now display the cooldown information, synced in real-time.
    - **Stability**: Resolves all issues with "floating" icons (e.g., Ravager) and layout jitter.
- **Live Restore**: Disabling the addon or specific features now instantly restores the original Blizzard frames to their native state without a reload.
- **Granular Toggles**: "Tracked Buffs" and "Tracked Bars" can now be toggled independently of the main "Cooldown Manager" (Essential/Utility) icons.
- **Timer Text**: Added support for displaying the numeric cooldown timer on proxies (scraped from native frames).

### Changed
- **Settings**: "Enable" checkbox for Cooldown Manager now only toggles the Essential/Utility bars, decoupling it from the Tracked Buffs/Bars.
- **Font Sizing**: Added explicit font size settings for Timer Text vs Stack Count for all viewers.

## [2.2.2] - 2025-12-16
### Added
- **Minimap Button**: Added a minimap button (LibDBIcon) with options to toggle it.
- **DataBroker Support**: Added LDB support for integration with Titan Panel, Bazooka, etc.

### Fixed
- **Minimap Button**: Fixed Right-Click interaction functionality (workaround for LibDBIcon limitation).
- **Settings Navigation**: Improved robustness of category detection when opening settings via Slash Command or LDB.

### Changed
- **Settings UI Layout**: Overhauled settings to use the native interface options tree structure instead of tabs.
- **Slash Command**: Updated `/ah` to open the integrated Settings panel instead of a standalone window.
- **Direct Navigation**: "Open Gameplay Enhancements" button now navigates directly to the correct WoW settings page (ID 42).

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
- **Class Resource Bars**: Universal support for secondary power bars (Combo Points, Holy Power, Chi, Arcane Charges, Soul Shards, Essence, Runes).
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
