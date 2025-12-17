local addonName, ns = ...
ns.Resources = {}
local Res = ns.Resources

local addon -- Reference to AceAddon object
local main
local container
local playerGroup, targetGroup
local playerHealth, playerPower
local targetHealth, targetPower

-- Configuration Cache
local RCFG = {
    enabled = true,
    position = "TOP",
    healthHeight = 6,
    powerHeight = 6,
    offset = 6,
    spacing = 1,
    showTarget = true,
}

local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.5)
    
    return bar
end

local function UpdateBarColor(bar, unit)
    if not bar or not UnitExists(unit) then return end
    
    if bar.type == "HEALTH" then
        if UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            local c = RAID_CLASS_COLORS[class]
            if c then
                bar:SetStatusBarColor(c.r, c.g, c.b)
            else
                bar:SetStatusBarColor(0, 1, 0)
            end
        else
             if UnitIsEnemy("player", unit) then
                bar:SetStatusBarColor(1, 0, 0)
             elseif UnitIsFriend("player", unit) then
                bar:SetStatusBarColor(0, 1, 0)
             else
                bar:SetStatusBarColor(1, 1, 0)
             end
        end
    elseif bar.type == "POWER" then
        local pType, pToken, altR, altG, altB = UnitPowerType(unit)
        local info = PowerBarColor[pToken]
        if info then
             bar:SetStatusBarColor(info.r, info.g, info.b)
        else
             if altR then
                bar:SetStatusBarColor(altR, altG, altB)
             else
                bar:SetStatusBarColor(0, 0, 1)
             end
        end
    end
end

local function UpdateBarValue(bar, unit)
    if not bar or not UnitExists(unit) then 
        bar:SetValue(0)
        return 
    end
    
    local cur, max
    if bar.type == "HEALTH" then
        cur = UnitHealth(unit)
        max = UnitHealthMax(unit)
    else
        cur = UnitPower(unit)
        max = UnitPowerMax(unit)
    end
    
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
end

function Res:UpdateLayout()
    if not container or not addon then return end
    
    local db = addon.db.profile
    RCFG.enabled = db.resEnabled == true
    RCFG.position = db.resPosition or "TOP"
    RCFG.healthHeight = db.resHealthHeight or 6
    RCFG.powerHeight = db.resPowerHeight or 6
    RCFG.offset = db.resOffset or 6
    RCFG.spacing = db.resSpacing or 1
    RCFG.showTarget = db.resShowTarget == true
    
    if not RCFG.enabled then
        container:Hide()
        return
    end
    container:Show()
    
    if not main then main = _G["ActionHudFrame"] end
    if not main then return end
    
    local hudWidth = main:GetWidth()
    
    container:SetSize(hudWidth, RCFG.healthHeight + RCFG.powerHeight + RCFG.spacing) 
    container:ClearAllPoints()
    
    if RCFG.position == "TOP" then
         container:SetPoint("BOTTOM", main, "TOP", 0, RCFG.offset)
    else
         container:SetPoint("TOP", main, "BOTTOM", 0, -RCFG.offset)
    end
    
    local useSplit = false
    if RCFG.showTarget and UnitExists("target") then
        useSplit = true
    end
    
    playerGroup:ClearAllPoints()
    targetGroup:ClearAllPoints()
    
    playerGroup:SetHeight(container:GetHeight())
    targetGroup:SetHeight(container:GetHeight())
    
    if useSplit then
        local halfWidth = (hudWidth - 5) / 2
        playerGroup:SetWidth(halfWidth)
        targetGroup:SetWidth(halfWidth)
        targetGroup:Show()
        
        playerGroup:SetPoint("LEFT", container, "LEFT", 0, 0)
        targetGroup:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    else
        playerGroup:SetWidth(hudWidth)
        targetGroup:Hide()
        playerGroup:SetPoint("CENTER", container, "CENTER", 0, 0)
    end
    
    playerHealth:SetHeight(RCFG.healthHeight)
    playerPower:SetHeight(RCFG.powerHeight)
    playerHealth:SetPoint("TOPLEFT", playerGroup, "TOPLEFT", 0, 0)
    playerHealth:SetPoint("TOPRIGHT", playerGroup, "TOPRIGHT", 0, 0)
    playerPower:SetPoint("BOTTOMLEFT", playerGroup, "BOTTOMLEFT", 0, 0)
    playerPower:SetPoint("BOTTOMRIGHT", playerGroup, "BOTTOMRIGHT", 0, 0)
    
    targetHealth:SetHeight(RCFG.healthHeight)
    targetPower:SetHeight(RCFG.powerHeight)
    targetHealth:SetPoint("TOPLEFT", targetGroup, "TOPLEFT", 0, 0)
    targetHealth:SetPoint("TOPRIGHT", targetGroup, "TOPRIGHT", 0, 0)
    targetPower:SetPoint("BOTTOMLEFT", targetGroup, "BOTTOMLEFT", 0, 0)
    targetPower:SetPoint("BOTTOMRIGHT", targetGroup, "BOTTOMRIGHT", 0, 0)
end

local function OnEvent(self, event, unit)
    if not RCFG.enabled then return end
    
    if event == "PLAYER_TARGET_CHANGED" then
        Res:UpdateLayout()
        UpdateBarColor(targetHealth, "target")
        UpdateBarColor(targetPower, "target")
        UpdateBarValue(targetHealth, "target")
        UpdateBarValue(targetPower, "target")
        
    elseif event == "UNIT_HEALTH" then
        if unit == "player" then UpdateBarValue(playerHealth, "player") end
        if unit == "target" then UpdateBarValue(targetHealth, "target") end
        
    elseif event == "UNIT_POWER_UPDATE" then
        if unit == "player" then UpdateBarValue(playerPower, "player") end
        if unit == "target" then UpdateBarValue(targetPower, "target") end
    
    elseif event == "UNIT_DISPLAYPOWER" then
        if unit == "player" then 
            UpdateBarColor(playerPower, "player") 
            UpdateBarValue(playerPower, "player")
        end
        if unit == "target" then
             UpdateBarColor(targetPower, "target")
             UpdateBarValue(targetPower, "target") 
        end
    end
end

function Res:Initialize(addonObj)
    if container then return end
    addon = addonObj -- Store AceAddon object
    main = _G["ActionHudFrame"]
    if not main then return end
    
    container = CreateFrame("Frame", "ActionHudResources", main)
    
    playerGroup = CreateFrame("Frame", nil, container)
    targetGroup = CreateFrame("Frame", nil, container)
    
    playerHealth = CreateBar(playerGroup)
    playerHealth.type = "HEALTH"
    playerPower = CreateBar(playerGroup)
    playerPower.type = "POWER"
    
    targetHealth = CreateBar(targetGroup)
    targetHealth.type = "HEALTH"
    targetPower = CreateBar(targetGroup)
    targetPower.type = "POWER"
    
    container:RegisterEvent("PLAYER_TARGET_CHANGED")
    container:RegisterEvent("UNIT_HEALTH")
    container:RegisterEvent("UNIT_POWER_UPDATE")
    container:RegisterEvent("UNIT_DISPLAYPOWER")
    container:SetScript("OnEvent", OnEvent)
    
    UpdateBarColor(playerHealth, "player")
    UpdateBarColor(playerPower, "player")
    UpdateBarValue(playerHealth, "player")
    UpdateBarValue(playerPower, "player")
    
    Res:UpdateLayout()
end
