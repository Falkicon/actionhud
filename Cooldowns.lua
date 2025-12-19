local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Cooldowns = addon:NewModule("Cooldowns", "AceEvent-3.0", "AceHook-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName, true)

-- Constants
local CVAR_COOLDOWN_VIEWER_ENABLED = "cooldownViewerEnabled"

-- Timer font helper - maps numeric slider values to Blizzard font names
-- SetCountdownFont requires named fonts, so we map ranges to the 4 available sizes
local function GetTimerFont(size)
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

-- Containers for our proxy frames
local cdContainer, tbContainer, buffContainer

-- Track which Blizzard frames we've hidden
local hiddenFrames = {}

-- Proxy System
local proxyPool = {}
local activeProxies = {} -- [spellID or auraID] = proxyFrame

-- State tracking for debug logging (persists across proxy recycling)
local lastKnownState = {} -- [cooldownID] = boolean (true=active, false=inactive)

-- Aura cache (event-driven via UNIT_AURA updateInfo)
-- We avoid relying on repeated GetPlayerAuraBySpellID calls because they can lag for some auras.
local auraBySpellID = {}
local auraByName = {}
local auraByInstanceID = {}

-- Target Blizzard Frames
local blizzardFrames = {
    cd = { "EssentialCooldownViewer", "UtilityCooldownViewer" },
    buffs = { "BuffIconCooldownViewer" },
    bars = { "BuffBarCooldownViewer", "TrackedBarCooldownViewer" },
}

-- Runtime category resolution (Enum.CooldownViewerCategory may not be populated at file load time)
local function GetCategoryForFrame(frameName)
    if not Enum.CooldownViewerCategory then return nil end
    
    local map = {
        EssentialCooldownViewer = Enum.CooldownViewerCategory.Essential,
        UtilityCooldownViewer = Enum.CooldownViewerCategory.Utility,
        BuffIconCooldownViewer = Enum.CooldownViewerCategory.TrackedBuff,
        BuffBarCooldownViewer = Enum.CooldownViewerCategory.TrackedBar,
        TrackedBarCooldownViewer = Enum.CooldownViewerCategory.TrackedBar,
    }
    return map[frameName]
end

-- Category enum accessors for rendering functions
local function GetEssentialCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential
end

local function GetUtilityCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility
end

local function GetTrackedBuffCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff
end

local function GetTrackedBarCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function AuraCache_Clear()
    wipe(auraBySpellID)
    wipe(auraByName)
    wipe(auraByInstanceID)
end

local function AuraCache_Add(auraData)
    if not auraData then return end
    if auraData.auraInstanceID then
        auraByInstanceID[auraData.auraInstanceID] = auraData
    end
    if auraData.spellId then
        auraBySpellID[auraData.spellId] = auraData
    end
    if auraData.name then
        auraByName[auraData.name] = auraData
    end
end

local function AuraCache_Remove(auraInstanceID)
    local existing = auraByInstanceID[auraInstanceID]
    if not existing then return end
    auraByInstanceID[auraInstanceID] = nil

    if existing.spellId and auraBySpellID[existing.spellId] == existing then
        auraBySpellID[existing.spellId] = nil
    end
    if existing.name and auraByName[existing.name] == existing then
        auraByName[existing.name] = nil
    end
end

local function AuraCache_RebuildFull()
    AuraCache_Clear()

    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        AuraCache_Add(aura)
    end

    -- Some items (e.g. certain stances/flags) can be tracked as HARMFUL.
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
        if not aura then break end
        AuraCache_Add(aura)
    end
end

local function AuraCache_ApplyUpdateInfo(unitAuraUpdateInfo)
    if not unitAuraUpdateInfo or unitAuraUpdateInfo.isFullUpdate then
        AuraCache_RebuildFull()
        return
    end

    if unitAuraUpdateInfo.removedAuraInstanceIDs then
        for _, auraInstanceID in ipairs(unitAuraUpdateInfo.removedAuraInstanceIDs) do
            AuraCache_Remove(auraInstanceID)
        end
    end

    if unitAuraUpdateInfo.updatedAuraInstanceIDs then
        for _, auraInstanceID in ipairs(unitAuraUpdateInfo.updatedAuraInstanceIDs) do
            local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
            if aura then
                AuraCache_Add(aura)
            else
                AuraCache_Remove(auraInstanceID)
            end
        end
    end

    if unitAuraUpdateInfo.addedAuras then
        for _, aura in ipairs(unitAuraUpdateInfo.addedAuras) do
            AuraCache_Add(aura)
        end
    end
end

-- Check if Blizzard's Cooldown Manager is enabled
function Cooldowns:IsBlizzardCooldownViewerEnabled()
    if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
        return CVarCallbackRegistry:GetCVarValueBool(CVAR_COOLDOWN_VIEWER_ENABLED)
    end
    -- Fallback for older clients
    local val = GetCVar(CVAR_COOLDOWN_VIEWER_ENABLED)
    return val == "1"
end

-- Safe wrapper for C_Spell.GetSpellCooldown
local function GetSpellCooldownSafe(spellID)
    if not spellID then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info then return info end
    return nil
end

-- Safe wrapper for C_Spell.GetSpellCharges
local function GetSpellChargesSafe(spellID)
    if not spellID then return nil end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if ok and info then return info end
    return nil
end

-- Safe wrapper for C_Spell.GetSpellTexture
local function GetSpellTextureSafe(spellID)
    if not spellID then return nil end
    local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if ok then return texture end
    return nil
end

-- Helper to get totem data for a spell (like Blizzard's CooldownViewerBuffItemMixin:GetTotemData)
-- Totems don't expose spellID directly, so we match by icon texture
local function GetTotemDataForSpellID(spellID)
    if not spellID then return nil end
    local spellTexture = GetSpellTextureSafe(spellID)
    if not spellTexture then return nil end
    
    for slot = 1, MAX_TOTEMS or 4 do
        local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
        if haveTotem and duration and duration > 0 then
            -- Match by icon texture
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

-- Get cooldown IDs from Blizzard's CooldownViewerSettings
local function GetCooldownIDsForCategory(category, categoryName)
    if not category then return {} end
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local provider = CooldownViewerSettings:GetDataProvider()
        if provider and provider.GetOrderedCooldownIDsForCategory then
            local ok, ids = pcall(provider.GetOrderedCooldownIDsForCategory, provider, category)
            if ok and ids then 
                return ids 
            else
                addon:Log(string.format("ERROR: GetCooldownIDsForCategory(%s) pcall failed", categoryName or "?"), "debug")
            end
        else
            addon:Log("ERROR: CooldownViewerSettings provider missing GetOrderedCooldownIDsForCategory", "debug")
        end
    else
        addon:Log("ERROR: CooldownViewerSettings not available", "debug")
    end
    return {}
end

-- Get cooldown info for a specific ID
local function GetCooldownInfoForID(cooldownID)
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
-- Module Lifecycle
-- ============================================================================

function Cooldowns:OnInitialize()
    self.db = addon.db
end

function Cooldowns:OnEnable()
    addon:Log("Cooldown Module Enabled", "discovery")
    
    self:CreateContainers()
    self:UpdateLayout()

    -- Prime aura cache early so first-use activations are instant
    AuraCache_RebuildFull()
    
    -- Register for spell cooldown events (event-driven updates)
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
    self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")  -- Also fires on cooldown changes
    self:RegisterEvent("SPELL_UPDATE_USABLE", "OnSpellUpdateCooldown")  -- Fires when spell becomes usable/unusable
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("PLAYER_TOTEM_UPDATE", "OnPlayerTotemUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")  -- Fires immediately on spell cast
    
    -- Listen for Blizzard's cooldown settings changes
    if EventRegistry then
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
            self:RefreshAllProxies()
        end, self)
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnSettingsLoaded", function()
            self:RefreshAllProxies()
        end, self)
    end
    
    -- Throttled OnUpdate for more responsive cooldown updates (fallback)
    self:StartThrottledUpdate()
    
    -- Retry UpdateLayout a few times in case data provider wasn't ready
    -- Blizzard's data provider can take a moment to populate after login
    C_Timer.After(0.2, function() self:UpdateLayout() end)
    C_Timer.After(0.5, function() self:UpdateLayout() end)
    C_Timer.After(1.0, function() self:UpdateLayout() end)
