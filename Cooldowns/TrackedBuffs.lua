local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffs = addon:NewModule("TrackedBuffs", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's BuffIconCooldownViewer frame
-- and apply custom styling. Position is controlled by Blizzard's EditMode.
-- This is similar to how ClassyMap styles the minimap without moving it.

local BLIZZARD_FRAME_NAME = "BuffIconCooldownViewer"

local isStylingActive = false
local hooksInstalled = false

function TrackedBuffs:OnInitialize()
    self.db = addon.db
end

function TrackedBuffs:OnEnable()
    addon:Log("TrackedBuffs:OnEnable (style-only mode)", "discovery")
    
    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function() 
        self:SetupStyling()
    end)
end

function TrackedBuffs:OnDisable()
    -- Note: Can't fully undo styling due to hooksecurefunc limitations
    -- but we stop applying new styling
    isStylingActive = false
end

-- Get the Blizzard frame we're styling
function TrackedBuffs:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

-- Install hooks on the Blizzard frame (only once, can't be removed)
function TrackedBuffs:InstallHooks()
    if hooksInstalled then return end
    
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then 
        addon:Log("TrackedBuffs: BuffIconCooldownViewer not found for hooks", "discovery")
        return false
    end
    
    -- Hook RefreshLayout to re-apply our styling after Blizzard updates
    hooksecurefunc(blizzFrame, "RefreshLayout", function()
        if isStylingActive then
            self:ApplyStyling()
        end
    end)
    
    -- Hook OnAcquireItemFrame to style individual items as they're created
    hooksecurefunc(blizzFrame, "OnAcquireItemFrame", function(_, itemFrame)
        if isStylingActive then
            self:StyleItemFrame(itemFrame)
        end
    end)
    
    hooksInstalled = true
    addon:Log("TrackedBuffs: Hooks installed on BuffIconCooldownViewer", "discovery")
    return true
end

-- Apply styling to the frame and all existing items
function TrackedBuffs:ApplyStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    local p = self.db.profile
    
    -- Style existing item frames
    if blizzFrame.itemFramePool then
        for itemFrame in blizzFrame.itemFramePool:EnumerateActive() do
            self:StyleItemFrame(itemFrame)
        end
    end
end

-- Style an individual item frame
function TrackedBuffs:StyleItemFrame(itemFrame)
    if not itemFrame then return end
    
    local p = self.db.profile
    
    -- Remove Blizzard's decorative elements (mask, overlay, shadows)
    self:StripBlizzardDecorations(itemFrame)
    
    -- Apply custom timer font size if specified
    if p.trackedTimerFontSize and itemFrame.Cooldown then
        local fontObject = Utils.GetTimerFont(p.trackedTimerFontSize)
        if fontObject then
            itemFrame.Cooldown:SetCountdownFont(fontObject)
        end
    end
    
    -- Apply custom count font size if specified (numeric)
    if p.trackedCountFontSize and type(p.trackedCountFontSize) == "number" then
        local applicationsFrame = itemFrame.Applications
        if applicationsFrame and applicationsFrame.Applications then
            applicationsFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", p.trackedCountFontSize, "OUTLINE")
        end
    end
end

-- Remove Blizzard's decorative textures (mask, overlay, shadow)
function TrackedBuffs:StripBlizzardDecorations(itemFrame)
    if not itemFrame then return end
    if itemFrame._ahStripped then return end -- Only strip once
    
    -- Hide MaskTextures and overlay textures
    local regions = {itemFrame:GetRegions()}
    for _, region in ipairs(regions) do
        if region:IsObjectType("MaskTexture") then
            region:Hide()
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

-- Main setup function
function TrackedBuffs:SetupStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBuffs: BuffIconCooldownViewer not available yet", "discovery")
        C_Timer.After(1.0, function() self:SetupStyling() end)
        return
    end
    
    local p = self.db.profile
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    
    if not p.styleTrackedBuffs or not blizzEnabled then
        isStylingActive = false
        addon:Log("TrackedBuffs: Styling disabled", "discovery")
        return
    end
    
    -- Install hooks (only once)
    if not self:InstallHooks() then
        return
    end
    
    -- Apply initial styling
    self:ApplyStyling()
    
    isStylingActive = true
    addon:Log("TrackedBuffs: Styling active", "discovery")
end

-- Update styling (called when settings change)
function TrackedBuffs:UpdateLayout()
    self:SetupStyling()
end
