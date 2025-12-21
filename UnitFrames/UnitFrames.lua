local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local UnitFrames = addon:NewModule("UnitFrames", "AceEvent-3.0")

-- Style-only approach: We hook into Blizzard's unit frames (PlayerFrame, TargetFrame, FocusFrame)
-- and apply custom styling. This is Midnight-safe as we only modify visual properties.

local isStylingActive = false
local hooksInstalled = false

-- Flat bar texture (solid color, no gradient)
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"

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
end

-- Install hooks on the unit frames (only once, can't be removed)
function UnitFrames:InstallHooks()
    if hooksInstalled then return true end
    
    -- PlayerFrame hooks - these ARE global functions
    if PlayerFrame_Update then
        hooksecurefunc("PlayerFrame_Update", function()
            if isStylingActive and self.db.profile.ufStylePlayer then
                self:StylePlayerFrame()
            end
        end)
    end
    
    if PlayerFrame_UpdateArt then
        hooksecurefunc("PlayerFrame_UpdateArt", function()
            if isStylingActive and self.db.profile.ufStylePlayer then
                self:StylePlayerFrame()
            end
        end)
    end
    
    -- TargetFrame hooks - these are MIXIN methods, hook on the frame object
    if TargetFrame and TargetFrame.Update then
        hooksecurefunc(TargetFrame, "Update", function()
            if isStylingActive and self.db.profile.ufStyleTarget then
                self:StyleTargetFrame()
            end
        end)
    end
    
    -- FocusFrame hooks - also mixin methods
    if FocusFrame and FocusFrame.Update then
        hooksecurefunc(FocusFrame, "Update", function()
            if isStylingActive and self.db.profile.ufStyleFocus then
                self:StyleFocusFrame()
            end
        end)
    end
    
    -- Register for target changed event to catch initial styling
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        if isStylingActive and self.db.profile.ufStyleTarget then
            C_Timer.After(0.1, function() self:StyleTargetFrame() end)
        end
    end)
    
    self:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
        if isStylingActive and self.db.profile.ufStyleFocus then
            C_Timer.After(0.1, function() self:StyleFocusFrame() end)
        end
    end)
    
    hooksInstalled = true
    addon:Log("UnitFrames: Hooks installed", "discovery")
    return true
end

-- Get the correct frame elements for PlayerFrame
function UnitFrames:GetPlayerFrameElements()
    if not PlayerFrame then return nil end
    
    local elements = {}
    
    -- Portrait: PlayerFrame.PlayerFrameContainer.PlayerPortrait
    if PlayerFrame.PlayerFrameContainer then
        elements.portrait = PlayerFrame.PlayerFrameContainer.PlayerPortrait
        elements.frameTexture = PlayerFrame.PlayerFrameContainer.FrameTexture
        elements.vehicleTexture = PlayerFrame.PlayerFrameContainer.VehicleFrameTexture
        elements.alternatePowerTexture = PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture
    end
    
    -- Main content
    if PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain then
        local main = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        
        -- Health bar container and bar
        if main.HealthBarsContainer then
            elements.healthContainer = main.HealthBarsContainer
            elements.healthBar = main.HealthBarsContainer.HealthBar
            elements.healthMask = main.HealthBarsContainer.HealthBarMask
        end
        
        -- Mana bar
        elements.manaBar = main.ManaBar
        if main.ManaBar then
            elements.manaMask = main.ManaBar.ManaBarMask
        end
    end
    
    return elements
end

-- Get the correct frame elements for TargetFrame
function UnitFrames:GetTargetFrameElements(frame)
    frame = frame or TargetFrame
    if not frame then return nil end
    
    local elements = {}
    
    -- Portrait: TargetFrame.TargetFrameContainer.Portrait
    if frame.TargetFrameContainer then
        elements.portrait = frame.TargetFrameContainer.Portrait
        elements.frameTexture = frame.TargetFrameContainer.FrameTexture
    end
    
    -- Main content
    if frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain then
        local main = frame.TargetFrameContent.TargetFrameContentMain
        
        -- Health bar container and bar
        if main.HealthBarsContainer then
            elements.healthContainer = main.HealthBarsContainer
            elements.healthBar = main.HealthBarsContainer.HealthBar
            elements.healthMask = main.HealthBarsContainer.HealthBarMask
        end
        
        -- Mana bar
        elements.manaBar = main.ManaBar
        if main.ManaBar then
            elements.manaMask = main.ManaBar.ManaBarMask
        end
        
        -- Name text
        elements.name = main.Name
    end
    
    return elements