end

function Cooldowns:OnDisable()
    -- Stop throttled updates
    self:StopThrottledUpdate()
    
    -- Hide our containers
    if cdContainer then cdContainer:Hide() end
    if tbContainer then tbContainer:Hide() end
    if buffContainer then buffContainer:Hide() end
    
    -- Restore all hidden Blizzard frames
    self:RestoreAllBlizzardFrames()
    
    -- Unregister callbacks
    if EventRegistry then
        EventRegistry:UnregisterCallback("CooldownViewerSettings.OnDataChanged", self)
        EventRegistry:UnregisterCallback("CooldownViewerSettings.OnSettingsLoaded", self)
    end
end

-- Throttled update system for responsive cooldown display
local updateFrame = nil
local THROTTLE_INTERVAL = 0.05  -- 20 updates per second for faster response

function Cooldowns:StartThrottledUpdate()
    if updateFrame then return end
    
    updateFrame = CreateFrame("Frame")
    updateFrame.elapsed = 0
    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= THROTTLE_INTERVAL then
            self.elapsed = 0
            Cooldowns:OnThrottledUpdate()
        end
    end)
end

function Cooldowns:StopThrottledUpdate()
    if updateFrame then
        updateFrame:SetScript("OnUpdate", nil)
        updateFrame:Hide()
        updateFrame = nil
    end
end

