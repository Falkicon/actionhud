local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local UnitFrames = addon:NewModule("UnitFrames", "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- Style-only approach: We hook into Blizzard's unit frames (PlayerFrame, TargetFrame, FocusFrame)
-- and apply custom styling. This is Midnight-safe as we only modify visual properties.

local isStylingActive = false
local hooksInstalled = false

-- Flat bar texture (solid color, no gradient)
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Forward declaration for local functions
local ApplyFlatTexture

-- Apply flat texture to a status bar and force color update
ApplyFlatTexture = function(bar, unit, barType)
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
    if texture.SetTexture then
        texture:SetTexture(nil)
    end
    if texture.SetAtlas then
        texture:SetAtlas(nil)
    end
end

-- Apply font to a status bar's text elements
local function ApplyFontToBar(bar, fontPath, fontSize, alwaysShow)
    if not bar then return end
    
    -- Common text elements on status bars
    local textElements = {
        bar.TextString,      -- Main text
        bar.LeftText,        -- Left-aligned text
        bar.RightText,       -- Right-aligned text
        bar.ManaBarText,     -- Mana bar specific
        bar.HealthBarText,   -- Health bar specific
    }
    
    for _, textEl in ipairs(textElements) do
        if textEl and textEl.SetFont then
            textEl:SetFont(fontPath, fontSize, "OUTLINE")
            
            -- Force text visibility if always show is enabled
            if alwaysShow then
                textEl:Show()
            end
        end
    end
    
    -- Force the main text visible if alwaysShow is enabled
    if alwaysShow and bar.TextString then
        bar.TextString:Show()
        -- Override Blizzard's visibility control
        bar.lockShow = 1
    end
end

-- Force text visibility on a status bar (called on updates)
local function ForceTextVisibility(bar)
    if not bar then return end
    if bar.TextString then
        bar.TextString:Show()
    end
end

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
    
    -- Power bar updates - Blizzard resets texture on power changes
    self:RegisterEvent("UNIT_DISPLAYPOWER", function(event, unit)
        if unit == "player" and isStylingActive and self.db.profile.ufStylePlayer then
            C_Timer.After(0.1, function() self:StylePlayerFrame() end)
        elseif unit == "target" and isStylingActive and self.db.profile.ufStyleTarget then
            C_Timer.After(0.1, function() self:StyleTargetFrame() end)
        elseif unit == "focus" and isStylingActive and self.db.profile.ufStyleFocus then
            C_Timer.After(0.1, function() self:StyleFocusFrame() end)
        end
    end)
    
    -- Power value updates - re-apply flat texture periodically since Blizzard may reset it
    self:RegisterEvent("UNIT_POWER_FREQUENT", function(event, unit)
        if unit == "player" and isStylingActive and self.db.profile.ufStylePlayer and self.db.profile.ufFlatBars then
            -- Throttle: only apply every ~0.5 seconds
            local now = GetTime()
            if not self.lastPowerStyle or (now - self.lastPowerStyle) > 0.5 then
                self.lastPowerStyle = now
                self:ApplyPlayerPowerBarFlat()
            end
        end
    end)
    
    hooksInstalled = true
    addon:Log("UnitFrames: Hooks installed", "discovery")
    return true
end

-- Create or get background frame for a unit frame
local backgrounds = {}
local function GetOrCreateBackground(parentFrame, name)
    if backgrounds[name] then return backgrounds[name] end
    
    local bg = CreateFrame("Frame", "ActionHudUF_BG_" .. name, parentFrame, "BackdropTemplate")
    bg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,  -- No border, cleaner look
        edgeSize = 0,
    })
    bg:SetBackdropColor(0, 0, 0, 0.75)
    bg:SetFrameStrata("BACKGROUND")
    backgrounds[name] = bg
    return bg
end

-- Apply flat texture to player power bar only (for throttled updates)
function UnitFrames:ApplyPlayerPowerBarFlat()
    local main = PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
    local manaBar = main and main.ManaBarArea and main.ManaBarArea.ManaBar
    if manaBar then
        ApplyFlatTexture(manaBar, "player", "mana")
    end
end

