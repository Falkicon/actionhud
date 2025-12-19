# ActionHud – Agent Documentation

Technical reference for AI agents modifying this addon.

## External References

### Development Documentation
For comprehensive addon development guidance, consult these resources:

- **[ADDON_DEV/AGENTS.md](../../ADDON_DEV/AGENTS.md)** – Library index, automation scripts, dependency chains
- **[Addon Development Guide](../../ADDON_DEV/Addon_Dev_Guide/)** – Full documentation covering:
  - Core principles, project structure, TOC best practices
  - UI engineering, configuration UI, combat lockdown
  - Performance optimization, API resilience
  - Debugging, packaging/release workflow
  - Midnight (12.0) compatibility and secret values

### Blizzard UI Source Code
For reverse-engineering, hijacking, or modifying official Blizzard UI frames:

- **[wow-ui-source-live](../../wow-ui-source-live/)** – Official Blizzard UI addon code
  - Use this to understand frame hierarchies, event patterns, and protected frame behavior
  - Essential when working with `Cooldowns.lua` proxy system and frame hijacking
  - Reference for standard UI templates and widget implementations

---

## Project Intent

A compact action bar HUD overlay that displays ability icons, cooldowns, and proc glows in a minimal footprint.

- Displays a 6×4 grid mapped to Action Bar 1 (slots 1-12) and Action Bar 2 (slots 61-72)
- Supports stance/form page swapping via `GetBonusBarOffset()`
- Hijacks Blizzard's CooldownViewer frames using a proxy system

## Constraints

- Must work on Retail 11.0+
- Uses Ace3 framework (AceAddon, AceDB, AceConfig)
- Event-driven design – never uses `OnUpdate` polling
- Static frame pool – 24 button frames created once at load, reused forever

## File Structure

| File | Purpose |
|------|---------|
| `Core.lua` | Frame creation, event handling, state updates |
| `Cooldowns.lua` | Cooldown Manager (Proxy System, Hijacking, Layout) |
| `SettingsUI.lua` | Blizzard Settings API integration (no external libs) |
| `ActionHud.toc` | Addon metadata and load order |

## Architecture

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

Opacity configurable via `CFG.procGlowAlpha` and `CFG.assistGlowAlpha`.

### The Proxy System (Cooldowns.lua)

ActionHud uses a **"hide-only" visibility model** that is minimally invasive to Blizzard's UI:

**Visibility States:**

| Blizzard CVar | ActionHud Module | Result |
|---------------|------------------|--------|
| `cooldownViewerEnabled = false` | N/A | Both hidden, ActionHud settings greyed out |
| `cooldownViewerEnabled = true` | OFF | Blizzard frames visible, ActionHud proxies hidden |
| `cooldownViewerEnabled = true` | ON | Blizzard frames hidden, ActionHud proxies visible |

**Key Design Decisions:**

1. **Simple Hide/Show**: We only call `SetShown(false)` on Blizzard frames - no reparenting, no alpha changes, no mouse disabling
2. **Direct API Queries**: Proxies get data directly from `C_Spell.GetSpellCooldown()`, `C_Spell.GetSpellCharges()`, `CooldownViewerSettings:GetDataProvider()` - not scraped from hidden frames
3. **Event-Driven Updates**: Uses `SPELL_UPDATE_COOLDOWN`, `UNIT_AURA`, `PLAYER_TOTEM_UPDATE` events instead of OnUpdate polling
4. **Clean Restoration**: When disabled, a single `SetShown(true)` restores Blizzard's native UI instantly

**Blizzard Frame Structure (Reference):**

