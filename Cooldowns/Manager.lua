local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Manager = addon:NewModule("CooldownManager", "AceEvent-3.0")
ns.CooldownManager = Manager

local Utils = ns.Utils

-- Local upvalues for performance
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local GetTime = GetTime
local pcall = pcall
local table_insert = table.insert
local CooldownFrame_Set = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear

-- Reusable empty table constant (never modify this!)
local EMPTY_TABLE = {}

-- Shared state
local proxyPool = {}
local hiddenFrames = {}
local containers = {}

-- Aura cache
local auraBySpellID = {}
local auraByName = {}
local auraByInstanceID = {}
local auraByIcon = {}

-- Pre-seeded texture to spellID mapping for tracked abilities
-- Built at addon enable (outside combat) to enable fallback matching when spellId is secret
local knownTextureToSpellID = {}

-- Target Blizzard Frames
local blizzardFrames = {
    cd = { "EssentialCooldownViewer", "UtilityCooldownViewer" },
    buffs = { "BuffIconCooldownViewer" },
    bars = { "BuffBarCooldownViewer", "TrackedBarCooldownViewer" },
}

-- Cached module references (populated in OnEnable, avoids GetModule lookup in hot path)
local cachedTrackedBars = nil
local cachedTrackedBuffs = nil

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Manager:OnEnable()
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("CVAR_UPDATE", "OnEvent")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "AuraCache_RebuildFull")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "AuraCache_RebuildFull")
    
    -- Pre-seed known spell textures for fallback matching during combat
    -- Delayed slightly to ensure data provider is ready
    C_Timer.After(0.5, function() self:PreSeedKnownSpells() end)
    
    self:AuraCache_RebuildFull()
    
    -- Cache module references to avoid GetModule lookups on every UNIT_AURA
    cachedTrackedBars = addon:GetModule("TrackedBars", true)
    cachedTrackedBuffs = addon:GetModule("TrackedBuffs", true)
    
    -- Watch for Blizzard Cooldown Manager setting changes
    if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
        CVarCallbackRegistry:RegisterCallback("cooldownViewerEnabled", self.OnCVarChanged, self)
    end
    
    addon:Log("CooldownManager Enabled", "proxy")
    local blizzEnabled = self:IsBlizzardCooldownViewerEnabled()
    addon:Log("Blizzard Cooldown Manager enabled: " .. tostring(blizzEnabled), "proxy")
end

function Manager:OnDisable()
    self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("CVAR_UPDATE")
    
    if CVarCallbackRegistry and CVarCallbackRegistry.UnregisterCallback then
        CVarCallbackRegistry:UnregisterCallback("cooldownViewerEnabled", self)
    end
end

function Manager:OnEvent(event, ...)
    if event == "CVAR_UPDATE" then
        local cvarName, value = ...
        if cvarName == "cooldownViewerEnabled" then
            self:OnCVarChanged(cvarName, value)
        end
    end
end

function Manager:OnCVarChanged(cvarName, value)
    addon:Log("CVar Changed: " .. tostring(cvarName) .. " = " .. tostring(value), "proxy")
    
    -- Notify all dependent modules to refresh their layout and visibility
    local modules = { "Cooldowns", "TrackedBars", "TrackedBuffs" }
    for _, modName in ipairs(modules) do
        local mod = addon:GetModule(modName, true)
        if mod and mod.UpdateLayout then
            mod:UpdateLayout()
        end
    end
    
    -- Trigger central layout recalculation
    local LM = addon:GetModule("LayoutManager", true)
    if LM then
        LM:TriggerLayoutUpdate()
    end
end

function Manager:OnPlayerRegenEnabled()
    -- Combat ended - rebuild cache if we deferred it earlier
    if self.needsCacheRebuild then
        addon:Log("OnPlayerRegenEnabled: Processing deferred cache rebuild", "discovery")
    end
    self:AuraCache_RebuildFull()
end

function Manager:OnUnitAura(event, unit, unitAuraUpdateInfo)
    if unit ~= "player" then return end
    self:AuraCache_ApplyUpdateInfo(unitAuraUpdateInfo)
    
    -- Notify cached modules (avoid GetModule lookup in hot path)
    if cachedTrackedBars and cachedTrackedBars:IsEnabled() and cachedTrackedBars.OnAuraUpdate then
        cachedTrackedBars:OnAuraUpdate()
    end
    if cachedTrackedBuffs and cachedTrackedBuffs:IsEnabled() and cachedTrackedBuffs.OnAuraUpdate then
        cachedTrackedBuffs:OnAuraUpdate()
    end
end

-- ============================================================================
-- Infrastructure
-- ============================================================================