function Cooldowns:OnThrottledUpdate()
    -- Cooldown proxies only. Buff/Bar activation should be event-driven via UNIT_AURA cache.
    if cdContainer and cdContainer:IsShown() then
        for key, proxy in pairs(activeProxies) do
            if key:match("^cd_") and proxy.cooldownInfo then
                self:PopulateProxy(proxy, proxy.cooldownID, proxy.cooldownInfo)
            end
        end
    end
end

-- ============================================================================
-- Container Creation
-- ============================================================================

function Cooldowns:CreateContainers()
    if cdContainer then return true end
    local main = _G["ActionHudFrame"]
    if not main then return false end
    
    -- Cooldown container (Essential/Utility)
    cdContainer = CreateFrame("Frame", "ActionHudCooldownContainer", main)
    cdContainer:SetSize(1, 1)
    cdContainer:SetPoint("CENTER", main, "CENTER", 0, 0)
    
    -- Tracked Bars container
    tbContainer = CreateFrame("Frame", "ActionHudTrackedBarsContainer", main)
    tbContainer:SetSize(1, 1)
    tbContainer:SetPoint("CENTER", main, "CENTER", 0, 0)

    -- Tracked Buffs container
    buffContainer = CreateFrame("Frame", "ActionHudBuffContainer", main)
    buffContainer:SetSize(1, 1)
    buffContainer:SetPoint("CENTER", main, "CENTER", 0, 0)
    
    return true
end

-- ============================================================================
-- Blizzard Frame Visibility (Hook-Based Hide/Show)
-- ============================================================================

-- Blizzard's UpdateShownState() keeps calling SetShown(true) on events like
-- PLAYER_REGEN_ENABLED, PLAYER_LEVEL_CHANGED, settings changes, etc.
-- We override UpdateShownState to prevent this when we want frames hidden.

function Cooldowns:HideBlizzardFrame(frameName)
    local frame = _G[frameName]
    if not frame then return end
    
    if not hiddenFrames[frameName] then
        -- Store original function reference
        hiddenFrames[frameName] = {
            originalUpdateShownState = frame.UpdateShownState
        }
        
        -- Override UpdateShownState to prevent Blizzard from auto-showing
        frame.UpdateShownState = function(self)
            -- Do nothing - ActionHud controls visibility
        end
        
        -- Actually hide the frame
        frame:Hide()
        
        addon:Log("Hooked and hidden Blizzard frame: " .. frameName, "frames")
    end
end

function Cooldowns:ShowBlizzardFrame(frameName)
    local frame = _G[frameName]
    if not frame then return end
    
    local saved = hiddenFrames[frameName]
    if saved then
        -- Restore original UpdateShownState function
        if saved.originalUpdateShownState then
            frame.UpdateShownState = saved.originalUpdateShownState
        end
        
        hiddenFrames[frameName] = nil
        
        -- Let Blizzard decide if it should show based on its own logic
        if frame.UpdateShownState then
            frame:UpdateShownState()
        else
            frame:Show()
        end
        
        addon:Log("Restored Blizzard frame: " .. frameName, "frames")
    end
end

function Cooldowns:RestoreAllBlizzardFrames()
    addon:Log("Restoring all Blizzard frames...", "frames")
    
    for _, group in pairs(blizzardFrames) do
        for _, frameName in ipairs(group) do
            self:ShowBlizzardFrame(frameName)
        end
    end
    
    wipe(hiddenFrames)
end

-- ============================================================================
-- Proxy Frame Management
-- ============================================================================

function Cooldowns:GetProxy(parent, proxyType)
    local proxy
    
    -- Try to find an unused proxy in the pool
    for _, p in ipairs(proxyPool) do
        if not p:IsShown() and p.proxyType == proxyType then
            proxy = p
            break
        end
    end
    
    -- Create new if needed
    if not proxy then
        proxy = CreateFrame("Button", nil, parent)
        proxy:SetSize(40, 40)
        proxy:EnableMouse(true)
        proxy.proxyType = proxyType
        
        -- Icon
        proxy.icon = proxy:CreateTexture(nil, "ARTWORK")
        proxy.icon:SetAllPoints()
        proxy.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        
        -- Cooldown swipe
        proxy.cooldown = CreateFrame("Cooldown", nil, proxy, "CooldownFrameTemplate")
        proxy.cooldown:SetAllPoints()
        proxy.cooldown:SetDrawEdge(false)
        
        -- Charge/Stack count (bottom right)
        proxy.count = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        proxy.count:SetPoint("BOTTOMRIGHT", proxy, "BOTTOMRIGHT", 2, -2)
        
        -- Timer text (center)
        proxy.timer = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        proxy.timer:SetPoint("CENTER", proxy, "CENTER", 0, 0)
        proxy.timer:SetTextColor(1, 0.8, 0) -- Gold
        
        -- Tooltip support
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

function Cooldowns:ReleaseProxy(proxy)
    proxy:Hide()
    proxy:ClearAllPoints()
    proxy.spellID = nil
    proxy.cooldownID = nil
    proxy.auraInstanceID = nil
    proxy.cooldownInfo = nil
