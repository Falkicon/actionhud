# ActionHud Development Status

**Last Updated:** 2026-01-05

## Current State Summary

### Working Modules
| Module | Status | Notes |
|--------|--------|-------|
| ActionBars | Working | Core functionality |
| Resources | Working | Health/Power/Class bars |
| Cooldowns | Working | Essential/Utility cooldowns |
| TrackedBuffs | Working | Style-only approach (hooks BuffIconCooldownViewer) |
| Trinkets | Working | Dedicated trinket tracking |
| UnitFrames | Working | Player/Target/Focus frames |
| LayoutManager | Working | Vertical stacking system |

### Disabled Modules
| Module | Status | Reason |
|--------|--------|--------|
| TrackedDefensives | **DISABLED** | Hooks cause taint, APIs blocked in 12.0 |
| DefensiveTracker | **DISABLED** | Test module - retained for future API testing |

---

## WoW 12.0 (Midnight) API Findings

### Secret Value Protection on Auras

Exhaustive testing confirmed **NO API approach works** for tracking secret-valued buffs in combat:

| API | Result in Combat |
|-----|------------------|
| `GetPlayerAuraBySpellID` | Returns `nil` for secret buffs |
| `GetAuraSlots` | **Blocked** (pcall fails) |
| `GetBuffDataByIndex` | **Blocked** (pcall fails) |
| `UNIT_AURA addedAuras` | Fields (`isHelpful`, `spellId`) are SECRET |
| Hooks on CooldownViewer | Causes taint propagation |

**Documentation:** See `docs/aura-api-testing.md` for full test matrix.

### What Still Works

- **Style-only hooks** on Blizzard frames (TrackedBuffs uses this)
- **Blizzard's CooldownViewer** displays tracked buffs correctly
- **EditMode positioning** for Tracked Buffs frames

---

## Pending/Waiting

### Waiting for Blizzard
- API changes that would allow addon access to aura data in combat
- Official guidance on addon patterns for tracked buff display
- Possible new safe APIs in future patches

### Future Considerations
- Monitor Blizzard API changes each patch
- TrackedDefensives could be restored if APIs become accessible
- Consider style-only approach for ExternalDefensivesFrame (if viable)

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `Cooldowns/TrackedBuffs.lua` | Working style-only buff icon styling |
| `Cooldowns/TrackedDefensives.lua` | Disabled stub module |
| `Cooldowns/DefensiveTracker.lua` | Disabled test harness (keep for future API testing) |
| `Cooldowns/SkinningReset.lua` | Centralized decoration stripping |
| `docs/aura-api-testing.md` | Exhaustive API test documentation |
