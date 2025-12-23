local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local UnitFrames = addon:NewModule("UnitFrames", "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's unit frames (PlayerFrame, TargetFrame, FocusFrame)
-- and apply custom styling. This is Midnight-safe as we only modify visual properties.

local isStylingActive = false
local hooksInstalled = false

-- Track one-time anchor setup per frame (to avoid taint from repeated calls)
local anchorsApplied = {}

-- Flat bar texture (solid color, no gradient)
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Forward declaration for local functions
local ApplyFlatTexture

-- Color multiplier to match Resources module (less saturated)
local COLOR_MULT = 0.85

-- Apply font to a status bar's text elements (font face and size only)
-- Note: "Always show text" feature is shelved due to Midnight secret value limitations.
-- Text visibility defaults to Blizzard's hover behavior.
local function ApplyFontToBar(bar, fontPath, fontSize)
	if not bar then
		return
	end

	-- Common text elements on status bars
	local textElements = {
		bar.TextString, -- Main text
		bar.LeftText, -- Left-aligned text
		bar.RightText, -- Right-aligned text
		bar.ManaBarText, -- Mana bar specific
		bar.HealthBarText, -- Health bar specific
	}

	for _, textEl in ipairs(textElements) do
		if textEl and textEl.SetFont then
			textEl:SetFont(fontPath, fontSize, "OUTLINE")
		end
	end
end

-- Style heal/absorb bars to match flat look
local function StylePredictionBar(bar)
	if not bar then
		return
	end
	bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	-- Prediction bars usually have their own color/alpha logic from Blizzard
end

-- Apply flat texture to a status bar and force color update
ApplyFlatTexture = function(bar, unit, barType)
	if not bar then
		return
	end

	bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)

	-- Force color based on bar type
	local r, g, b = Utils.GetUnitColor(unit, barType:upper(), COLOR_MULT)
	bar:SetStatusBarColor(r, g, b)

	-- Style children bars (absorbs/prediction)
	local container = bar:GetParent()
	if container and container.IsObjectType and container:IsObjectType("Frame") then
		StylePredictionBar(container.MyHealPredictionBar)
		StylePredictionBar(container.OtherHealPredictionBar)
		StylePredictionBar(container.HealAbsorbBar)
		StylePredictionBar(container.TotalAbsorbBar)
	end

	-- Hide power bar animations (FullPowerFrame = gate animation, Spark = moving glow)
	if bar.FullPowerFrame then
		bar.FullPowerFrame:Hide()
	end
	if bar.Spark then
		bar.Spark:Hide()
	end
	if bar.FeedbackFrame then
		bar.FeedbackFrame:Hide()
	end
end

-- Apply font to a FontString element
local function ApplyFontToText(fontString, fontPath, fontSize, outline, justifyH)
	if fontString and fontString.SetFont then
		fontString:SetFont(fontPath, fontSize, outline or "OUTLINE")
		if justifyH then
			fontString:SetJustifyH(justifyH)
		end
	end
end

