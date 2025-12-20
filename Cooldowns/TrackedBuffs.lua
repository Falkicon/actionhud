local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffs = addon:NewModule("TrackedBuffs", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Reskin approach: We hook into Blizzard's BuffIconCooldownViewer frame
-- and reparent/restyle it instead of creating our own proxy frames.
-- This allows Blizzard's code to handle the protected API calls for aura data.

local BLIZZARD_FRAME_NAME = "BuffIconCooldownViewer"

-- State for reskin management
local isReskinActive = false
local originalParent = nil
local originalPoints = nil
local originalScale = nil
local hooksInstalled = false

function TrackedBuffs:OnInitialize()
    self.db = addon.db
end

function TrackedBuffs:OnEnable()
    addon:Log("TrackedBuffs:OnEnable called (reskin mode)", "discovery")
    
    -- Create our container for positioning
    Manager:CreateContainer("buffs", "ActionHudBuffContainer")
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function() 
        self:SetupReskin()
    end)
end

function TrackedBuffs:OnDisable()
    self:RestoreBlizzardFrame()
    local container = Manager:GetContainer("buffs")
    if container then container:Hide() end
end

-- Get the Blizzard frame we're reskinning
function TrackedBuffs:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

-- Calculate the height of this module for LayoutManager
function TrackedBuffs:CalculateHeight()
    local p = self.db.profile
    if not p.buffsEnabled then return 0 end
    
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    if not blizzEnabled then return 0 end
    
    -- Height is based on scaled Blizzard frame size
    local blizzFrame = self:GetBlizzardFrame()
    if blizzFrame and isReskinActive then
        local scale = p.buffsScale or 1.0
        return (blizzFrame:GetHeight() or 40) * scale
    end
    
    return p.buffsHeight or 40
end

-- Get the width of this module for LayoutManager
function TrackedBuffs:GetLayoutWidth()
    local blizzFrame = self:GetBlizzardFrame()
    if blizzFrame and isReskinActive then
        local p = self.db.profile
        local scale = p.buffsScale or 1.0
        return (blizzFrame:GetWidth() or 200) * scale
    end
    return 200
end

-- Apply position from LayoutManager
function TrackedBuffs:ApplyLayoutPosition()
    local container = Manager:GetContainer("buffs")
    if not container then return end
    
    local p = self.db.profile
    if not p.buffsEnabled then 
        container:Hide()
        self:RestoreBlizzardFrame()
        return
    end
    
    local main = _G["ActionHudFrame"]
    if not main then return end
    
    local LM = addon:GetModule("LayoutManager", true)
    if not LM then return end
    
    local yOffset = LM:GetModulePosition("trackedBuffs")
    container:ClearAllPoints()
    container:SetPoint("TOP", main, "TOP", 0, yOffset)
    container:Show()
    
    -- Re-apply positioning to Blizzard frame
    self:PositionBlizzardFrame()
    
    addon:Log(string.format("TrackedBuffs positioned: yOffset=%d", yOffset), "layout")
end

-- Install hooks on the Blizzard frame (only once)
function TrackedBuffs:InstallHooks()
    if hooksInstalled then return end
    
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then 
        addon:Log("TrackedBuffs: BuffIconCooldownViewer not found for hooks", "discovery")
        return 
    end
    
    -- Hook RefreshLayout to re-apply our styling after Blizzard updates layout
    hooksecurefunc(blizzFrame, "RefreshLayout", function()
        if isReskinActive then
            self:ApplyCustomStyling()
        end
    end)
    
    -- Hook OnAcquireItemFrame to style individual items
    hooksecurefunc(blizzFrame, "OnAcquireItemFrame", function(_, itemFrame)
        if isReskinActive then
            self:StyleItemFrame(itemFrame)
        end
    end)
    
    -- Hook UpdateShownState to manage visibility
    hooksecurefunc(blizzFrame, "UpdateShownState", function()
        if isReskinActive then
            -- Ensure our container visibility matches
            local container = Manager:GetContainer("buffs")
            if container then
                container:SetShown(blizzFrame:IsShown())
            end
        end
    end)
    
    hooksInstalled = true
    addon:Log("TrackedBuffs: Hooks installed on BuffIconCooldownViewer", "discovery")
