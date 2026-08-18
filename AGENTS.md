# ActionHud – Agent Documentation

Technical reference for AI agents modifying this addon.

For shared patterns, library references, and development guides, see **[Mechanic/AGENTS.md](../Mechanic/AGENTS.md)**.

---

## CurseForge

| Item | Value |
|------|-------|
| **Project ID** | 1409478 |
| **Project URL** | https://www.curseforge.com/wow/addons/actionhud |
| **Files** | https://authors.curseforge.com/#/projects/1409478/files |

---

## Project Intent

A compact action bar HUD overlay that displays ability icons, cooldowns, and proc glows in a minimal footprint.

- **Action Bar Mirroring**: Dynamically synchronizes layout (rows, icons) with Blizzard's Edit Mode settings for Bar 1 and Bar 6.
- **Dynamic Layout**: Components automatically restack and update HUD height when modules or individual bars are toggled.
- Supports stance/form page swapping via `GetBonusBarOffset()`
- Uses Blizzard's opt-in action range events and native duration objects where available.
- **Midnight Compatibility**: ActionHud targets WoW 12.1 and treats protected values as opaque pass-through data. Combat testing remains required for every protected-API change.

### Key Midnight Patterns

1.  **Safe Wrappers**: Always use `Utils.GetActionCooldownSafe()`, `Utils.GetInventoryItemCooldownSafe()`, `Utils.GetActionDisplayCountSafe()`, etc., instead of global APIs. These handle `C_ActionBar`/`C_Item` table returns and secret values.
2.  **Safe Comparisons**: Use `Utils.SafeCompare(a, b, op)` for any numeric comparison involving values from game APIs (health, power, cooldowns).
3.  **Regression Tests**: Run `python Tests/run.py`; it compiles first-party Lua and executes the standalone protected-value tests.
4.  **Scoped Ignores**: Existing `-- @scan-ignore: midnight-*` comments document reviewed API boundaries; do not add one without verifying the call in combat.

---

## ⚠️ Temporarily Disabled Modules (Midnight API Stabilization)

The following modules are retained as source but are not loaded or packaged while Blizzard's cooldown-viewer APIs stabilize:

| Module | Status | Reason |
|--------|--------|--------|
| **Cooldown Manager** (Essential/Utility) | Disabled | `CooldownViewerSettings` and related APIs are unstable |
| **TrackedBuffs** | Disabled | Aura icon styling hooks unreliable |
| **TrackedDefensives** | Disabled | Secret value protection on aura APIs |

These features will be revisited in a future update once the APIs are more reliable.

---

## File Structure

| File | Purpose |
|------|---------|
| `ActionHud.lua` | Addon initialization, slash commands, frame logic |
| `Utils.lua` | Shared utility functions (safe API wrappers, fonts, Midnight compatibility) |
| `LayoutManager.lua` | Centralized module positioning and stack management |
| `ActionBars.lua` | Action bar grid (6×4 button frames) |
| `Resources.lua` | Health, Power, and Class Resource bars (individual visibility/height) |
| `Cooldowns/` | Dormant cooldown-viewer experiments; not listed in `ActionHud.toc` |
| `UnitFrames/UnitFrames.lua` | Optional custom secure unit frames for Player, Target, Target of Target, and Focus |
| `Trinkets.lua` | Dedicated module for tracking equipped trinket cooldowns |
| `Settings/init.lua` | Core settings setup, shared helpers, AceConfig registration |
| `Settings/ActionBars.lua` | Action Bars tab options |
| `Settings/Resources.lua` | Resource Bars tab options |
| `Settings/EssentialCooldowns.lua` | Dormant source; not listed in `ActionHud.toc` |
| `Settings/UtilityCooldowns.lua` | Dormant source; not listed in `ActionHud.toc` |
| `Settings/UnitFrames.lua` | Unit Frames tab options |
| `Settings/Trinkets.lua` | Trinkets tab options |
| `Settings/Layout.lua` | Layout/Stack order tab options |
| `ActionHud.toc` | Addon metadata and load order |

---

