local addonName, ns = ...

ns.Utils = {}
local Utils = ns.Utils

-- Local upvalues for performance
local GetTime = GetTime
local pcall = pcall
local wipe = wipe

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

-- ============================================================================
-- Frame-level API caching (invalidates each frame to avoid stale data)
-- ============================================================================
local cooldownCache = {}
local chargesCache = {}
local textureCache = {}
local overlayCache = {}
local cacheTime = 0
local CACHE_DURATION = 0.016  -- ~1 frame at 60fps, invalidate after this

-- Texture cache cleanup tracking
local textureCacheTime = 0
local TEXTURE_CACHE_DURATION = 60  -- Wipe texture cache every 60 seconds

local function InvalidateCacheIfNeeded()
    local now = GetTime()
    if now - cacheTime > CACHE_DURATION then
        wipe(cooldownCache)
        wipe(chargesCache)
        wipe(overlayCache)
        cacheTime = now
    end
    -- Texture cache cleanup less frequently (textures rarely change)
    if now - textureCacheTime > TEXTURE_CACHE_DURATION then
        wipe(textureCache)
        textureCacheTime = now
    end
end

-- Safe API wrappers with pcall and frame-level caching (per API Resilience guide 09)
function Utils.GetSpellCooldownSafe(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end
    
    InvalidateCacheIfNeeded()
    
    local cached = cooldownCache[spellID]
    if cached ~= nil then return cached end
    
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info then
        cooldownCache[spellID] = info
        return info
    end
    cooldownCache[spellID] = false  -- Cache negative results too
    return nil
end

function Utils.GetSpellChargesSafe(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellCharges then return nil end
    
    InvalidateCacheIfNeeded()
    
    local cached = chargesCache[spellID]
    if cached ~= nil then return cached or nil end
    
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if ok and info then
        chargesCache[spellID] = info
        return info
    end
    chargesCache[spellID] = false  -- Cache negative results too
    return nil
end

function Utils.GetSpellTextureSafe(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellTexture then return nil end
    
    -- Texture cache persists longer (textures rarely change)
    local cached = textureCache[spellID]
    if cached ~= nil then return cached or nil end
    
    local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and texture then
        textureCache[spellID] = texture
        return texture
    end
    textureCache[spellID] = false  -- Cache negative results too
    return nil
end

function Utils.IsSpellOverlayedSafe(spellID)
    if not spellID then return false end
    
    InvalidateCacheIfNeeded()
    
    local cached = overlayCache[spellID]
    if cached ~= nil then return cached end
    
    -- Try new API first
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        local ok, result = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        if ok then
            overlayCache[spellID] = result or false
            return result
        end
    end
    -- Fallback to old API
    if IsSpellOverlayed then
        local ok, result = pcall(IsSpellOverlayed, spellID)
        if ok then
            overlayCache[spellID] = result or false
            return result
        end
    end
    overlayCache[spellID] = false
    return false
end

-- Invalidate texture cache on spell changes (called from event handlers if needed)
function Utils.InvalidateTextureCache()
    wipe(textureCache)
end

-- Timer font helper - maps numeric slider values to Blizzard font names
-- SetCountdownFont requires named fonts, so we map ranges to the 4 available sizes
-- Pre-allocated table to avoid garbage creation
local legacyFontMap = {
    ["small"] = "GameFontHighlightSmallOutline",
    ["medium"] = "GameFontHighlightOutline",
    ["large"] = "GameFontHighlightLargeOutline",
    ["huge"] = "GameFontHighlightHugeOutline",
}

function Utils.GetTimerFont(size)
    if type(size) == "string" then
        -- Legacy support for old string values
        return legacyFontMap[size] or "GameFontHighlightOutline"
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
-- Reusable table to avoid garbage creation
local totemDataCache = { expirationTime = 0, duration = 0, modRate = 1, slot = 0 }

function Utils.GetTotemDataForSpellID(spellID)
    if not spellID then return nil end
    local spellTexture = Utils.GetSpellTextureSafe(spellID)
    if not spellTexture then return nil end
    
    for slot = 1, MAX_TOTEMS or 4 do
        local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
        if haveTotem and duration and duration > 0 then
            if icon == spellTexture then
                -- Reuse cached table instead of creating new one
                totemDataCache.expirationTime = startTime + duration
                totemDataCache.duration = duration
                totemDataCache.modRate = 1
                totemDataCache.slot = slot
                return totemDataCache
            end
        end
    end
    return nil
end