end

function Cooldowns:ReleaseAllProxies()
    for key, proxy in pairs(activeProxies) do
        self:ReleaseProxy(proxy)
    end
    wipe(activeProxies)
end

-- ============================================================================
-- Data Population (Direct API Queries)
-- ============================================================================

function Cooldowns:PopulateProxy(proxy, cooldownID, cooldownInfo)
    if not cooldownInfo then return end
    
    local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    proxy.spellID = spellID
    proxy.cooldownID = cooldownID
    proxy.cooldownInfo = cooldownInfo
    
    -- Icon texture
    local texture = GetSpellTextureSafe(spellID)
    if texture then
        proxy.icon:SetTexture(texture)
    end
    
    -- Cooldown swipe
    local cdInfo = GetSpellCooldownSafe(spellID)
    if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
        local start = cdInfo.startTime
        local duration = cdInfo.duration
        local modRate = cdInfo.modRate or 1
        
        -- Check if it's just GCD (skip showing GCD)
        if cdInfo.activeCategory == Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY then
            CooldownFrame_Clear(proxy.cooldown)
            proxy.icon:SetDesaturated(false)
        else
            CooldownFrame_Set(proxy.cooldown, start, duration, true, false, modRate)
            proxy.icon:SetDesaturated(true)
        end
    else
        CooldownFrame_Clear(proxy.cooldown)
        proxy.icon:SetDesaturated(false)
    end
    
    -- Charge count
    local chargeInfo = GetSpellChargesSafe(spellID)
    if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
        proxy.count:SetText(chargeInfo.currentCharges)
        proxy.count:Show()
        
        -- If we have charges remaining but one is recharging, show charge cooldown
        if chargeInfo.currentCharges > 0 and chargeInfo.cooldownStartTime and chargeInfo.cooldownStartTime > 0 then
            CooldownFrame_Set(proxy.cooldown, chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, true, true, chargeInfo.chargeModRate or 1)
            proxy.icon:SetDesaturated(false)
        end
    else
        -- Check for spell cast count (e.g., Aimed Shot stacks)
        local castCount = spellID and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(spellID)
        if castCount and castCount > 0 then
            proxy.count:SetText(castCount)
            proxy.count:Show()
        else
            proxy.count:Hide()
        end
    end
    
    -- Hide timer (let cooldown frame handle it natively)
    proxy.timer:Hide()
    
    proxy:Show()
end

