local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBars = addon:NewModule("TrackedBars", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's BuffBarCooldownViewer frame
-- and apply custom styling. Position is controlled by Blizzard's EditMode.
-- This is similar to how ClassyMap styles the minimap without moving it.

local BLIZZARD_FRAME_NAME = "BuffBarCooldownViewer"

local isStylingActive = false
local hooksInstalled = false

function TrackedBars:OnInitialize()
    self.db = addon.db
end

function TrackedBars:OnEnable()
    addon:Log("TrackedBars:OnEnable (style-only mode)", "discovery")
    
    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function() 
        self:SetupStyling()
    end)
end

function TrackedBars:OnDisable()
    -- Note: Can't fully undo styling due to hooksecurefunc limitations
    isStylingActive = false
end

-- Get the Blizzard frame we're styling
function TrackedBars:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

-- Install hooks on the Blizzard frame (only once, can't be removed)
function TrackedBars:InstallHooks()
    if hooksInstalled then return true end
    
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then 
        addon:Log("TrackedBars: BuffBarCooldownViewer not found for hooks", "discovery")
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
    addon:Log("TrackedBars: Hooks installed on BuffBarCooldownViewer", "discovery")
    return true
end

-- Apply styling to the frame and all existing items
function TrackedBars:ApplyStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end
    
    -- Style existing item frames
    if blizzFrame.itemFramePool then
        for itemFrame in blizzFrame.itemFramePool:EnumerateActive() do
            self:StyleItemFrame(itemFrame)
        end
    end
end

-- Style an individual bar item frame
function TrackedBars:StyleItemFrame(itemFrame)
    if not itemFrame then return end
    
    local p = self.db.profile
    
    -- Always strip decorations (Blizzard may re-apply them)
    self:StripBlizzardDecorations(itemFrame)
    
    -- Apply custom timer font size if specified
    -- SetFontObject requires an actual font object (global), not a string
    local timerSize = p.barsTimerFontSize or "medium"
    if timerSize then
        local fontName = Utils.GetTimerFont(timerSize)
        local fontObject = fontName and _G[fontName]
        if fontObject then
            if itemFrame.Bar and itemFrame.Bar.Duration then
                itemFrame.Bar.Duration:SetFontObject(fontObject)
            end
            if itemFrame.Bar and itemFrame.Bar.Name then
                itemFrame.Bar.Name:SetFontObject(fontObject)
            end
        end
    end
    
    -- Apply custom count font size if specified (numeric)
    local countSize = p.barsCountFontSize or 10
    if countSize and type(countSize) == "number" then
        local iconFrame = itemFrame.Icon
        if iconFrame and iconFrame.Applications then
            iconFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", countSize, "OUTLINE")
        end
    end
end

-- Remove Blizzard's decorative textures (mask, overlay, shadow, bar background)
-- Called every time to ensure decorations stay hidden
function TrackedBars:StripBlizzardDecorations(itemFrame)
    if not itemFrame then return end
    
    -- Strip decorations from the Icon frame
    if itemFrame.Icon then
        local iconFrame = itemFrame.Icon
        local regions = {iconFrame:GetRegions()}
        for _, region in ipairs(regions) do
            if region:IsObjectType("MaskTexture") then
                region:Hide()
            elseif region:IsObjectType("Texture") and region ~= iconFrame.Icon then
                region:Hide()
            end
        end
        if iconFrame.Icon then
            iconFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    
    -- Strip decorations from the Bar frame
    if itemFrame.Bar then
        local barFrame = itemFrame.Bar
        local regions = {barFrame:GetRegions()}
        for _, region in ipairs(regions) do
            if region:IsObjectType("Texture") then
                local barTexture = barFrame:GetStatusBarTexture()
                if region ~= barTexture then
                    region:Hide()
                end
            end
        end
        if barFrame.Pip then
            barFrame.Pip:Hide()
        end
    end
end

-- Main setup function
function TrackedBars:SetupStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBars: BuffBarCooldownViewer not available yet", "discovery")
        C_Timer.After(1.0, function() self:SetupStyling() end)
        return
    end
    
    local p = self.db.profile
    local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()
    
    if not p.styleTrackedBars or not blizzEnabled then
        isStylingActive = false
        addon:Log("TrackedBars: Styling disabled", "discovery")
        return
    end
    
    -- Install hooks (only once)
    if not self:InstallHooks() then
        return
    end
    
    -- Apply initial styling
    self:ApplyStyling()
    
    isStylingActive = true
    addon:Log("TrackedBars: Styling active", "discovery")
end

-- Update styling (called when settings change)
function TrackedBars:UpdateLayout()
    self:SetupStyling()
    
    -- Force re-apply styling to all existing frames
    if isStylingActive then
        self:ApplyStyling()
    end
end
