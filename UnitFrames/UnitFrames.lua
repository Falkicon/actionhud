local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local UnitFrames = addon:NewModule("UnitFrames", "AceEvent-3.0")
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's unit frames (PlayerFrame, TargetFrame, FocusFrame)
-- and apply custom styling. This is Midnight-safe as we only modify visual properties.

local isStylingActive = false
local hooksInstalled = false

-- Flat bar texture (solid color, no gradient)
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Cache for original textures (for potential restoration)
local originalTextures = {}

function UnitFrames:OnInitialize()
    self.db = addon.db
end

function UnitFrames:OnEnable()
    addon:Log("UnitFrames:OnEnable", "discovery")
    
    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function()
        self:SetupStyling()
    end)
end

function UnitFrames:OnDisable()
    isStylingActive = false
    -- Note: Can't fully undo styling due to hooksecurefunc limitations
    -- User must reload to restore default appearance
end

-- Install hooks on the unit frames (only once, can't be removed)
function UnitFrames:InstallHooks()
    if hooksInstalled then return true end
    
    -- PlayerFrame hooks
    if PlayerFrame then
        -- Hook art update to re-apply styling
        hooksecurefunc("PlayerFrame_UpdateArt", function()
            if isStylingActive and self.db.profile.ufStylePlayer then
                self:StylePlayerFrame()
            end
        end)
        
        -- Hook status update
        hooksecurefunc("PlayerFrame_UpdateStatus", function()
            if isStylingActive and self.db.profile.ufStylePlayer then
                self:StylePlayerFrame()
            end
        end)
    end
    
    -- TargetFrame hooks
    if TargetFrame then
        hooksecurefunc("TargetFrame_Update", function()
            if isStylingActive and self.db.profile.ufStyleTarget then
                self:StyleTargetFrame()
            end
        end)
        
        hooksecurefunc("TargetFrame_CheckClassification", function()
            if isStylingActive and self.db.profile.ufStyleTarget then
                self:StyleTargetFrame()
            end
        end)
    end
    
    -- FocusFrame hooks (shares code with TargetFrame)
    if FocusFrame then
        -- FocusFrame uses TargetFrame functions but we can hook its specific update
        hooksecurefunc(FocusFrame, "Update", function()
            if isStylingActive and self.db.profile.ufStyleFocus then
                self:StyleFocusFrame()
            end
        end)
    end
    
    hooksInstalled = true
    addon:Log("UnitFrames: Hooks installed", "discovery")
    return true
end

-- Style the Player Frame
function UnitFrames:StylePlayerFrame()
    if not PlayerFrame then return end
    
    local p = self.db.profile
    
    -- Get the content containers (structure varies by WoW version)
    local content = PlayerFrame.PlayerFrameContent
    if not content then return end
    
    local main = content.PlayerFrameContentMain
    if not main then return end
    
    -- Hide portrait
    if p.ufHidePortraits then
        self:HidePortrait(main)
    end
    
    -- Hide borders
    if p.ufHideBorders then
        self:HideBorders(PlayerFrame)
        self:HideBorders(main)
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars then
        self:ApplyFlatBars(main)
    end
    
    -- Resize bars
    if p.ufHealthHeight or p.ufManaHeight then
        self:ResizeBars(main, p.ufHealthHeight, p.ufManaHeight)
    end
    
    -- Style class power bar
    if p.ufClassBarHeight then
        self:StyleClassPowerBar(main)
    end
end

-- Style the Target Frame
function UnitFrames:StyleTargetFrame()
    if not TargetFrame then return end
    
    local p = self.db.profile
    
    -- TargetFrame has a different structure
    local content = TargetFrame.TargetFrameContent
    if not content then return end
    
    local main = content.TargetFrameContentMain
    if not main then return end
    
    -- Hide portrait
    if p.ufHidePortraits then
        self:HidePortrait(main)
    end
    
    -- Hide borders
    if p.ufHideBorders then
        self:HideBorders(TargetFrame)
        self:HideBorders(main)
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars then
        self:ApplyFlatBars(main)
    end
    
    -- Resize bars
    if p.ufHealthHeight or p.ufManaHeight then
        self:ResizeBars(main, p.ufHealthHeight, p.ufManaHeight)
    end
end

-- Style the Focus Frame
function UnitFrames:StyleFocusFrame()
    if not FocusFrame then return end
    
    local p = self.db.profile
    
    -- FocusFrame has similar structure to TargetFrame
    local content = FocusFrame.TargetFrameContent
    if not content then return end
    
    local main = content.TargetFrameContentMain
    if not main then return end
    
    -- Hide portrait
    if p.ufHidePortraits then
        self:HidePortrait(main)
    end
    
    -- Hide borders
    if p.ufHideBorders then
        self:HideBorders(FocusFrame)
        self:HideBorders(main)
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars then
        self:ApplyFlatBars(main)
    end
    
    -- Resize bars
    if p.ufHealthHeight or p.ufManaHeight then
        self:ResizeBars(main, p.ufHealthHeight, p.ufManaHeight)
    end
end

-- Hide the portrait area
function UnitFrames:HidePortrait(main)
    if not main then return end
    
    -- Try different portrait locations based on frame structure
    local portraitFrame = main.PortraitFrame
    if portraitFrame then
        if portraitFrame.Portrait then
            portraitFrame.Portrait:SetAlpha(0)
        end
        if portraitFrame.PortraitMask then
            portraitFrame.PortraitMask:SetAlpha(0)
        end
        -- Hide the entire portrait frame background
        for _, region in pairs({portraitFrame:GetRegions()}) do
            if region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end
    end
    
    -- Also try direct Portrait key (some frames)
    if main.Portrait then
        main.Portrait:SetAlpha(0)
    end
end

-- Hide border decorations
function UnitFrames:HideBorders(frame)
    if not frame then return end
    
    -- Hide frame-level textures that are borders/decorations
    local regions = {frame:GetRegions()}
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            local name = region:GetDebugName() or ""
            -- Hide textures that look like borders/decorations
            if name:find("Border") or name:find("Ring") or name:find("Decoration") 
               or name:find("Frame") or name:find("Background") then
                region:SetAlpha(0)
            end
        end
    end
    
    -- Also check for named border elements
    if frame.Border then
        frame.Border:SetAlpha(0)
    end
    if frame.BorderLeft then frame.BorderLeft:SetAlpha(0) end
    if frame.BorderRight then frame.BorderRight:SetAlpha(0) end
    if frame.BorderTop then frame.BorderTop:SetAlpha(0) end
    if frame.BorderBottom then frame.BorderBottom:SetAlpha(0) end
end

-- Apply flat texture to status bars
function UnitFrames:ApplyFlatBars(main)
    if not main then return end
    
    -- Health bar
    local healthBarContainer = main.HealthBarContainer or main.HealthBarsContainer
    if healthBarContainer then
        local healthBar = healthBarContainer.HealthBar or healthBarContainer.healthBar
        if healthBar and healthBar.SetStatusBarTexture then
            healthBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
    end
    
    -- Mana bar
    local manaBar = main.ManaBar or main.manaBar
    if manaBar and manaBar.SetStatusBarTexture then
        manaBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
    end
    
    -- Also try PowerBar (alternative name)
    local powerBar = main.PowerBar or main.powerBar
    if powerBar and powerBar.SetStatusBarTexture then
        powerBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
    end
end

-- Resize health and mana bars
function UnitFrames:ResizeBars(main, healthHeight, manaHeight)
    if not main then return end
    
    local p = self.db.profile
    
    -- Health bar
    if healthHeight then
        local healthBarContainer = main.HealthBarContainer or main.HealthBarsContainer
        if healthBarContainer then
            healthBarContainer:SetHeight(healthHeight)
        end
    end
    
    -- Mana bar
    if manaHeight then
        local manaBar = main.ManaBar or main.manaBar or main.PowerBar or main.powerBar
        if manaBar then
            manaBar:SetHeight(manaHeight)
        end
    end
    
    -- Apply bar width scale
    if p.ufBarScale and p.ufBarScale ~= 1.0 then
        local healthBarContainer = main.HealthBarContainer or main.HealthBarsContainer
        if healthBarContainer then
            local width = healthBarContainer:GetWidth()
            healthBarContainer:SetWidth(width * p.ufBarScale)
        end
        
        local manaBar = main.ManaBar or main.manaBar or main.PowerBar or main.powerBar
        if manaBar then
            local width = manaBar:GetWidth()
            manaBar:SetWidth(width * p.ufBarScale)
        end
    end
end

-- Style the class power bar (combo points, holy power, etc.)
function UnitFrames:StyleClassPowerBar(main)
    if not main then return end
    
    local p = self.db.profile
    
    -- Try to find class power bar
    local classPowerBar = main.ClassPowerBar
    if not classPowerBar then
        -- Try PlayerFrame directly
        if PlayerFrame and PlayerFrame.classPowerBar then
            classPowerBar = PlayerFrame.classPowerBar
        end
    end
    
    if classPowerBar then
        if p.ufClassBarHeight then
            classPowerBar:SetHeight(p.ufClassBarHeight)
        end
        
        -- Apply flat texture to class bar segments if they exist
        if p.ufFlatBars then
            for i = 1, 10 do
                local segment = classPowerBar["ClassPowerBarSegment" .. i]
                if segment and segment.SetStatusBarTexture then
                    segment:SetStatusBarTexture(FLAT_BAR_TEXTURE)
                elseif segment and segment.SetTexture then
                    segment:SetTexture(FLAT_BAR_TEXTURE)
                end
            end
        end
    end
    
    -- Also try the alternate power bar (some classes)
    local alternatePowerBar = main.AlternatePowerBar
    if alternatePowerBar then
        if p.ufClassBarHeight then
            alternatePowerBar:SetHeight(p.ufClassBarHeight)
        end
        if p.ufFlatBars and alternatePowerBar.SetStatusBarTexture then
            alternatePowerBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
    end
end

-- Refresh all styled frames
function UnitFrames:RefreshAllFrames()
    local p = self.db.profile
    
    if p.ufStylePlayer then
        self:StylePlayerFrame()
    end
    
    if p.ufStyleTarget then
        self:StyleTargetFrame()
    end
    
    if p.ufStyleFocus then
        self:StyleFocusFrame()
    end
end

-- Main setup function
function UnitFrames:SetupStyling()
    local p = self.db.profile
    
    if not p.ufEnabled then
        isStylingActive = false
        addon:Log("UnitFrames: Styling disabled", "discovery")
        return
    end
    
    -- Install hooks (only once)
    if not self:InstallHooks() then
        -- Retry if frames weren't ready
        C_Timer.After(1.0, function() self:SetupStyling() end)
        return
    end
    
    isStylingActive = true
    
    -- Apply to all frames
    self:RefreshAllFrames()
    
    addon:Log("UnitFrames: Styling active", "discovery")
end

-- Update layout (called when settings change)
function UnitFrames:UpdateLayout()
    local p = self.db.profile
    
    if p.ufEnabled then
        isStylingActive = true
        self:RefreshAllFrames()
    else
        isStylingActive = false
    end
end

-- Module doesn't participate in HUD stack layout
function UnitFrames:CalculateHeight()
    return 0
end

function UnitFrames:GetLayoutWidth()
    return 0
end

function UnitFrames:ApplyLayoutPosition(yOffset)
    -- Unit frames are independent of HUD positioning
end