-- Normalized dimensions for all frames
local NORMALIZED_BAR_WIDTH = 126
local NORMALIZED_HEALTH_HEIGHT = 20 -- Default health bar height
local NORMALIZED_MANA_HEIGHT = 10 -- Default mana/power bar height
local BG_PADDING = 1 -- Background padding around bars (thinner = tighter)

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
	if hooksInstalled then
		return true
	end

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

	if PlayerFrame_UpdateStatus then
		hooksecurefunc("PlayerFrame_UpdateStatus", function()
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
			C_Timer.After(0.1, function()
				self:StyleTargetFrame()
			end)
		end
	end)

	self:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
		if isStylingActive and self.db.profile.ufStyleFocus then
			C_Timer.After(0.1, function()
				self:StyleFocusFrame()
			end)
		end
	end)

	-- Power bar updates - Blizzard resets texture on power changes
	self:RegisterEvent("UNIT_DISPLAYPOWER", function(event, unit)
		if unit == "player" and isStylingActive and self.db.profile.ufStylePlayer then
			C_Timer.After(0.1, function()
				self:StylePlayerFrame()
			end)
		elseif unit == "target" and isStylingActive and self.db.profile.ufStyleTarget then
			C_Timer.After(0.1, function()
				self:StyleTargetFrame()
			end)
		elseif unit == "focus" and isStylingActive and self.db.profile.ufStyleFocus then
			C_Timer.After(0.1, function()
				self:StyleFocusFrame()
			end)
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
-- Standardize bar layout, anchoring, and growth direction
local function EnsureBarLayout(main, frameKey, p)
	if not main or InCombatLockdown() then
		return
	end

	local healthContainer = main.HealthBarsContainer
	local manaBar = (frameKey == "Player") and (main.ManaBarArea and main.ManaBarArea.ManaBar) or main.ManaBar

	if not healthContainer then
		return
	end

	local scaledWidth = NORMALIZED_BAR_WIDTH * (p.ufBarScale or 1.0)
	local healthHeight = p.ufHealthHeight or NORMALIZED_HEALTH_HEIGHT
	local manaHeight = p.ufManaHeight or NORMALIZED_MANA_HEIGHT

	-- Normalize HealthBarsContainer: Ensure it grows downwards
	if not anchorsApplied[frameKey .. "HealthContainer"] then
		-- For Target and Focus, the default anchor is BOTTOMRIGHT, which makes it grow UP.
		-- We want to switch it to TOPLEFT so it grows DOWN.
		if frameKey == "Target" or frameKey == "Focus" then
			local left = healthContainer:GetLeft()
			local top = healthContainer:GetTop()
			if left and top then
				-- Calculate position relative to parent's BOTTOMLEFT
				local pLeft, pBottom = healthContainer:GetParent():GetRect()
				if pLeft and pBottom then
					healthContainer:ClearAllPoints()
					healthContainer:SetPoint(
						"TOPLEFT",
						healthContainer:GetParent(),
						"BOTTOMLEFT",
						left - pLeft,
						top - pBottom
					)
					anchorsApplied[frameKey .. "HealthContainer"] = true
				end
			end
		else
			-- Player frame is already TOPLEFT by default
			anchorsApplied[frameKey .. "HealthContainer"] = true
		end
	end

	-- Sizing
	healthContainer:SetWidth(scaledWidth)
	healthContainer:SetHeight(healthHeight)

	if healthContainer.HealthBar then
		healthContainer.HealthBar:SetWidth(scaledWidth)
		healthContainer.HealthBar:SetHeight(healthHeight)

		-- Force HealthBar to fill the container exactly (one-time)
		if not anchorsApplied[frameKey .. "HealthBarInternal"] then
			healthContainer.HealthBar:ClearAllPoints()
			healthContainer.HealthBar:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", 0, 0)
			healthContainer.HealthBar:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", 0, 0)
			anchorsApplied[frameKey .. "HealthBarInternal"] = true
		end

		-- Position the HealthBar text strings (Health/Percentage)
		-- In Screenshot 2, they are centered at the bottom of the bar
		if not anchorsApplied[frameKey .. "HealthText"] then
			local hb = healthContainer.HealthBar
			local texts = { hb.TextString, hb.LeftText, hb.RightText }
			for _, txt in ipairs(texts) do
				if txt then
					txt:ClearAllPoints()
					-- Center at the bottom of the health bar
					txt:SetPoint("BOTTOM", hb, "BOTTOM", 0, 2)
				end
			end
			anchorsApplied[frameKey .. "HealthText"] = true
		end
	end

	-- Mana/Power bar layout
	if manaBar then
		manaBar:SetWidth(scaledWidth)
		manaBar:SetHeight(manaHeight)

		-- One-time anchor fix: Align to bottom of health container with 1px gap
		if not anchorsApplied[frameKey .. "ManaBar"] then
			manaBar:ClearAllPoints()
			-- Anchor TOPLEFT to HealthContainer BOTTOMLEFT with 1px gap
			manaBar:SetPoint("TOPLEFT", healthContainer, "BOTTOMLEFT", 0, -1)
			-- Anchor BOTTOMRIGHT to ensure it fills width and has correct height
			manaBar:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", 0, -(1 + manaHeight))
			anchorsApplied[frameKey .. "ManaBar"] = true
		end

		-- Position ManaBar text centered
		if not anchorsApplied[frameKey .. "ManaText"] then
			local mTexts = { manaBar.TextString, manaBar.LeftText, manaBar.RightText, manaBar.ManaBarText }
			for _, txt in ipairs(mTexts) do
				if txt then
					txt:ClearAllPoints()
					txt:SetPoint("CENTER", manaBar, "CENTER", 0, 0)
				end
			end
			anchorsApplied[frameKey .. "ManaText"] = true
		end
	end

	-- Normalize Name and Level position
	-- Based on Screenshot 2:
	--   Level is TOPLEFT inside health bar
	--   Name is TOP center inside health bar
	if not anchorsApplied[frameKey .. "NameLevel"] then
		local name = main.Name or (frameKey == "Player" and _G.PlayerName)
		local level = main.LevelText or (frameKey == "Player" and _G.PlayerLevelText)

		if name then
			name:ClearAllPoints()
			-- Anchor to TOP of healthContainer
			name:SetPoint("TOP", healthContainer, "TOP", 0, -2)
			name:SetJustifyH("CENTER")
		end

		if level then
			level:ClearAllPoints()
			-- Anchor to TOPLEFT of healthContainer
			level:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", 4, -2)
			level:SetJustifyH("LEFT")
		end
		anchorsApplied[frameKey .. "NameLevel"] = true
	end
end

local function GetOrCreateBackground(parentFrame, name)
	if backgrounds[name] then
		return backgrounds[name]
	end

	local bg = CreateFrame("Frame", "ActionHudUF_BG_" .. name, parentFrame, "BackdropTemplate")
	bg:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = nil, -- No border, cleaner look
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
		ApplyFlatTexture(manaBar, "player", "power")
	end
end

-- Style the Player Frame
function UnitFrames:StylePlayerFrame()
	if not PlayerFrame or InCombatLockdown() then
		return
	end

	local p = self.db.profile
	local container = PlayerFrame.PlayerFrameContainer
	local content = PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local contextual = content and content.PlayerFrameContentContextual

	-- Hide portrait AND associated elements (Zzz, arrow, corner icon)
	-- These are all visually part of the "portrait area"
	if p.ufHidePortraits then
		if container then
			if container.PlayerPortrait then
				container.PlayerPortrait:SetAlpha(0)
			end
			if container.PlayerPortraitMask then
				container.PlayerPortraitMask:Hide()
			end
		end

		-- Portrait-area contextual elements
		if contextual then
			-- The yellow corner arrow/embellishment
			Utils.HideTexture(contextual.PlayerPortraitCornerIcon)
			-- Combat sword icon and Zzz rest animation are repositioned/replaced below
			-- PVP icons (appear near portrait)
			Utils.HideTexture(contextual.PVPIcon)
			Utils.HideTexture(contextual.PrestigePortrait)
			Utils.HideTexture(contextual.PrestigeBadge)
		end

		-- Hide the healing/damage text (HitIndicator)
		if main and main.HitIndicator then
			main.HitIndicator:Hide()
			main.HitIndicator:SetAlpha(0)
		end
	end

	-- Hide borders/frame textures (the main frame decoration)
	if p.ufHideBorders then
		if container then
			-- Main frame textures - these include portrait ring AND bar decorations
			Utils.HideTexture(container.FrameTexture)
			Utils.HideTexture(container.VehicleFrameTexture)
			Utils.HideTexture(container.AlternatePowerFrameTexture)
			Utils.HideTexture(container.FrameFlash)
		end

		-- Group/leader indicators (part of frame decoration)
		if contextual then
			if contextual.GroupIndicator then
				contextual.GroupIndicator:Hide()
			end
			Utils.HideTexture(contextual.LeaderIcon)
			Utils.HideTexture(contextual.GuideIcon)
			Utils.HideTexture(contextual.RoleIcon)
		end

		-- Status texture (resting flash on portrait area)
		if main and main.StatusTexture then
			Utils.HideTexture(main.StatusTexture)
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
			ApplyFlatTexture(manaBar, "player", "power")
		end
	end

	-- Standardize bar layout, anchoring, and growth direction
	EnsureBarLayout(main, "Player", p)

	-- Add background behind bars (tight padding)
	if p.ufShowBackground and main then
		local healthContainer = main.HealthBarsContainer
		local manaBar = main.ManaBarArea and main.ManaBarArea.ManaBar
		if healthContainer then
			local bg = GetOrCreateBackground(PlayerFrame, "Player")
			bg:ClearAllPoints()
			bg:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", -BG_PADDING, BG_PADDING)
			if manaBar and manaBar:IsShown() then
				bg:SetPoint("BOTTOMRIGHT", manaBar, "BOTTOMRIGHT", BG_PADDING, -BG_PADDING)
			else
				bg:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", BG_PADDING, -BG_PADDING)
			end
			bg:Show()
		end
	elseif backgrounds["Player"] then
		backgrounds["Player"]:Hide()
	end

	-- Apply font styling (text shows on hover by default - Midnight limitation)
	local fontPath = LSM:Fetch("font", p.ufFontName) or "Fonts\\FRIZQT__.TTF"
	local fontSize = p.ufFontSize or 10

	-- Bar text font
	if main then
		local healthContainer = main.HealthBarsContainer
		if healthContainer and healthContainer.HealthBar then
			ApplyFontToBar(healthContainer.HealthBar, fontPath, fontSize)
		end
		if manaBar then
			ApplyFontToBar(manaBar, fontPath, fontSize)
		end
	end

	-- Name and level text (global frame names for PlayerFrame)
	ApplyFontToText(PlayerName, fontPath, fontSize, "OUTLINE", "CENTER")
	ApplyFontToText(PlayerLevelText, fontPath, fontSize, "OUTLINE", "LEFT")

	-- Handle Resting and Combat Icons
	if contextual then
		-- Hide the modern animated Zzz
		if contextual.PlayerRestLoop then
			contextual.PlayerRestLoop:SetAlpha(0)
			contextual.PlayerRestLoop:Hide()
		end

		-- Create/Update old school resting icon
		if not contextual.OldRestingIcon then
			contextual.OldRestingIcon = contextual:CreateTexture(nil, "OVERLAY")
			contextual.OldRestingIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
			contextual.OldRestingIcon:SetTexCoord(0, 0.5, 0, 0.421875)
			contextual.OldRestingIcon:SetSize(22, 22)
		end

		local healthContainer = main and main.HealthBarsContainer
		if healthContainer then
			contextual.OldRestingIcon:ClearAllPoints()
			-- Position in the top right corner of the plate (health bar)
			contextual.OldRestingIcon:SetPoint("CENTER", healthContainer, "TOPRIGHT", -2, -2)
		end

		if IsResting() then
			contextual.OldRestingIcon:Show()
		else
			contextual.OldRestingIcon:Hide()
		end

		-- Combat icon (Swords) - repositioning it as well to be consistent
		if contextual.AttackIcon then
			contextual.AttackIcon:ClearAllPoints()
			if healthContainer then
				contextual.AttackIcon:SetPoint("CENTER", healthContainer, "TOPRIGHT", -2, -2)
			else
				contextual.AttackIcon:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 0, 0)
			end
			contextual.AttackIcon:SetScale(0.6)
		end
	end
