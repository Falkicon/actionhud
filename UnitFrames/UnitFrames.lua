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

-- Apply flat texture to a status bar and preserve/reapply color
local function ApplyFlatTexture(bar)
    if not bar then return end
    bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
    
    -- Force the bar to re-color itself
    -- Health bars are colored by UnitFrameHealthBar functions
    if bar.lockColor then
        -- Bar has a locked color, get and reapply it
        local r, g, b = bar:GetStatusBarColor()
        if r and g and b then
            bar:SetStatusBarColor(r, g, b)
        end
    end
end

-- Style the Player Frame
-- Exact paths from Blizzard's PlayerFrame.xml
function UnitFrames:StylePlayerFrame()
    if not PlayerFrame then return end
    
    local p = self.db.profile
    local container = PlayerFrame.PlayerFrameContainer
    local content = PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local contextual = content and content.PlayerFrameContentContextual
    
    -- Hide portrait
    if p.ufHidePortraits then
        if container and container.PlayerPortrait then
            container.PlayerPortrait:SetAlpha(0)
        end
        if container and container.PlayerPortraitMask then
            container.PlayerPortraitMask:Hide()
        end
    end
    
    -- Hide borders/frame textures
    if p.ufHideBorders then
        if container then
            -- Main frame textures
            if container.FrameTexture then container.FrameTexture:SetAlpha(0) end
            if container.VehicleFrameTexture then container.VehicleFrameTexture:SetAlpha(0) end
            if container.AlternatePowerFrameTexture then container.AlternatePowerFrameTexture:SetAlpha(0) end
            if container.FrameFlash then container.FrameFlash:SetAlpha(0) end
        end
        
        -- Contextual elements (corner icon, rest indicator, etc.)
        if contextual then
            -- The yellow corner arrow/embellishment
            if contextual.PlayerPortraitCornerIcon then contextual.PlayerPortraitCornerIcon:SetAlpha(0) end
            -- Combat sword icon
            if contextual.AttackIcon then contextual.AttackIcon:SetAlpha(0) end
            -- Zzz rest animation
            if contextual.PlayerRestLoop then contextual.PlayerRestLoop:Hide() end
            -- PVP icons
            if contextual.PVPIcon then contextual.PVPIcon:SetAlpha(0) end
            if contextual.PrestigePortrait then contextual.PrestigePortrait:SetAlpha(0) end
            if contextual.PrestigeBadge then contextual.PrestigeBadge:SetAlpha(0) end
            -- Group indicator
            if contextual.GroupIndicator then contextual.GroupIndicator:SetAlpha(0) end
            -- Leader/Guide icons
            if contextual.LeaderIcon then contextual.LeaderIcon:SetAlpha(0) end
            if contextual.GuideIcon then contextual.GuideIcon:SetAlpha(0) end
            if contextual.RoleIcon then contextual.RoleIcon:SetAlpha(0) end
        end
        
        -- Status texture (resting flash on portrait area)
        if main and main.StatusTexture then
            main.StatusTexture:SetAlpha(0)
        end
        
        -- Hide the bar masks (these create curved edges)
        if main then
            local healthContainer = main.HealthBarsContainer
            if healthContainer and healthContainer.HealthBarMask then
                healthContainer.HealthBarMask:Hide()
            end
            if main.ManaBar and main.ManaBar.ManaBarMask then
                main.ManaBar.ManaBarMask:Hide()
            end
        end
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFlatTexture(healthContainer.HealthBar)
        end
        if main.ManaBar then
            ApplyFlatTexture(main.ManaBar)
        end
    end
    
    -- Resize bars
    if main and p.ufHealthHeight then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            healthContainer:SetHeight(p.ufHealthHeight)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetHeight(p.ufHealthHeight)
            end
        end
    end
    
    if main and main.ManaBar and p.ufManaHeight then
        main.ManaBar:SetHeight(p.ufManaHeight)
    end
end

