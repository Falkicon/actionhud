# ActionHud — Agent Documentation

Technical reference for AI agents modifying this addon.

## File Structure

| File | Purpose |
|------|---------|
| `Core.lua` | Frame creation, event handling, state updates. |
| `SettingsUI.lua` | Blizzard Settings API integration (no external libs). |
| `ActionHud.toc` | Addon metadata and load order. |

## Architecture

### Design Principles
- **No External Libraries**: Pure WoW API for performance and compatibility.
- **Event-Driven**: Never uses `OnUpdate` polling. Listens to specific events.
- **Static Frame Pool**: 24 button frames created once at load, reused forever.

### Slot Mapping
Displays a 6×4 grid mapped to:
- **Row 1-2**: Action Bar 1, slots 1-12
- **Row 3-4**: Action Bar 2, slots 61-72

Slots are stored in `CFG.slots` and support stance/form page swapping via `GetBonusBarOffset()`.

## Core Logic (Core.lua)

### Update Functions
| Function | Triggers | Purpose |
|----------|----------|---------|
| `UpdateAction` | `ACTIONBAR_SLOT_CHANGED` | Updates icon texture, spell ID, charge count. |
| `UpdateCooldown` | `SPELL_UPDATE_COOLDOWN` | Sets cooldown sweep, handles GCD vs real CD. |
| `UpdateState` | `ACTIONBAR_UPDATE_STATE`, `SPELL_ACTIVATION_OVERLAY_*` | Usability, range, proc glows. |
| `RefreshAll` | `PLAYER_ENTERING_WORLD`, `ACTIONBAR_PAGE_CHANGED` | Full recalculation of all slots. |

### Cooldown Spark Logic (`SetDrawEdge`)
- **GCD**: Disabled (smooth dark sweep).
- **Short Lockouts (≤1.5s)**: Disabled (e.g., Skyriding buffer).
- **Real Cooldowns (>1.5s)**: Enabled (gold spark).
- **Charge Refill**: Enabled (shows next charge filling).

### Glow System
| Glow | Color | Width | Z-Order | Source |
|------|-------|-------|---------|--------|
| Proc | Yellow | 1px | +12 | `SPELL_ACTIVATION_OVERLAY_GLOW_*` events |
| Assist | Blue | 2px | +5 | `hooksecurefunc(AssistedCombatManager, "SetAssistedHighlightFrameShown", ...)` |

Opacity for both is configurable via `CFG.procGlowAlpha` and `CFG.assistGlowAlpha`.

## Settings (SettingsUI.lua)

Uses Blizzard's `Settings.RegisterVerticalLayoutCategory` API (Retail 10.0+).

### Saved Variables
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
}
```

### Opacity Slider Pattern
UI displays integers 0-100. Internally stored as 0.0-1.0:
```lua
GetValue: return math.floor(profile.value * 100 + 0.5)
SetValue: profile.value = sliderValue / 100
```

## Debugging

- **Slash Command**: `/actionhud` outputs all button states to the error frame.
- **Globals**: `ActionHudFrame` (main window), `ActionHudDB` (saved variables).

## Future Considerations (12.0 Midnight)

WoW 12.0 may introduce "Secret Values" that block numeric comparisons during combat.
- Current risk: `count > 1` comparisons may error.
- Mitigation: Use `issecretvalue()` checks or Boolean states if needed.

---

**Agent Guidelines**:
1. Maintain separation between `Core.lua` (logic) and `SettingsUI.lua` (config).
2. Do not add external dependencies (no Ace3, LibStub, etc.).
3. Test stance/form bar swaps (Druid, Rogue) when modifying slot logic.