## Architecture

### Layout System

The HUD uses a centralized `LayoutManager` module that coordinates vertical stacking of all components.

**Stack Model:**
- Active stack modules (Resources, Action Bars, and optionally Trinkets) are treated as rows in a vertical stack
- Resources module handles Health, Power, and Class Resource bars
- Order is fully customizable via the Layout settings panel
- Cooldown-viewer modules are excluded from the active registry and load path

**Module Integration:**
Each stackable module implements:
- `CalculateHeight()` – Returns the module's rendered height
- `GetLayoutWidth()` – Returns the module's width
- `ApplyLayoutPosition()` – Positions the module based on LayoutManager's calculated Y offset

### Update Functions

| Function | Triggers | Purpose |
|----------|----------|---------|
| `UpdateAction` | `ACTIONBAR_SLOT_CHANGED` | Resolves the paged action ID, then delegates to `UpdateIcon` |
| `UpdateIcon` | `SPELL_UPDATE_ICON` | Re-reads spell ID and texture for the current slot; returns `true` when the icon changed so spell overrides (Slam → Heroic Strike) also refresh cooldown/state |
| `UpdateCooldown` | `SPELL_UPDATE_COOLDOWN` | Sets cooldown sweep, handles GCD vs real CD |
| `UpdateState` | `ACTIONBAR_UPDATE_STATE`, `SPELL_ACTIVATION_OVERLAY_*` | Usability, range, proc glows |

> **Spell overrides:** never cache an action's spell ID across events. A proc that overrides a slot (Slam → Heroic Strike) changes the backing spell without changing the slot, so `ACTIONBAR_SLOT_CHANGED` does not fire. `UpdateIcon` and `UpdateProc` both re-read it via `ResolveSpellID`, mirroring Blizzard's `ActionButton.lua:UpdateSpellAlert`, which re-reads `GetActionInfo` on every evaluation.
| `RefreshAll` | `PLAYER_ENTERING_WORLD`, `ACTIONBAR_PAGE_CHANGED` | Full recalculation of all slots |

### Cooldown Spark Logic (`SetDrawEdge`)

- **GCD**: Disabled (smooth dark sweep)
- **Short Lockouts (≤1.5s)**: Disabled (e.g., Skyriding buffer)
- **Real Cooldowns (>1.5s)**: Enabled (gold spark)
- **Charge Refill**: Enabled (shows next charge filling)

### Glow System

| Glow | Color | Width | Z-Order | Source |
|------|-------|-------|---------|--------|
| Proc | Yellow | 1px | +12 | `SPELL_ACTIVATION_OVERLAY_GLOW_*` events |
| Assist | Blue | 2px | +5 | `hooksecurefunc(AssistedCombatManager, "SetAssistedHighlightFrameShown", ...)` |

### Dormant Proxy Experiments (`Cooldowns/`)

This section describes retained historical experiments. None of these files are loaded by `ActionHud.toc` or included in CurseForge packages.

#### Cooldowns Module (Essential/Utility)
Uses a **"hide-only" visibility model** with custom proxy frames:

| Blizzard CVar | ActionHud Module | Result |
|---------------|------------------|--------|
| `cooldownViewerEnabled = false` | N/A | Both hidden |
| `cooldownViewerEnabled = true` | OFF | Blizzard visible |
| `cooldownViewerEnabled = true` | ON | ActionHud proxies visible |

**Key Design:**
1. Only call `SetShown(false)` on Blizzard frames - no reparenting
2. Query data directly from `C_Spell.GetSpellCooldown()`, `CooldownViewerSettings:GetDataProvider()`
3. Watch `cooldownViewerEnabled` CVar via `CVAR_UPDATE` for real-time toggling

#### TrackedBuffs (Style-Only Approach)

**Midnight (12.0) Compatibility:** TrackedBuffs uses a "style-only" approach. Blizzard's frames handle all aura data (protected APIs). ActionHud only applies visual styling.

| Blizzard Frame | ActionHud Module |
|----------------|------------------|
| `BuffIconCooldownViewer` | TrackedBuffs |

