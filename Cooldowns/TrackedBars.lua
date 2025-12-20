local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBars = addon:NewModule("TrackedBars", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Reskin approach: We hook into Blizzard's BuffBarCooldownViewer frame
-- and reparent/restyle it instead of creating our own proxy frames.
-- This allows Blizzard's code to handle the protected API calls for aura data.

local BLIZZARD_FRAME_NAME = "BuffBarCooldownViewer"

-- State for reskin management
local isReskinActive = false
local originalParent = nil
local originalPoints = nil
local originalScale = nil
local hooksInstalled = false

function TrackedBars:OnInitialize()
    self.db = addon.db
end

function TrackedBars:OnEnable()
    addon:Log("TrackedBars:OnEnable called (reskin mode)", "discovery")
    
    -- Create our container for positioning
    Manager:CreateContainer("bars", "ActionHudTrackedBarsContainer")
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function() 
        self:SetupReskin()
    end)
end

function TrackedBars:OnDisable()
    self:RestoreBlizzardFrame()
    local container = Manager:GetContainer("bars")
    if container then container:Hide() end
end

-- Get the Blizzard frame we're reskinning
function TrackedBars:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

-- TrackedBars is a "sidecar" module - not part of vertical stack
-- It uses independent X/Y offset positioning from profile

-- Apply position from profile settings (sidecar positioning)
function TrackedBars:ApplyLayoutPosition()
    local container = Manager:GetContainer("bars")
    if not container then return end
    
    local p = self.db.profile
    if not p.tbEnabled then 
        container:Hide()
        self:RestoreBlizzardFrame()
        return
    end
    
    local main = _G["ActionHudFrame"]
    if not main then return end
    
    -- Sidecar positioning: independent X/Y offsets from main frame center
    container:ClearAllPoints()
    container:SetPoint("CENTER", main, "CENTER", p.tbXOffset or 76, p.tbYOffset or 0)
    container:Show()
    
    -- Re-apply positioning to Blizzard frame
    self:PositionBlizzardFrame()
    
    addon:Log(string.format("TrackedBars positioned: xOffset=%d, yOffset=%d", 
        p.tbXOffset or 76, p.tbYOffset or 0), "layout")
end

-- Install hooks on the Blizzard frame (only once)
function TrackedBars:InstallHooks()
    if hooksInstalled then return end
    
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then 
        addon:Log("TrackedBars: BuffBarCooldownViewer not found for hooks", "discovery")
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
            local container = Manager:GetContainer("bars")
            if container then
                container:SetShown(blizzFrame:IsShown())
            end
        end
    end)
    
    hooksInstalled = true
    addon:Log("TrackedBars: Hooks installed on BuffBarCooldownViewer", "discovery")
end

-- Save original state of Blizzard frame for restoration
function TrackedBars:SaveOriginalState()
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
        
        addon:Log("TrackedBars: Saved original Blizzard frame state", "discovery")
    end
end

-- Restore Blizzard frame to its original state
function TrackedBars:RestoreBlizzardFrame()
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
    
    isReskinActive = false
    addon:Log("TrackedBars: Restored Blizzard frame to original state", "discovery")
end

-- Position the Blizzard frame within our container
function TrackedBars:PositionBlizzardFrame()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    local container = Manager:GetContainer("bars")
    if not container then return end
    
    local p = self.db.profile
    if not p.tbEnabled then return end
    
    -- Apply positioning - center in container
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", container, "CENTER", 0, 0)
end

