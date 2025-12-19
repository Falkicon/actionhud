local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBars = addon:NewModule("TrackedBars", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

local lastKnownState = {} -- [cooldownID] = boolean
local activeProxies = {} -- [proxyKey] = proxyFrame

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

    -- Initial retries for Blizzard data
    C_Timer.After(0.2, function() self:UpdateLayout() end)
    C_Timer.After(0.5, function() self:UpdateLayout() end)
    C_Timer.After(1.0, function() self:UpdateLayout() end)
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
    
    -- Track which proxies we use in this pass
    local usedKeys = {}
    local allProxyData = {} -- Store proxy + isActive for later positioning
    
    -- PASS 1: Get/create proxies and populate them (don't show/hide yet)
    for _, cooldownID in ipairs(cooldownIDs) do
        local info = Manager:GetCooldownInfoForID(cooldownID)
        if info and info.spellID then
            local proxyKey = "tb_" .. cooldownID
            usedKeys[proxyKey] = true
            
            local proxy = activeProxies[proxyKey]
            if not proxy then
                proxy = Manager:GetProxy(container, "bar")
                activeProxies[proxyKey] = proxy
            end
            
            -- Mark this proxy as leased to this key
            proxy.leasedTo = proxyKey
            
            proxy:SetSize(p.tbWidth, p.tbHeight)
            proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.tbCountFontSize or 10, "OUTLINE")
            proxy.cooldown:SetCountdownFont(Utils.GetTimerFont(p.tbTimerFontSize))
            
            proxy.cooldownID = cooldownID
            proxy.cooldownInfo = info
            
            Manager:PopulateBuffProxy(proxy, cooldownID, info, lastKnownState, ns)
            
            local isActive = not proxy.icon:IsDesaturated()
            table.insert(allProxyData, { proxy = proxy, isActive = isActive, key = proxyKey })
        end
    end
    
    -- PASS 2: Position and show visible proxies
    local yOffset = 0
    for _, data in ipairs(allProxyData) do
        if hideInactive and not data.isActive then
            -- Will be hidden in pass 3
        else
            data.proxy:SetAlpha(data.isActive and 1.0 or inactiveAlpha)
            data.proxy:ClearAllPoints()
            data.proxy:SetPoint("TOP", container, "TOP", 0, -yOffset)
            data.proxy:Show()
            addon:Log(string.format("  TrackedBar: %s at y=-%.1f", data.proxy.spellName or "??", yOffset), "proxy")
            yOffset = yOffset + p.tbHeight + gap
        end
    end
    
    -- PASS 3: Hide inactive proxies (after all positioning is done)
    for _, data in ipairs(allProxyData) do
        if hideInactive and not data.isActive then
            data.proxy:Hide()
            data.proxy:ClearAllPoints()
        end
    end
    
    if yOffset > 0 then
        container:SetSize(p.tbWidth, yOffset - gap)
    else
        container:SetSize(1, 1)
    end
    
    -- Cleanup any proxies that are no longer in the configured list
    for key, proxy in pairs(activeProxies) do
        if not usedKeys[key] then
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

-- Called by Manager after aura cache update
function TrackedBars:OnAuraUpdate()
    local container = Manager:GetContainer("bars")
    if container and container:IsShown() then
        self:RenderTrackedBarProxies(container, self.db.profile)
    end
end

function TrackedBars:OnPlayerEnteringWorld()
    C_Timer.After(0.5, function() self:UpdateLayout() end)
end
