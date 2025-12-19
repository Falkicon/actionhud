local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffs = addon:NewModule("TrackedBuffs", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Local upvalues for performance
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local table_insert = table.insert

local lastKnownState = {} -- [cooldownID] = boolean
local activeProxies = {} -- [proxyKey] = proxyFrame

-- Reusable tables to avoid garbage creation
local usedKeysCache = {}
local allProxyDataCache = {}
local visibleProxiesCache = {}

local function GetTrackedBuffCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff
end

function TrackedBuffs:OnInitialize()
    self.db = addon.db
end

function TrackedBuffs:OnEnable()
    Manager:CreateContainer("buffs", "ActionHudBuffContainer")
    self:UpdateLayout()
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

    -- Single delayed retry in case data provider wasn't ready at OnEnable
    C_Timer.After(0.5, function() self:UpdateLayout() end)
end

function TrackedBuffs:OnDisable()
    local container = Manager:GetContainer("buffs")
    if container then container:Hide() end
    local blizzardFrames = Manager:GetBlizzardFrames()
    for _, frameName in ipairs(blizzardFrames.buffs) do
        Manager:ShowBlizzardFrame(frameName)
    end
end

-- Calculate the height of this module for LayoutManager
function TrackedBuffs:CalculateHeight()
    local p = self.db.profile
    if not p.buffsEnabled then return 0 end
    
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    if not blizzEnabled then return 0 end
    
    return p.buffsHeight or 28
end

-- Get the width of this module for LayoutManager
function TrackedBuffs:GetLayoutWidth()
    local p = addon.db.profile
    local cols = 6
    return cols * (p.iconWidth or 20)
end

-- Apply position from LayoutManager
function TrackedBuffs:ApplyLayoutPosition()
    local container = Manager:GetContainer("buffs")
    if not container then return end
    
    local p = self.db.profile
    if not p.buffsEnabled then 
        container:Hide()
        return
    end
    
    local main = _G["ActionHudFrame"]
    if not main then return end
    
    local LM = addon:GetModule("LayoutManager", true)
    if not LM then return end
    
    local yOffset = LM:GetModulePosition("trackedBuffs")
    container:ClearAllPoints()
    -- Center horizontally within main frame
    container:SetPoint("TOP", main, "TOP", 0, yOffset)
    container:Show()
    
    addon:Log(string.format("TrackedBuffs positioned: yOffset=%d", yOffset), "layout")
end

function TrackedBuffs:UpdateLayout()
    local main = _G["ActionHudFrame"]
    if not main then return end
    local p = self.db.profile
    local container = Manager:GetContainer("buffs")
    if not container then return end
    
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    
    -- Report height to LayoutManager
    local LM = addon:GetModule("LayoutManager", true)
    local height = self:CalculateHeight()
    if LM then
        LM:SetModuleHeight("trackedBuffs", height)
    end
    
    if p.buffsEnabled and blizzEnabled then
        local blizzardFrames = Manager:GetBlizzardFrames()
        if not p.debugShowBlizzardFrames then
            for _, frameName in ipairs(blizzardFrames.buffs) do Manager:HideBlizzardFrame(frameName) end
        else
            for _, frameName in ipairs(blizzardFrames.buffs) do Manager:ShowBlizzardFrame(frameName) end
        end
        container:Show()
        Manager:UpdateContainerDebug("buffs", {r=0, g=1, b=0}) -- Green for buffs
        self:RenderBuffProxies(container, p)
    else
        container:Hide()
        local blizzardFrames = Manager:GetBlizzardFrames()
        for _, frameName in ipairs(blizzardFrames.buffs) do Manager:ShowBlizzardFrame(frameName) end
        self:ReleaseBuffProxies()
    end
end

function TrackedBuffs:RenderBuffProxies(container, p)
    local category = GetTrackedBuffCategory()
    if not category then return end
    
    local cooldownIDs = Manager:GetCooldownIDsForCategory(category, "TrackedBuff")
    local gap = p.buffsSpacing
    local hideInactive = p.buffsHideInactive
    local inactiveAlpha = p.buffsInactiveOpacity or 0.5
    
    -- Reuse cached tables to avoid garbage creation
    wipe(usedKeysCache)
    wipe(allProxyDataCache)
    wipe(visibleProxiesCache)
    
    -- PASS 1: Get/create proxies and populate them (don't show/hide yet)
    for _, cooldownID in ipairs(cooldownIDs) do
        local info = Manager:GetCooldownInfoForID(cooldownID)
        if info and info.spellID then
            -- Cache proxyKey on proxy to avoid repeated string concat
            local proxy = activeProxies[cooldownID]
            if not proxy then
                proxy = Manager:GetProxy(container, "buff")
                activeProxies[cooldownID] = proxy
                proxy.proxyKey = cooldownID
            end
            usedKeysCache[cooldownID] = true
            
            -- Mark this proxy as leased to this key
            proxy.leasedTo = cooldownID
            
            proxy:SetSize(p.buffsWidth, p.buffsHeight)
            proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.buffsCountFontSize or 8, "OUTLINE")
            proxy.cooldown:SetCountdownFont(Utils.GetTimerFont(p.buffsTimerFontSize))
            
            proxy.cooldownID = cooldownID
            proxy.cooldownInfo = info
            
            Manager:PopulateBuffProxy(proxy, cooldownID, info, lastKnownState, ns)
            
            -- Store isActive on proxy to avoid creating intermediate tables
            proxy._isActive = not proxy.icon:IsDesaturated()
            table_insert(allProxyDataCache, proxy)
        end
    end
    
    -- PASS 2: Determine which proxies to show and collect them for positioning
    for _, proxy in ipairs(allProxyDataCache) do
        if hideInactive and not proxy._isActive then
            -- Will be hidden in pass 3
        else
            proxy:SetAlpha(proxy._isActive and 1.0 or inactiveAlpha)
            table_insert(visibleProxiesCache, proxy)
        end
    end
    
    -- PASS 3: Position and show visible proxies, hide inactive ones
    local numVisible = #visibleProxiesCache
    if numVisible > 0 then
        local totalWidth = (numVisible * p.buffsWidth) + ((numVisible - 1) * gap)
        local startX = -totalWidth / 2
        -- Debug logging removed from hot path to avoid string.format garbage
        for i, proxy in ipairs(visibleProxiesCache) do
            proxy:ClearAllPoints()
            local x = startX + (i - 1) * (p.buffsWidth + gap)
            proxy:SetPoint("LEFT", container, "CENTER", x, 0)
            proxy:Show()
        end
        container:SetSize(totalWidth, p.buffsHeight)
    else
        container:SetSize(1, 1)
    end
    
    -- PASS 4: Hide inactive proxies (after all positioning is done)
    for _, proxy in ipairs(allProxyDataCache) do
        if hideInactive and not proxy._isActive then
            proxy:Hide()
            proxy:ClearAllPoints()
        end
    end

    -- Cleanup any proxies that are no longer in the configured list
    for key, proxy in pairs(activeProxies) do
        if not usedKeysCache[key] then
            Manager:ReleaseProxy(proxy)
            activeProxies[key] = nil
        end
    end
end

function TrackedBuffs:ReleaseBuffProxies()
    for key, proxy in pairs(activeProxies) do
        Manager:ReleaseProxy(proxy)
        activeProxies[key] = nil
    end
end

-- Lightweight update: refresh existing proxies without full re-render
-- Only updates aura state, doesn't recreate or reposition proxies
function TrackedBuffs:RefreshActiveProxies()
    local p = self.db.profile
    local hideInactive = p.buffsHideInactive
    local inactiveAlpha = p.buffsInactiveOpacity or 0.5
    local gap = p.buffsSpacing
    local needsReposition = false
    
    -- Update each proxy's state
    for key, proxy in pairs(activeProxies) do
        if proxy.cooldownInfo then
            local wasActive = not proxy.icon:IsDesaturated()
            Manager:PopulateBuffProxy(proxy, proxy.cooldownID, proxy.cooldownInfo, lastKnownState, ns)
            local isActive = not proxy.icon:IsDesaturated()
            
            -- Check if visibility changed (needs repositioning)
            if hideInactive and wasActive ~= isActive then
                needsReposition = true
            end
            
            -- Update alpha for visible proxies
            if not hideInactive or isActive then
                proxy:SetAlpha(isActive and 1.0 or inactiveAlpha)
            end
        end
    end
    
    -- Only do full reposition if visibility changed
    if needsReposition then
        local container = Manager:GetContainer("buffs")
        if container then
            self:RenderBuffProxies(container, p)
        end
    end
end

-- Called by Manager after aura cache update
function TrackedBuffs:OnAuraUpdate()
    local container = Manager:GetContainer("buffs")
    if container and container:IsShown() then
        -- Use lightweight refresh instead of full re-render
        self:RefreshActiveProxies()
    end
end

function TrackedBuffs:OnPlayerEnteringWorld()
    -- Direct call - data provider should be ready for zone transitions
    self:UpdateLayout()
end
