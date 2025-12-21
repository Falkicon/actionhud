local addonName, ns = ...

ns.Utils = {}
local Utils = ns.Utils

-- Local upvalues for performance
local GetTime = GetTime
local pcall = pcall
local wipe = wipe
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitPowerType = UnitPowerType
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor

-- Midnight (12.0) compatibility (per Secret Values guide 13)
Utils.IS_MIDNIGHT = (select(4, GetBuildInfo()) >= 120000)

-- Helper: Check if value is a Midnight secret value
-- Returns true if value is secret and cannot be compared/formatted
function Utils.IsValueSecret(value)
    if not Utils.IS_MIDNIGHT then return false end
    if value == nil then return false end
    
    -- Official checker is the most reliable
    if issecretvalue then
        return issecretvalue(value) == true
    end
    
    -- Robust fallback: Try an operation that secrets are known to block.
    -- We use pcall to catch the "attempt to compare... (a secret value)" error.
    -- We avoid == nil check as it might also trigger it in some cases.
    local ok = pcall(function() 
        local _ = (value > -1e12) or (value == 0)
    end)
    
    return not ok
end

-- Helper: Safe comparison that handles secret values
-- Returns nil if comparison is not possible
function Utils.SafeCompare(a, b, op)
    -- Wrap everything in pcall including nil checks
    local ok, result = pcall(function()
        if a == nil or b == nil then return nil end
        if op == ">" then return a > b
        elseif op == "<" then return a < b
        elseif op == ">=" then return a >= b
        elseif op == "<=" then return a <= b
        elseif op == "==" then return a == b
        end
        return nil
    end)
    
    if ok then return result end
    return nil 
end

-- ============================================================================
-- UI Helpers
-- ============================================================================

-- Aggressively hide a texture
function Utils.HideTexture(texture)
    if not texture then return end
    texture:SetAlpha(0)
    texture:Hide()
    if texture.SetTexture then texture:SetTexture(nil) end
    if texture.SetAtlas then texture:SetAtlas(nil) end
end

-- Apply standardized icon crop
function Utils.ApplyIconCrop(texture, w, h)
    if not texture then return end
    local ratio = w / h
    if ratio > 1 then
         local scale = h / w
         local range = 0.84 * scale
         local mid = 0.5
         texture:SetTexCoord(0.08, 0.92, mid - range/2, mid + range/2)
    elseif ratio < 1 then
         local scale = w / h
         local range = 0.84 * scale
         local mid = 0.5
         texture:SetTexCoord(mid - range/2, mid + range/2, 0.08, 0.92)
    else
         texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Remove Blizzard decorations (masks, borders, etc)
function Utils.StripBlizzardDecorations(frame)
    if not frame then return end
    
    local regions = {frame:GetRegions()}
    for _, region in ipairs(regions) do
        if region:IsObjectType("MaskTexture") then
            region:Hide()
        elseif region:IsObjectType("Texture") then
            -- Hide based on object name/purpose if not the main icon/bar
            local name = region:GetDebugName()
            if name and not Utils.IsValueSecret(name) then
                if name:find("Border") or name:find("Overlay") or name:find("Highlight") or name:find("Shadow") or name:find("Mask") then
                    region:Hide()
                end
            end
        end
    end
    
    -- Hide explicit pips or decorations if they exist as children
    if frame.Pip then frame.Pip:Hide() end
    if frame.HealthBarMask then frame.HealthBarMask:Hide() end
    if frame.ManaBarMask then frame.ManaBarMask:Hide() end
end

-- Unified color lookup for health/power bars
function Utils.GetUnitColor(unit, barType, mult)
    mult = mult or 1
    if barType == "HEALTH" then
        if UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            local c = RAID_CLASS_COLORS[class]
            if c then
                return c.r * mult, c.g * mult, c.b * mult
            end
        else
            if UnitIsEnemy("player", unit) then
                return 0.8 * mult, 0, 0
            elseif UnitIsFriend("player", unit) then
                return 0, 0.8 * mult, 0
            else
                return 0.8 * mult, 0.8 * mult, 0
            end
        end
        return 0, 0.8 * mult, 0 -- Default green
    elseif barType == "POWER" or barType == "MANA" then
        local pType, pToken, altR, altG, altB = UnitPowerType(unit)
        local info = PowerBarColor[pToken]
        if info then
            return info.r * mult, info.g * mult, info.b * mult
        elseif altR then
            return altR * mult, altG * mult, altB * mult
        end
        return 0, 0, 0.8 * mult -- Default blue
    end
    return 1, 1, 1
end

-- ============================================================================
-- Action Bar Compatibility (12.0)
-- ============================================================================

function Utils.GetActionCooldownSafe(actionID)
    if not actionID then return 0, 0, false, 1 end
    
    if Utils.IS_MIDNIGHT and C_ActionBar and C_ActionBar.GetActionCooldown then
        local ok, info = pcall(C_ActionBar.GetActionCooldown, actionID)
        if ok and info then
            -- Returns (startTime, duration, isEnabled, modRate)
            return info.startTime or 0, info.duration or 0, info.isEnabled, info.modRate or 1
        end
    end
    
    -- Fallback to global
    if GetActionCooldown then -- @scan-ignore: midnight-wrapper
        return GetActionCooldown(actionID) -- @scan-ignore: midnight-wrapper
    end
    
    return 0, 0, false, 1