```
EssentialCooldownViewer / UtilityCooldownViewer
├── Inherits: UIParentBottomManagedFrameTemplate, EditModeCooldownViewerSystemTemplate, GridLayoutFrame
├── .itemFramePool - Pool of CooldownViewerCooldownItemMixin frames
│   └── Item Frame
│       ├── .Icon (Texture)
│       ├── .Cooldown (CooldownFrame)
│       └── .ChargeCount.Current (FontString)

BuffIconCooldownViewer
├── Inherits: Same as above
├── .itemFramePool - Pool of CooldownViewerBuffIconItemMixin frames
│   └── Item Frame
│       ├── .Icon (Texture)
│       ├── .Cooldown (CooldownFrame, reverse=true)
│       └── .Applications.Applications (FontString)

BuffBarCooldownViewer / TrackedBarCooldownViewer
├── .itemFramePool - Pool of CooldownViewerBuffBarItemMixin frames
│   └── Item Frame
│       ├── .Icon.Icon (Texture)
│       ├── .Bar (StatusBar)
│       │   ├── .Name (FontString)
│       │   ├── .Duration (FontString)
│       │   └── .Pip (Texture)
│       └── .Icon.Applications (FontString)
```

**Getting Cooldown Data:**

```lua
-- Get list of tracked spells for a category
local category = Enum.CooldownViewerCategory.Essential  -- or Utility, TrackedBuff, TrackedBar
local cooldownIDs = CooldownViewerSettings:GetDataProvider():GetOrderedCooldownIDsForCategory(category)

-- Get info for a specific cooldown ID
local info = CooldownViewerSettings:GetDataProvider():GetCooldownInfoForID(cooldownID)
-- info.spellID, info.overrideSpellID, info.linkedSpellIDs, etc.

-- Query spell data directly
local cdInfo = C_Spell.GetSpellCooldown(spellID)
local chargeInfo = C_Spell.GetSpellCharges(spellID)
local texture = C_Spell.GetSpellTexture(spellID)
local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
```

**Why Not Style Blizzard Frames Directly:**

Blizzard's CooldownViewer frames inherit from `UIParentManagedFrameMixin` and `GridLayoutFrameMixin` which:
- Recalculate position on every `OnShow` event
- Override size/position via `Layout()` calls
- Persist state through EditMode serialization

Any custom styling gets constantly overwritten. The proxy approach avoids fighting these systems.

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
}
```

**Opacity Slider Pattern**: UI displays integers 0-100. Internally stored as 0.0-1.0:

```lua
GetValue: return math.floor(profile.value * 100 + 0.5)
SetValue: profile.value = sliderValue / 100
```

## Slash Commands

- `/actionhud` – Outputs all button states to the error frame

## Debugging

- **Slash Command**: `/actionhud` outputs diagnostic info
- **Globals**: `ActionHudFrame` (main window), `ActionHudDB` (saved variables)

## Future Considerations

WoW 12.0 (Midnight) may introduce "Secret Values" that block numeric comparisons during combat.

- Current risk: `count > 1` comparisons may error
- Mitigation: Use `issecretvalue()` checks or Boolean states if needed

## Agent Guidelines

1. Maintain separation between `Core.lua` (logic) and `SettingsUI.lua` (config)
2. Test stance/form bar swaps (Druid, Rogue) when modifying slot logic

## Documentation Requirements

**Always update documentation when making changes:**

### CHANGELOG.md
Update the changelog for any change that:
- Adds new features or functionality
- Fixes bugs or issues
- Changes existing behavior
- Modifies settings or configuration options
- Improves performance or stability

**Format** (Keep a Changelog style):
```markdown
## [Version] - YYYY-MM-DD
### Added
- New features

### Changed
- Changes to existing functionality

### Fixed
- Bug fixes

### Removed
- Removed features
```

### README.md
Update the README when:
- Adding new features that users should know about
- Changing slash commands or settings
- Modifying installation or usage instructions
- Adding new dependencies or requirements

**Key sections to review**: Features, Slash Commands, Configuration, Technical Notes

## Library Management

This addon manages its libraries using `update_libs.ps1` located in `Interface\ADDON_DEV`.
**DO NOT** manually update libraries in `Libs`.
Instead, if you need to update libraries, run:
`powershell -File "c:\Program Files (x86)\World of Warcraft\_retail_\Interface\ADDON_DEV\update_libs.ps1"`
