# Aura API Testing Matrix

Testing different approaches to read player auras in Midnight (12.0) with secret values.

**Test Spell:** Phalanx - Warrior buff from Thunderclap
- **Talent/Ability ID:** 1269312 (wowhead link)
- **Buff Spell ID:** 1278009 (actual aura.spellId in aura data)

> **CRITICAL DISCOVERY:** The spell ID shown on Wowhead for a talent/ability is often NOT
> the same as the spellId returned in aura data. Always verify by dumping actual aura cache.

## Test Approaches

| # | Method | Description |
|---|--------|-------------|
| 1 | GetAuraSlots + select() | Our implementation mirroring AuraUtil.lua |
| 2 | GetBuffDataByIndex | Simple index loop 1-40 |
| 3 | AuraUtil.ForEachAura | Blizzard's helper (usePackedAura=true) |
| 4 | GetPlayerAuraBySpellID | Direct lookup by spell ID |
| 5 | UNIT_AURA incremental | Uses updateInfo.addedAuras/removedAuras |

## Test Results

### Test Run 1: 2026-01-04 (Wrong Spell ID)

**Environment:** Beta, open world
**Issue:** Initially tested with spell ID 1269312 (talent ID), which is different from buff ID 1278009

| # | Out of Combat | In Combat | Notes |
|---|---------------|-----------|-------|
| 1 | N (6 auras) | N | Found auras but wrong ID |
| 2 | N (6 auras) | N | Found auras but wrong ID |
| 3 | N (6 auras) | N | Found auras but wrong ID |
| 4 | N | N | Wrong ID to look up |
| 5 | N (6 cached) | N | Wrong ID to look up |

**Key Finding:** All 5 methods found 6 auras consistently - the APIs work!
The issue was looking for the wrong spell ID.

### Test Run 2: 2026-01-04 (Correct Spell ID 1278009)

**Environment:** Beta, open world

| # | Out of Combat | In Combat (no buff) | In Combat (with buff) | Notes |
|---|---------------|---------------------|----------------------|-------|
| 1 | Y | E (pcall fail) | E (pcall fail) | GetAuraSlots blocked in combat! |
| 2 | Y | N (10 auras) | N (10 auras) | Finds auras but NOT Phalanx in combat |
| 3 | Y | N (10 auras) | N (10 auras) | Same as #2 - secret buff hidden |
| 4 | Y | N (none) | N (none) | Direct lookup fails for this spell |
| 5 | N | N | N | addedAuras fields also SECRET |

**CRITICAL FINDINGS:**
1. `GetAuraSlots` is **blocked in combat** (pcall fails)
2. `GetBuffDataByIndex` and `AuraUtil.ForEachAura` work in combat BUT **don't return secret-valued buffs like Phalanx**
3. `GetPlayerAuraBySpellID` doesn't work for this specific spell in combat
4. **UNIT_AURA incremental ALSO FAILS** - addedAuras fields (isHelpful, spellId) are SECRET
   - Note: May briefly work for ~1 second when entering combat, then fails
   - Always has bugs even in the brief working window

### Test Run 3: 2026-01-04 (Defensive Buffs - Shield Block)

**Environment:** Beta, open world combat
**Test Spell:** Shield Block (2565), Ignore Pain (190456), Shield Wall (871)
**Module:** DefensiveTracker multi-approach tester

| # | Method | Out of Combat | In Combat | Notes |
|---|--------|---------------|-----------|-------|
| 1 | GetPlayerAuraBySpellID | Y | NOSECRET | Returns nil for defensive buffs |
| 2 | GetBuffDataByIndex | Y (9-13 auras) | **BLOCKED** | pcall fails in combat! |
| 3 | UNIT_AURA addedAuras | - | **SECRET** | Even spellId field is SECRET |
| 4 | Duration + SetTimerDuration | - | waiting | Never ran (no cache) |
| 5 | Duration + SetCooldown | - | waiting | Never ran (no cache) |

**CRITICAL NEW FINDINGS:**

1. **GetBuffDataByIndex is now BLOCKED in combat** - Different from Test Run 2 (Phalanx).
   The pcall fails entirely, not just hiding the buff.

2. **UNIT_AURA addedAuras fields are SECRET** - Both `isHelpful` AND `spellId` are
   SECRET values for defensive buffs. Cannot even identify which aura was added.

3. **Different buff types have different protection levels:**
   - Phalanx (1278009): addedAuras worked, spellId accessible
   - Shield Block (2565): addedAuras fields are completely SECRET

4. **Taint propagation persists** - Even with TrackedBuffs/TrackedDefensives disabled,
   Blizzard's CooldownViewer still gets ADDON_ACTION_BLOCKED errors from GetPlayerAuraBySpellID.
   The taint from previous hooks may persist across /reload.