end

-- Save original state of Blizzard frame for restoration
function TrackedBuffs:SaveOriginalState()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    if not originalParent then
        originalParent = blizzFrame:GetParent()
        originalScale = blizzFrame:GetScale()
        
        -- Save all anchor points
        originalPoints = {}
        for i = 1, blizzFrame:GetNumPoints() do
            local point, relativeTo, relativePoint, xOfs, yOfs = blizzFrame:GetPoint(i)
            table.insert(originalPoints, {point, relativeTo, relativePoint, xOfs, yOfs})
        end
        
        addon:Log("TrackedBuffs: Saved original Blizzard frame state", "discovery")
    end
end

-- Restore Blizzard frame to its original state
function TrackedBuffs:RestoreBlizzardFrame()
    if not isReskinActive then return end
    
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    -- Restore parent
    if originalParent then
        blizzFrame:SetParent(originalParent)
    end
    
    -- Restore scale
    if originalScale then
        blizzFrame:SetScale(originalScale)
    end
    
    -- Restore anchor points
    if originalPoints and #originalPoints > 0 then
        blizzFrame:ClearAllPoints()
        for _, pointData in ipairs(originalPoints) do
            blizzFrame:SetPoint(pointData[1], pointData[2], pointData[3], pointData[4], pointData[5])
        end
    end
    
    -- Re-enable UIParent management
    if blizzFrame.layoutParent == nil and originalParent then
        -- The frame will be re-managed by UIParent on next layout cycle
    end
    
    isReskinActive = false
    addon:Log("TrackedBuffs: Restored Blizzard frame to original state", "discovery")
end

-- Position the Blizzard frame within our container
function TrackedBuffs:PositionBlizzardFrame()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    local container = Manager:GetContainer("buffs")
    if not container then return end
    
    local p = self.db.profile
    if not p.buffsEnabled then return end
    
    -- Apply positioning
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", container, "CENTER", 0, 0)
end

-- Apply our custom styling to the Blizzard frame
function TrackedBuffs:ApplyCustomStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    local p = self.db.profile
    
    -- Apply scale
    local scale = p.buffsScale or 1.0
    blizzFrame:SetScale(scale)
    
    -- Apply opacity
    local opacity = p.buffsOpacity or 1.0
    blizzFrame:SetAlpha(opacity)
    
    -- Override padding if we have custom spacing
    if p.buffsSpacing then
        blizzFrame.childXPadding = p.buffsSpacing
        blizzFrame.childYPadding = p.buffsSpacing
    end
    
    -- Style each item frame
    for itemFrame in blizzFrame.itemFramePool:EnumerateActive() do
        self:StyleItemFrame(itemFrame)
    end
    
    -- Force re-layout with our settings
    local itemContainerFrame = blizzFrame:GetItemContainerFrame()
    if itemContainerFrame and itemContainerFrame.Layout then
        itemContainerFrame:Layout()
    end
    
    -- Update container size to match
    local container = Manager:GetContainer("buffs")
    if container then
        local width = blizzFrame:GetWidth() * scale
        local height = blizzFrame:GetHeight() * scale
        container:SetSize(math.max(width, 1), math.max(height, 1))
    end
end

-- Style an individual item frame
function TrackedBuffs:StyleItemFrame(itemFrame)
    if not itemFrame then return end
    
    local p = self.db.profile
    
    -- Remove Blizzard's decorative elements (mask, overlay, shadows)
    -- These are defined in CooldownViewerBuffIconItemTemplate
    self:StripBlizzardDecorations(itemFrame)
    
    -- Apply custom timer font size if specified
    -- p.buffsTimerFontSize is a string like "small", "medium", "large", "huge"
    if p.buffsTimerFontSize and itemFrame.Cooldown then
        local fontObject = Utils.GetTimerFont(p.buffsTimerFontSize)
        if fontObject then
            itemFrame.Cooldown:SetCountdownFont(fontObject)
        end
    end
    
    -- Apply custom count font size if specified (numeric)
    if p.buffsCountFontSize and type(p.buffsCountFontSize) == "number" then
        local applicationsFrame = itemFrame.Applications
        if applicationsFrame and applicationsFrame.Applications then
            applicationsFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", p.buffsCountFontSize, "OUTLINE")
        end
    end