-- Style the Player Frame
-- PlayerFrame structure:
--   Portrait: PlayerFrame.PlayerFrameContainer.PlayerPortrait
--   FrameTexture: PlayerFrame.PlayerFrameContainer.FrameTexture (includes portrait ring AND bar decorations)
--   HealthBar: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
--   ManaBar: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar (note: inside ManaBarArea!)
--   Contextual: PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual (Zzz, arrow, etc.)
function UnitFrames:StylePlayerFrame()
    if not PlayerFrame then return end
    
    local p = self.db.profile
    local container = PlayerFrame.PlayerFrameContainer
    local content = PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local contextual = content and content.PlayerFrameContentContextual
    
    -- Hide portrait AND associated elements (Zzz, arrow, corner icon)
    -- These are all visually part of the "portrait area"
    if p.ufHidePortraits then
        if container then
            if container.PlayerPortrait then container.PlayerPortrait:SetAlpha(0) end
            if container.PlayerPortraitMask then container.PlayerPortraitMask:Hide() end
        end
        
        -- Portrait-area contextual elements
        if contextual then
            -- The yellow corner arrow/embellishment
            HideTexture(contextual.PlayerPortraitCornerIcon)
            -- Combat sword icon (appears near portrait)
            HideTexture(contextual.AttackIcon)
            -- Zzz rest animation
            if contextual.PlayerRestLoop then contextual.PlayerRestLoop:Hide() end
            -- PVP icons (appear near portrait)
            HideTexture(contextual.PVPIcon)
            HideTexture(contextual.PrestigePortrait)
            HideTexture(contextual.PrestigeBadge)
        end
    end
    
    -- Hide borders/frame textures (the main frame decoration)
    if p.ufHideBorders then
        if container then
            -- Main frame textures - these include portrait ring AND bar decorations
            HideTexture(container.FrameTexture)
            HideTexture(container.VehicleFrameTexture)
            HideTexture(container.AlternatePowerFrameTexture)
            HideTexture(container.FrameFlash)
        end
        
        -- Group/leader indicators (part of frame decoration)
        if contextual then
            if contextual.GroupIndicator then contextual.GroupIndicator:Hide() end
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
            -- ManaBar is inside ManaBarArea for PlayerFrame
            local manaBarArea = main.ManaBarArea
            if manaBarArea and manaBarArea.ManaBar and manaBarArea.ManaBar.ManaBarMask then
                manaBarArea.ManaBar.ManaBarMask:Hide()
            end
        end
    end
    
    -- Get the mana bar (PlayerFrame has it inside ManaBarArea)
    local manaBar = main and main.ManaBarArea and main.ManaBarArea.ManaBar
    
    -- Apply flat bar texture with proper colors
    if p.ufFlatBars and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFlatTexture(healthContainer.HealthBar, "player", "health")
        end
        if manaBar then
            ApplyFlatTexture(manaBar, "player", "mana")
        end
    end
    
    -- Resize health bar (skip during combat to avoid taint)
    if main and p.ufHealthHeight and not InCombatLockdown() then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            healthContainer:SetHeight(p.ufHealthHeight)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetHeight(p.ufHealthHeight)
            end
        end
    end
    
    -- Resize mana bar (skip during combat)
    if manaBar and p.ufManaHeight and not InCombatLockdown() then
        manaBar:SetHeight(p.ufManaHeight)
    end
    
    -- Apply bar width scale (skip during combat)
    if p.ufBarScale and p.ufBarScale ~= 1.0 and main and not InCombatLockdown() then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            local defaultWidth = 124  -- Default from XML
            healthContainer:SetWidth(defaultWidth * p.ufBarScale)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetWidth(defaultWidth * p.ufBarScale)
            end
        end
        if manaBar then
            local defaultManaWidth = 124  -- Default from XML
            manaBar:SetWidth(defaultManaWidth * p.ufBarScale)
        end
    end
    
    -- Add background behind bars
    if p.ufShowBackground and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            local bg = GetOrCreateBackground(PlayerFrame, "Player")
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", -3, 3)
            if manaBar and manaBar:IsShown() then
                bg:SetPoint("BOTTOMRIGHT", manaBar, "BOTTOMRIGHT", 3, -3)
            else
                bg:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", 3, -3)
            end
            bg:Show()
        end
    elseif backgrounds["Player"] then
        backgrounds["Player"]:Hide()
    end
    
    -- Apply font styling
    if p.ufFontName and main then
        local fontPath = LSM:Fetch("font", p.ufFontName) or "Fonts\\FRIZQT__.TTF"
        local fontSize = p.ufFontSize or 10
        local alwaysShow = p.ufAlwaysShowText
        
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFontToBar(healthContainer.HealthBar, fontPath, fontSize, alwaysShow)
        end
        if manaBar then
            ApplyFontToBar(manaBar, fontPath, fontSize, alwaysShow)
        end
    end
end

