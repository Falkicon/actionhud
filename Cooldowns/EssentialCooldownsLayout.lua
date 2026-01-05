-- Cooldowns/EssentialCooldownsLayout.lua
-- Positions Blizzard's EssentialCooldownViewer frame in the ActionHud stack.
-- Uses early container creation to block Edit Mode interference.

local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local EssentialCooldownsLayout = addon:NewModule("EssentialCooldownsLayout", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local Reset = ns.SkinningReset

local BLIZZARD_FRAME_NAME = "EssentialCooldownViewer"

-- ============================================================================
-- EARLY CONTAINER CREATION
-- Create container at FILE LOAD TIME, before Blizzard's EditModeManager initializes.
-- This is critical for blocking Edit Mode from taking control of the viewer.
-- ============================================================================
local container = CreateFrame("Frame", "ActionHud_EssentialCooldownsContainer", UIParent)
container:SetSize(200, 50)
container:SetFrameStrata("LOW")
container:SetFrameLevel(10)
container:SetClampedToScreen(true)
container:SetMovable(true)
container:EnableMouse(false)
container:SetPoint("CENTER", UIParent, "CENTER", 0, -100)  -- Default position

-- Add OnUpdate polling to constantly reposition Blizzard viewer (blocks Edit Mode)
-- Only runs when Edit Mode is active for performance
container:SetScript("OnUpdate", function(self)
    -- Only enforce positioning during Edit Mode
    if not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        return
    end
    
    local blizzFrame = _G[BLIZZARD_FRAME_NAME]
    if blizzFrame and blizzFrame._ActionHud_Controlled then
        if blizzFrame._ActionHud_OrigSetPoint then
            blizzFrame._ActionHud_OrigClearAllPoints(blizzFrame)
            blizzFrame._ActionHud_OrigSetPoint(blizzFrame, "CENTER", self, "CENTER")
        end
    end
end)

function EssentialCooldownsLayout:OnInitialize()
    self.db = addon.db
end

function EssentialCooldownsLayout:OnEnable()
    self:SetupContainer()
end

local function SetLayoutModified()
    if LibStub("AceConfigRegistry-3.0", true) then
        LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
    end
end

function EssentialCooldownsLayout:IsLocked()
    local p = self.db and self.db.profile
    return not (p and p.layoutUnlocked)
end

function EssentialCooldownsLayout:SetupContainer()
    -- Container already created at file load time
    -- Now configure it for ActionHud
    local main = _G["ActionHudFrame"]
    if not main then
        C_Timer.After(0.5, function() self:SetupContainer() end)
        return
    end

    -- Reparent to ActionHud's main frame
    container:SetParent(main)
    container:SetScript("OnDragStart", function(s) s:StartMoving() end)
    container:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local parent = s:GetParent()
        local cx, cy = s:GetCenter()
        local px, py = parent:GetCenter()
        
        self.db.profile.essentialCooldownsXOffset = cx - px
        self.db.profile.essentialCooldownsYOffset = cy - py
        
        SetLayoutModified()
    end)

    -- Create drag overlay
    container.overlay = container:CreateTexture(nil, "OVERLAY")
    container.overlay:SetAllPoints()
    container.overlay:SetColorTexture(0, 0.5, 1, 0.4) -- Blue tint for Essential
    container.overlay:Hide()

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(L["Essential Cooldowns"])
    container.label = label
    label:Hide()

    self:UpdateLayout()

    -- Position Blizzard's viewer
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("EssentialCooldownsLayout: Viewer not available yet, retrying...", "discovery")
        C_Timer.After(1.0, function() self:SetupContainer() end)
        return
    end

    self:PositionBlizzardFrame(blizzFrame)
    
    -- Hook Edit Mode to restore positioning when it closes
    -- (Edit Mode allows users to move Blizzard frames, which desynchronizes them from our containers)
    if EditModeManagerFrame and not self._editModeHooked then
        EditModeManagerFrame:HookScript("OnHide", function()
            addon:Log("EssentialCooldownsLayout: Edit Mode closed, restoring position", "layout")
            local frame = self:GetBlizzardFrame()
            if frame then
                frame._ActionHud_Controlled = false  -- Allow repositioning
                self:PositionBlizzardFrame(frame)
            end
            self:UpdateLayout()
        end)
        self._editModeHooked = true
    end
    
    -- Hook to apply styling reset to icons as they're created
    self:InstallStylingHooks(blizzFrame)
    
    addon:Log("EssentialCooldownsLayout: Container setup complete", "layout")
end

-- Install hooks to apply SkinningReset to icon frames as they appear
function EssentialCooldownsLayout:InstallStylingHooks(blizzFrame)
    if not blizzFrame or self._stylingHooked then return end
    if not Reset then return end  -- SkinningReset not available
    
    -- Hook OnAcquireItemFrame to style icons as they're created
    if blizzFrame.OnAcquireItemFrame then
        hooksecurefunc(blizzFrame, "OnAcquireItemFrame", function(viewer, itemFrame)
            if Reset and Reset.StripIconFrame then
                Reset.StripIconFrame(itemFrame)
            end
        end)
        self._stylingHooked = true
        addon:Log("EssentialCooldownsLayout: Styling hooks installed", "discovery")
    end
    
    -- Also style any existing icons
    self:ApplyStylingToExistingIcons(blizzFrame)