end

-- Style the Player Frame
function UnitFrames:StylePlayerFrame()
    local elements = self:GetPlayerFrameElements()
    if not elements then return end
    
    local p = self.db.profile
    
    -- Hide portrait
    if p.ufHidePortraits and elements.portrait then
        elements.portrait:SetAlpha(0)
    end
    
    -- Hide borders/frame texture
    if p.ufHideBorders then
        if elements.frameTexture then elements.frameTexture:SetAlpha(0) end
        if elements.vehicleTexture then elements.vehicleTexture:SetAlpha(0) end
        if elements.alternatePowerTexture then elements.alternatePowerTexture:SetAlpha(0) end
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars then
        if elements.healthBar then
            elements.healthBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
        if elements.manaBar then
            elements.manaBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
    end
    
    -- Hide masks for cleaner look (masks create the curved edges)
    if p.ufHideBorders then
        if elements.healthMask then elements.healthMask:Hide() end
        if elements.manaMask then elements.manaMask:Hide() end
    end
    
    -- Resize bars
    if elements.healthContainer and p.ufHealthHeight then
        elements.healthContainer:SetHeight(p.ufHealthHeight)
        if elements.healthBar then
            elements.healthBar:SetHeight(p.ufHealthHeight)
        end
    end
    
    if elements.manaBar and p.ufManaHeight then
        elements.manaBar:SetHeight(p.ufManaHeight)
    end
end

-- Style the Target Frame
function UnitFrames:StyleTargetFrame()
    local elements = self:GetTargetFrameElements(TargetFrame)
    if not elements then return end
    
    local p = self.db.profile
    
    -- Hide portrait
    if p.ufHidePortraits and elements.portrait then
        elements.portrait:SetAlpha(0)
    end
    
    -- Hide borders/frame texture
    if p.ufHideBorders then
        if elements.frameTexture then elements.frameTexture:SetAlpha(0) end
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars then
        if elements.healthBar then
            elements.healthBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
        if elements.manaBar then
            elements.manaBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
    end
    
    -- Hide masks
    if p.ufHideBorders then
        if elements.healthMask then elements.healthMask:Hide() end
        if elements.manaMask then elements.manaMask:Hide() end
    end
    
    -- Resize bars
    if elements.healthContainer and p.ufHealthHeight then
        elements.healthContainer:SetHeight(p.ufHealthHeight)
        if elements.healthBar then
            elements.healthBar:SetHeight(p.ufHealthHeight)
        end
    end
    
    if elements.manaBar and p.ufManaHeight then
        elements.manaBar:SetHeight(p.ufManaHeight)
    end
end

-- Style the Focus Frame
function UnitFrames:StyleFocusFrame()
    -- FocusFrame uses the same structure as TargetFrame
    local elements = self:GetTargetFrameElements(FocusFrame)
    if not elements then return end
    
    local p = self.db.profile
    
    -- Hide portrait
    if p.ufHidePortraits and elements.portrait then
        elements.portrait:SetAlpha(0)
    end
    
    -- Hide borders/frame texture
    if p.ufHideBorders then
        if elements.frameTexture then elements.frameTexture:SetAlpha(0) end
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars then
        if elements.healthBar then
            elements.healthBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
        if elements.manaBar then
            elements.manaBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
        end
    end
    
    -- Hide masks
    if p.ufHideBorders then
        if elements.healthMask then elements.healthMask:Hide() end
        if elements.manaMask then elements.manaMask:Hide() end
    end
    
    -- Resize bars
    if elements.healthContainer and p.ufHealthHeight then
        elements.healthContainer:SetHeight(p.ufHealthHeight)
        if elements.healthBar then
            elements.healthBar:SetHeight(p.ufHealthHeight)
        end
    end
    
    if elements.manaBar and p.ufManaHeight then
        elements.manaBar:SetHeight(p.ufManaHeight)
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
    self:InstallHooks()
    
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
        -- Re-install hooks if not done yet
        self:InstallHooks()
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
