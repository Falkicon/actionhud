local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):NewAddon("ActionHud", "AceEvent-3.0", "AceConsole-3.0")
_G.ActionHud = ActionHud -- Global for debugging

local defaults = {
    profile = {
        locked = false,
        iconWidth = 20,
        iconHeight = 17,
        opacity = 0.0,
        procGlowAlpha = 0.75,
        assistGlowAlpha = 0.65,
        cooldownFontSize = 8,
        countFontSize = 8,
        resEnabled = true,
        resShowTarget = true,
        resPosition = "TOP",
        resHealthHeight = 8,
        resPowerHeight = 4,
        resClassHeight = 4,
        resOffset = 1,
        resSpacing = 0,
        resGap = 5,
        xOffset = 0,
        yOffset = -220,
        cdEnabled = true,
        cdPosition = "BOTTOM",
        cdSpacing = 2,
        cdReverse = false,
        cdGap = 4,
        cdItemGap = 0,
        cdEssentialWidth = 20,
        cdEssentialHeight = 20,
        cdUtilityWidth = 20,
        cdUtilityHeight = 20,
        cdCountFontSize = 8, -- Changed to 8
        debugDiscovery = false,
        minimap = {
            hide = false,
        },
    }
}

function ActionHud:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ActionHudDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
    -- Initialize LDB & Minimap
    local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("ActionHud", {
        type = "launcher",
        text = "ActionHud",
        icon = "Interface\\Icons\\Ability_DualWield",
        OnClick = function(clickedframe, button)
            -- print("ActionHud Debug: " .. tostring(button)) 
            if button == "RightButton" then
                self:SlashHandler("")
            else
                self.db.profile.locked = not self.db.profile.locked
                self:UpdateLockState()
                local status = self.db.profile.locked and "|cff00ff00Locked|r" or "|cffff0000Unlocked|r"
                print("|cff33ff99ActionHud:|r " .. status)
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("ActionHud")
            tt:AddLine("|cffeda55fLeft-Click|r to Toggle Lock")
            tt:AddLine("|cffeda55fRight-Click|r to Open Settings")
        end,
    })
    
    self.icon = LibStub("LibDBIcon-1.0")
    self.icon:Register("ActionHud", ldb, self.db.profile.minimap)
    
    -- Fix LibDBIcon click registration (Right-Click support)
    local btn = self.icon:GetMinimapButton("ActionHud") 
    if btn then btn:RegisterForClicks("AnyUp") end
    
    self:SetupOptions() -- In SettingsUI.lua
end

function ActionHud:OnProfileChanged()
    self:UpdateLockState()
    -- Notify modules
    for name, module in self:IterateModules() do
        if module.UpdateLayout then module:UpdateLayout() end
        if module.RefreshAll then module:RefreshAll() end
    end
end

function ActionHud:OnEnable()
    self:CreateMainFrame()
    self:ApplySettings()
    
    self:RegisterChatCommand("actionhud", "SlashHandler")
    self:RegisterChatCommand("ah", "SlashHandler")
    
    -- Initialize Resources
    if ns.Resources and ns.Resources.Initialize then
         ns.Resources:Initialize(self)
    end
end

function ActionHud:SlashHandler(msg)
    if msg == "debug" then
        self.db.profile.debugDiscovery = not self.db.profile.debugDiscovery
        print("ActionHud Debug: " .. tostring(self.db.profile.debugDiscovery))
        return
    end

    if Settings and Settings.OpenToCategory then
        -- Try to find the category ID explicitly (most reliable in 11.0)
        local categoryID
        if SettingsPanel and SettingsPanel.GetAllCategories then
             for _, cat in ipairs(SettingsPanel:GetAllCategories()) do
                 if cat.name == "ActionHud" then
                     categoryID = cat:GetID()
                     break
                 end
             end
        end
        
        if categoryID then
             Settings.OpenToCategory(categoryID)
        else
             Settings.OpenToCategory("ActionHud")
        end
    else
        InterfaceOptionsFrame_OpenToCategory("ActionHud")
    end
end

-- =========================================================================
-- Frame Logic (Root Container)
-- =========================================================================

function ActionHud:CreateMainFrame()
    if self.frame then return end
    
    local f = CreateFrame("Frame", "ActionHudFrame", UIParent)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    
    f:SetScript("OnDragStart", function(s)
        if not self.db.profile.locked then s:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local _, _, _, x, y = s:GetPoint()
        self.db.profile.xOffset = x
        self.db.profile.yOffset = y
    end)
    
    -- Drag Bg
    f.dragBg = f:CreateTexture(nil, "BACKGROUND")
    f.dragBg:SetAllPoints()
    f.dragBg:SetColorTexture(0, 1, 0, 0.3)
    f.dragBg:Hide()
    
    self.frame = f
end

function ActionHud:ApplySettings()
    -- Apply Saved Position
    local p = self.db.profile
    if p.xOffset and p.yOffset then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", p.xOffset, p.yOffset)
    else
        self.frame:SetPoint("CENTER", 0, -220)
    end
    self.frame:Show()
    self:UpdateLockState()
    
    -- Trigger Modules
    for name, module in self:IterateModules() do
        if module.UpdateLayout then module:UpdateLayout() end
    end
end

function ActionHud:UpdateLockState()
    local locked = self.db.profile.locked
    self.frame:EnableMouse(not locked)
    if locked then self.frame.dragBg:Hide() else self.frame.dragBg:Show() end
end
