local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Cooldowns = addon:NewModule("Cooldowns", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Local upvalues for performance
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local table_insert = table.insert
local CooldownFrame_Set = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear

local activeProxies = {} -- [cooldownID] = proxyFrame

-- Reusable tables to avoid garbage creation
local usedKeysCache = {}
local categoriesCache = {}
local rowProxiesCache = {}

-- Pre-allocated category info tables (reused each frame)
local essentialCatInfo = { name = "Essential", cat = nil, w = 0, h = 0 }
local utilityCatInfo = { name = "Utility", cat = nil, w = 0, h = 0 }

-- Runtime category resolution
local function GetEssentialCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential
end

local function GetUtilityCategory()
    return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility
end

function Cooldowns:OnInitialize()
    self.db = addon.db
end

function Cooldowns:OnEnable()
    Manager:CreateContainer("cd", "ActionHudCooldownContainer")
    self:UpdateLayout()
    
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
    self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
    self:RegisterEvent("SPELL_UPDATE_USABLE", "OnSpellUpdateCooldown")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    if EventRegistry then
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
            self:UpdateLayout()
        end, self)
    end

    -- Single delayed retry in case data provider wasn't ready at OnEnable
    C_Timer.After(0.5, function() self:UpdateLayout() end)
end

function Cooldowns:OnDisable()
    local container = Manager:GetContainer("cd")
    if container then container:Hide() end
    
    local blizzardFrames = Manager:GetBlizzardFrames()
    for _, frameName in ipairs(blizzardFrames.cd) do
        Manager:ShowBlizzardFrame(frameName)
    end
end

-- Cache for calculated height
local cachedHeight = 0

-- Calculate the height of this module for LayoutManager
function Cooldowns:CalculateHeight()
    local p = self.db.profile
    if not p.cdEnabled then return 0 end
    
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    if not blizzEnabled then return 0 end
    
    local essentialCat = GetEssentialCategory()
    local utilityCat = GetUtilityCategory()
    
    local totalHeight = 0
    local spacing = p.cdSpacing
    local rowCount = 0
    
    -- Count rows and their heights
    if essentialCat then
        local cooldownIDs = Manager:GetCooldownIDsForCategory(essentialCat, "Essential")
        if cooldownIDs and #cooldownIDs > 0 then
            totalHeight = totalHeight + p.cdEssentialHeight
            rowCount = rowCount + 1
        end
    end
    
    if utilityCat then
        local cooldownIDs = Manager:GetCooldownIDsForCategory(utilityCat, "Utility")
        if cooldownIDs and #cooldownIDs > 0 then
            totalHeight = totalHeight + p.cdUtilityHeight
            rowCount = rowCount + 1
        end
    end
    
    -- Add spacing between rows
    if rowCount > 1 then
        totalHeight = totalHeight + (spacing * (rowCount - 1))
    end
    
    cachedHeight = totalHeight
    return totalHeight
end

-- Get the width of this module for LayoutManager
function Cooldowns:GetLayoutWidth()
    local p = addon.db.profile
    local cols = 6
    return cols * (p.iconWidth or 20)
end

-- Apply position from LayoutManager
function Cooldowns:ApplyLayoutPosition()
    local container = Manager:GetContainer("cd")
    if not container then return end
    
    local p = self.db.profile
    if not p.cdEnabled then 
        container:Hide()
        return
    end
    
    local main = _G["ActionHudFrame"]
    if not main then return end
    
    local LM = addon:GetModule("LayoutManager", true)
    if not LM then return end
    
    local yOffset = LM:GetModulePosition("cooldowns")
    container:ClearAllPoints()
    -- Center horizontally within main frame
    container:SetPoint("TOP", main, "TOP", 0, yOffset)
    container:Show()
    
    addon:Log(string.format("Cooldowns positioned: yOffset=%d", yOffset), "layout")
end

function Cooldowns:UpdateLayout()
    local main = _G["ActionHudFrame"]
    if not main then return end
    local p = self.db.profile
    local container = Manager:GetContainer("cd")
    if not container then return end
    
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    
    -- Report height to LayoutManager
    local LM = addon:GetModule("LayoutManager", true)
    local height = self:CalculateHeight()
    if LM then
        LM:SetModuleHeight("cooldowns", height)
    end
    
    if p.cdEnabled and blizzEnabled then
        local blizzardFrames = Manager:GetBlizzardFrames()
        if not p.debugShowBlizzardFrames then
            for _, frameName in ipairs(blizzardFrames.cd) do Manager:HideBlizzardFrame(frameName) end
        else
            for _, frameName in ipairs(blizzardFrames.cd) do Manager:ShowBlizzardFrame(frameName) end
        end
        container:Show()
        Manager:UpdateContainerDebug("cd", {r=0, g=0, b=1}) -- Blue for CDs
        self:RenderCooldownProxies(container, p)
    else
        container:Hide()
        local blizzardFrames = Manager:GetBlizzardFrames()
        for _, frameName in ipairs(blizzardFrames.cd) do Manager:ShowBlizzardFrame(frameName) end
        self:ReleaseCooldownProxies()
    end
end