-- Style the Target Frame
-- Exact paths from Blizzard's TargetFrame.xml (TargetFrameTemplate)
function UnitFrames:StyleTargetFrame()
    if not TargetFrame then return end
    
    local p = self.db.profile
    local container = TargetFrame.TargetFrameContainer
    local content = TargetFrame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    local contextual = content and content.TargetFrameContentContextual
    
    -- Hide portrait
    if p.ufHidePortraits then
        if container and container.Portrait then
            container.Portrait:SetAlpha(0)
        end
        if container and container.PortraitMask then
            container.PortraitMask:Hide()
        end
    end
    
    -- Hide borders/frame textures
    if p.ufHideBorders then
        if container then
            if container.FrameTexture then container.FrameTexture:SetAlpha(0) end
            if container.Flash then container.Flash:SetAlpha(0) end
            if container.BossPortraitFrameTexture then container.BossPortraitFrameTexture:SetAlpha(0) end
        end
        
        -- Contextual elements
        if contextual then
            if contextual.HighLevelTexture then contextual.HighLevelTexture:SetAlpha(0) end
            if contextual.PetBattleIcon then contextual.PetBattleIcon:SetAlpha(0) end
            if contextual.PvpIcon then contextual.PvpIcon:SetAlpha(0) end
            if contextual.PrestigePortrait then contextual.PrestigePortrait:SetAlpha(0) end
            if contextual.PrestigeBadge then contextual.PrestigeBadge:SetAlpha(0) end
            if contextual.NumericalThreat then contextual.NumericalThreat:SetAlpha(0) end
            if contextual.QuestIcon then contextual.QuestIcon:SetAlpha(0) end
            if contextual.RaidTargetIcon then contextual.RaidTargetIcon:SetAlpha(0) end
        end
        
        -- Hide the bar masks
        if main then
            local healthContainer = main.HealthBarsContainer
            if healthContainer and healthContainer.HealthBarMask then
                healthContainer.HealthBarMask:Hide()
            end
            if main.ManaBar and main.ManaBar.ManaBarMask then
                main.ManaBar.ManaBarMask:Hide()
            end
        end
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFlatTexture(healthContainer.HealthBar)
        end
        if main.ManaBar then
            ApplyFlatTexture(main.ManaBar)
        end
    end
    
    -- Resize bars
    if main and p.ufHealthHeight then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            healthContainer:SetHeight(p.ufHealthHeight)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetHeight(p.ufHealthHeight)
            end
        end
    end
    
    if main and main.ManaBar and p.ufManaHeight then
        main.ManaBar:SetHeight(p.ufManaHeight)
    end
end

-- Style the Focus Frame (uses same structure as TargetFrameTemplate)
function UnitFrames:StyleFocusFrame()
    if not FocusFrame then return end
    
    local p = self.db.profile
    local container = FocusFrame.TargetFrameContainer
    local content = FocusFrame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    local contextual = content and content.TargetFrameContentContextual
    
    -- Hide portrait
    if p.ufHidePortraits then
        if container and container.Portrait then
            container.Portrait:SetAlpha(0)
        end
        if container and container.PortraitMask then
            container.PortraitMask:Hide()
        end
    end
    
    -- Hide borders/frame textures
    if p.ufHideBorders then
        if container then
            if container.FrameTexture then container.FrameTexture:SetAlpha(0) end
            if container.Flash then container.Flash:SetAlpha(0) end
            if container.BossPortraitFrameTexture then container.BossPortraitFrameTexture:SetAlpha(0) end
        end
        
        -- Contextual elements
        if contextual then
            if contextual.HighLevelTexture then contextual.HighLevelTexture:SetAlpha(0) end
            if contextual.PetBattleIcon then contextual.PetBattleIcon:SetAlpha(0) end
            if contextual.PvpIcon then contextual.PvpIcon:SetAlpha(0) end
            if contextual.PrestigePortrait then contextual.PrestigePortrait:SetAlpha(0) end
            if contextual.PrestigeBadge then contextual.PrestigeBadge:SetAlpha(0) end
            if contextual.NumericalThreat then contextual.NumericalThreat:SetAlpha(0) end
            if contextual.QuestIcon then contextual.QuestIcon:SetAlpha(0) end
            if contextual.RaidTargetIcon then contextual.RaidTargetIcon:SetAlpha(0) end
        end
        
        -- Hide the bar masks
        if main then
            local healthContainer = main.HealthBarsContainer
            if healthContainer and healthContainer.HealthBarMask then
                healthContainer.HealthBarMask:Hide()
            end
            if main.ManaBar and main.ManaBar.ManaBarMask then
                main.ManaBar.ManaBarMask:Hide()
            end
        end
    end
    
    -- Apply flat bar texture
    if p.ufFlatBars and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFlatTexture(healthContainer.HealthBar)
        end
        if main.ManaBar then
            ApplyFlatTexture(main.ManaBar)
        end
    end
    
    -- Resize bars
    if main and p.ufHealthHeight then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            healthContainer:SetHeight(p.ufHealthHeight)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetHeight(p.ufHealthHeight)
            end
        end
    end
    
    if main and main.ManaBar and p.ufManaHeight then
        main.ManaBar:SetHeight(p.ufManaHeight)
    end
