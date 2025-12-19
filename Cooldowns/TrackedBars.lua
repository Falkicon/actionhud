local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBars = addon:NewModule("TrackedBars", "AceEvent-3.0")
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

local function GetTrackedBarCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
end

function TrackedBars:OnInitialize()
    self.db = addon.db
end

function TrackedBars:OnEnable()
    Manager:CreateContainer("bars", "ActionHudTrackedBarsContainer")
    self:UpdateLayout()
    
    self:RegisterEvent("PLAYER_TOTEM_UPDATE", "OnAuraUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

    -- Single delayed retry in case data provider wasn't ready at OnEnable
    C_Timer.After(0.5, function() self:UpdateLayout() end)
end

function TrackedBars:OnDisable()
    local container = Manager:GetContainer("bars")
    if container then container:Hide() end
    
    local blizzardFrames = Manager:GetBlizzardFrames()
    for _, frameName in ipairs(blizzardFrames.bars) do
        Manager:ShowBlizzardFrame(frameName)
    end
end

function TrackedBars:UpdateLayout()
    local main = _G["ActionHudFrame"]
    if not main then return end
    local p = self.db.profile
    local container = Manager:GetContainer("bars")
    if not container then return end
    
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    
    container:ClearAllPoints()
    container:SetPoint("CENTER", main, "CENTER", p.tbXOffset or 100, p.tbYOffset or 0)
    
    if p.tbEnabled and blizzEnabled then
        local blizzardFrames = Manager:GetBlizzardFrames()
        if not p.debugShowBlizzardFrames then
            for _, frameName in ipairs(blizzardFrames.bars) do Manager:HideBlizzardFrame(frameName) end
        else
            for _, frameName in ipairs(blizzardFrames.bars) do Manager:ShowBlizzardFrame(frameName) end
        end
        container:Show()
        Manager:UpdateContainerDebug("bars", {r=1, g=0, b=0}) -- Red for bars
        self:RenderTrackedBarProxies(container, p)
    else
        container:Hide()
        local blizzardFrames = Manager:GetBlizzardFrames()
        for _, frameName in ipairs(blizzardFrames.bars) do Manager:ShowBlizzardFrame(frameName) end
        self:ReleaseTrackedBarProxies()
    end
end

function TrackedBars:RenderTrackedBarProxies(container, p)
    local category = GetTrackedBarCategory()
    if not category then return end
    
    local cooldownIDs = Manager:GetCooldownIDsForCategory(category, "TrackedBar")
    local gap = p.tbGap
    local hideInactive = p.tbHideInactive
    local inactiveAlpha = p.tbInactiveOpacity or 0.5
    
    -- Reuse cached tables to avoid garbage creation
    wipe(usedKeysCache)
    wipe(allProxyDataCache)
    
    -- PASS 1: Get/create proxies and populate them (don't show/hide yet)
    for _, cooldownID in ipairs(cooldownIDs) do
        local info = Manager:GetCooldownInfoForID(cooldownID)
        if info and info.spellID then
            -- Use cooldownID directly as key to avoid string concatenation
            local proxy = activeProxies[cooldownID]
            if not proxy then
                proxy = Manager:GetProxy(container, "bar")
                activeProxies[cooldownID] = proxy
                proxy.proxyKey = cooldownID
            end
            usedKeysCache[cooldownID] = true
            
            -- Mark this proxy as leased to this key
            proxy.leasedTo = cooldownID
            
            proxy:SetSize(p.tbWidth, p.tbHeight)
            proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.tbCountFontSize or 10, "OUTLINE")
            proxy.cooldown:SetCountdownFont(Utils.GetTimerFont(p.tbTimerFontSize))
            
            proxy.cooldownID = cooldownID
            proxy.cooldownInfo = info
            
            Manager:PopulateBuffProxy(proxy, cooldownID, info, lastKnownState, ns)
            
            -- Store isActive on proxy to avoid creating intermediate tables
            proxy._isActive = not proxy.icon:IsDesaturated()
            table_insert(allProxyDataCache, proxy)
        end
    end
    
    -- PASS 2: Position and show visible proxies
    local yOffset = 0
    for _, proxy in ipairs(allProxyDataCache) do
        if hideInactive and not proxy._isActive then
            -- Will be hidden in pass 3
        else
            proxy:SetAlpha(proxy._isActive and 1.0 or inactiveAlpha)
            proxy:ClearAllPoints()
            proxy:SetPoint("TOP", container, "TOP", 0, -yOffset)
            proxy:Show()
            -- Debug logging removed from hot path to avoid string.format garbage
            yOffset = yOffset + p.tbHeight + gap
        end
    end
    
    -- PASS 3: Hide inactive proxies (after all positioning is done)
    for _, proxy in ipairs(allProxyDataCache) do
        if hideInactive and not proxy._isActive then
            proxy:Hide()
            proxy:ClearAllPoints()
        end
    end
    
    if yOffset > 0 then
        container:SetSize(p.tbWidth, yOffset - gap)
    else
        container:SetSize(1, 1)
    end
    
    -- Cleanup any proxies that are no longer in the configured list
    for key, proxy in pairs(activeProxies) do
        if not usedKeysCache[key] then
            Manager:ReleaseProxy(proxy)
            activeProxies[key] = nil
        end
    end
end

function TrackedBars:ReleaseTrackedBarProxies()
    for key, proxy in pairs(activeProxies) do
        Manager:ReleaseProxy(proxy)
        activeProxies[key] = nil
    end
end

-- Lightweight update: refresh existing proxies without full re-render
-- Only updates aura state, doesn't recreate or reposition proxies
function TrackedBars:RefreshActiveProxies()
    local p = self.db.profile
    local hideInactive = p.tbHideInactive
    local inactiveAlpha = p.tbInactiveOpacity or 0.5
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
        local container = Manager:GetContainer("bars")
        if container then
            self:RenderTrackedBarProxies(container, p)
        end
    end
end

-- Called by Manager after aura cache update
function TrackedBars:OnAuraUpdate()
    local container = Manager:GetContainer("bars")
    if container and container:IsShown() then
        -- Use lightweight refresh instead of full re-render
        self:RefreshActiveProxies()
    end
end

function TrackedBars:OnPlayerEnteringWorld()
    -- Direct call - data provider should be ready for zone transitions
    self:UpdateLayout()
end
