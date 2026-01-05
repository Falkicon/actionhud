-- Cooldowns\TrackedBuffsLayout.lua
-- Handles the custom layout for TrackedBuffs by reparenting the Blizzard viewer icon.
-- This bypasses Blizzard's EditMode positioning and allows ActionHud to control its placement.

local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffsLayout = addon:NewModule("TrackedBuffsLayout", "AceEvent-3.0")
local Utils = ns.Utils

local BLIZZARD_FRAME_NAME = "BuffIconCooldownViewer"
local container

function TrackedBuffsLayout:OnInitialize()
    self.db = addon.db
end

function TrackedBuffsLayout:OnEnable()
    -- Initialize the container and start the reparenting process
    self:SetupContainer()
end

local function SetLayoutModified()
    if LibStub("AceConfigRegistry-3.0", true) then
        LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
    end
end

function TrackedBuffsLayout:IsLocked()
    local p = self.db and self.db.profile
    return not (p and p.layoutUnlocked)
end

function TrackedBuffsLayout:ToggleLock()
    local p = self.db and self.db.profile
    if p then
        p.layoutUnlocked = not p.layoutUnlocked
    end
    self:UpdateOverlay()
    -- Also update all other draggable containers
    local DraggableContainer = ns.DraggableContainer
    if DraggableContainer then
        DraggableContainer:UpdateAllOverlays()
    end
    SetLayoutModified()
end

function TrackedBuffsLayout:SetupContainer()
    if container then return end

    -- 1. Create invisible container at load time (ActionHudFrame is the parent)
    local main = _G["ActionHudFrame"]
    if not main then
        -- ActionHudFrame might not be ready yet
        C_Timer.After(0.5, function() self:SetupContainer() end)
        return
    end

    container = CreateFrame("Frame", "ActionHudTrackedBuffsContainer", main)
    container:SetSize(40, 40) -- Initial size
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    container:SetScript("OnDragStart", function(s) s:StartMoving() end)
    container:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local _, _, _, x, y = s:GetPoint()
        -- Convert point to offset from CENTER of ActionHudFrame
        local parent = s:GetParent()
        local cx, cy = s:GetCenter()
        local px, py = parent:GetCenter()
        
        self.db.profile.buffsXOffset = cx - px
        self.db.profile.buffsYOffset = cy - py
        
        SetLayoutModified()
        addon:Log(string.format("TrackedBuffs saved pos: %d, %d", self.db.profile.buffsXOffset, self.db.profile.buffsYOffset), "layout")
    end)

    -- Create drag overlay
    container.overlay = container:CreateTexture(nil, "OVERLAY")
    container.overlay:SetAllPoints()
    container.overlay:SetColorTexture(0, 1, 0, 0.4)
    container.overlay:Hide()

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(L["Buffs"])
    container.label = label
    label:Hide()

    -- Lay initial position from profile
    self:UpdateLayout()

    -- 2. Reparent Blizzard viewer into container
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBuffsLayout: Viewer not available yet, retrying...", "discovery")
        C_Timer.After(1.0, function() self:SetupContainer() end)
        return
    end

    -- Hook SetPoint/ClearAllPoints to block EditMode interference
    self:OverrideBlizzardPositioning(blizzFrame)

    addon:Log("TrackedBuffsLayout: Container setup and reparenting complete", "layout")
end

function TrackedBuffsLayout:UpdateOverlay()
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

function TrackedBuffsLayout:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

function TrackedBuffsLayout:OverrideBlizzardPositioning(blizzFrame)
    if not blizzFrame or blizzFrame._ActionHud_Controlled then return end

    -- Position the Blizzard frame at our container's center
    -- NOTE: We intentionally do NOT reparent or block SetPoint - 
    -- doing so breaks Blizzard's internal update cycle for the buff icons.
    -- The frame will still follow our container's position.
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", container, "CENTER")
    
    blizzFrame._ActionHud_Controlled = true
end

function TrackedBuffsLayout:ApplyInternalPosition(blizzFrame)
    if not blizzFrame then return end
    
    -- Just reposition without blocking
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", container, "CENTER")
end

function TrackedBuffsLayout:UpdateLayout()
    if not container then return end

    local p = self.db.profile
    local main = _G["ActionHudFrame"]
    if not main then return end

    -- Check if we're in stack mode
    local LM = addon:GetModule("LayoutManager", true)
    local inStack = LM and LM:IsModuleInStack("trackedBuffs")

    container:ClearAllPoints()

    -- Calculate container size based on content
    local contentHeight = self:CalculateHeight()
    local contentWidth = self:GetLayoutWidth()

    if inStack and LM then
        -- Stack mode: use full HUD width from LayoutManager
        local containerWidth = LM:GetMaxWidth()
        if containerWidth <= 0 then
            containerWidth = 120 -- Fallback
        end
        local yOffset = LM:GetModulePosition("trackedBuffs")
        container:SetSize(containerWidth, contentHeight)
        container:SetPoint("TOP", main, "TOP", 0, yOffset)
        container:EnableMouse(false)
        container:RegisterForDrag()
        
        -- Report height to LayoutManager
        LM:SetModuleHeight("trackedBuffs", contentHeight)
    else
        -- Independent mode: fit content and enable dragging
        container:SetSize(math.max(contentWidth, 40), math.max(contentHeight, 40))
        local xOffset = p.buffsXOffset or 0
        local yOffset = p.buffsYOffset or -180
        container:SetPoint("CENTER", main, "CENTER", xOffset, yOffset)
        container:EnableMouse(true)
        container:RegisterForDrag("LeftButton")
    end
    
    -- Debug outline
    addon:UpdateLayoutOutline(container, "Tracked Buffs", "buffs")
end

-- Stack layout functions
function TrackedBuffsLayout:CalculateHeight()
    local p = self.db.profile
    if not p.styleTrackedBuffs then
        return 0
    end
    -- Return icon size as height (single row)
    return p.buffsIconSize or 36
end

function TrackedBuffsLayout:GetLayoutWidth()
    local p = self.db.profile
    if not p.styleTrackedBuffs then
        return 0
    end
    -- Width based on columns and icon size
    local iconSize = p.buffsIconSize or 36
    local spacing = p.buffsSpacingH or 2
    local columns = p.buffsColumns or 8
    return (iconSize * columns) + (spacing * (columns - 1))
end

-- Called by LayoutManager if it wants to tell us to update
function TrackedBuffsLayout:ApplyLayoutPosition()
    self:UpdateLayout()
end
