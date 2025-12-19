local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Manager = addon:NewModule("CooldownManager", "AceEvent-3.0")
ns.CooldownManager = Manager

local Utils = ns.Utils

-- Shared state
local proxyPool = {}
local hiddenFrames = {}
local containers = {}

-- Aura cache
local auraBySpellID = {}
local auraByName = {}
local auraByInstanceID = {}

-- Target Blizzard Frames
local blizzardFrames = {
    cd = { "EssentialCooldownViewer", "UtilityCooldownViewer" },
    buffs = { "BuffIconCooldownViewer" },
    bars = { "BuffBarCooldownViewer", "TrackedBarCooldownViewer" },
}

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Manager:OnEnable()
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:AuraCache_RebuildFull()
    
    addon:Log("CooldownManager Enabled", "proxy")
    local blizzEnabled = self:IsBlizzardCooldownViewerEnabled()
    addon:Log("Blizzard Cooldown Manager enabled: " .. tostring(blizzEnabled), "proxy")
end

function Manager:OnUnitAura(event, unit, unitAuraUpdateInfo)
    if unit ~= "player" then return end
    self:AuraCache_ApplyUpdateInfo(unitAuraUpdateInfo)
    
    -- Notify other modules that need aura data
    for _, moduleName in ipairs({"TrackedBars", "TrackedBuffs"}) do
        local m = addon:GetModule(moduleName, true)
        if m and m:IsEnabled() and m.OnAuraUpdate then
            m:OnAuraUpdate()
        end
    end
end

-- ============================================================================
-- Infrastructure
-- ============================================================================

function Manager:IsBlizzardCooldownViewerEnabled()
    if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
        return CVarCallbackRegistry:GetCVarValueBool("cooldownViewerEnabled")
    end
    local val = GetCVar("cooldownViewerEnabled")
    return val == "1"
end

function Manager:GetCooldownIDsForCategory(category, categoryName)
    if not category then return {} end
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local provider = CooldownViewerSettings:GetDataProvider()
        if provider and provider.GetOrderedCooldownIDsForCategory then
            local ok, ids = pcall(provider.GetOrderedCooldownIDsForCategory, provider, category)
            if ok and ids then return ids end
        end
    end
    return {}
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
        hiddenFrames[frameName] = {
            originalUpdateShownState = frame.UpdateShownState
        }
        frame.UpdateShownState = function(self) end
        frame:Hide()
        addon:Log("Hooked and hidden Blizzard frame: " .. frameName, "frames")
    end
end

function Manager:ShowBlizzardFrame(frameName)
    local frame = _G[frameName]
    if not frame then return end
    
    local saved = hiddenFrames[frameName]
    if saved then
        if saved.originalUpdateShownState then
            frame.UpdateShownState = saved.originalUpdateShownState
        end
        hiddenFrames[frameName] = nil
        if frame.UpdateShownState then
            frame:UpdateShownState()
        else
            frame:Show()
        end
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
-- Population Helpers (Shared by Buffs and Bars)
-- ============================================================================