end

-- Style the Target Frame
function UnitFrames:StyleTargetFrame()
	if not TargetFrame or InCombatLockdown() then
		return
	end

	local p = self.db.profile
	local container = TargetFrame.TargetFrameContainer
	local content = TargetFrame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	local contextual = content and content.TargetFrameContentContextual

	-- Hide portrait
	if p.ufHidePortraits then
		if container then
			if container.Portrait then
				container.Portrait:SetAlpha(0)
			end
			if container.PortraitMask then
				container.PortraitMask:Hide()
			end
		end

		-- Hide the healing/damage text (HitIndicator)
		if main and main.HitIndicator then
			main.HitIndicator:Hide()
			main.HitIndicator:SetAlpha(0)
		end
	end

	-- Hide borders/frame textures
	if p.ufHideBorders then
		if container then
			Utils.HideTexture(container.FrameTexture)
			Utils.HideTexture(container.Flash)
			Utils.HideTexture(container.BossPortraitFrameTexture)
		end

		-- Contextual elements
		if contextual then
			Utils.HideTexture(contextual.HighLevelTexture)
			Utils.HideTexture(contextual.PetBattleIcon)
			Utils.HideTexture(contextual.PvpIcon)
			Utils.HideTexture(contextual.PrestigePortrait)
			Utils.HideTexture(contextual.PrestigeBadge)
			if contextual.NumericalThreat then
				contextual.NumericalThreat:Hide()
			end
			Utils.HideTexture(contextual.QuestIcon)
			Utils.HideTexture(contextual.RaidTargetIcon)
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

			-- Hide ReputationColor (the blue/green bar showing unit type)
			Utils.HideTexture(main.ReputationColor)
		end
	end

	-- Apply flat bar texture with proper colors
	if p.ufFlatBars and main then
		local healthContainer = main.HealthBarsContainer
		if healthContainer and healthContainer.HealthBar then
			ApplyFlatTexture(healthContainer.HealthBar, "target", "health")
		end
		if main.ManaBar then
			ApplyFlatTexture(main.ManaBar, "target", "power")
		end
	end

	-- Standardize bar layout, anchoring, and growth direction
	EnsureBarLayout(main, "Target", p)

	-- Add background behind bars (tight padding)
	if p.ufShowBackground and main then
		local healthContainer = main.HealthBarsContainer
		if healthContainer then
			local bg = GetOrCreateBackground(TargetFrame, "Target")
			bg:ClearAllPoints()
			bg:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", -BG_PADDING, BG_PADDING)
			if main.ManaBar and main.ManaBar:IsShown() then
				bg:SetPoint("BOTTOMRIGHT", main.ManaBar, "BOTTOMRIGHT", BG_PADDING, -BG_PADDING)
			else
				bg:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", BG_PADDING, -BG_PADDING)
			end
			bg:Show()
		end
	elseif backgrounds["Target"] then
		backgrounds["Target"]:Hide()
	end

	-- Apply font styling (text shows on hover by default - Midnight limitation)
	local fontPath = LSM:Fetch("font", p.ufFontName) or "Fonts\\FRIZQT__.TTF"
	local fontSize = p.ufFontSize or 10

	-- Bar text font
	if main then
		local healthContainer = main.HealthBarsContainer
		if healthContainer and healthContainer.HealthBar then
			ApplyFontToBar(healthContainer.HealthBar, fontPath, fontSize)
		end
		if main.ManaBar then
			ApplyFontToBar(main.ManaBar, fontPath, fontSize)
		end

		-- Name and level text
		ApplyFontToText(main.Name, fontPath, fontSize, "OUTLINE", "CENTER")
		ApplyFontToText(main.LevelText, fontPath, fontSize, "OUTLINE", "LEFT")
	end