end

-- Debug function to print frame structure
function UnitFrames:DebugPlayerFrame()
    if not PlayerFrame then
        print("PlayerFrame not found")
        return
    end
    
    print("=== PlayerFrame Debug ===")
    print("PlayerFrameContainer:", PlayerFrame.PlayerFrameContainer and "YES" or "NO")
    
    if PlayerFrame.PlayerFrameContainer then
        local c = PlayerFrame.PlayerFrameContainer
        print("  .PlayerPortrait:", c.PlayerPortrait and "YES" or "NO")
        print("  .PlayerPortraitMask:", c.PlayerPortraitMask and "YES" or "NO")
        print("  .FrameTexture:", c.FrameTexture and "YES" or "NO")
    end
    
    print("PlayerFrameContent:", PlayerFrame.PlayerFrameContent and "YES" or "NO")
    
    if PlayerFrame.PlayerFrameContent then
        local content = PlayerFrame.PlayerFrameContent
        print("  .PlayerFrameContentMain:", content.PlayerFrameContentMain and "YES" or "NO")
        print("  .PlayerFrameContentContextual:", content.PlayerFrameContentContextual and "YES" or "NO")
        
        if content.PlayerFrameContentContextual then
            local ctx = content.PlayerFrameContentContextual
            print("    .PlayerPortraitCornerIcon:", ctx.PlayerPortraitCornerIcon and "YES" or "NO")
            print("    .AttackIcon:", ctx.AttackIcon and "YES" or "NO")
            print("    .PlayerRestLoop:", ctx.PlayerRestLoop and "YES" or "NO")
        end
        
        if content.PlayerFrameContentMain then
            local main = content.PlayerFrameContentMain
            print("    .HealthBarsContainer:", main.HealthBarsContainer and "YES" or "NO")
            print("    .StatusTexture:", main.StatusTexture and "YES" or "NO")
            
            if main.HealthBarsContainer then
                local hc = main.HealthBarsContainer
                print("      .HealthBar:", hc.HealthBar and "YES" or "NO")
                print("      .HealthBarMask:", hc.HealthBarMask and "YES" or "NO")
            end
            
            print("    .ManaBar:", main.ManaBar and "YES" or "NO")
            if main.ManaBar then
                print("      .ManaBarMask:", main.ManaBar.ManaBarMask and "YES" or "NO")
            end
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

-- Slash command for debugging
SLASH_AHUF1 = "/ahuf"
SlashCmdList["AHUF"] = function(msg)
    if msg == "debug" then
        UnitFrames:DebugPlayerFrame()
    elseif msg == "style" then
        UnitFrames:RefreshAllFrames()
        print("ActionHud UnitFrames: Refreshed all frames")
    else
        print("ActionHud UnitFrames commands:")
        print("  /ahuf debug - Print frame structure")
        print("  /ahuf style - Force refresh styling")
    end
end