function Cooldowns:PopulateBuffProxy(proxy, cooldownID, cooldownInfo)
    if not cooldownInfo then return end
    
    -- Display spellID: prefer overrideTooltipSpellID for icon/name (Blizzard pattern)
    -- This fixes cases like "Seeing Red" vs "Violent Outburst" where they share the same base spellID
    local displaySpellID = cooldownInfo.overrideTooltipSpellID or cooldownInfo.overrideSpellID or cooldownInfo.spellID
    
    -- Aura check spellID: use overrideSpellID or base spellID (not tooltip override)
    local auraSpellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    
    proxy.spellID = auraSpellID
    proxy.cooldownID = cooldownID
    proxy.cooldownInfo = cooldownInfo
    
    -- Cache spell name for state change logging
    local spellName = displaySpellID and C_Spell.GetSpellName and C_Spell.GetSpellName(displaySpellID) or "Unknown"
    proxy.spellName = spellName
    
    -- Always show icon texture using displaySpellID (like Blizzard does for configured buffs)
    local texture = GetSpellTextureSafe(displaySpellID)
    if texture then
        proxy.icon:SetTexture(texture)
    end
    
    -- Always show proxy - configured buffs should always be visible
    proxy:Show()
    
    -- Track previous state for change detection (use persistent table, not proxy)
    local wasActive = lastKnownState[cooldownID]
    local isActive = false
    local activeSource = nil
    local foundSpellID = nil
    
    -- Check for totem first (like Blizzard's CooldownViewerBuffItemMixin:ShouldBeActive)
    local totemData = GetTotemDataForSpellID(auraSpellID)
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
        -- Check for active aura
        local auraData = nil

        -- Prefer linkedSpellIDs (Blizzard model), but use our event-driven aura cache.
        if cooldownInfo.linkedSpellIDs then
            for _, linkedID in ipairs(cooldownInfo.linkedSpellIDs) do
                auraData = auraBySpellID[linkedID]
                if auraData then
                    foundSpellID = linkedID
                    activeSource = "linked"
                    break
                end
            end
        end

        -- Fallback to auraSpellID
        if not auraData and auraSpellID then
            auraData = auraBySpellID[auraSpellID]
            if auraData then
                foundSpellID = auraSpellID
                activeSource = "aura"
            end
        end

        -- Also try overrideSpellID if different
        if not auraData and cooldownInfo.overrideSpellID and cooldownInfo.overrideSpellID ~= auraSpellID then
            auraData = auraBySpellID[cooldownInfo.overrideSpellID]
            if auraData then
                foundSpellID = cooldownInfo.overrideSpellID
                activeSource = "override"
            end
        end

        -- Last resort: match by name using cache (no scanning)
        if not auraData and spellName and spellName ~= "Unknown" then
            auraData = auraByName[spellName]
            if auraData then
                foundSpellID = auraData.spellId
                activeSource = "name_cache"
            end
        end

        -- Now populate proxy with auraData (whether found by ID or name)
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
            -- Inactive - clear cached data
            proxy.auraInstanceID = nil
            proxy.icon:SetDesaturated(true)
            CooldownFrame_Clear(proxy.cooldown)
            proxy.count:Hide()
        end
    end
    
    -- Log only on state change (using persistent table to survive proxy recycling)
    if wasActive ~= isActive then
        if isActive then
            addon:Log(string.format("ACTIVATED: %s (id=%s, source=%s, foundID=%s)", 
                spellName, tostring(cooldownID), activeSource or "?", tostring(foundSpellID)), "debug")
        else
            -- Only log DEACTIVATED if we previously knew it was active (not first time seeing it)
            if wasActive == true then
                addon:Log(string.format("DEACTIVATED: %s (id=%s)", spellName, tostring(cooldownID)), "debug")
            end
        end
    end
    lastKnownState[cooldownID] = isActive
end

-- ============================================================================
-- Layout and Rendering
-- ============================================================================

function Cooldowns:UpdateLayout()
    if not self:CreateContainers() then return end
    local main = _G["ActionHudFrame"]
    if not main then return end
    local p = self.db.profile
    
    -- Check if Blizzard's Cooldown Manager is even enabled
    local blizzEnabled = self:IsBlizzardCooldownViewerEnabled()
    
    -- --- 1. COOLDOWN CONTAINER (Essential/Utility) ---
    self:UpdateCooldownContainer(main, p, blizzEnabled)
    
    -- --- 2. TRACKED BARS ---
    self:UpdateTrackedBarsContainer(main, p, blizzEnabled)
    
    -- --- 3. TRACKED BUFFS ---
    self:UpdateTrackedBuffsContainer(main, p, blizzEnabled)
end

function Cooldowns:UpdateCooldownContainer(main, p, blizzEnabled)
    if not cdContainer then return end
    
    -- Position the container
    local anchorFrame = main
    if ns.Resources and ns.Resources.GetContainer then
        local resContainer = ns.Resources:GetContainer()
        if resContainer and resContainer:IsShown() then
            if addon.db.profile.resPosition == p.cdPosition then
                anchorFrame = resContainer
            end
        end
    end
    
    cdContainer:ClearAllPoints()
    local gap = p.cdGap
    if p.cdPosition == "TOP" then
        cdContainer:SetPoint("BOTTOM", anchorFrame, "TOP", 0, gap)
    else 
        cdContainer:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -gap)
    end
    
    if p.cdEnabled and blizzEnabled then
        -- Hide Blizzard frames (unless debug mode is on)
        if not p.debugShowBlizzardFrames then
            for _, frameName in ipairs(blizzardFrames.cd) do
                self:HideBlizzardFrame(frameName)
            end
        else
            -- Debug mode: show both Blizzard and our proxies
            for _, frameName in ipairs(blizzardFrames.cd) do
                self:ShowBlizzardFrame(frameName)
            end
        end
        
        cdContainer:Show()
        self:RenderCooldownProxies(cdContainer, p)
    else
        cdContainer:Hide()
        -- Restore Blizzard frames
        for _, frameName in ipairs(blizzardFrames.cd) do
            self:ShowBlizzardFrame(frameName)
        end
        -- Release proxies for this container
        self:ReleaseCooldownProxies()
    end
end

function Cooldowns:UpdateTrackedBarsContainer(main, p, blizzEnabled)
    if not tbContainer then return end
    
    -- Position (sidecar)
    tbContainer:ClearAllPoints()
    tbContainer:SetPoint("CENTER", main, "CENTER", p.tbXOffset or 100, p.tbYOffset or 0)
    
    if p.tbEnabled and blizzEnabled then
        -- Hide Blizzard frames (unless debug mode is on)
        if not p.debugShowBlizzardFrames then
            for _, frameName in ipairs(blizzardFrames.bars) do
                self:HideBlizzardFrame(frameName)
            end
        else
            -- Debug mode: show both Blizzard and our proxies
            for _, frameName in ipairs(blizzardFrames.bars) do
                self:ShowBlizzardFrame(frameName)
            end
        end
        
        tbContainer:Show()
        self:RenderTrackedBarProxies(tbContainer, p)
    else
        tbContainer:Hide()
        -- Restore Blizzard frames
        for _, frameName in ipairs(blizzardFrames.bars) do
            self:ShowBlizzardFrame(frameName)
        end
        self:ReleaseTrackedBarProxies()
    end
end