**Conclusion:** ALL combat-relevant buffs appear to have secret value protection.
No API approach has been found that works in combat for tracking these buffs.

### Test Run 4: [DATE] - Fresh Client Test

**Environment:** Beta, fresh WoW launch (no previous addon hooks)
**Purpose:** Verify if taint persists from previous session or is inherent to APIs

| # | Method | Notes |
|---|--------|-------|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |

## Legend

- **Y** = Found Phalanx successfully
- **N** = Method worked but Phalanx not active
- **E** = Error/pcall failed
- **P** = Protected (API blocked)

## Code Snippets

### Approach 1: GetAuraSlots + select()
```lua
local function ProcessSlots(continuationToken, ...)
    local n = select("#", ...)
    for i = 1, n do
        local slot = select(i, ...)
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySlot, "player", slot)
        if ok and aura and aura.spellId then
            cache[aura.spellId] = aura
        end
    end
    return continuationToken
end

local continuationToken
repeat
    local ok, result = pcall(function()
        return ProcessSlots(C_UnitAuras.GetAuraSlots("player", "HELPFUL", nil, continuationToken))
    end)
    if not ok then break end
    continuationToken = result
until not continuationToken
```

### Approach 2: GetBuffDataByIndex
```lua
for index = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index, "HELPFUL")
    if not ok or not aura then break end
    cache[aura.spellId] = aura
end
```

### Approach 3: AuraUtil.ForEachAura
```lua
AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
    cache[aura.spellId] = aura
end, true) -- usePackedAura = true (CRITICAL)
```

### Approach 4: GetPlayerAuraBySpellID
```lua
local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
-- Expected to fail in M+/raids (protected)
```

### Approach 5: UNIT_AURA Incremental
```lua
function OnUnitAura(event, unit, updateInfo)
    if not updateInfo then
        -- Full refresh needed
        return
    end

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.isHelpful then
                cache[aura.spellId] = aura
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for spellId, aura in pairs(cache) do
            for _, removedID in ipairs(updateInfo.removedAuraInstanceIDs) do
                if aura.auraInstanceID == removedID then
                    cache[spellId] = nil
                end
            end
        end
    end
end
```

## Observations

### Spell ID Mismatch (Critical)
- Wowhead shows talent/ability ID (1269312) which is NOT the buff ID
- Actual buff aura has spellId = 1278009
- Blizzard's CooldownViewerSettings data provider uses linkedSpellIDs to handle this
- TrackedBuffs found 1278009 in tracked list because it pulls from data provider

### TrackedBuffs Working State
From console output when TrackedBuffs IS showing Phalanx:
```
TrackedBuffs: 6 auras [6673,1278009,386208,335150,202602...] vs 34 tracked [1278009,385954,...] = 2 matches
```
- `1278009` appears in both aura cache and tracked list
- This confirms the select() pattern is working correctly

### TrackedBars Not Working
```
TrackedBars: 6 auras vs 3 tracked = 0 matches
```
- TrackedBars finds auras but has 0 matches
- Need to verify what spell IDs TrackedBars is tracking vs what's in the aura cache

## Conclusions

1. **Out of combat: All 5 approaches work**
2. **In combat: NO APPROACH WORKS** for secret-valued buffs
3. **GetAuraSlots is blocked in combat** - pcall fails completely
4. **GetBuffDataByIndex/ForEachAura hide secret buffs in combat** - they return aura count but exclude secret-valued buffs
5. **UNIT_AURA incremental ALSO FAILS** - addedAuras fields (isHelpful, spellId) are SECRET in combat
6. **The spell ID mismatch was a red herring** - the real issue is combat protection of secret values

### NO Working Approach Found
As of Test Run 3, **no API approach has been found that works in combat** for tracking
secret-valued buffs like Shield Block, Ignore Pain, Shield Wall, or Phalanx.

The only remaining options are:
1. **Accept Blizzard's CooldownViewer** - Use their UI without modification
2. **Style-only approach** - Hook frame appearance without touching aura data
3. **Wait for Blizzard** - Hope for API changes or documentation on intended patterns

### Approaches That Were Tested But Failed

```lua
-- Approach 5: UNIT_AURA incremental (FAILS - fields are SECRET)
-- This was previously thought to work but testing confirms it does not
function OnUnitAura(event, unit, updateInfo)
    if unit ~= "player" then return end
    if not updateInfo or not updateInfo.addedAuras then return end

    for _, aura in ipairs(updateInfo.addedAuras) do
        -- FAILS: aura.isHelpful and aura.spellId are SECRET values in combat
        -- pcall fails when trying to access these fields
        local ok = pcall(function()
            if aura.isHelpful and aura.spellId then
                auraCache[aura.spellId] = aura
            end
        end)
        -- ok = false for combat-relevant buffs
    end
end
```
