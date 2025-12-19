# Changelog

All notable changes to this project will be documented in this file.


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
