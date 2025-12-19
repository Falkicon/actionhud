local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffs = addon:NewModule("TrackedBuffs", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

local lastKnownState = {} -- [cooldownID] = boolean
local activeProxies = {} -- [proxyKey] = proxyFrame

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

    -- Initial retries for Blizzard data
    C_Timer.After(0.2, function() self:UpdateLayout() end)
    C_Timer.After(0.5, function() self:UpdateLayout() end)
    C_Timer.After(1.0, function() self:UpdateLayout() end)
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
    
    -- Track which proxies we use in this pass
    local usedKeys = {}
    local allProxyData = {} -- Store proxy + isActive for later positioning
    
    -- PASS 1: Get/create proxies and populate them (don't show/hide yet)
    for _, cooldownID in ipairs(cooldownIDs) do
        local info = Manager:GetCooldownInfoForID(cooldownID)
        if info and info.spellID then
            local proxyKey = "buff_" .. cooldownID
            usedKeys[proxyKey] = true
            
            local proxy = activeProxies[proxyKey]
            if not proxy then
                proxy = Manager:GetProxy(container, "buff")
                activeProxies[proxyKey] = proxy
            end
            
            -- Mark this proxy as leased to this key
            proxy.leasedTo = proxyKey
            
            proxy:SetSize(p.buffsWidth, p.buffsHeight)
            proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.buffsCountFontSize or 8, "OUTLINE")
            proxy.cooldown:SetCountdownFont(Utils.GetTimerFont(p.buffsTimerFontSize))
            
            proxy.cooldownID = cooldownID
            proxy.cooldownInfo = info
            
            Manager:PopulateBuffProxy(proxy, cooldownID, info, lastKnownState, ns)
            
            local isActive = not proxy.icon:IsDesaturated()
            table.insert(allProxyData, { proxy = proxy, isActive = isActive, key = proxyKey })
        end
    end
    
    -- PASS 2: Determine which proxies to show and collect them for positioning
    local visibleProxies = {}
    for _, data in ipairs(allProxyData) do
        if hideInactive and not data.isActive then
            -- Will be hidden in pass 3
        else
            data.proxy:SetAlpha(data.isActive and 1.0 or inactiveAlpha)
            table.insert(visibleProxies, data.proxy)
        end
    end
    
    -- PASS 3: Position and show visible proxies, hide inactive ones
    if #visibleProxies > 0 then
        local totalWidth = (#visibleProxies * p.buffsWidth) + ((#visibleProxies - 1) * gap)
        local startX = -totalWidth / 2
        addon:Log(string.format("TrackedBuffs: Rendering %d active buffs. Total width: %.1f", #visibleProxies, totalWidth), "proxy")
        for i, proxy in ipairs(visibleProxies) do
            proxy:ClearAllPoints()
            local x = startX + (i - 1) * (p.buffsWidth + gap)
            proxy:SetPoint("LEFT", container, "CENTER", x, 0)
            proxy:Show()
            addon:Log(string.format("  [%d] %s at x=%.1f", i, proxy.spellName or "??", x), "proxy")
        end
        container:SetSize(totalWidth, p.buffsHeight)
    else
        container:SetSize(1, 1)
    end
    
    -- PASS 4: Hide inactive proxies (after all positioning is done)
    for _, data in ipairs(allProxyData) do
        if hideInactive and not data.isActive then
            data.proxy:Hide()
            data.proxy:ClearAllPoints()
        end
    end

    -- Cleanup any proxies that are no longer in the configured list
    for key, proxy in pairs(activeProxies) do
        if not usedKeys[key] then
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

-- Called by Manager after aura cache update
function TrackedBuffs:OnAuraUpdate()
    local container = Manager:GetContainer("buffs")
    if container and container:IsShown() then
        self:RenderBuffProxies(container, self.db.profile)
    end
end

function TrackedBuffs:OnPlayerEnteringWorld()
    C_Timer.After(0.5, function() self:UpdateLayout() end)
end