-- Style the Target Frame
-- TargetFrame structure:
--   Portrait: TargetFrame.TargetFrameContainer.Portrait
--   FrameTexture: TargetFrame.TargetFrameContainer.FrameTexture
--   HealthBar: TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
--   ManaBar: TargetFrame.TargetFrameContent.TargetFrameContentMain.ManaBar (directly under main, no ManaBarArea!)
function UnitFrames:StyleTargetFrame()
    if not TargetFrame then return end
    
    local p = self.db.profile
    local container = TargetFrame.TargetFrameContainer
    local content = TargetFrame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    local contextual = content and content.TargetFrameContentContextual
    
    -- Hide portrait
    if p.ufHidePortraits then
        if container then
            if container.Portrait then container.Portrait:SetAlpha(0) end
            if container.PortraitMask then container.PortraitMask:Hide() end
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
    
    -- Resize health bar (skip during combat to avoid taint)
    if main and p.ufHealthHeight and not InCombatLockdown() then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            healthContainer:SetHeight(p.ufHealthHeight)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetHeight(p.ufHealthHeight)
            end
        end
    end
    
    -- Resize mana bar (skip during combat)
    if main and main.ManaBar and p.ufManaHeight and not InCombatLockdown() then
        main.ManaBar:SetHeight(p.ufManaHeight)
    end
    
    -- Apply bar width scale (skip during combat)
    if p.ufBarScale and p.ufBarScale ~= 1.0 and main and not InCombatLockdown() then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            local defaultWidth = 126  -- Default from XML
            healthContainer:SetWidth(defaultWidth * p.ufBarScale)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetWidth(defaultWidth * p.ufBarScale)
            end
        end
        if main.ManaBar then
            local defaultManaWidth = 134  -- Default from XML
            main.ManaBar:SetWidth(defaultManaWidth * p.ufBarScale)
        end
    end
    
    -- Add background behind bars
    if p.ufShowBackground and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            local bg = GetOrCreateBackground(TargetFrame, "Target")
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", -3, 3)
            if main.ManaBar and main.ManaBar:IsShown() then
                bg:SetPoint("BOTTOMRIGHT", main.ManaBar, "BOTTOMRIGHT", 3, -3)
            else
                bg:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", 3, -3)
            end
            bg:Show()
        end
    elseif backgrounds["Target"] then
        backgrounds["Target"]:Hide()
    end
    
    -- Apply font styling
    if p.ufFontName and main then
        local fontPath = LSM:Fetch("font", p.ufFontName) or "Fonts\\FRIZQT__.TTF"
        local fontSize = p.ufFontSize or 10
        local alwaysShow = p.ufAlwaysShowText
        
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFontToBar(healthContainer.HealthBar, fontPath, fontSize, alwaysShow)
        end
        if main.ManaBar then
            ApplyFontToBar(main.ManaBar, fontPath, fontSize, alwaysShow)
        end
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
        if container then
            if container.Portrait then container.Portrait:SetAlpha(0) end
            if container.PortraitMask then container.PortraitMask:Hide() end
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
    
    -- Resize health bar (skip during combat to avoid taint)
    if main and p.ufHealthHeight and not InCombatLockdown() then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            healthContainer:SetHeight(p.ufHealthHeight)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetHeight(p.ufHealthHeight)
            end
        end
    end
    
    -- Resize mana bar (skip during combat)
    if main and main.ManaBar and p.ufManaHeight and not InCombatLockdown() then
        main.ManaBar:SetHeight(p.ufManaHeight)
    end
    
    -- Apply bar width scale (skip during combat)
    if p.ufBarScale and p.ufBarScale ~= 1.0 and main and not InCombatLockdown() then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            local defaultWidth = 126
            healthContainer:SetWidth(defaultWidth * p.ufBarScale)
            if healthContainer.HealthBar then
                healthContainer.HealthBar:SetWidth(defaultWidth * p.ufBarScale)
            end
        end
        if main.ManaBar then
            local defaultManaWidth = 134
            main.ManaBar:SetWidth(defaultManaWidth * p.ufBarScale)
        end
    end
    
    -- Add background behind bars
    if p.ufShowBackground and main then
        local healthContainer = main.HealthBarsContainer
        if healthContainer then
            local bg = GetOrCreateBackground(FocusFrame, "Focus")
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", -3, 3)
            if main.ManaBar and main.ManaBar:IsShown() then
                bg:SetPoint("BOTTOMRIGHT", main.ManaBar, "BOTTOMRIGHT", 3, -3)
            else
                bg:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", 3, -3)
            end
            bg:Show()
        end
    elseif backgrounds["Focus"] then
        backgrounds["Focus"]:Hide()
    end
    
    -- Apply font styling
    if p.ufFontName and main then
        local fontPath = LSM:Fetch("font", p.ufFontName) or "Fonts\\FRIZQT__.TTF"
        local fontSize = p.ufFontSize or 10
        local alwaysShow = p.ufAlwaysShowText
        
        local healthContainer = main.HealthBarsContainer
        if healthContainer and healthContainer.HealthBar then
            ApplyFontToBar(healthContainer.HealthBar, fontPath, fontSize, alwaysShow)
        end
        if main.ManaBar then
            ApplyFontToBar(main.ManaBar, fontPath, fontSize, alwaysShow)
        end
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
            print("    .ManaBarArea:", main.ManaBarArea and "YES" or "NO")
            
            if main.HealthBarsContainer then
                local hc = main.HealthBarsContainer
                print("      .HealthBar:", hc.HealthBar and "YES" or "NO")
                print("      .HealthBarMask:", hc.HealthBarMask and "YES" or "NO")
            end
            
            if main.ManaBarArea then
                print("      .ManaBarArea.ManaBar:", main.ManaBarArea.ManaBar and "YES" or "NO")
            end
            
            -- Also check direct ManaBar path
            print("    .ManaBar (direct):", main.ManaBar and "YES" or "NO")
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