end

function Utils.GetActionDisplayCountSafe(actionID)
    if not actionID then return 0 end
    
    if Utils.IS_MIDNIGHT and C_ActionBar and C_ActionBar.GetActionDisplayCount then
        local ok, count = pcall(C_ActionBar.GetActionDisplayCount, actionID)
        if ok then
            -- Handle potential table return if Blizzard changes it later
            if type(count) == "table" then return count.count or count.displayCount or 0 end
            return count or 0
        end
    end
    
    if GetActionCount then
        local count = GetActionCount(actionID)
        if type(count) == "table" then return count.count or count.displayCount or 0 end
        return count or 0
    end
    
    return 0
end

function Utils.GetActionBarPageSafe()
    if Utils.IS_MIDNIGHT and C_ActionBar and C_ActionBar.GetActionBarPage then
        local ok, page = pcall(C_ActionBar.GetActionBarPage)
        if ok then 
            if type(page) == "table" then return page.page or page.currentPage or 1 end
            return page or 1 
        end
    end
    
    if GetActionBarPage then -- @scan-ignore: midnight-wrapper
        return GetActionBarPage() -- @scan-ignore: midnight-wrapper
    end
    
    return 1
end

function Utils.GetActionTextureSafe(actionID)
    if not actionID then return nil end
    
    if Utils.IS_MIDNIGHT and C_ActionBar and C_ActionBar.GetActionTexture then
        local ok, texture = pcall(C_ActionBar.GetActionTexture, actionID)
        if ok then 
            if type(texture) == "table" then return texture.texture or texture.icon end
            return texture 
        end
    end
    
    if GetActionTexture then -- @scan-ignore: midnight-wrapper
        return GetActionTexture(actionID) -- @scan-ignore: midnight-wrapper
    end
    
    return nil
end

function Utils.IsUsableActionSafe(actionID)
    if not actionID then return false, false end
    
    if Utils.IS_MIDNIGHT and C_ActionBar and C_ActionBar.IsUsableAction then
        local ok, isUsable, noMana = pcall(C_ActionBar.IsUsableAction, actionID)
        if ok then 
            if type(isUsable) == "table" then
                return isUsable.isUsable or isUsable.usable, isUsable.notEnoughMana or isUsable.noMana
            end
            return isUsable, noMana 
        end
    end
    
    if IsUsableAction then -- @scan-ignore: midnight-wrapper
        return IsUsableAction(actionID) -- @scan-ignore: midnight-wrapper
    end
    
    return false, false
end

function Utils.IsActionInRangeSafe(actionID)
    if not actionID then return nil end
    
    if Utils.IS_MIDNIGHT and C_ActionBar and C_ActionBar.IsActionInRange then
        local ok, inRange = pcall(C_ActionBar.IsActionInRange, actionID)
        if ok then 
            if type(inRange) == "table" then return inRange.inRange or inRange.isInRange end
            return inRange 
        end
    end
    
    if IsActionInRange then -- @scan-ignore: midnight-wrapper
        return IsActionInRange(actionID) -- @scan-ignore: midnight-wrapper
    end
    
    return nil
end

function Utils.GetSpecializationSafe()
    if Utils.IS_MIDNIGHT and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local ok, spec = pcall(C_SpecializationInfo.GetSpecialization)
        if ok then 
            -- Normalize to number if possible, secrets will return nil for tonumber
            return tonumber(spec) or spec 
        end
    end
    
    if GetSpecialization then
        local spec = GetSpecialization()
        return tonumber(spec) or spec
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
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end -- @scan-ignore: midnight-wrapper
    
    InvalidateCacheIfNeeded()
    
    local cached = cooldownCache[spellID]
    if cached ~= nil then return cached end
    
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID) -- @scan-ignore: midnight-wrapper
    if ok and info then
        cooldownCache[spellID] = info
        return info
    end
    cooldownCache[spellID] = false  -- Cache negative results too
    return nil
end

function Utils.GetSpellChargesSafe(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellCharges then return nil end -- @scan-ignore: midnight-wrapper
    
    InvalidateCacheIfNeeded()
    
    local cached = chargesCache[spellID]
    if cached ~= nil then return cached or nil end
    
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID) -- @scan-ignore: midnight-wrapper
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

function Utils.GetItemSpellSafe(itemInfo)
    if not itemInfo then return nil end
    if not C_Item or not C_Item.GetItemSpell then return nil end
    
    local ok, name, spellID = pcall(C_Item.GetItemSpell, itemInfo)
    if ok then
        return name, spellID
    end
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

-- Timer font helper - maps string values to Blizzard font names
-- SetCountdownFont requires font NAME strings, not font objects
-- Pre-allocated table to avoid garbage creation
local fontNameMap = {
    ["small"] = "GameFontHighlightSmallOutline",
    ["medium"] = "GameFontHighlightOutline",
    ["large"] = "GameFontHighlightLargeOutline",
    ["huge"] = "GameFontHighlightHugeOutline",
}

function Utils.GetTimerFont(size)
    if type(size) == "string" then
        -- String value like "small", "medium", "large", "huge"
        return fontNameMap[size] or "GameFontHighlightOutline"
    end
    
    -- Numeric size mapping (6-18 range) - legacy support
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