**Design:**
1. **No reparenting or positioning** – Use Blizzard's EditMode for position/size
2. Hook into Blizzard's native frames via `hooksecurefunc`:
   - `OnAcquireItemFrame` → Style individual icons as they're created
3. Style operations only:
   - Strip decorations (MaskTexture, overlay borders) via `SkinningReset`
   - Apply custom fonts for timers and stack counts
   - Crop icons with `SetTexCoord`

**Available Settings:**

| Setting | Description |
|---------|-------------|
| Style Tracked Buffs | Toggle styling on/off |
| Stack Count Font Size | Numeric font size for stack counts |
| Timer Font Size | Font size for cooldown timers (small/medium/large/huge) |

**Note:** Sizing and positioning are controlled via Blizzard's EditMode (ESC → Edit Mode). ActionHud does not manage placement for these frames.

#### TrackedDefensives (DISABLED in 12.0)

> **Note:** TrackedDefensives is disabled due to WoW 12.0's secret value protection on aura APIs. See `docs/aura-api-testing.md` for details.

**TrackedBuffs** is also dormant and not loaded.

#### UnitFrames Module

The active implementation creates optional `SecureUnitButtonTemplate` frames for Player, Target, Target of Target, and Focus. It does not reskin Blizzard frames. Frames and unit-scoped events are created only when the feature is enabled.

Blizzard frames can optionally be hidden while the custom frames are active and are restored when the feature is disabled.

**Available Settings:**

| Setting | Description |
|---------|-------------|
| Enable Unit Frame Styling | Master toggle |
| Hide Portraits | Remove circular portrait images |
| Hide Borders | Remove frame borders/decorations |
| Flat Bar Texture | Use solid color texture |
| Health Bar Height | Pixel height (5-40) |
| Mana/Power Bar Height | Pixel height (2-30) |
| Bar Width Scale | Scale multiplier (0.5-1.5) |
| Class Bar Height | Pixel height for class resources |
| Style Player/Target/Focus | Per-frame toggles |

**Note:** Requires `/reload` after changing settings.

**Known Limitations (Midnight 12.0):**

The "Always Show Text" feature for health/power values was shelved due to Midnight's secret value system. Key findings:

| Issue | Details |
|-------|---------|
| `UnitHealthPercent()` returns secret value | Even this "safe" API returns a secret value in instanced content |
| `bar:GetValue()` returns secret value | Cannot calculate percentage from bar values |
| Comparison crashes | Any `if percent > 0` or arithmetic on secret values crashes |
| Heal prediction bars | `UnitFrameHealPredictionBars_Update` uses `maxHealth` internally, causing cascading errors |

**Attempted Approaches (all failed):**
1. **pauseUpdates + Custom Overlay** - `UnitHealthPercent()` still returns secret values
2. **Hook SetBarText** - Runs after crash-prone code
3. **Replace UpdateTextString** - Still need safe values to display

