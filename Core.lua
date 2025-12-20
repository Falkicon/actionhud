local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):NewAddon("ActionHud", "AceEvent-3.0", "AceConsole-3.0")
_G.ActionHud = ActionHud -- Global for debugging

-- Development mode detection (set by DevMarker.lua which is excluded from CurseForge packages)
local IS_DEV_MODE = ns.IS_DEV_MODE or false
ns.IS_DEV_MODE = IS_DEV_MODE  -- Ensure it's available to other modules

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
        cdCountFontSize = 10,
        cdTimerFontSize = "medium",

        -- Tracked Abilities (style-only, position via EditMode)
        styleTrackedBuffs = true,
        styleTrackedBars = true,
        trackedCountFontSize = 10,
        trackedTimerFontSize = "medium",

        -- Minimap Icon (LibDBIcon)
        minimap = {
            hide = false,
        },

        -- Debugging (Consolidated)
        debugDiscovery = false,
        debugFrames = false,
        debugEvents = false,
        debugShowBlizzardFrames = false,
        debugProxy = false,
        debugLayout = false,
        debugContainers = false,
        
        -- Layout (managed by LayoutManager)
        -- layout = { stack = {...}, gaps = {...} }
        -- Initialized by LayoutManager:EnsureLayoutData() or migration
    }
}

function ActionHud:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ActionHudDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
    -- Migrate old position settings to new layout system
    self:MigrateLayoutSettings()
    
    -- Register with Addon Compartment (Blizzard's dropdown menu)
    if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
        AddonCompartmentFrame:RegisterAddon({
            text = "ActionHud",
            icon = "Interface\\Icons\\Ability_DualWield",
            notCheckable = true,
            func = function() self:SlashHandler("") end,
        })
    end
    
    self:SetupOptions() -- In SettingsUI.lua
end

-- Migrate old position/gap settings to new unified layout system
function ActionHud:MigrateLayoutSettings()
    local p = self.db.profile
    
    -- If layout already exists, clean up trackedBuffs if present (moved to EditMode)
    if p.layout then
        local newStack = {}
        local newGaps = {}
        for i, id in ipairs(p.layout.stack) do
            if id ~= "trackedBuffs" then
                table.insert(newStack, id)
                table.insert(newGaps, p.layout.gaps[i] or 0)
            end
        end
        if #newStack ~= #p.layout.stack then
            p.layout.stack = newStack
            p.layout.gaps = newGaps
        end
        return
    end
    
    -- Build new stack based on old position settings
    local topModules = {}
    local bottomModules = {}
    
    -- Resources
    if p.resPosition == "TOP" or p.resPosition == nil then
        table.insert(topModules, { id = "resources", gap = p.resOffset or 1 })
    else
        table.insert(bottomModules, { id = "resources", gap = p.resOffset or 1 })
    end
    
    -- Cooldowns
    if p.cdPosition == "TOP" then
        table.insert(topModules, { id = "cooldowns", gap = p.cdGap or 4 })
    else
        table.insert(bottomModules, { id = "cooldowns", gap = p.cdGap or 4 })
    end
    
    -- Build final stack: top modules (reversed so furthest is first), actionBars, bottom modules
    local stack = {}
    local gaps = {}
    
    -- Top modules: reverse order so furthest from center is at top of list
    for i = #topModules, 1, -1 do
        table.insert(stack, topModules[i].id)
        table.insert(gaps, topModules[i].gap)
    end
    
    -- ActionBars in the middle
    table.insert(stack, "actionBars")
    table.insert(gaps, 0)
    
    -- Bottom modules (closest to center first)
    for _, mod in ipairs(bottomModules) do
        table.insert(stack, mod.id)
        table.insert(gaps, mod.gap)
    end
    
    -- Store the new layout
    p.layout = {
        stack = stack,
        gaps = gaps,
    }
    
    self:Print("Layout migrated from legacy settings.")
end

function ActionHud:OnProfileChanged()
    self:UpdateLockState()
    
    -- Migrate layout if needed for new profile
    self:MigrateLayoutSettings()
    
    -- Trigger LayoutManager to recalculate positions
    local LM = self:GetModule("LayoutManager", true)
    if LM then
        LM:TriggerLayoutUpdate()
    else
        -- Fallback: notify modules directly
        for name, module in self:IterateModules() do
            if module.UpdateLayout then module:UpdateLayout() end
            if module.RefreshAll then module:RefreshAll() end
        end
    end
end

function ActionHud:OnEnable()
    self:CreateMainFrame()
    self:ApplySettings()
    
    self:RegisterChatCommand("actionhud", "SlashHandler")
    self:RegisterChatCommand("ah", "SlashHandler")
    
    if IS_DEV_MODE then
        self:Print("|cff00ff00[DEV MODE]|r Running from git clone")
    end
end

-- Debug message buffer for clipboard export
local debugBuffer = {}
local debugRecording = false
local DEBUG_BUFFER_CAP = 1000

function ActionHud:Log(msg, debugType)
    -- Only record if recording is active
    if not debugRecording then return end
    
    local p = self.db.profile
    
    -- Check if this specific debug type is enabled
    local enabled = false
    if debugType == "discovery" and p.debugDiscovery then enabled = true
    elseif debugType == "frames" and p.debugFrames then enabled = true
    elseif debugType == "events" and p.debugEvents then enabled = true
    elseif debugType == "proxy" and p.debugProxy then enabled = true
    elseif debugType == "layout" and p.debugLayout then enabled = true
    elseif debugType == "debug" and p.debugDiscovery then enabled = true  -- General debug piggybacks on discovery
    elseif not debugType then enabled = true -- General logs
    end
    
    if not enabled then return end

    -- Safe tostring that handles secret values (they error on tostring/format)
    local function SafeToString(v)
        if ns.Utils.IsValueSecret(v) then return "<secret>" end
        return tostring(v)
    end

    local timestamp = date("%H:%M:%S")
    local safeMsg = SafeToString(msg)
    
    -- Print to chat if discovery is on so it shows in BugSack
    if p.debugDiscovery then
        print(string.format("|cff33ff99AH[%s]|r %s", debugType or "Debug", safeMsg))
    end

    -- Add to debug buffer (no chat output - buffer only)
    table.insert(debugBuffer, string.format("[%s][%s] %s", timestamp, debugType or "General", safeMsg))
    
    -- Check buffer cap and auto-stop if reached
    if #debugBuffer >= DEBUG_BUFFER_CAP then
        debugRecording = false
        print("|cff33ff99ActionHud:|r Debug recording auto-stopped (buffer cap of " .. DEBUG_BUFFER_CAP .. " reached).")
    end
end

function ActionHud:StartDebugRecording()
    debugRecording = true
    print("|cff33ff99ActionHud:|r Debug recording started.")
end

function ActionHud:StopDebugRecording()
    debugRecording = false
    print("|cff33ff99ActionHud:|r Debug recording stopped (" .. #debugBuffer .. " entries buffered).")
end

function ActionHud:IsDebugRecording()
    return debugRecording
end

-- Debug export popup frame (created on demand)
local debugExportFrame = nil

local function CreateDebugExportFrame()
    local frame = CreateFrame("Frame", "ActionHudDebugExportFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    
    -- Title
    frame.TitleText:SetText("ActionHud Debug Export")
    
    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 10, -5)
    instructions:SetText("Press Ctrl+A to select all, then Ctrl+C to copy:")
    
    -- ScrollFrame with EditBox
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 10, -25)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -30, 10)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox
    
    -- Close with Escape
    tinsert(UISpecialFrames, "ActionHudDebugExportFrame")
    
    return frame