function Manager:PopulateBuffProxy(proxy, cooldownID, cooldownInfo, stateTable, ns)
    if not cooldownInfo then return end
    local Utils = ns.Utils
    
    local displaySpellID = cooldownInfo.overrideTooltipSpellID or cooldownInfo.overrideSpellID or cooldownInfo.spellID
    local auraSpellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    
    addon:Log(string.format("Populating proxy for ID %d (spell %s)", cooldownID, tostring(displaySpellID)), "proxy")
    
    proxy.spellID = auraSpellID
    proxy.cooldownID = cooldownID
    proxy.cooldownInfo = cooldownInfo
    
    local spellName = displaySpellID and C_Spell.GetSpellName and C_Spell.GetSpellName(displaySpellID) or "Unknown"
    proxy.spellName = spellName
    
    local texture = Utils.GetSpellTextureSafe(displaySpellID)
    if texture then proxy.icon:SetTexture(texture) end
    proxy:Show()
    
    local wasActive = stateTable[cooldownID]
    local isActive = false
    local activeSource = nil
    local foundSpellID = nil
    
    local totemData = Utils.GetTotemDataForSpellID(auraSpellID)
    if totemData then
        isActive = true
        activeSource = "totem"
        proxy.auraInstanceID = nil
        proxy.icon:SetDesaturated(false)
        if totemData.expirationTime and totemData.duration and totemData.duration > 0 then
            local startTime = totemData.expirationTime - totemData.duration
            proxy.cooldown:SetReverse(true)
            CooldownFrame_Set(proxy.cooldown, startTime, totemData.duration, true, false, totemData.modRate or 1)
        else
            CooldownFrame_Clear(proxy.cooldown)
        end
        proxy.count:Hide()
    else
        local auraData = nil
        if cooldownInfo.linkedSpellIDs then
            for _, linkedID in ipairs(cooldownInfo.linkedSpellIDs) do
                auraData = self:GetAuraBySpellID(linkedID)
                if auraData then foundSpellID = linkedID; activeSource = "linked"; break end
            end
        end
        if not auraData and auraSpellID then
            auraData = self:GetAuraBySpellID(auraSpellID)
            if auraData then foundSpellID = auraSpellID; activeSource = "aura" end
        end
        if not auraData and cooldownInfo.overrideSpellID and cooldownInfo.overrideSpellID ~= auraSpellID then
            auraData = self:GetAuraBySpellID(cooldownInfo.overrideSpellID)
            if auraData then foundSpellID = cooldownInfo.overrideSpellID; activeSource = "override" end
        end
        if not auraData and spellName and spellName ~= "Unknown" then
            auraData = self:GetAuraByName(spellName)
            if auraData then foundSpellID = auraData.spellId; activeSource = "name_cache" end
        end

        if auraData and (auraData.expirationTime == 0 or auraData.expirationTime > GetTime()) then
            isActive = true
            proxy.auraInstanceID = auraData.auraInstanceID
            proxy.icon:SetDesaturated(false)
            if auraData.expirationTime and auraData.duration and auraData.duration > 0 then
                local startTime = auraData.expirationTime - auraData.duration
                proxy.cooldown:SetReverse(true)
                CooldownFrame_Set(proxy.cooldown, startTime, auraData.duration, true, false, auraData.timeMod or 1)
            else
                CooldownFrame_Clear(proxy.cooldown)
            end
            if auraData.applications and auraData.applications > 1 then
                proxy.count:SetText(auraData.applications)
                proxy.count:Show()
            else
                proxy.count:Hide()
            end
        else
            proxy.auraInstanceID = nil
            proxy.icon:SetDesaturated(true)
            CooldownFrame_Clear(proxy.cooldown)
            proxy.count:Hide()
        end
    end
    
    if wasActive ~= isActive then
        if isActive then
            addon:Log(string.format("ACTIVATED: %s (id=%s, source=%s, foundID=%s)", spellName, tostring(cooldownID), activeSource or "?", tostring(foundSpellID)), "proxy")
        elseif wasActive == true then
            addon:Log(string.format("DEACTIVATED: %s (id=%s)", spellName, tostring(cooldownID)), "proxy")
        end
    end
    stateTable[cooldownID] = isActive
end

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
end

function Manager:AuraCache_Add(auraData)
    if not auraData then return end
    if auraData.auraInstanceID then auraByInstanceID[auraData.auraInstanceID] = auraData end
    if auraData.spellId then auraBySpellID[auraData.spellId] = auraData end
    if auraData.name then auraByName[auraData.name] = auraData end
end

function Manager:AuraCache_Remove(auraInstanceID)
    local existing = auraByInstanceID[auraInstanceID]
    if not existing then return end
    auraByInstanceID[auraInstanceID] = nil
    if existing.spellId and auraBySpellID[existing.spellId] == existing then auraBySpellID[existing.spellId] = nil end
    if existing.name and auraByName[existing.name] == existing then auraByName[existing.name] = nil end
end

function Manager:AuraCache_RebuildFull()
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
    return auraBySpellID[spellID]
end

function Manager:GetAuraByName(name)
    return auraByName[name]
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
