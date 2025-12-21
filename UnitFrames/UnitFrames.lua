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

-- Apply flat texture to a status bar and force color update
local function ApplyFlatTexture(bar, unit, barType)
    if not bar then return end
    bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
    
    -- Force color based on bar type
    if barType == "health" then
        -- For health bars, use class color or green
        if unit and UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            if class then
                local color = RAID_CLASS_COLORS[class]
                if color then
                    bar:SetStatusBarColor(color.r, color.g, color.b)
                    return
                end
            end
        end
        -- Default green for health
        bar:SetStatusBarColor(0, 0.8, 0)
    elseif barType == "mana" then
        -- Get power type and color appropriately
        if unit then
            local powerType = UnitPowerType(unit)
            local color = PowerBarColor[powerType]
            if color then
                bar:SetStatusBarColor(color.r, color.g, color.b)
                return
            end
        end
        -- Default blue for mana
        bar:SetStatusBarColor(0, 0.5, 1)
    end
end

-- Aggressively hide a texture (try multiple methods)
local function HideTexture(texture)
    if not texture then return end
    texture:SetAlpha(0)
    texture:Hide()
    -- Also try clearing the texture
    if texture.SetTexture then
        texture:SetTexture(nil)
    end
    if texture.SetAtlas then
        texture:SetAtlas(nil)
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
            -- Main frame textures - use aggressive hiding
            HideTexture(container.FrameTexture)
            HideTexture(container.VehicleFrameTexture)
            HideTexture(container.AlternatePowerFrameTexture)
            HideTexture(container.FrameFlash)
        end
        
        -- Contextual elements (corner icon, rest indicator, etc.)
        if contextual then
            -- The yellow corner arrow/embellishment
            HideTexture(contextual.PlayerPortraitCornerIcon)
            -- Combat sword icon
            HideTexture(contextual.AttackIcon)
            -- Zzz rest animation
            if contextual.PlayerRestLoop then contextual.PlayerRestLoop:Hide() end
            -- PVP icons
            HideTexture(contextual.PVPIcon)
            HideTexture(contextual.PrestigePortrait)
            HideTexture(contextual.PrestigeBadge)
            -- Group indicator
            if contextual.GroupIndicator then contextual.GroupIndicator:Hide() end
            -- Leader/Guide icons
            HideTexture(contextual.LeaderIcon)
            HideTexture(contextual.GuideIcon)
            HideTexture(contextual.RoleIcon)
        end
        
        -- Status texture (resting flash on portrait area)
        if main and main.StatusTexture then
            HideTexture(main.StatusTexture)
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
    
    -- Apply flat bar texture with proper colors
    if p.ufFlatBars and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFlatTexture(healthContainer.HealthBar, "player", "health")
        end
        if main.ManaBar then
            ApplyFlatTexture(main.ManaBar, "player", "mana")
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
            HideTexture(container.FrameTexture)
            HideTexture(container.Flash)
            HideTexture(container.BossPortraitFrameTexture)
        end
        
        -- Contextual elements
        if contextual then
            HideTexture(contextual.HighLevelTexture)
            HideTexture(contextual.PetBattleIcon)
            HideTexture(contextual.PvpIcon)
            HideTexture(contextual.PrestigePortrait)
            HideTexture(contextual.PrestigeBadge)
            if contextual.NumericalThreat then contextual.NumericalThreat:Hide() end
            HideTexture(contextual.QuestIcon)
            HideTexture(contextual.RaidTargetIcon)
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
    
    -- Apply flat bar texture with proper colors
    if p.ufFlatBars and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFlatTexture(healthContainer.HealthBar, "target", "health")
        end
        if main.ManaBar then
            ApplyFlatTexture(main.ManaBar, "target", "mana")
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
            HideTexture(container.FrameTexture)
            HideTexture(container.Flash)
            HideTexture(container.BossPortraitFrameTexture)
        end
        
        -- Contextual elements
        if contextual then
            HideTexture(contextual.HighLevelTexture)
            HideTexture(contextual.PetBattleIcon)
            HideTexture(contextual.PvpIcon)
            HideTexture(contextual.PrestigePortrait)
            HideTexture(contextual.PrestigeBadge)
            if contextual.NumericalThreat then contextual.NumericalThreat:Hide() end
            HideTexture(contextual.QuestIcon)
            HideTexture(contextual.RaidTargetIcon)
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
    
    -- Apply flat bar texture with proper colors
    if p.ufFlatBars and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFlatTexture(healthContainer.HealthBar, "focus", "health")
        end
        if main.ManaBar then
            ApplyFlatTexture(main.ManaBar, "focus", "mana")
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