function Manager:IsBlizzardCooldownViewerEnabled()
    if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
        local val = CVarCallbackRegistry:GetCVarValueBool("cooldownViewerEnabled")
        if val ~= nil then return val end
    end
    local val = GetCVar("cooldownViewerEnabled")
    return Utils.SafeCompare(val, "1", "==")
end

function Manager:GetCooldownIDsForCategory(category, categoryName)
    local ids = EMPTY_TABLE
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local provider = CooldownViewerSettings:GetDataProvider()
        if provider and provider.GetOrderedCooldownIDsForCategory then
            local ok, result = pcall(provider.GetOrderedCooldownIDsForCategory, provider, category)
            if ok and result then ids = result end
        end
    end
    return ids
end

function Manager:GetCooldownInfoForID(cooldownID)
    if not cooldownID then return nil end
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local provider = CooldownViewerSettings:GetDataProvider()
        if provider and provider.GetCooldownInfoForID then
            local ok, info = pcall(provider.GetCooldownInfoForID, provider, cooldownID)
            if ok and info then return info end
        end
    end
    return nil
end

-- ============================================================================
-- Blizzard Frame Management
-- ============================================================================

function Manager:HideBlizzardFrame(frameName)
    local frame = _G[frameName]
    if not frame then return end
    
    if not hiddenFrames[frameName] then
        hiddenFrames[frameName] = true
        -- Use Alpha/Mouse instead of function override to avoid taint in 12.0
        frame:SetAlpha(0)
        frame:SetPropagateMouseClicks(true) -- Let clicks pass through to our proxies
        addon:Log("Visual-hidden Blizzard frame: " .. frameName, "frames")
    end
end

function Manager:ShowBlizzardFrame(frameName)
    local frame = _G[frameName]
    if not frame then return end
    
    if hiddenFrames[frameName] then
        hiddenFrames[frameName] = nil
        frame:SetAlpha(1)
        frame:SetPropagateMouseClicks(false)
        addon:Log("Restored Blizzard frame: " .. frameName, "frames")
    end
end

function Manager:RestoreAllBlizzardFrames()
    for _, group in pairs(blizzardFrames) do
        for _, frameName in ipairs(group) do
            self:ShowBlizzardFrame(frameName)
        end
    end
    wipe(hiddenFrames)
end

function Manager:GetBlizzardFrames()
    return blizzardFrames
end

-- ============================================================================
-- Proxy Management
-- ============================================================================

function Manager:GetProxy(parent, proxyType)
    local proxy
    for _, p in ipairs(proxyPool) do
        -- Only reuse if hidden AND not leased to anyone
        if not p:IsShown() and p.proxyType == proxyType and not p.leasedTo then
            proxy = p
            break
        end
    end
    
    if not proxy then
        proxy = CreateFrame("Button", nil, parent)
        proxy:SetSize(40, 40)
        proxy:EnableMouse(true)
        proxy.proxyType = proxyType
        
        proxy.icon = proxy:CreateTexture(nil, "ARTWORK")
        proxy.icon:SetAllPoints()
        proxy.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        
        proxy.cooldown = CreateFrame("Cooldown", nil, proxy, "CooldownFrameTemplate")
        proxy.cooldown:SetAllPoints()
        proxy.cooldown:SetDrawEdge(false)
        
        proxy.count = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        proxy.count:SetPoint("BOTTOMRIGHT", proxy, "BOTTOMRIGHT", 2, -2)
        
        proxy.timer = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        proxy.timer:SetPoint("CENTER", proxy, "CENTER", 0, 0)
        proxy.timer:SetTextColor(1, 0.8, 0)
        
        proxy:SetScript("OnEnter", function(self)
            if self.spellID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)
                GameTooltip:Show()
            elseif self.auraInstanceID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitBuffByAuraInstanceID("player", self.auraInstanceID)
                GameTooltip:Show()
            end
        end)
        proxy:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        table.insert(proxyPool, proxy)
    end
    
    proxy:SetParent(parent)
    proxy:SetFrameStrata("MEDIUM")
    return proxy
end

function Manager:ReleaseProxy(proxy)
    proxy:Hide()
    proxy:ClearAllPoints()
    proxy.spellID = nil
    proxy.cooldownID = nil
    proxy.auraInstanceID = nil
    proxy.cooldownInfo = nil
    proxy.leasedTo = nil  -- Clear lease so pool can reuse
    proxy.spellName = nil
end

-- ============================================================================
-- Population Helpers
-- ============================================================================

