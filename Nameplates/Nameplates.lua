local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Nameplates = addon:NewModule("Nameplates", "AceEvent-3.0")
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's nameplate frames and apply
-- custom styling. This is Midnight-safe as we only modify visual properties.

local isStylingActive = false
local hooksInstalled = false

-- Flat bar texture (solid color, no gradient)
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Cache for styled nameplates to avoid redundant work
local styledPlates = {}

function Nameplates:OnInitialize()
    self.db = addon.db
end

function Nameplates:OnEnable()
    addon:Log("Nameplates:OnEnable", "discovery")
    
    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function()
        self:SetupStyling()
    end)
end

function Nameplates:OnDisable()
    isStylingActive = false
    -- Note: Can't fully undo styling due to hooksecurefunc limitations
    -- User must reload to restore default appearance
end

-- Install hooks on the NamePlateDriver (only once, can't be removed)
function Nameplates:InstallHooks()
    if hooksInstalled then return true end
    
    if not NamePlateDriverFrame then
        addon:Log("Nameplates: NamePlateDriverFrame not found", "discovery")
        return false
    end
    
    -- Hook when a nameplate is added to apply styling
    hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(driver, namePlateUnitToken)
        if isStylingActive then
            local namePlateFrame = C_NamePlate.GetNamePlateForUnit(namePlateUnitToken)
            if namePlateFrame then
                self:StyleNameplate(namePlateFrame)
            end
        end
    end)
    
    -- Hook when nameplate options are updated (EditMode, CVars, etc.)
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
        if isStylingActive then
            self:RefreshAllNameplates()
        end
    end)
    
    hooksInstalled = true
    addon:Log("Nameplates: Hooks installed on NamePlateDriverFrame", "discovery")
    return true
end

-- Apply styling to a single nameplate
function Nameplates:StyleNameplate(namePlateFrame)
    if not namePlateFrame or not namePlateFrame.UnitFrame then return end
    
    local unitFrame = namePlateFrame.UnitFrame
    local p = self.db.profile
    
    -- Health bar container
    local healthContainer = unitFrame.HealthBarsContainer
    if not healthContainer then return end
    
    local healthBar = healthContainer.healthBar
    local border = healthContainer.border
    
    -- Hide borders for clean look
    if p.npHideBorders and border then
        self:HideBorder(border)
    end
    
    -- Flat bar texture
    if p.npFlatBars and healthBar then
        self:ApplyFlatTexture(healthBar)
    end
    
    -- Custom bar height
    if p.npBarHeight and p.npBarHeight ~= 4 then
        PixelUtil.SetHeight(healthContainer, p.npBarHeight)
        if border then
            border:UpdateSizes()
        end
    end
    
    -- Custom bar width scale
    if p.npBarScale and p.npBarScale ~= 1.0 then
        -- Adjust the left/right anchors to change width
        local baseOffset = 12 * p.npBarScale
        healthContainer:ClearAllPoints()
        PixelUtil.SetPoint(healthContainer, "LEFT", namePlateFrame, "LEFT", baseOffset, 5)
        PixelUtil.SetPoint(healthContainer, "RIGHT", namePlateFrame, "RIGHT", -baseOffset, 5)
    end
    
    -- Track that we've styled this plate
    styledPlates[namePlateFrame] = true
end

-- Hide the border frame's textures
function Nameplates:HideBorder(border)
    if not border then return end
    
    -- The border frame has Left, Right, Top, Bottom textures in .Textures array
    if border.Textures then
        for _, texture in ipairs(border.Textures) do
            texture:SetAlpha(0)
        end
    end
    
    -- Also try individual keys
    if border.Left then border.Left:SetAlpha(0) end
    if border.Right then border.Right:SetAlpha(0) end
    if border.Top then border.Top:SetAlpha(0) end
    if border.Bottom then border.Bottom:SetAlpha(0) end
end

-- Apply flat solid texture to a status bar
function Nameplates:ApplyFlatTexture(statusBar)
    if not statusBar then return end
    statusBar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
end

-- Style the class nameplate bar (mana bar for casters, etc.)
function Nameplates:StyleClassBar()
    local p = self.db.profile
    if not p.npClassBarHeight then return end
    
    local classBar = NamePlateDriverFrame:GetClassNameplateManaBar()
    if classBar then
        if p.npClassBarHeight and p.npClassBarHeight ~= 4 then
            PixelUtil.SetHeight(classBar, p.npClassBarHeight)
            if classBar.Border then
                classBar.Border:UpdateSizes()
            end
        end
        
        if p.npHideBorders and classBar.Border then
            self:HideBorder(classBar.Border)
        end
        
        if p.npFlatBars then
            self:ApplyFlatTexture(classBar)
        end
    end
end

-- Refresh styling on all active nameplates
function Nameplates:RefreshAllNameplates()
    for _, namePlateFrame in pairs(C_NamePlate.GetNamePlates()) do
        self:StyleNameplate(namePlateFrame)
    end
    self:StyleClassBar()
end

-- Main setup function
function Nameplates:SetupStyling()
    local p = self.db.profile
    
    if not p.npEnabled then
        isStylingActive = false
        addon:Log("Nameplates: Styling disabled", "discovery")
        return
    end
    
    -- Install hooks (only once)
    if not self:InstallHooks() then
        -- Retry if NamePlateDriverFrame wasn't ready
        C_Timer.After(1.0, function() self:SetupStyling() end)
        return
    end
    
    isStylingActive = true
    
    -- Apply to all existing nameplates
    self:RefreshAllNameplates()
    
    -- Also style player frame portrait if enabled
    self:UpdatePlayerPortrait()
    
    addon:Log("Nameplates: Styling active", "discovery")
end

-- Handle Player Frame portrait visibility
function Nameplates:UpdatePlayerPortrait()
    local p = self.db.profile
    
    if not p.npHidePlayerPortrait then return end
    
    -- PlayerFrame structure varies by WoW version
    -- In modern WoW (11.0+), portrait is in PlayerFrameContent
    local portrait = nil
    
    if PlayerFrame and PlayerFrame.PlayerFrameContent then
        local content = PlayerFrame.PlayerFrameContent
        if content.PlayerFrameContentMain then
            local main = content.PlayerFrameContentMain
            if main.PortraitFrame then
                portrait = main.PortraitFrame
            end
        end
    end
    
    -- Fallback for older structure
    if not portrait and PlayerFrameTexture then
        portrait = PlayerFrameTexture
    end
    
    if portrait then
        if p.npHidePlayerPortrait then
            portrait:SetAlpha(0)
        else
            portrait:SetAlpha(1)
        end
    end
end

-- Update layout (called when settings change)
function Nameplates:UpdateLayout()
    local p = self.db.profile
    
    if p.npEnabled then
        isStylingActive = true
        self:RefreshAllNameplates()
        self:UpdatePlayerPortrait()
    else
        isStylingActive = false
    end
end

-- Module doesn't participate in HUD stack layout
function Nameplates:CalculateHeight()
    return 0
end

function Nameplates:GetLayoutWidth()
    return 0
end

function Nameplates:ApplyLayoutPosition(yOffset)
    -- Nameplates are independent of HUD positioning
end
