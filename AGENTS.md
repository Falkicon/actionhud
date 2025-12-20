# ActionHud – Agent Documentation

Technical reference for AI agents modifying this addon.

For shared patterns, documentation requirements, and library management, see **[ADDON_DEV/AGENTS.md](../../ADDON_DEV/AGENTS.md)**.

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

- Displays a 6×4 grid mapped to Action Bar 1 (slots 1-12) and Action Bar 2 (slots 61-72)
- Supports stance/form page swapping via `GetBonusBarOffset()`
- Hijacks Blizzard's CooldownViewer frames using a proxy system

---

## File Structure

| File | Purpose |
|------|---------|
| `Core.lua` | Addon initialization, debug system, slash commands |
| `Utils.lua` | Shared utility functions (safe API wrappers, fonts) |
| `LayoutManager.lua` | Centralized module positioning and stack management |
| `ActionBars.lua` | Action bar grid (6×4 button frames) |
| `Resources.lua` | Health, Power, and Class Resource bars |
| `Cooldowns/Manager.lua` | Centralized proxy pool, aura cache, Blizzard frame management |
| `Cooldowns/Cooldowns.lua` | Essential/Utility cooldown icons |
| `Cooldowns/TrackedBars.lua` | Tracked Bar proxies (status bar style, sidecar positioning) |
| `Cooldowns/TrackedBuffs.lua` | Tracked Buff proxies (icon style) |
| `SettingsUI.lua` | Blizzard Settings API integration (no external libs) |
| `ActionHud.toc` | Addon metadata and load order |

---

## Architecture

### Layout System

The HUD uses a centralized `LayoutManager` module that coordinates vertical stacking of all components.

**Stack Model:**
- All modules (TrackedBuffs, Resources, ActionBars, Cooldowns) are treated as "rows" in a vertical stack
- Resources module handles Health, Power, and Class Resource bars
- Order is fully customizable via the Layout settings panel
- TrackedBars is a "sidecar" module with independent X/Y offset positioning

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

ActionHud uses a **"hide-only" visibility model** for Blizzard's CooldownViewer frames:

| Blizzard CVar | ActionHud Module | Result |
|---------------|------------------|--------|
| `cooldownViewerEnabled = false` | N/A | Both hidden |
| `cooldownViewerEnabled = true` | OFF | Blizzard visible |
| `cooldownViewerEnabled = true` | ON | ActionHud proxies visible |

**Key Design:**
1. Only call `SetShown(false)` on Blizzard frames - no reparenting
2. Query data directly from `C_Spell.GetSpellCooldown()`, `CooldownViewerSettings:GetDataProvider()`
3. Watch `cooldownViewerEnabled` CVar via `CVAR_UPDATE` for real-time toggling

For detailed Blizzard frame structure and API reference, see `Docs/proxy-system.md`.

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
    stack = { "trackedBuffs", "resources", "actionBars", "cooldowns" },
    gaps = { 10, 4, 0, 2 },
  },
  
  -- TrackedBars sidecar positioning
  tbXOffset = 100,      -- X offset from HUD center
  tbYOffset = 0,        -- Y offset from HUD center
}
```

---

## Slash Commands

- `/actionhud` – Outputs all button states to the error frame

---

## Debugging

- **Slash Command**: `/actionhud` outputs diagnostic info
- **Globals**: `ActionHudFrame` (main window), `ActionHudDB` (saved variables)

---

## Deep-Dive Documentation

For detailed implementation docs, see the `Docs/` folder:
- [Proxy System](Docs/proxy-system.md) – Blizzard frame structure, CooldownViewer API reference
- [Performance Learnings](Docs/performance.md) – Memory optimization, API quirks, GCD handling

---

## Agent Guidelines

1. Maintain separation between `Core.lua` (logic) and `SettingsUI.lua` (config)
2. Test stance/form bar swaps (Druid, Rogue) when modifying slot logic
3. Prefer smaller, focused modules over large monolithic files