-- NOTE: PopulateBuffProxy was removed in the reskin approach.
-- TrackedBuffs and TrackedBars now hook Blizzard's native frames directly,
-- allowing Blizzard's code to handle protected API calls for aura data.
-- The Cooldowns module (Essential/Utility) uses its own PopulateProxy in Cooldowns.lua.

-- ============================================================================
-- Container Management
-- ============================================================================

function Manager:GetContainer(containerType)
    return containers[containerType]
end

function Manager:CreateContainer(containerType, name)
    if containers[containerType] then return containers[containerType] end
    local main = _G["ActionHudFrame"]
    if not main then return nil end
    
    local container = CreateFrame("Frame", name, main)
    container:SetSize(1, 1)
    container:SetPoint("CENTER", main, "CENTER", 0, 0)
    containers[containerType] = container
    return container
end

function Manager:UpdateContainerDebug(containerType, color)
    local container = containers[containerType]
    if not container then return end
    
    local p = addon.db.profile
    if p.debugContainers then
        if not container.debugBg then
            container.debugBg = container:CreateTexture(nil, "BACKGROUND")
            container.debugBg:SetAllPoints()
        end
        container.debugBg:SetColorTexture(color.r, color.g, color.b, 0.5)
        container.debugBg:Show()
        -- Ensure size is visible
        if container:GetWidth() <= 1 then container:SetSize(100, 100) end
    elseif container.debugBg then
        container.debugBg:Hide()
        -- Reset size if it was 1x1
        -- Actually, it's better to let the module manage size
    end
end

-- ============================================================================
-- Aura Cache
-- ============================================================================

function Manager:AuraCache_Clear()
    wipe(auraBySpellID)
    wipe(auraByName)
    wipe(auraByInstanceID)
    wipe(auraByIcon)
end

-- Pre-seed known spell textures for tracked abilities
-- Call this at addon enable (outside combat) to build fallback lookup
function Manager:PreSeedKnownSpells()
    wipe(knownTextureToSpellID)
    local categories = {
        Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff,
        Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar,
    }
    local count = 0
    for _, cat in ipairs(categories) do
        if cat then
            local ids = self:GetCooldownIDsForCategory(cat)
            for _, cooldownID in ipairs(ids) do
                local info = self:GetCooldownInfoForID(cooldownID)
                if info and info.spellID then
                    local texture = Utils.GetSpellTextureSafe(info.spellID)
                    if texture then
                        knownTextureToSpellID[texture] = info.spellID
                        count = count + 1
                    end
                    -- Also seed linked spellIDs
                    if info.linkedSpellIDs then
                        for _, linkedID in ipairs(info.linkedSpellIDs) do
                            local linkedTexture = Utils.GetSpellTextureSafe(linkedID)
                            if linkedTexture then
                                knownTextureToSpellID[linkedTexture] = linkedID
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
    end
    addon:Log(string.format("PreSeedKnownSpells: Seeded %d texture->spellID mappings", count), "discovery")
end

-- Get known spellID for a texture (fallback for secret spellId)
function Manager:GetKnownSpellIDForTexture(texture)
    if not texture then return nil end
    return knownTextureToSpellID[texture]
end

function Manager:AuraCache_Add(auraData)
    if not auraData or not auraData.auraInstanceID or Utils.IsValueSecret(auraData.auraInstanceID) then return end
    
    local id = auraData.auraInstanceID
    local existing = auraByInstanceID[id]

    -- Preserve known spellId/name/icon if new ones are secret (common in combat)
    if not Utils.IsValueSecret(auraData.spellId) then
        auraData._spellId = auraData.spellId
    elseif existing then
        auraData._spellId = existing._spellId
    end
    
    if not Utils.IsValueSecret(auraData.name) then
        auraData._name = auraData.name
    elseif existing then
        auraData._name = existing._name
    end

    if not Utils.IsValueSecret(auraData.icon) then
        auraData._icon = auraData.icon
    elseif existing then
        auraData._icon = existing._icon
    end
    
    -- Fallback: If spellId is still unknown but icon is readable, use pre-seeded lookup
    if not auraData._spellId and auraData._icon then
        local knownSpellID = knownTextureToSpellID[auraData._icon]
        if knownSpellID then
            auraData._spellId = knownSpellID
        end
    end
    
    auraByInstanceID[id] = auraData
    
    if auraData._spellId then
        auraBySpellID[auraData._spellId] = auraData
    end
    if auraData._name then
        auraByName[auraData._name] = auraData
    end
    if auraData._icon then
        auraByIcon[auraData._icon] = auraData
    end
end

