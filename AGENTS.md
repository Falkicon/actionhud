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
| `Utils.lua` | Shared utility functions (safe API wrappers, fonts, Midnight compatibility) |
| `LayoutManager.lua` | Centralized module positioning and stack management |
| `ActionBars.lua` | Action bar grid (6×4 button frames) |
| `Resources.lua` | Health, Power, and Class Resource bars |
| `Cooldowns/Manager.lua` | Centralized proxy pool, aura cache, Blizzard frame management |
| `Cooldowns/Cooldowns.lua` | Essential/Utility cooldown icons (custom proxies) |
| `Cooldowns/TrackedBars.lua` | Tracked Bars reskin (hooks BuffBarCooldownViewer, sidecar positioning) |
| `Cooldowns/TrackedBuffs.lua` | Tracked Buffs reskin (hooks BuffIconCooldownViewer) |
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

#### TrackedBuffs/TrackedBars (Style-Only Approach)

**Midnight (12.0) Compatibility:** These modules use a "style-only" approach. Blizzard's frames handle all aura data (protected APIs). ActionHud only applies visual styling.

| Blizzard Frame | ActionHud Module |
|----------------|------------------|
| `BuffIconCooldownViewer` | TrackedBuffs |
| `BuffBarCooldownViewer` | TrackedBars |

**Design:**
1. **No reparenting or positioning** – Use Blizzard's EditMode for position/size
2. Hook into Blizzard's native frames via `hooksecurefunc`:
   - `RefreshLayout` → Re-apply styling after Blizzard updates
   - `OnAcquireItemFrame` → Style individual icons/bars as they're created
3. Style operations only:
   - Strip decorations (MaskTexture, overlay borders)
   - Apply custom fonts for timers and stack counts
   - Crop icons with `SetTexCoord`

**Available Settings:**

| Setting | Description |
|---------|-------------|
| Style Tracked Buffs | Toggle styling on/off |
| Style Tracked Bars | Toggle styling on/off |
| Stack Count Font Size | Numeric font size for stack counts |
| Timer Font Size | Font size for cooldown timers (small/medium/large/huge) |
| Compact Mode (Bars) | Hide cooldown bars, show icons only |
| Timer on Icon (Bars) | Display timer text centered on icon (stack count moves to bottom-right) |

**Note:** Sizing and positioning are controlled via Blizzard's EditMode (ESC → Edit Mode). ActionHud does not manage placement for these frames.

**Midnight Compatibility Notes:**
- Compact Mode and Timer on Icon are style-only operations (LOW risk) - tested and working

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
    stack = { "resources", "actionBars", "cooldowns" },
    gaps = { 4, 4, 0 },
  },
  
  -- Tracked Abilities (style-only, position via EditMode)
  styleTrackedBuffs = true,
  styleTrackedBars = true,
  trackedCountFontSize = 10,
  trackedTimerFontSize = "medium",
  
  -- TrackedBars Compact Mode
  barsCompactMode = false,    -- Hide bars, show icons only
  barsTimerOnIcon = false,    -- Move timer text on top of icon
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