end

-- Style the Focus Frame (uses same structure as TargetFrameTemplate)
function UnitFrames:StyleFocusFrame()
	if not FocusFrame or InCombatLockdown() then
		return
	end

	local p = self.db.profile
	local container = FocusFrame.TargetFrameContainer
	local content = FocusFrame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	local contextual = content and content.TargetFrameContentContextual

	-- Hide portrait
	if p.ufHidePortraits then
		if container then
			if container.Portrait then
				container.Portrait:SetAlpha(0)
			end
			if container.PortraitMask then
				container.PortraitMask:Hide()
			end
		end

		-- Hide the healing/damage text (HitIndicator)
		if main and main.HitIndicator then
			main.HitIndicator:Hide()
			main.HitIndicator:SetAlpha(0)
		end
	end

	-- Hide borders/frame textures
	if p.ufHideBorders then
		if container then
			Utils.HideTexture(container.FrameTexture)
			Utils.HideTexture(container.Flash)
			Utils.HideTexture(container.BossPortraitFrameTexture)
		end

		-- Contextual elements
		if contextual then
			Utils.HideTexture(contextual.HighLevelTexture)
			Utils.HideTexture(contextual.PetBattleIcon)
			Utils.HideTexture(contextual.PvpIcon)
			Utils.HideTexture(contextual.PrestigePortrait)
			Utils.HideTexture(contextual.PrestigeBadge)
			if contextual.NumericalThreat then
				contextual.NumericalThreat:Hide()
			end
			Utils.HideTexture(contextual.QuestIcon)
			Utils.HideTexture(contextual.RaidTargetIcon)
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

			-- Hide ReputationColor (the blue/green bar showing unit type)
			Utils.HideTexture(main.ReputationColor)
		end
	end

	-- Apply flat bar texture with proper colors
	if p.ufFlatBars and main then
		local healthContainer = main.HealthBarsContainer
		if healthContainer and healthContainer.HealthBar then
			ApplyFlatTexture(healthContainer.HealthBar, "focus", "health")
		end
		if main.ManaBar then
			ApplyFlatTexture(main.ManaBar, "focus", "power")
		end
	end

	-- Standardize bar layout, anchoring, and growth direction
	EnsureBarLayout(main, "Focus", p)

	-- Add background behind bars (tight padding)
	if p.ufShowBackground and main then
		local healthContainer = main.HealthBarsContainer
		if healthContainer then
			local bg = GetOrCreateBackground(FocusFrame, "Focus")
			bg:ClearAllPoints()
			bg:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", -BG_PADDING, BG_PADDING)
			if main.ManaBar and main.ManaBar:IsShown() then
				bg:SetPoint("BOTTOMRIGHT", main.ManaBar, "BOTTOMRIGHT", BG_PADDING, -BG_PADDING)
			else
				bg:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", BG_PADDING, -BG_PADDING)
			end
			bg:Show()
		end
	elseif backgrounds["Focus"] then
		backgrounds["Focus"]:Hide()
	end

	-- Apply font styling (text shows on hover by default - Midnight limitation)
	local fontPath = LSM:Fetch("font", p.ufFontName) or "Fonts\\FRIZQT__.TTF"
	local fontSize = p.ufFontSize or 10

	-- Bar text font
	if main then
		local healthContainer = main.HealthBarsContainer
		if healthContainer and healthContainer.HealthBar then
			ApplyFontToBar(healthContainer.HealthBar, fontPath, fontSize)
		end
		if main.ManaBar then
			ApplyFontToBar(main.ManaBar, fontPath, fontSize)
		end

		-- Name and level text (Focus uses same structure as Target)
		ApplyFontToText(main.Name, fontPath, fontSize, "OUTLINE", "CENTER")
		ApplyFontToText(main.LevelText, fontPath, fontSize, "OUTLINE", "LEFT")
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

	-- Reset anchor tracking so they can be reapplied
	-- ONLY do this outside combat to avoid taint from ClearAllPoints
	if not InCombatLockdown() then
		wipe(anchorsApplied)
	end

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