function Manager:AuraCache_Remove(auraInstanceID)
    if not auraInstanceID or Utils.IsValueSecret(auraInstanceID) then return end
    local existing = auraByInstanceID[auraInstanceID]
    
    -- #region agent log
    addon:Log(string.format("AuraCache_Remove[%s]: existing=%s", tostring(auraInstanceID), tostring(existing ~= nil)), "discovery")
    -- #endregion

    if not existing then return end
    
    auraByInstanceID[auraInstanceID] = nil
    
    -- Use preserved metadata to clear specific caches
    if existing._spellId and auraBySpellID[existing._spellId] == existing then 
        auraBySpellID[existing._spellId] = nil 
    end
    if existing._name and auraByName[existing._name] == existing then 
        auraByName[existing._name] = nil 
    end
    if existing._icon and auraByIcon[existing._icon] == existing then
        auraByIcon[existing._icon] = nil
    end
end

function Manager:AuraCache_RebuildFull()
    -- Don't wipe cache during combat - values will be secret and we'll lose lookup keys
    if InCombatLockdown() then
        self.needsCacheRebuild = true
        addon:Log("AuraCache_RebuildFull: Deferred (in combat)", "discovery")
        return
    end
    self.needsCacheRebuild = false
    
    self:AuraCache_Clear()
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        self:AuraCache_Add(aura)
    end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
        if not aura then break end
        self:AuraCache_Add(aura)
    end
    addon:Log("AuraCache_RebuildFull: Completed", "discovery")
end

function Manager:AuraCache_ApplyUpdateInfo(unitAuraUpdateInfo)
    if not unitAuraUpdateInfo or unitAuraUpdateInfo.isFullUpdate then
        self:AuraCache_RebuildFull()
        return
    end
    if unitAuraUpdateInfo.removedAuraInstanceIDs then
        for _, auraInstanceID in ipairs(unitAuraUpdateInfo.removedAuraInstanceIDs) do
            self:AuraCache_Remove(auraInstanceID)
        end
    end
    if unitAuraUpdateInfo.updatedAuraInstanceIDs then
        for _, auraInstanceID in ipairs(unitAuraUpdateInfo.updatedAuraInstanceIDs) do
            local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
            if aura then self:AuraCache_Add(aura) else self:AuraCache_Remove(auraInstanceID) end
        end
    end
    if unitAuraUpdateInfo.addedAuras then
        for _, aura in ipairs(unitAuraUpdateInfo.addedAuras) do
            self:AuraCache_Add(aura)
        end
    end
end

function Manager:GetAuraBySpellID(spellID)
    if not spellID or Utils.IsValueSecret(spellID) then return nil end
    return auraBySpellID[spellID]
end

function Manager:GetAuraByName(name)
    if not name or Utils.IsValueSecret(name) then return nil end
    return auraByName[name]
end

function Manager:GetAuraByIcon(icon)
    if not icon or Utils.IsValueSecret(icon) then return nil end
    return auraByIcon[icon]
end

-- ============================================================================
-- Debug / Discovery
-- ============================================================================

function Manager:FindPotentialTargets()
    addon:Log("Scanning for Blizzard CooldownViewer frames...", "discovery")
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:match("Viewer$") or k:match("Tracked")) then
            if type(v) == "table" and v.GetObjectType then
                local ok, objType = pcall(v.GetObjectType, v)
                if ok and (objType == "Frame" or objType == "Button") then
                    addon:Log("Found: " .. k .. " (Type: " .. objType .. ")", "discovery")
                end
            end
        end
    end
end

function Manager:DumpTrackedBuffInfo()
    print("|cff33ff99ActionHud:|r Dumping Cooldown Manager Info...")
    
    local categories = {
        { name = "Essential", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential },
        { name = "Utility", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility },
        { name = "TrackedBuff", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff },
        { name = "TrackedBar", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar },
    }

    for _, catInfo in ipairs(categories) do
        if catInfo.cat then
            local ids = self:GetCooldownIDsForCategory(catInfo.cat, catInfo.name)
            print(string.format("|cff00ff00%s:|r %d items", catInfo.name, #ids))
            for _, cooldownID in ipairs(ids) do
                local info = self:GetCooldownInfoForID(cooldownID)
                if info then
                    local name = C_Spell.GetSpellName(info.spellID) or "?"
                    local linkedStr = (info.linkedSpellIDs and #info.linkedSpellIDs > 0) and table.concat(info.linkedSpellIDs, ", ") or "none"
                    print(string.format("  [%d] %s: spellID=%s, linked=[%s], override=%s, tooltipOverride=%s",
                        cooldownID, name, tostring(info.spellID), linkedStr,
                        tostring(info.overrideSpellID), tostring(info.overrideTooltipSpellID)))
                end
            end
        end
    end
    print("|cff33ff99ActionHud:|r Dump complete.")
end
