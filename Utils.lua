local addonName, ns = ...

ns.Utils = {}
local Utils = ns.Utils

-- Midnight (12.0) compatibility (per Secret Values guide 13)
Utils.IS_MIDNIGHT = (select(4, GetBuildInfo()) >= 120000)

-- Helper: Check if value is a Midnight secret value
-- Returns true if value is secret and cannot be compared/formatted
function Utils.IsValueSecret(value)
    if not Utils.IS_MIDNIGHT then return false end
    if not issecretvalue then return false end
    return issecretvalue(value) == true
end

-- Helper: Safe comparison that handles secret values
-- Returns nil if comparison is not possible
function Utils.SafeCompare(a, b, op)
    if Utils.IsValueSecret(a) or Utils.IsValueSecret(b) then return nil end
    if op == ">" then return a > b
    elseif op == "<" then return a < b
    elseif op == ">=" then return a >= b
    elseif op == "<=" then return a <= b
    elseif op == "==" then return a == b
    end
    return nil
end

-- Safe API wrappers with pcall (per API Resilience guide 09)
function Utils.GetSpellCooldownSafe(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info then return info end
    return nil
end

function Utils.GetSpellChargesSafe(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellCharges then return nil end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if ok and info then return info end
    return nil
end

function Utils.GetSpellTextureSafe(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellTexture then return nil end
    local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if ok then return texture end
    return nil
end

function Utils.IsSpellOverlayedSafe(spellID)
    if not spellID then return false end
    -- Try new API first
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        local ok, result = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        if ok then return result end
    end
    -- Fallback to old API
    if IsSpellOverlayed then
        local ok, result = pcall(IsSpellOverlayed, spellID)
        if ok then return result end
    end
    return false
end

-- Timer font helper - maps numeric slider values to Blizzard font names
-- SetCountdownFont requires named fonts, so we map ranges to the 4 available sizes
function Utils.GetTimerFont(size)
    if type(size) == "string" then
        -- Legacy support for old string values
        local legacyMap = {
            ["small"] = "GameFontHighlightSmallOutline",
            ["medium"] = "GameFontHighlightOutline",
            ["large"] = "GameFontHighlightLargeOutline",
            ["huge"] = "GameFontHighlightHugeOutline",
        }
        return legacyMap[size] or "GameFontHighlightOutline"
    end
    
    -- Numeric size mapping (6-18 range)
    size = size or 10
    if size <= 9 then
        return "GameFontHighlightSmallOutline"
    elseif size <= 12 then
        return "GameFontHighlightOutline"
    elseif size <= 15 then
        return "GameFontHighlightLargeOutline"
    else
        return "GameFontHighlightHugeOutline"
    end
end

-- Helper to get totem data for a spell
-- Totems don't expose spellID directly, so we match by icon texture
function Utils.GetTotemDataForSpellID(spellID)
    if not spellID then return nil end
    local spellTexture = Utils.GetSpellTextureSafe(spellID)
    if not spellTexture then return nil end
    
    for slot = 1, MAX_TOTEMS or 4 do
        local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
        if haveTotem and duration and duration > 0 then
            if icon == spellTexture then
                return {
                    expirationTime = startTime + duration,
                    duration = duration,
                    modRate = 1,
                    slot = slot
                }
            end
        end
    end
    return nil
end