end

-- Remove Blizzard's decorative textures (mask, overlay, shadow)
-- Target specific known elements to avoid secret value issues with GetDrawLayer()
function TrackedBuffs:StripBlizzardDecorations(itemFrame)
    if not itemFrame then return end
    if itemFrame._ahStripped then return end -- Only strip once
    
    -- Blizzard's CooldownViewerBuffIconItemTemplate structure:
    -- - Icon (Texture, parentKey) - KEEP
    -- - MaskTexture - Hide to remove rounded corners
    -- - Texture (IconOverlay atlas) - Hide to remove border
    
    local regions = {itemFrame:GetRegions()}
    for _, region in ipairs(regions) do
        -- Hide MaskTextures (removes rounded corner masking)
        if region:IsObjectType("MaskTexture") then
            region:Hide()
        -- Hide non-icon textures (the overlay border)
        elseif region:IsObjectType("Texture") and region ~= itemFrame.Icon then
            region:Hide()
        end
    end
    
    -- Apply standard icon crop
    if itemFrame.Icon then
        itemFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    
    itemFrame._ahStripped = true
end

-- Main setup function for the reskin
function TrackedBuffs:SetupReskin()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBuffs: BuffIconCooldownViewer not available yet", "discovery")
        -- Retry after a delay
        C_Timer.After(1.0, function() self:SetupReskin() end)
        return
    end
    
    local p = self.db.profile
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    
    addon:Log(string.format("TrackedBuffs:SetupReskin: enabled=%s, blizzEnabled=%s", 
        tostring(p.buffsEnabled), tostring(blizzEnabled)), "discovery")
    
    -- Report height to LayoutManager
    local LM = addon:GetModule("LayoutManager", true)
    if LM then
        LM:SetModuleHeight("trackedBuffs", self:CalculateHeight())
    end
    
    if not p.buffsEnabled or not blizzEnabled then
        self:RestoreBlizzardFrame()
        local container = Manager:GetContainer("buffs")
        if container then container:Hide() end
        return
    end
    
    -- Install hooks (only once)
    self:InstallHooks()
    
    -- Save original state before modifying
    self:SaveOriginalState()
    
    -- Get our container
    local container = Manager:GetContainer("buffs")
    if not container then return end
    
    -- Reparent Blizzard frame to our container
    blizzFrame:SetParent(container)
    
    -- Remove from UIParent's managed frame system to prevent conflicts
    if blizzFrame.layoutParent then
        blizzFrame.layoutParent = nil
    end
    
    -- Position and style
    self:PositionBlizzardFrame()
    self:ApplyCustomStyling()
    
    -- Show container and debug overlay
    container:Show()
    Manager:UpdateContainerDebug("buffs", {r=0, g=1, b=0}) -- Green for buffs
    
    isReskinActive = true
    addon:Log("TrackedBuffs: Reskin active, Blizzard frame reparented", "discovery")
end

-- Update layout (called when settings change)
function TrackedBuffs:UpdateLayout()
    addon:Log("TrackedBuffs:UpdateLayout", "discovery")
    self:SetupReskin()
    
    -- Notify LayoutManager of potential height change
    local LM = addon:GetModule("LayoutManager", true)
    if LM then
        LM:SetModuleHeight("trackedBuffs", self:CalculateHeight())
        LM:TriggerLayoutUpdate()
    end
end

-- Called on zone/world changes
function TrackedBuffs:OnPlayerEnteringWorld()
    -- Re-apply layout after zone changes
    C_Timer.After(0.2, function()
        self:UpdateLayout()
    end)
end

-- Called by Manager (for compatibility, but not used in reskin mode)
function TrackedBuffs:OnAuraUpdate()
    -- In reskin mode, Blizzard handles aura updates automatically
    -- We don't need to do anything here
end