end

-- Apply styling to any icons already in the viewer
function EssentialCooldownsLayout:ApplyStylingToExistingIcons(blizzFrame)
    if not blizzFrame or not Reset then return end
    
    -- Iterate children to find icon frames
    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child and child.Icon and Reset.StripIconFrame then
            Reset.StripIconFrame(child)
        end
    end
end

function EssentialCooldownsLayout:UpdateOverlay()
    if not container then return end
    
    local isUnlocked = not self:IsLocked()

    if isUnlocked then
        container:EnableMouse(true)
        container:RegisterForDrag("LeftButton")
        container.overlay:Show()
        container.label:Show()
        container:SetFrameStrata("HIGH")
    else
        container:EnableMouse(false)
        container:RegisterForDrag()
        container.overlay:Hide()
        container.label:Hide()
        container:SetFrameStrata("MEDIUM")
    end
end

function EssentialCooldownsLayout:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

function EssentialCooldownsLayout:PositionBlizzardFrame(blizzFrame)
    if not blizzFrame then return end
    
    -- Store original data (only once)
    if not blizzFrame._ActionHud_OrigSetPoint then
        blizzFrame._ActionHud_OrigParent = blizzFrame:GetParent()
        blizzFrame._ActionHud_OrigSetPoint = blizzFrame.SetPoint
        blizzFrame._ActionHud_OrigClearAllPoints = blizzFrame.ClearAllPoints
        
        -- Hook SetPoint to block Edit Mode interference
        blizzFrame.SetPoint = function(self, ...)
            if self._ActionHud_Controlled then
                return
            end
            return self._ActionHud_OrigSetPoint(self, ...)
        end
        
        -- Hook ClearAllPoints to block Edit Mode interference
        blizzFrame.ClearAllPoints = function(self, ...)
            if self._ActionHud_Controlled then
                return
            end
            return self._ActionHud_OrigClearAllPoints(self, ...)
        end
    end
    
    -- Reparent viewer to our container (key for Edit Mode blocking)
    blizzFrame:SetParent(container)
    
    -- Position within container
    blizzFrame._ActionHud_Controlled = false
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", container, "CENTER")
    blizzFrame._ActionHud_Controlled = true
    
    blizzFrame:SetAlpha(1)
    blizzFrame:Show()
end

function EssentialCooldownsLayout:UpdateLayout()
    if not container then return end

    local p = self.db.profile
    local main = _G["ActionHudFrame"]
    if not main then return end

    -- Check if module is enabled
    if not p.essentialCooldownsEnabled then
        container:Hide()
        return
    end

    -- Check if we're in stack mode
    local LM = addon:GetModule("LayoutManager", true)
    local inStack = LM and LM:IsModuleInStack("essentialCooldowns")

    container:ClearAllPoints()

    local contentHeight = self:CalculateHeight()
    local contentWidth = self:GetLayoutWidth()

    if inStack and LM then
        local containerWidth = LM:GetMaxWidth()
        if containerWidth <= 0 then
            containerWidth = 120
        end
        local yOffset = LM:GetModulePosition("essentialCooldowns")
        container:SetSize(containerWidth, contentHeight)
        container:SetPoint("TOP", main, "TOP", 0, yOffset)
        container:EnableMouse(false)
        container:RegisterForDrag()
        
        LM:SetModuleHeight("essentialCooldowns", contentHeight)
    else
        container:SetSize(math.max(contentWidth, 40), math.max(contentHeight, 40))
        local xOffset = p.essentialCooldownsXOffset or 0
        local yOffset = p.essentialCooldownsYOffset or -100
        container:SetPoint("CENTER", main, "CENTER", xOffset, yOffset)
        container:EnableMouse(true)
        container:RegisterForDrag("LeftButton")
    end
    
    -- Re-position Blizzard frame each layout update
    local blizzFrame = self:GetBlizzardFrame()
    if blizzFrame then
        blizzFrame:ClearAllPoints()
        blizzFrame:SetPoint("CENTER", container, "CENTER")
    end
    
    container:Show()
    addon:UpdateLayoutOutline(container, "Essential Cooldowns", "essentialCooldowns")
end

function EssentialCooldownsLayout:CalculateHeight()
    local p = self.db.profile
    if not p.essentialCooldownsEnabled then
        return 0
    end
    
    -- Try to get actual height from Blizzard frame
    local blizzFrame = self:GetBlizzardFrame()
    if blizzFrame and blizzFrame:IsShown() then
        local height = blizzFrame:GetHeight()
        if height and height > 0 then
            return height
        end
    end
    
    -- Fallback to configured icon size
    return p.essentialCooldownsIconSize or 36
end

function EssentialCooldownsLayout:GetLayoutWidth()
    local p = self.db.profile
    if not p.essentialCooldownsEnabled then
        return 0
    end
    local iconSize = p.essentialCooldownsIconSize or 36
    local columns = p.essentialCooldownsColumns or 8
    local spacing = 2
    return (iconSize * columns) + (spacing * (columns - 1))
end

function EssentialCooldownsLayout:ApplyLayoutPosition()
    self:UpdateLayout()
end
