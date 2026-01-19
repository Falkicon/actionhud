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
- Hijacks Blizzard's CooldownViewer frames using a proxy system
- **Midnight Compatibility**: ActionHud is fully compatible with the "Royal" interpretive API model (Beta 5+). All systems use **Async Styling Injection** (`C_Timer.After(0)`) and native **Duration Objects** to ensure 100% stability in combat.

### Key Midnight Patterns

1.  **Safe Wrappers**: Always use `Utils.GetActionCooldownSafe()`, `Utils.GetInventoryItemCooldownSafe()`, `Utils.GetActionDisplayCountSafe()`, etc., instead of global APIs. These handle `C_ActionBar`/`C_Item` table returns and secret values.
2.  **Safe Comparisons**: Use `Utils.SafeCompare(a, b, op)` for any numeric comparison involving values from game APIs (health, power, cooldowns).
3.  **Deprecation Scanning**: Use the tool in `../ADDON_DEV/Tools/DeprecationScanner` to verify compatibility.
4.  **Scoped Ignores**: When a line is verified safe, use `-- @scan-ignore: midnight` to silence the scanner for the current game version.

---

## File Structure

| File | Purpose |
|------|---------|
| `ActionHud.lua` | Addon initialization, slash commands, frame logic |
| `Utils.lua` | Shared utility functions (safe API wrappers, fonts, Midnight compatibility) |
| `LayoutManager.lua` | Centralized module positioning and stack management |
| `ActionBars.lua` | Action bar grid (6×4 button frames) |
| `Resources.lua` | Health, Power, and Class Resource bars (individual visibility/height) |
| `Cooldowns/Manager.lua` | Centralized proxy pool, aura cache, Blizzard frame management |
| `Cooldowns/Cooldowns.lua` | Essential/Utility cooldown icons (custom proxies) |
| `Cooldowns/TrackedBuffs.lua` | Tracked Buffs reskin (hooks BuffIconCooldownViewer) - style-only approach |
| `Cooldowns/TrackedDefensives.lua` | External Defensives reskin (hooks ExternalDefensivesFrame) - **DISABLED in 12.0** |
| `UnitFrames/UnitFrames.lua` | Unit Frame reskin (PlayerFrame, TargetFrame, FocusFrame) |
| `Trinkets.lua` | Dedicated module for tracking equipped trinket cooldowns |
| `Settings/init.lua` | Core settings setup, shared helpers, AceConfig registration |
| `Settings/ActionBars.lua` | Action Bars tab options |
| `Settings/Resources.lua` | Resource Bars tab options |
| `Settings/Cooldowns.lua` | Cooldown Manager tab options |
| `Settings/Tracked.lua` | Tracked Abilities (Buffs/Defensives) tab options |
| `Settings/UnitFrames.lua` | Unit Frames tab options |
| `Settings/Trinkets.lua` | Trinkets tab options |
| `Settings/Layout.lua` | Layout/Stack order tab options |
| `ActionHud.toc` | Addon metadata and load order |

---

## Architecture

### Layout System

The HUD uses a centralized `LayoutManager` module that coordinates vertical stacking of all components.

**Stack Model:**
- All modules (Resources, ActionBars, Cooldowns) are treated as "rows" in a vertical stack
- Resources module handles Health, Power, and Class Resource bars
- Order is fully customizable via the Layout settings panel
- TrackedBuffs uses style-only approach (working); TrackedDefensives disabled in 12.0

**Module Integration:**
Each stackable module implements:
- `CalculateHeight()` – Returns the module's rendered height
- `GetLayoutWidth()` – Returns the module's width
- `ApplyLayoutPosition()` – Positions the module based on LayoutManager's calculated Y offset

### Update Functions

| Function | Triggers | Purpose |
|----------|----------|---------|
| `UpdateAction` | `ACTIONBAR_SLOT_CHANGED` | Updates icon texture, spell ID, charge count |
| `UpdateCooldown` | `SPELL_UPDATE_COOLDOWN` | Sets cooldown sweep, handles GCD vs real CD |
| `UpdateState` | `ACTIONBAR_UPDATE_STATE`, `SPELL_ACTIVATION_OVERLAY_*` | Usability, range, proc glows |
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

### The Proxy System (Cooldowns/)

ActionHud uses different strategies for different CooldownViewer components:

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

**TrackedBuffs** remains fully functional using a style-only approach.

#### UnitFrames Module (Style-Only Approach)

**Midnight (12.0) Compatibility:** Uses the same style-only approach for Player, Target, and Focus frames.

| Blizzard Frame | ActionHud Hook |
|----------------|----------------|
| `PlayerFrame` | `PlayerFrame_UpdateArt`, `PlayerFrame_UpdateStatus` |
| `TargetFrame` | `TargetFrame_Update`, `TargetFrame_CheckClassification` |
| `FocusFrame` | `FocusFrame:Update` |

**Design:**
1. Hook into Blizzard's unit frame update functions
2. Style operations only:
   - Hide portrait textures (circular character images)
   - Hide border/decoration textures
   - Apply flat solid bar texture
   - Adjust health/mana bar height and width
   - Style class resource bars (combo points, holy power, etc.)

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

ActionHud uses FenCore for pure logic domains with graceful fallbacks:

- **Math.Clamp**: Used by settings validators in `Core/init.lua`
- All FenCore usage is wrapped via `Core/FenCoreCompat.lua` for optional dependency

The FenCoreCompat module provides fallback implementations when FenCore is not available, ensuring ActionHud works standalone or with FenCore.

**Verify FenCore integration:**
```bash
# Sync FenCore library (if needed)
mech call libs.sync -i '{"addon": "ActionHud"}'

# Run sandbox tests
mech call sandbox.test -i '{"addon": "ActionHud"}'
```

### FenUI Integration

ActionHud uses FenUI.Utils for Midnight-safe API wrappers:
- `IsValueSecret` – Secret value detection
- `SafeCompare` – Secret-safe comparisons
- `GetSpellCooldownSafe`, `GetActionCooldownSafe`, etc. – Protected API wrappers

All FenUI usage includes fallback to basic implementations when FenUI is unavailable.

---

## Agent Guidelines

1. Maintain separation between `Core.lua` (logic) and `SettingsUI.lua` (config)
2. Test stance/form bar swaps (Druid, Rogue) when modifying slot logic
3. Prefer smaller, focused modules over large monolithic files

---

## Tooling and Localization

### Standard Workflows
- **Linting**: `mech call addon.lint -i '{"addon": "ActionHud"}'`
- **Formatting**: `mech call addon.format -i '{"addon": "ActionHud"}'` (uses StyLua)
- **Testing**: `mech call sandbox.test -i '{"addon": "ActionHud"}'`

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
Critical utility functions in `Utils.lua` (especially Midnight-safe comparisons) are covered by unit tests in `Tests/test_utils.lua`.
- **Mocking**: The test environment mocks necessary WoW APIs (`GetBuildInfo`, `issecretvalue`, etc.).
- **Execution**: Run via the `run_tests` tool or manually with a Lua interpreter if available.
