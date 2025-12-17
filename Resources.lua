local addonName, ns = ...
ns.Resources = {}
local Res = ns.Resources

local addon
local main
local container
local playerGroup, targetGroup
local playerHealth, playerPower, playerClassBar
local targetHealth, targetPower
local classSegments = {}

-- Configuration Cache
local RCFG = {
    enabled = true,
    position = "TOP",
    healthHeight = 6,
    powerHeight = 6,
    classHeight = 4,
    offset = 6,
    spacing = 1,
    gap = 5,
    showTarget = true,
}

local ClassBarColors = {
    [Enum.PowerType.ComboPoints] = {r=0.9, g=0.3, b=0.3},     -- Rogue/Feral Red
    [Enum.PowerType.Chi]         = {r=0.6, g=0.9, b=0.8},     -- Monk Seafoam
    [Enum.PowerType.HolyPower]   = {r=0.9, g=0.8, b=0.3},     -- Paladin Gold
    [Enum.PowerType.SoulShards]  = {r=0.6, g=0.45, b=0.65},   -- Warlock Purple
    [Enum.PowerType.ArcaneCharges]= {r=0.3, g=0.5, b=0.9},    -- Mage Blue
    [Enum.PowerType.Essence]     = {r=0.3, g=0.7, b=0.6},     -- Evoker Teal
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

local function GetClassPowerType()
    local _, class = UnitClass("player")
    if class == "ROGUE" or class == "DRUID" then return Enum.PowerType.ComboPoints
    elseif class == "PALADIN" then return Enum.PowerType.HolyPower
    elseif class == "WARLOCK" then return Enum.PowerType.SoulShards
    elseif class == "MAGE" then return Enum.PowerType.ArcaneCharges
    elseif class == "MONK" then return Enum.PowerType.Chi
    elseif class == "EVOKER" then return Enum.PowerType.Essence
    end
    return nil
end

local function CanShowClassPower()
    local pType = GetClassPowerType()
    if not pType then return false, nil, 0 end
    
    local max = UnitPowerMax("player", pType)
    if max <= 0 then return false, pType, 0 end
    
    -- User Request: Only show if we actually have points/charges
    local cur = UnitPower("player", pType, true)
    if cur <= 0 then return false, pType, 0 end
    
    return true, pType, max
end

local function UpdateClassPower()
    if not playerClassBar then return end
    
    local show, pType, max = CanShowClassPower()
    if not show then 
        playerClassBar:Hide()
        return 
    end
    
    local cur = UnitPower("player", pType, true)
    
    playerClassBar:Show()
    
    -- Ensure segments exist
    for i = 1, max do
        if not classSegments[i] then
            local f = playerClassBar:CreateTexture(nil, "ARTWORK")
            f:SetTexture("Interface\\Buttons\\WHITE8x8")
            classSegments[i] = f
        end
    end
    
    -- Hide extra
    for i = max + 1, #classSegments do
        classSegments[i]:Hide()
    end
    
    -- Layout
    local width = playerClassBar:GetWidth()
    local spacing = 1
    local segWidth = (width - ((max - 1) * spacing)) / max
    if segWidth < 1 then segWidth = 1 end
    
    for i = 1, max do
        local seg = classSegments[i]
        seg:ClearAllPoints()
        seg:SetWidth(segWidth)
        seg:SetHeight(playerClassBar:GetHeight())
        
        if i == 1 then
            seg:SetPoint("LEFT", playerClassBar, "LEFT", 0, 0)
        else
            seg:SetPoint("LEFT", classSegments[i-1], "RIGHT", spacing, 0)
        end
        
        -- Color / Alpha
        if i <= cur then
            seg:SetAlpha(1)
            local c = ClassBarColors[pType]
            if c then seg:SetColorTexture(c.r, c.g, c.b)
            else seg:SetColorTexture(1, 1, 0) end
        else
            seg:SetAlpha(0.3)
            local c = ClassBarColors[pType]
            if c then seg:SetColorTexture(c.r * 0.5, c.g * 0.5, c.b * 0.5)
            else seg:SetColorTexture(0.5, 0.5, 0.5) end
        end
        seg:Show()
    end
end

local function UpdateBarColor(bar, unit)
    if not bar or not UnitExists(unit) then return end
    
    local mult = 0.85 -- Desaturation multiplier
    
    if bar.type == "HEALTH" then
        if UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            local c = RAID_CLASS_COLORS[class]
            if c then
                bar:SetStatusBarColor(c.r * mult, c.g * mult, c.b * mult)
            else
                bar:SetStatusBarColor(0, 0.8, 0)
            end
        else
             if UnitIsEnemy("player", unit) then
                bar:SetStatusBarColor(0.8, 0, 0)
             elseif UnitIsFriend("player", unit) then
                bar:SetStatusBarColor(0, 0.8, 0)
             else
                bar:SetStatusBarColor(0.8, 0.8, 0)
             end
        end
    elseif bar.type == "POWER" then
        local pType, pToken, altR, altG, altB = UnitPowerType(unit)
        local info = PowerBarColor[pToken]
        if info then
             bar:SetStatusBarColor(info.r * mult, info.g * mult, info.b * mult)
        else
             if altR then
                bar:SetStatusBarColor(altR * mult, altG * mult, altB * mult)
             else
                bar:SetStatusBarColor(0, 0, 0.8)
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
    RCFG.classHeight = db.resClassHeight or 4
    RCFG.offset = db.resOffset or 6
    RCFG.spacing = db.resSpacing or 1
    RCFG.gap = db.resGap or 5
    RCFG.showTarget = db.resShowTarget == true
    
    if not RCFG.enabled then
        container:Hide()
        return
    end
    container:Show()
    
    if not main then main = _G["ActionHudFrame"] end
    if not main then return end
    
    local hudWidth = main:GetWidth()
    
    local hasClassBar, _, _ = CanShowClassPower()
    
    local totalHeight = RCFG.healthHeight + RCFG.powerHeight + RCFG.spacing
    if hasClassBar then
        totalHeight = totalHeight + RCFG.classHeight + RCFG.spacing
    end
    
    container:SetSize(hudWidth, totalHeight) 
    container:ClearAllPoints()
    
    -- Main Container Anchor
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
        local halfWidth = (hudWidth - RCFG.gap) / 2
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
    
    -- Clear internal points
    playerHealth:ClearAllPoints()
    playerPower:ClearAllPoints()
    playerClassBar:ClearAllPoints()
    targetHealth:ClearAllPoints()
    targetPower:ClearAllPoints()
    
    -- Set Dimensions
    playerHealth:SetHeight(RCFG.healthHeight)
    playerPower:SetHeight(RCFG.powerHeight)
    targetHealth:SetHeight(RCFG.healthHeight)
    targetPower:SetHeight(RCFG.powerHeight)
    if hasClassBar then playerClassBar:SetHeight(RCFG.classHeight) end
    
    -- Horizontal anchors (always fill width of group)
    local function FillWidth(f, p)
        f:SetPoint("LEFT", p, "LEFT", 0, 0)
        f:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    end
    
    FillWidth(playerHealth, playerGroup)
    FillWidth(playerPower, playerGroup)
    if hasClassBar then FillWidth(playerClassBar, playerGroup) end
    FillWidth(targetHealth, targetGroup)
    FillWidth(targetPower, targetGroup)
    
    -- Vertical Anchoring
    if RCFG.position == "TOP" then
        -- Bottom-up Stack: [Power] -> [Health] -> [Class]
        -- Power is at bottom of container (closest to HUD)
        playerPower:SetPoint("BOTTOM", playerGroup, "BOTTOM", 0, 0)
        playerHealth:SetPoint("BOTTOM", playerPower, "TOP", 0, RCFG.spacing)
        
        targetPower:SetPoint("BOTTOM", targetGroup, "BOTTOM", 0, 0)
        targetHealth:SetPoint("BOTTOM", targetPower, "TOP", 0, RCFG.spacing)
        
        if hasClassBar then
            playerClassBar:Show()
            playerClassBar:SetPoint("BOTTOM", playerHealth, "TOP", 0, RCFG.spacing)
            UpdateClassPower()
        else
            playerClassBar:Hide()
        end
        
    else -- BOTTOM
        -- Top-down Stack: [Health] -> [Power] -> [Class]
        -- Health is at top of container (closest to HUD)
        playerHealth:SetPoint("TOP", playerGroup, "TOP", 0, 0)
        playerPower:SetPoint("TOP", playerHealth, "BOTTOM", 0, -RCFG.spacing)
        
        targetHealth:SetPoint("TOP", targetGroup, "TOP", 0, 0)
        targetPower:SetPoint("TOP", targetHealth, "BOTTOM", 0, -RCFG.spacing)
        
        if hasClassBar then
            playerClassBar:Show()
            playerClassBar:SetPoint("TOP", playerPower, "BOTTOM", 0, -RCFG.spacing)
            UpdateClassPower()
        else
            playerClassBar:Hide()
        end
    end
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
        if unit == "player" then 
            UpdateBarValue(playerPower, "player") 
            
            local cType = GetClassPowerType()
            if cType then
                 local shouldShow = CanShowClassPower()
                 local isShown = playerClassBar:IsShown()
                 if shouldShow ~= isShown then
                     Res:UpdateLayout()
                 else
                     if shouldShow then UpdateClassPower() end
                 end
            end
        end
        if unit == "target" then UpdateBarValue(targetPower, "target") end
    
    elseif event == "UNIT_DISPLAYPOWER" then
        if unit == "player" then 
            UpdateBarColor(playerPower, "player") 
            UpdateBarValue(playerPower, "player")
            UpdateClassPower() 
        end
        if unit == "target" then
             UpdateBarColor(targetPower, "target")
             UpdateBarValue(targetPower, "target") 
        end
    elseif event == "UNIT_MAXPOWER" then
        if unit == "player" then
             UpdateClassPower()
             Res:UpdateLayout() 
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        UpdateClassPower()
        Res:UpdateLayout()
    end
end

function Res:Initialize(addonObj)
    if container then return end
    addon = addonObj 
    main = _G["ActionHudFrame"]
    if not main then return end
    
    container = CreateFrame("Frame", "ActionHudResources", main)
    
    playerGroup = CreateFrame("Frame", nil, container)
    targetGroup = CreateFrame("Frame", nil, container)
    
    playerHealth = CreateBar(playerGroup)
    playerHealth.type = "HEALTH"
    playerPower = CreateBar(playerGroup)
    playerPower.type = "POWER"
    
    playerClassBar = CreateFrame("Frame", nil, playerGroup)
    
    targetHealth = CreateBar(targetGroup)
    targetHealth.type = "HEALTH"
    targetPower = CreateBar(targetGroup)
    targetPower.type = "POWER"
    
    container:RegisterEvent("PLAYER_TARGET_CHANGED")
    container:RegisterEvent("UNIT_HEALTH")
    container:RegisterEvent("UNIT_POWER_UPDATE")
    container:RegisterEvent("UNIT_DISPLAYPOWER")
    container:RegisterEvent("UNIT_MAXPOWER")
    container:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    
    container:SetScript("OnEvent", OnEvent)
    
    UpdateBarColor(playerHealth, "player")
    UpdateBarColor(playerPower, "player")
    UpdateBarValue(playerHealth, "player")
    UpdateBarValue(playerPower, "player")
    UpdateClassPower()
    
    Res:UpdateLayout()
end

function Res:GetContainer()
    return container
end