function Cooldowns:UpdateTrackedBuffsContainer(main, p, blizzEnabled)
    if not buffContainer then return end
    
    -- Position (above HUD/Resources)
    buffContainer:ClearAllPoints()
    local resFrame = _G["ActionHudResources"]
    local resPos = p.resPosition or "TOP"
    if resFrame and resFrame:IsShown() and resPos == "TOP" then
        buffContainer:SetPoint("BOTTOM", resFrame, "TOP", 0, p.buffsGap)
    else
        buffContainer:SetPoint("BOTTOM", main, "TOP", 0, p.buffsGap)
    end
    
    if p.buffsEnabled and blizzEnabled then
        -- Hide Blizzard frames (unless debug mode is on)
        if not p.debugShowBlizzardFrames then
            for _, frameName in ipairs(blizzardFrames.buffs) do
                self:HideBlizzardFrame(frameName)
            end
        else
            -- Debug mode: show both Blizzard and our proxies
            for _, frameName in ipairs(blizzardFrames.buffs) do
                self:ShowBlizzardFrame(frameName)
            end
        end
        
        buffContainer:Show()
        self:RenderBuffProxies(buffContainer, p)
    else
        buffContainer:Hide()
        -- Restore Blizzard frames
        for _, frameName in ipairs(blizzardFrames.buffs) do
            self:ShowBlizzardFrame(frameName)
        end
        self:ReleaseBuffProxies()
    end
end

-- ============================================================================
-- Proxy Rendering
-- ============================================================================

function Cooldowns:RenderCooldownProxies(container, p)
    -- Release old proxies first to prevent stale items from previous filter state
    self:ReleaseCooldownProxies()
    
    local categories = {}
    
    -- Resolve categories at runtime (Enum may not be populated at file load)
    local essentialCat = GetEssentialCategory()
    local utilityCat = GetUtilityCategory()
    
    -- Determine order
    if p.cdReverse then
        if utilityCat then table.insert(categories, { name = "Utility", cat = utilityCat, w = p.cdUtilityWidth, h = p.cdUtilityHeight }) end
        if essentialCat then table.insert(categories, { name = "Essential", cat = essentialCat, w = p.cdEssentialWidth, h = p.cdEssentialHeight }) end
    else
        if essentialCat then table.insert(categories, { name = "Essential", cat = essentialCat, w = p.cdEssentialWidth, h = p.cdEssentialHeight }) end
        if utilityCat then table.insert(categories, { name = "Utility", cat = utilityCat, w = p.cdUtilityWidth, h = p.cdUtilityHeight }) end
    end
    
    local yOffset = 0
    local spacing = p.cdSpacing
    local itemGap = p.cdItemGap
    
    for _, catInfo in ipairs(categories) do
        local cooldownIDs = GetCooldownIDsForCategory(catInfo.cat, catInfo.name)
        if #cooldownIDs > 0 then
            local rowWidth = 0
            local xOffset = 0
            
            for i, cooldownID in ipairs(cooldownIDs) do
                local info = GetCooldownInfoForID(cooldownID)
                if info and info.spellID then
                    local proxyKey = "cd_" .. cooldownID
                    local proxy = activeProxies[proxyKey]
                    if not proxy then
                        proxy = self:GetProxy(container, "cooldown")
                        activeProxies[proxyKey] = proxy
                    end
                    
                    proxy:SetSize(catInfo.w, catInfo.h)
                    proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.cdCountFontSize or 10, "OUTLINE")
                    proxy.cooldown:SetCountdownFont(GetTimerFont(p.cdTimerFontSize))
                    
                    self:PopulateProxy(proxy, cooldownID, info)
                    
                    -- Position horizontally centered
                    proxy:ClearAllPoints()
                    -- We'll calculate center offset after counting all items
                    proxy.pendingX = xOffset
                    proxy.pendingY = yOffset
                    
                    xOffset = xOffset + catInfo.w + itemGap
                    rowWidth = xOffset - itemGap
                end
            end
            
            -- Now center all proxies in this row
            local centerOffset = -rowWidth / 2
            for _, cooldownID in ipairs(cooldownIDs) do
                local proxyKey = "cd_" .. cooldownID
                local proxy = activeProxies[proxyKey]
                if proxy and proxy.pendingX then
                    if p.cdPosition == "TOP" then
                        proxy:SetPoint("BOTTOMLEFT", container, "BOTTOM", centerOffset + proxy.pendingX, proxy.pendingY)
                    else
                        proxy:SetPoint("TOPLEFT", container, "TOP", centerOffset + proxy.pendingX, -proxy.pendingY)
                    end
                    proxy.pendingX = nil
                    proxy.pendingY = nil
                end
            end
            
            yOffset = yOffset + catInfo.h + spacing
        end
    end
end

