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
  - Essential when working with `Cooldowns/` proxy system and frame hijacking
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

## Architecture

### Layout System

The HUD uses a centralized `LayoutManager` module that coordinates vertical stacking of all components:

**Stack Model:**
- All modules (TrackedBuffs, Resources, ActionBars, Cooldowns) are treated as "rows" in a vertical stack
- Order is fully customizable via the Layout settings panel
- Gaps between modules are defined independently for each adjacent pair
- TrackedBars is a "sidecar" module with independent X/Y offset positioning

**Data Structure** (in `ActionHudDB.profile.layout`):
```lua
{
    stack = { "trackedBuffs", "resources", "actionBars", "cooldowns" },
    gaps = { 10, 4, 0, 2 },  -- gaps[i] = gap AFTER stack[i]
}
```

**Module Integration:**
Each stackable module implements:
- `CalculateHeight()` – Returns the module's rendered height
- `GetLayoutWidth()` – Returns the module's width
- `ApplyLayoutPosition()` – Positions the module based on LayoutManager's calculated Y offset

**Update Flow:**
1. `LayoutManager:TriggerLayoutUpdate()` is called
2. LayoutManager queries each module's height via `CalculateHeight()`
3. LayoutManager calculates cumulative Y positions
4. LayoutManager updates main container size
5. Each module's `ApplyLayoutPosition()` is called to position itself

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

### The Proxy System (Cooldowns/)

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

## Performance Learnings

### File Structure Impact

Breaking large `.lua` files into smaller modules (e.g., extracting `LayoutManager.lua` from a monolithic file) significantly improved Tracked Bars display latency from ~10 seconds to instant. Likely causes:

- **Incremental parsing**: Smaller files parse/execute incrementally vs. waiting for one large file
- **Module initialization timing**: AceAddon modules fire `OnEnable` independently
- **Reduced scope complexity**: Fewer locals per file = faster compilation
- **TOC load order**: Critical frames can display while later files still load

### API Quirks: GCD Category Misreporting

Some abilities report incorrect `activeCategory` from `C_Spell.GetSpellCooldown()` for 1-2 seconds after cast:

**Example: Demoralizing Shout (spellID 1160)**
- Has a 45-second cooldown
- Initially returns `activeCategory = 133` (GCD category) despite 45s duration
- After ~1-2 seconds, switches to `activeCategory = nil`

**Solution:** Don't trust `activeCategory` alone. Check duration threshold:

```lua
local GCD_THRESHOLD = 1.5
local isActualGCD = cdInfo.activeCategory == Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY
                   and cdInfo.duration <= GCD_THRESHOLD
```

This ensures abilities with real cooldowns (>1.5s) are displayed immediately, regardless of the reported category.

### Ability-Specific Delays (Tracked Buffs/Bars)

Some abilities may have slight delays for their associated **buff tracking** (not cooldown display). Causes:

- Buff spell ID differs from the cast spell ID
- `linkedSpellIDs` needing resolution from the DataProvider
- Abilities that apply debuffs to enemies rather than buffs to player

### Memory Optimization Patterns (v2.5.2)

Key garbage creation sources in WoW addons and how to avoid them:

**Table Allocations:**
- `return {}` on failure paths creates new tables every call → Use shared `EMPTY_TABLE` constant
- Tables created inside functions → Move to module level and reuse with `wipe()`
- Intermediate data tables `{ key = value }` → Store properties directly on existing objects

**String Allocations:**
- `string.format()` in debug logging evaluates BEFORE the function call → Remove from hot paths or guard with explicit checks
- String concatenation `"prefix_" .. id` → Use numeric keys directly where possible

**API Call Patterns:**
- Blizzard APIs like `C_Spell.GetSpellCooldown()` return new tables each call → Cache results at frame level
- `addon:GetModule("name")` lookups → Cache module references at enable time
- Duplicate API calls in same function → Store result in local and reuse

**Cache Management:**
- Texture/spell caches should have periodic cleanup (e.g., wipe every 60s)
- Frame-level caches (0.016s TTL) reduce API calls within same frame
- Never wipe caches in hot paths (UNIT_AURA handlers, etc.)

**Expected Behavior:**
- Memory will grow between GC cycles - this is normal Lua behavior
- Watch for memory returning to baseline after GC runs
- True leaks: memory never returns to baseline, grows indefinitely

## Agent Guidelines

1. Maintain separation between `Core.lua` (logic) and `SettingsUI.lua` (config)
2. Test stance/form bar swaps (Druid, Rogue) when modifying slot logic
3. Prefer smaller, focused modules over large monolithic files for better load performance

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