**Future Follow-up:** Monitor Blizzard API changes in future patches. Blizzard may expose safe text APIs similar to how they added `UnitHealthPercent` (though it's not fully safe yet). Check for:
- New safe unit info APIs in patch notes
- Changes to `TextStatusBarMixin` behavior
- Community solutions from other addon authors

For now, text visibility defaults to Blizzard's hover behavior. Font styling (face/size) still works.

---

## SavedVariables

Stored in `ActionHudDB.profile`:

```lua
{
  iconWidth = 20,       -- pixels
  iconHeight = 15,      -- pixels
  cooldownFontSize = 6, -- pixels
  countFontSize = 6,    -- pixels
  opacity = 0.0,        -- 0.0-1.0
  procGlowAlpha = 1.0,  -- 0.0-1.0
  assistGlowAlpha = 1.0,-- 0.0-1.0
  xOffset = 0,          -- saved position
  yOffset = -220,       -- saved position
  locked = false,       -- draggable state
  
  -- Layout (managed by LayoutManager)
  layout = {
    stack = { "resources", "actionBars", "cooldowns" },
    gaps = { 4, 4, 0 },
  },
  
  -- Tracked Buffs (style-only, position via EditMode)
  styleTrackedBuffs = true,
  buffsCountFontSize = 10,
  buffsTimerFontSize = "medium",
  -- TrackedBars was removed from codebase due to API restrictions
  
  -- Unit Frames Reskin (Player/Target/Focus)
  ufEnabled = false,          -- Master toggle
  ufHidePortraits = true,     -- Hide circular portraits
  ufHideBorders = true,       -- Hide borders/decorations
  ufFlatBars = true,          -- Solid bar texture
  ufHealthHeight = 20,        -- Health bar height (pixels)
  ufManaHeight = 10,          -- Mana bar height (pixels)
  ufBarScale = 1.0,           -- Width scale multiplier
  ufClassBarHeight = 10,      -- Class resource bar height
  ufStylePlayer = true,       -- Style Player Frame
  ufStyleTarget = true,       -- Style Target Frame
  ufStyleFocus = true,        -- Style Focus Frame
}
```

---

## Slash Commands

- `/ah` or `/actionhud` – Opens the settings panel.
- `/ah debug` or `/ah record` – Toggles debug recording (logs buffered in memory).
- `/ah clear` – Clears the debug log buffer.
- `/ah dump` – Outputs tracked aura info to chat (if Cooldown Manager is active).

---

## Development Mode

ActionHud detects development mode via MechanicLib:

```lua
local MechanicLib = LibStub("MechanicLib-1.0", true)
local isDeveloper = MechanicLib and MechanicLib:IsEnabled()
```

When !Mechanic is installed:
- Debug settings appear in ActionHud options
- Debug logs forward to Mechanic console
- Use `/mech` to access full debug tools

The old DevMarker.lua pattern has been removed.

---

## Deep-Dive Documentation

For detailed implementation docs, see the `Docs/` folder:
- [Aura API Testing](Docs/aura-api-testing.md) – Midnight aura research, secret value behavior
- [Skinning Patterns](Docs/skinning-patterns.md) – Style-only approach for Blizzard frames

---

## Libraries

### FenCore Integration

FenCore is an optional dependency. `Utils.lua` uses its environment, secret, and table helpers when present and falls back to the minimal embedded FenUI utilities or local implementations. Legacy `Core/FenCoreCompat.lua` and `Core/init.lua` remain test/reference source but are not in the runtime load path.

### FenUI Integration

ActionHud uses FenUI.Utils for Midnight-safe API wrappers:
- `IsValueSecret` – Secret value detection
- `SafeCompare` – Secret-safe comparisons
- `GetSpellCooldownSafe`, `GetActionCooldownSafe`, etc. – Protected API wrappers

All FenUI usage includes fallback to basic implementations when FenUI is unavailable.

---

## Agent Guidelines

1. Maintain separation between runtime modules and the files under `Settings/`
2. Test stance/form bar swaps (Druid, Rogue) when modifying slot logic
3. Prefer smaller, focused modules over large monolithic files

---

## Tooling and Localization

### Standard Workflow

- **Testing and syntax validation**: install `lupa==2.8`, then run `python Tests/run.py` from the addon root.
- GitHub Actions runs the same command for pushes and pull requests.

### Localization (AceLocale-3.0)
ActionHud uses standard localization patterns. All UI strings must be wrapped in `L["KEY"]`.

- **Base Locale**: `Locales/enUS.lua`
- **Settings UI Pattern**:
  ```lua
  local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
  -- ...
  name = L["Lock Frame"],
  desc = L["Lock the HUD in place. Uncheck to drag."],
  ```
- **Adding Strings**: When adding new UI elements, update `Locales/enUS.lua` with the new key.

### Unit Testing
Protected-value wrappers, action cooldowns, unit-frame identity handling, scoped unit events, and layout-gap behavior are covered by the standalone files under `Tests/`.
- **Mocking**: The test environment mocks necessary WoW APIs (`GetBuildInfo`, `issecretvalue`, etc.).
- **Execution**: Run `python Tests/run.py` from the addon root.
