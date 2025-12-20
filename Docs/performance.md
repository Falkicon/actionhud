# ActionHud Performance – Deep Dive

Performance learnings and optimization patterns from ActionHud development.

---

## File Structure Impact

Breaking large `.lua` files into smaller modules (e.g., extracting `LayoutManager.lua` from a monolithic file) significantly improved Tracked Bars display latency from ~10 seconds to instant. Likely causes:

- **Incremental parsing**: Smaller files parse/execute incrementally vs. waiting for one large file
- **Module initialization timing**: AceAddon modules fire `OnEnable` independently
- **Reduced scope complexity**: Fewer locals per file = faster compilation
- **TOC load order**: Critical frames can display while later files still load

---

## API Quirks: GCD Category Misreporting

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

---

## Ability-Specific Delays (Tracked Buffs/Bars)

Some abilities may have slight delays for their associated **buff tracking** (not cooldown display). Causes:

- Buff spell ID differs from the cast spell ID
- `linkedSpellIDs` needing resolution from the DataProvider
- Abilities that apply debuffs to enemies rather than buffs to player

---

## Memory Optimization Patterns (v2.5.2)

Key garbage creation sources in WoW addons and how to avoid them:

### Table Allocations

- `return {}` on failure paths creates new tables every call → Use shared `EMPTY_TABLE` constant
- Tables created inside functions → Move to module level and reuse with `wipe()`
- Intermediate data tables `{ key = value }` → Store properties directly on existing objects

### String Allocations

- `string.format()` in debug logging evaluates BEFORE the function call → Remove from hot paths or guard with explicit checks
- String concatenation `"prefix_" .. id` → Use numeric keys directly where possible

### API Call Patterns

- Blizzard APIs like `C_Spell.GetSpellCooldown()` return new tables each call → Cache results at frame level
- `addon:GetModule("name")` lookups → Cache module references at enable time
- Duplicate API calls in same function → Store result in local and reuse

### Cache Management

- Texture/spell caches should have periodic cleanup (e.g., wipe every 60s)
- Frame-level caches (0.016s TTL) reduce API calls within same frame
- Never wipe caches in hot paths (UNIT_AURA handlers, etc.)

---

## Expected Memory Behavior

- Memory will grow between GC cycles - this is normal Lua behavior
- Watch for memory returning to baseline after GC runs
- True leaks: memory never returns to baseline, grows indefinitely

---

## Midnight (12.0) Considerations

WoW 12.0 (Midnight) may introduce "Secret Values" that block numeric comparisons during combat.

- Current risk: `count > 1` comparisons may error
- Mitigation: Use `issecretvalue()` checks or Boolean states if needed
