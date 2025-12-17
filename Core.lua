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
        cdEssentialWidth = 40,
        cdEssentialHeight = 40,
        cdUtilityWidth = 30,
        cdUtilityHeight = 30,
        cdCountFontSize = 8, -- Changed to 8
        debugDiscovery = false,
    }
}

function ActionHud:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ActionHudDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
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
    if not msg or msg == "" then
        LibStub("AceConfigDialog-3.0"):Open("ActionHud")
    else
        LibStub("AceConfigCmd-3.0"):HandleCommand("actionhud", "ActionHud", msg)
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