function Cooldowns:RenderTrackedBarProxies(container, p)
    -- Release old proxies first to prevent stale items from previous filter state
    self:ReleaseTrackedBarProxies()
    
    -- Resolve category at runtime
    local category = GetTrackedBarCategory()
    if not category then return end
    
    local cooldownIDs = GetCooldownIDsForCategory(category, "TrackedBar")
    local yOffset = 0
    local gap = p.tbGap
    local hideInactive = p.tbHideInactive
    local inactiveAlpha = p.tbInactiveOpacity or 0.5
    
    for i, cooldownID in ipairs(cooldownIDs) do
        local info = GetCooldownInfoForID(cooldownID)
        if info and info.spellID then
            local proxyKey = "tb_" .. cooldownID
            local proxy = activeProxies[proxyKey]
            if not proxy then
                proxy = self:GetProxy(container, "bar")
                activeProxies[proxyKey] = proxy
            end
            
            proxy:SetSize(p.tbWidth, p.tbHeight)
            proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.tbCountFontSize or 10, "OUTLINE")
            proxy.cooldown:SetCountdownFont(GetTimerFont(p.tbTimerFontSize))
            
            -- Store references for throttled updates
            proxy.cooldownID = cooldownID
            proxy.cooldownInfo = info
            
            self:PopulateBuffProxy(proxy, cooldownID, info)
            
            -- Handle visibility based on active state and hideInactive setting
            local isActive = not proxy.icon:IsDesaturated()
            
            if hideInactive and not isActive then
                proxy:Hide()
            else
                proxy:Show()
                -- Apply opacity for inactive bars
                if not isActive then
                    proxy:SetAlpha(inactiveAlpha)
                else
                    proxy:SetAlpha(1.0)
                end
                
                proxy:ClearAllPoints()
                proxy:SetPoint("TOP", container, "TOP", 0, -yOffset)
                yOffset = yOffset + p.tbHeight + gap
            end
        end
    end
end