end

function ActionHud:ShowDebugExport()
    local count = #debugBuffer
    if count == 0 then
        print("|cff33ff99ActionHud:|r Debug buffer is empty. Start recording and perform some actions first.")
        return
    end
    
    -- Create frame if needed
    if not debugExportFrame then
        debugExportFrame = CreateDebugExportFrame()
    end
    
    -- Set text
    local text = table.concat(debugBuffer, "\n")
    debugExportFrame.editBox:SetText(text)
    
    -- Show and focus
    debugExportFrame:Show()
    debugExportFrame.editBox:SetFocus()
    debugExportFrame.editBox:HighlightText()
    
    print("|cff33ff99ActionHud:|r Debug export opened (" .. count .. " entries). Use Ctrl+A, Ctrl+C to copy.")
end

function ActionHud:GetDebugBufferCount()
    return #debugBuffer
end

function ActionHud:ClearDebugBuffer()
    wipe(debugBuffer)
    print("|cff33ff99ActionHud:|r Debug buffer cleared.")
end

function ActionHud:SlashHandler(msg)
    msg = msg and msg:trim():lower() or ""
    
    if msg == "debug" then
        self.db.profile.debugDiscovery = not self.db.profile.debugDiscovery
        print("|cff33ff99ActionHud:|r Debug Discovery is now " .. (self.db.profile.debugDiscovery and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        return
    end

    if msg == "record" then
        if debugRecording then
            self:StopDebugRecording()
        else
            self:StartDebugRecording()
        end
        return
    end
    
    if msg == "log" then
        self:ShowDebugExport()
        return
    end
    
    if msg == "clear" then
        self:ClearDebugBuffer()
        return
    end

    if msg == "dump" then
        local Manager = ns.CooldownManager
        if Manager and Manager.DumpTrackedBuffInfo then
            Manager:DumpTrackedBuffInfo()
        else
            print("|cff33ff99ActionHud:|r Cooldown Manager not available.")
        end
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
    
    -- Use LayoutManager to coordinate module positioning
    local LM = self:GetModule("LayoutManager", true)
    if LM then
        -- Delay slightly to ensure all modules are initialized
        C_Timer.After(0.1, function()
            LM:TriggerLayoutUpdate()
        end)
    else
        -- Fallback: trigger modules directly
        for name, module in self:IterateModules() do
            if module.UpdateLayout then module:UpdateLayout() end
        end
    end
end

function ActionHud:UpdateLockState()
    local locked = self.db.profile.locked
    self.frame:EnableMouse(not locked)
    if locked then self.frame.dragBg:Hide() else self.frame.dragBg:Show() end
end