-- Apply our custom styling to the Blizzard frame
-- IMPORTANT: We only apply safe visual changes here. DO NOT call:
--   - SetHideWhenInactive() - triggers Blizzard refresh with protected APIs
--   - itemContainerFrame:Layout() - triggers refresh cycle
--   - Setting blizzFrame.iconScale - triggers internal refresh logic
function TrackedBars:ApplyCustomStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    local p = self.db.profile
    
    -- Calculate scale based on desired height vs default 30
    local DEFAULT_BAR_HEIGHT = 30
    local desiredHeight = p.tbHeight or DEFAULT_BAR_HEIGHT
    local scale = desiredHeight / DEFAULT_BAR_HEIGHT
    
    -- Apply scale to the entire frame (safe - doesn't trigger refresh)
    blizzFrame:SetScale(scale)
    
    -- Apply opacity (safe)
    blizzFrame:SetAlpha(p.tbOpacity or 1.0)
    
    -- Override padding if we have custom gap (safe - just property assignment)
    if p.tbGap then
        blizzFrame.childXPadding = p.tbGap
        blizzFrame.childYPadding = p.tbGap
    end
    
    -- Update container size to match scaled frame
    local container = Manager:GetContainer("bars")
    if container then
        local width = (blizzFrame:GetWidth() or 220) * scale
        local height = (blizzFrame:GetHeight() or 30) * scale
        container:SetSize(math.max(width, 1), math.max(height, 1))
    end
end

-- Style an individual bar item frame
function TrackedBars:StyleItemFrame(itemFrame)
    if not itemFrame then return end
    
    local p = self.db.profile
    
    -- Remove Blizzard's decorative elements (mask, overlay, shadows)
    self:StripBlizzardDecorations(itemFrame)
    
    -- Apply custom timer font size if specified
    -- p.tbTimerFontSize is a string like "small", "medium", "large", "huge"
    if p.tbTimerFontSize then
        local fontObject = Utils.GetTimerFont(p.tbTimerFontSize)
        
        local durationFontString = itemFrame.Bar and itemFrame.Bar.Duration
        if durationFontString and fontObject then
            durationFontString:SetFontObject(fontObject)
        end
        
        local nameFontString = itemFrame.Bar and itemFrame.Bar.Name
        if nameFontString and fontObject then
            nameFontString:SetFontObject(fontObject)
        end
    end
    
    -- Apply custom count font size if specified (numeric)
    if p.tbCountFontSize and type(p.tbCountFontSize) == "number" then
        local iconFrame = itemFrame.Icon
        if iconFrame and iconFrame.Applications then
            iconFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", p.tbCountFontSize, "OUTLINE")
        end
    end
end

-- Remove Blizzard's decorative textures (mask, overlay, shadow, bar background)
-- Target specific known elements to avoid secret value issues with GetDrawLayer()
function TrackedBars:StripBlizzardDecorations(itemFrame)
    if not itemFrame then return end
    if itemFrame._ahStripped then return end -- Only strip once
    
    -- Blizzard's CooldownViewerBuffBarItemTemplate structure:
    -- Icon frame contains: Icon texture, MaskTexture, IconOverlay texture, Applications FontString
    -- Bar frame contains: BarTexture, Background texture, Pip texture, Name FontString, Duration FontString
    
    -- Strip decorations from the Icon frame
    if itemFrame.Icon then
        local iconFrame = itemFrame.Icon
        local regions = {iconFrame:GetRegions()}
        for _, region in ipairs(regions) do
            -- Hide MaskTextures (removes rounded corner masking)
            if region:IsObjectType("MaskTexture") then
                region:Hide()
            -- Hide textures that aren't the main icon
            elseif region:IsObjectType("Texture") and region ~= iconFrame.Icon then
                region:Hide()
            end
        end
        -- Apply standard icon crop
        if iconFrame.Icon then
            iconFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    
    -- Strip decorations from the Bar frame
    if itemFrame.Bar then
        local barFrame = itemFrame.Bar
        local regions = {barFrame:GetRegions()}
        for _, region in ipairs(regions) do
            -- Hide textures that aren't the status bar fill
            -- The BarTexture is set via :GetStatusBarTexture(), not a child region
            if region:IsObjectType("Texture") then
                -- Hide background/pip textures but keep the bar fill
                local barTexture = barFrame:GetStatusBarTexture()
                if region ~= barTexture then
                    region:Hide()
                end
            end
        end
        -- Hide the pip (end cap indicator) - it's a parentKey
        if barFrame.Pip then
            barFrame.Pip:Hide()
        end
    end
    
    itemFrame._ahStripped = true
end

-- Main setup function for the reskin
function TrackedBars:SetupReskin()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBars: BuffBarCooldownViewer not available yet", "discovery")
        -- Retry after a delay
        C_Timer.After(1.0, function() self:SetupReskin() end)
        return
    end
    
    local p = self.db.profile
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    
    addon:Log(string.format("TrackedBars:SetupReskin: enabled=%s, blizzEnabled=%s", 
        tostring(p.tbEnabled), tostring(blizzEnabled)), "discovery")
    
    if not p.tbEnabled or not blizzEnabled then
        self:RestoreBlizzardFrame()
        local container = Manager:GetContainer("bars")
        if container then container:Hide() end
        return
    end
    
    -- Install hooks (only once)
    self:InstallHooks()
    
    -- Save original state before modifying
    self:SaveOriginalState()
    
    -- Get our container
    local container = Manager:GetContainer("bars")
    if not container then return end
    
    -- Reparent Blizzard frame to our container
    blizzFrame:SetParent(container)
    
    -- Remove from any managed frame system to prevent conflicts
    if blizzFrame.layoutParent then
        blizzFrame.layoutParent = nil
    end
    
    -- Position and style
    self:PositionBlizzardFrame()
    self:ApplyCustomStyling()
    
    -- Position the container (sidecar positioning)
    self:ApplyLayoutPosition()
    
    -- Show container and debug overlay
    container:Show()
    Manager:UpdateContainerDebug("bars", {r=1, g=0, b=0}) -- Red for bars
    
    isReskinActive = true
    addon:Log("TrackedBars: Reskin active, Blizzard frame reparented", "discovery")
end

-- Update layout (called when settings change)
function TrackedBars:UpdateLayout()
    addon:Log("TrackedBars:UpdateLayout", "discovery")
    self:SetupReskin()
end

-- Called on zone/world changes
function TrackedBars:OnPlayerEnteringWorld()
    -- Re-apply layout after zone changes
    C_Timer.After(0.2, function()
        self:UpdateLayout()
    end)
end

-- Called by Manager (for compatibility, but not used in reskin mode)
function TrackedBars:OnAuraUpdate()
    -- In reskin mode, Blizzard handles aura updates automatically
    -- We don't need to do anything here
end