function Cooldowns:RenderCooldownProxies(container, p)
    -- Reuse cached tables to avoid garbage creation
    wipe(usedKeysCache)
    wipe(categoriesCache)
    
    local essentialCat = GetEssentialCategory()
    local utilityCat = GetUtilityCategory()
    
    -- Update pre-allocated category info tables
    if p.cdReverse then
        if utilityCat then
            utilityCatInfo.cat = utilityCat
            utilityCatInfo.w = p.cdUtilityWidth
            utilityCatInfo.h = p.cdUtilityHeight
            table_insert(categoriesCache, utilityCatInfo)
        end
        if essentialCat then
            essentialCatInfo.cat = essentialCat
            essentialCatInfo.w = p.cdEssentialWidth
            essentialCatInfo.h = p.cdEssentialHeight
            table_insert(categoriesCache, essentialCatInfo)
        end
    else
        if essentialCat then
            essentialCatInfo.cat = essentialCat
            essentialCatInfo.w = p.cdEssentialWidth
            essentialCatInfo.h = p.cdEssentialHeight
            table_insert(categoriesCache, essentialCatInfo)
        end
        if utilityCat then
            utilityCatInfo.cat = utilityCat
            utilityCatInfo.w = p.cdUtilityWidth
            utilityCatInfo.h = p.cdUtilityHeight
            table_insert(categoriesCache, utilityCatInfo)
        end
    end
    
    local yOffset = 0
    local spacing = p.cdSpacing
    local itemGap = p.cdItemGap
    
    for _, catInfo in ipairs(categoriesCache) do
        local cooldownIDs = Manager:GetCooldownIDsForCategory(catInfo.cat, catInfo.name)
        if #cooldownIDs > 0 then
            local rowWidth = 0
            local xOffset = 0
            wipe(rowProxiesCache)
            
            for i, cooldownID in ipairs(cooldownIDs) do
                local info = Manager:GetCooldownInfoForID(cooldownID)
                if info and info.spellID then
                    -- Use cooldownID directly as key to avoid string concatenation
                    usedKeysCache[cooldownID] = true
                    
                    local proxy = activeProxies[cooldownID]
                    if not proxy then
                        proxy = Manager:GetProxy(container, "cooldown")
                        activeProxies[cooldownID] = proxy
                        proxy.proxyKey = cooldownID
                    end
                    
                    -- Mark this proxy as leased to this key
                    proxy.leasedTo = cooldownID
                    
                    proxy:SetSize(catInfo.w, catInfo.h)
                    proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.cdCountFontSize or 10, "OUTLINE")
                    proxy.cooldown:SetCountdownFont(Utils.GetTimerFont(p.cdTimerFontSize))
                    
                    self:PopulateProxy(proxy, cooldownID, info)
                    
                    proxy:ClearAllPoints()
                    proxy.pendingX = xOffset
                    proxy.pendingY = yOffset
                    table_insert(rowProxiesCache, proxy)
                    
                    xOffset = xOffset + catInfo.w + itemGap
                    rowWidth = xOffset - itemGap
                end
            end
            
            local centerOffset = -rowWidth / 2
            for _, proxy in ipairs(rowProxiesCache) do
                -- Position from top of container (LayoutManager handles overall positioning)
                proxy:SetPoint("TOPLEFT", container, "TOP", centerOffset + proxy.pendingX, -proxy.pendingY)
                proxy.pendingX = nil
                proxy.pendingY = nil
            end
            yOffset = yOffset + catInfo.h + spacing
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

function Cooldowns:PopulateProxy(proxy, cooldownID, cooldownInfo)
    if not cooldownInfo then return end
    local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    proxy.spellID = spellID
    proxy.cooldownID = cooldownID
    proxy.cooldownInfo = cooldownInfo
    
    local texture = Utils.GetSpellTextureSafe(spellID)
    if texture then proxy.icon:SetTexture(texture) end
    
    local cdInfo = Utils.GetSpellCooldownSafe(spellID)
    if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
        -- Check if this is truly the GCD vs a real cooldown
        -- Some spells (like Demo Shout) incorrectly report GCD category initially
        -- but have durations >> 1.5s. Trust duration over category.
        local GCD_THRESHOLD = 1.5
        local isActualGCD = cdInfo.activeCategory == Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY
                           and cdInfo.duration <= GCD_THRESHOLD
        
        if isActualGCD then
            CooldownFrame_Clear(proxy.cooldown)
            proxy.icon:SetDesaturated(false)
        else
            CooldownFrame_Set(proxy.cooldown, cdInfo.startTime, cdInfo.duration, true, false, cdInfo.modRate or 1)
            proxy.icon:SetDesaturated(true)
        end
    else
        CooldownFrame_Clear(proxy.cooldown)
        proxy.icon:SetDesaturated(false)
    end
    
    local chargeInfo = Utils.GetSpellChargesSafe(spellID)
    if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
        proxy.count:SetText(chargeInfo.currentCharges)
        proxy.count:Show()
        if chargeInfo.currentCharges > 0 and chargeInfo.cooldownStartTime and chargeInfo.cooldownStartTime > 0 then
            CooldownFrame_Set(proxy.cooldown, chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, true, true, chargeInfo.chargeModRate or 1)
            proxy.icon:SetDesaturated(false)
        end
    else
        local castCount = spellID and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(spellID)
        if castCount and castCount > 0 then
            proxy.count:SetText(castCount)
            proxy.count:Show()
        else
            proxy.count:Hide()
        end
    end
    proxy.timer:Hide()
    proxy:Show()
end

function Cooldowns:ReleaseCooldownProxies()
    for key, proxy in pairs(activeProxies) do
        Manager:ReleaseProxy(proxy)
        activeProxies[key] = nil
    end
end

function Cooldowns:OnSpellUpdateCooldown()
    local container = Manager:GetContainer("cd")
    if container and container:IsShown() then
        for key, proxy in pairs(activeProxies) do
            if proxy.cooldownInfo then
                self:PopulateProxy(proxy, proxy.cooldownID, proxy.cooldownInfo)
            end
        end
    end
end

function Cooldowns:OnPlayerEnteringWorld()
    -- Direct call - data provider should be ready for zone transitions
    self:UpdateLayout()
end
