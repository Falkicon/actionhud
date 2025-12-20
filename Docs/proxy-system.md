# ActionHud Proxy System – Deep Dive

Detailed documentation for the CooldownViewer proxy architecture.

---

## Blizzard Frame Structure (Reference)

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

---

## Getting Cooldown Data

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

---

## Why Not Style Blizzard Frames Directly

Blizzard's CooldownViewer frames inherit from `UIParentManagedFrameMixin` and `GridLayoutFrameMixin` which:
- Recalculate position on every `OnShow` event
- Override size/position via `Layout()` calls
- Persist state through EditMode serialization

Any custom styling gets constantly overwritten. The proxy approach avoids fighting these systems.

---

## Key Design Decisions

1. **Simple Hide/Show**: We only call `SetShown(false)` on Blizzard frames - no reparenting, no alpha changes, no mouse disabling
2. **Direct API Queries**: Proxies get data directly from `C_Spell.GetSpellCooldown()`, `C_Spell.GetSpellCharges()`, `CooldownViewerSettings:GetDataProvider()` - not scraped from hidden frames
3. **Event-Driven Updates**: Uses `SPELL_UPDATE_COOLDOWN`, `UNIT_AURA`, `PLAYER_TOTEM_UPDATE` events instead of OnUpdate polling
4. **Real-time Configuration Detection**: Watches `cooldownViewerEnabled` CVar via `CVAR_UPDATE` and `CVarCallbackRegistry` to instantly toggle proxies when Blizzard settings change
5. **Clean Restoration**: When disabled, a single `SetShown(true)` restores Blizzard's native UI instantly.