function Cooldowns:RenderBuffProxies(container, p)
    -- Release old proxies first to prevent stale items from previous filter state
    self:ReleaseBuffProxies()
    
    -- Resolve category at runtime
    local category = GetTrackedBuffCategory()
    if not category then return end
    
    local cooldownIDs = GetCooldownIDsForCategory(category, "TrackedBuff")
    local gap = p.buffsSpacing
    local allProxies = {}
    local hideInactive = p.buffsHideInactive
    local inactiveAlpha = p.buffsInactiveOpacity or 0.5
    
    for i, cooldownID in ipairs(cooldownIDs) do
        local info = GetCooldownInfoForID(cooldownID)
        if info and info.spellID then
            local proxyKey = "buff_" .. cooldownID
            local proxy = activeProxies[proxyKey]
            if not proxy then
                proxy = self:GetProxy(container, "buff")
                activeProxies[proxyKey] = proxy
            end
            
            proxy:SetSize(p.buffsWidth, p.buffsHeight)
            proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.buffsCountFontSize or 8, "OUTLINE")
            proxy.cooldown:SetCountdownFont(GetTimerFont(p.buffsTimerFontSize))
            
            -- Store references for throttled updates
            proxy.cooldownID = cooldownID
            proxy.cooldownInfo = info
            
            self:PopulateBuffProxy(proxy, cooldownID, info)
            
            -- Handle visibility based on active state and hideInactive setting
            local isActive = not proxy.icon:IsDesaturated()
            
            if hideInactive and not isActive then
                proxy:Hide()
            else
                proxy:Show()
                -- Apply opacity for inactive buffs
                if not isActive then
                    proxy:SetAlpha(inactiveAlpha)
                else
                    proxy:SetAlpha(1.0)
                end
                table.insert(allProxies, proxy)
            end
        end
    end
    
    -- Center all visible proxies
    if #allProxies > 0 then
        local totalWidth = (#allProxies * p.buffsWidth) + ((#allProxies - 1) * gap)
        local startX = -totalWidth / 2
        
        for i, proxy in ipairs(allProxies) do
            proxy:ClearAllPoints()
            proxy:SetPoint("LEFT", container, "CENTER", startX + (i - 1) * (p.buffsWidth + gap), 0)
        end
    end
end

-- Release functions for each category
function Cooldowns:ReleaseCooldownProxies()
    for key, proxy in pairs(activeProxies) do
        if key:match("^cd_") then
            self:ReleaseProxy(proxy)
            activeProxies[key] = nil
        end
    end
end

function Cooldowns:ReleaseTrackedBarProxies()
    for key, proxy in pairs(activeProxies) do
        if key:match("^tb_") then
            self:ReleaseProxy(proxy)
            activeProxies[key] = nil
        end
    end
end

function Cooldowns:ReleaseBuffProxies()
    for key, proxy in pairs(activeProxies) do
        if key:match("^buff_") then
            self:ReleaseProxy(proxy)
            activeProxies[key] = nil
        end
    end
end

-- ============================================================================
-- Event Handlers (Event-Driven Updates)
-- ============================================================================

function Cooldowns:OnSpellUpdateCooldown()
    -- Refresh cooldown proxies
    if cdContainer and cdContainer:IsShown() then
        for key, proxy in pairs(activeProxies) do
            if key:match("^cd_") and proxy.cooldownInfo then
                self:PopulateProxy(proxy, proxy.cooldownID, proxy.cooldownInfo)
            end
        end
    end
end

function Cooldowns:OnUnitAura(event, unit, unitAuraUpdateInfo)
    if unit ~= "player" then return end
    
    -- Update our aura cache first (Blizzard-style event-driven model)
    AuraCache_ApplyUpdateInfo(unitAuraUpdateInfo)

    local p = self.db.profile
    
    -- Refresh buff proxies (don't re-render, just update existing)
    if buffContainer and buffContainer:IsShown() then
        for key, proxy in pairs(activeProxies) do
            if key:match("^buff_") and proxy.cooldownInfo then
                self:PopulateBuffProxy(proxy, proxy.cooldownID, proxy.cooldownInfo)
                -- Update opacity immediately based on active state
                local isActive = not proxy.icon:IsDesaturated()
                if p.buffsHideInactive and not isActive then
                    proxy:Hide()
                else
                    proxy:Show()
                    proxy:SetAlpha(isActive and 1.0 or (p.buffsInactiveOpacity or 0.5))
                end
            end
        end
    end
    
    if tbContainer and tbContainer:IsShown() then
        for key, proxy in pairs(activeProxies) do
            if key:match("^tb_") and proxy.cooldownInfo then
                self:PopulateBuffProxy(proxy, proxy.cooldownID, proxy.cooldownInfo)
                -- Update opacity immediately based on active state
                local isActive = not proxy.icon:IsDesaturated()
                if p.tbHideInactive and not isActive then
                    proxy:Hide()
                else
                    proxy:Show()
                    proxy:SetAlpha(isActive and 1.0 or (p.tbInactiveOpacity or 0.5))
                end
            end
        end
    end
end

function Cooldowns:OnPlayerTotemUpdate()
    -- Totems affect some cooldown displays
    self:OnUnitAura("UNIT_AURA", "player")
end

function Cooldowns:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    -- Fires immediately when player casts a spell - trigger buff check
    if unit ~= "player" then return end
    -- Small delay to allow aura to be applied
    C_Timer.After(0.01, function()
        self:OnUnitAura("UNIT_AURA", "player")
    end)
end

function Cooldowns:OnPlayerEnteringWorld()
    -- Full refresh on zone changes
    C_Timer.After(0.5, function()
        self:UpdateLayout()
    end)
end

function Cooldowns:RefreshAllProxies()
    self:UpdateLayout()
end

-- ============================================================================
-- Debug Functions
-- ============================================================================

function Cooldowns:FindPotentialTargets()
    if not self.db.profile.debugDiscovery then return end
    
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

-- Diagnostic: Dump all tracked buff/bar info for debugging spell ID issues
function Cooldowns:DumpTrackedBuffInfo()
    print("|cff33ff99ActionHud:|r Dumping Tracked Buff/Bar Info...")
    
    -- Tracked Buffs
    local buffCategory = GetTrackedBuffCategory()
    if buffCategory then
        local buffIDs = GetCooldownIDsForCategory(buffCategory, "TrackedBuff")
        print("|cff00ff00Tracked Buffs:|r " .. #buffIDs .. " items")
        for i, cooldownID in ipairs(buffIDs) do
            local info = GetCooldownInfoForID(cooldownID)
            if info then
                local name = C_Spell.GetSpellName(info.spellID) or "?"
                local linkedStr = "none"
                if info.linkedSpellIDs and #info.linkedSpellIDs > 0 then
                    linkedStr = table.concat(info.linkedSpellIDs, ", ")
                end
                print(string.format("  [%d] %s: spellID=%s, linked=[%s], override=%s, tooltipOverride=%s",
                    cooldownID, name, tostring(info.spellID), linkedStr,
                    tostring(info.overrideSpellID), tostring(info.overrideTooltipSpellID)))
            end
        end
    end
    
    -- Tracked Bars
    local barCategory = GetTrackedBarCategory()
    if barCategory then
        local barIDs = GetCooldownIDsForCategory(barCategory, "TrackedBar")
        print("|cff00ff00Tracked Bars:|r " .. #barIDs .. " items")
        for i, cooldownID in ipairs(barIDs) do
            local info = GetCooldownInfoForID(cooldownID)
            if info then
                local name = C_Spell.GetSpellName(info.spellID) or "?"
                local linkedStr = "none"
                if info.linkedSpellIDs and #info.linkedSpellIDs > 0 then
                    linkedStr = table.concat(info.linkedSpellIDs, ", ")
                end
                print(string.format("  [%d] %s: spellID=%s, linked=[%s], override=%s, tooltipOverride=%s",
                    cooldownID, name, tostring(info.spellID), linkedStr,
                    tostring(info.overrideSpellID), tostring(info.overrideTooltipSpellID)))
            end
        end
    end
    
    print("|cff33ff99ActionHud:|r Dump complete.")
end
