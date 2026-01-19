-- UnitFrames.lua
-- Implements ActionHud's unit frames with Midnight compatibility

local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")
local Utils = ns.Utils

local UnitFrames = ActionHud:NewModule("UnitFrames", "AceEvent-3.0")

-- Constants
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
	insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- Helper to safely return a value or a default, avoiding boolean tests on secrets
local function Pass(v, default)
	if type(v) == "nil" then
		return default or 0
	end
	return v
end

-- Robust IsActive check that avoids crashing on secret values
local function IsActive(val)
	if type(val) == "nil" then
		return false
	end

	-- In Midnight, secrets have type "number" but crash on comparison.
	if Utils.IsValueSecret(val) then
		return true -- Assume active if secret
	end

	-- If it's a normal number, check if > 0
	if type(val) == "number" then
		return val > 0
	end

	-- Fallback for other types
	local ok, res = pcall(function()
		return val > 0
	end)
	if not ok then
		return true
	end
	return res
end

-- Format large numbers (1000 -> 1K) safely
local function FormatValue(val)
	if type(val) == "nil" then
		return "???"
	end

	-- If it's a number, we can use AbbreviateNumbers
	if type(val) == "number" then
		local ok, res = pcall(AbbreviateNumbers, val)
		return ok and res or tostring(val)
	end

	-- If it's a secret value, AbbreviateNumbers might crash.
	-- We return it as-is for %s formatting later.
	return val
end

-- Create a single status bar with overlays
local function CreateUnitBar(parent, name)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)

	-- Background for the bar
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

	-- Heal Prediction Overlay
	bar.predict = CreateFrame("StatusBar", nil, bar)
	bar.predict:SetAllPoints()
	bar.predict:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar.predict:SetStatusBarColor(0, 1, 0, 0.4)
	bar.predict:SetFrameLevel(bar:GetFrameLevel() + 1)

	-- Absorb Overlay
	bar.absorb = CreateFrame("StatusBar", nil, bar)
	bar.absorb:SetAllPoints()
	bar.absorb:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar.absorb:SetStatusBarColor(0, 0.8, 1, 0.6)
	bar.absorb:SetFrameLevel(bar:GetFrameLevel() + 2)
	if bar.absorb.SetReverseFill then
		bar.absorb:SetReverseFill(true)
	end

	return bar
end

-- Create a text element
local function CreateTextElement(parent, name)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	return { fontString = fs }
end

-- Create an icon element
local function CreateIcon(parent, name)
	-- Fix: drawLayer must be "OVERLAY", not "HIGH"
	local tex = parent:CreateTexture(nil, "OVERLAY")
	return tex
end

local function ApplyTextStyle(fontString, config, unit)
	if not fontString or not config then
		return
	end

	local fontPath = LSM:Fetch("font", config.font) or "Fonts\\FRIZQT__.TTF"
	local fontSize = config.size or 12  -- Default to 12 if nil
	fontString:SetFont(fontPath, fontSize, config.outline ~= "NONE" and config.outline or nil)

	local r, g, b = 1, 1, 1
	if config.colorMode == "custom" then
		r, g, b = config.color.r, config.color.g, config.color.b
	elseif config.colorMode == "class" then
		local _, class = UnitClass(unit)
		local classColor = RAID_CLASS_COLORS[class]
		if classColor then
			r, g, b = classColor.r, classColor.g, classColor.b
		end
	elseif config.colorMode == "reaction" then
		local rr, gg, bb = Utils.GetUnitColor(unit, "HEALTH")
		if rr then
			r, g, b = rr, gg, bb
		end
	end
	fontString:SetTextColor(r, g, b)
end

function UnitFrames:OnInitialize()
	self.db = ActionHud.db
	self.frames = {}
	self.healCalculator = Utils.CreateHealCalculator()
end

function UnitFrames:OnEnable()
	self:CreateFrames()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateAll")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "UpdateAll")
	self:RegisterEvent("UNIT_HEALTH", "UpdateFrameEvent")
	self:RegisterEvent("UNIT_MAXHEALTH", "UpdateFrameEvent")
	self:RegisterEvent("UNIT_POWER_UPDATE", "UpdateFrameEvent")
	self:RegisterEvent("UNIT_MAXPOWER", "UpdateFrameEvent")
	self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "UpdateFrameEvent")
	self:RegisterEvent("UNIT_HEAL_PREDICTION", "UpdateFrameEvent")
	self:UpdateAll()
end

function UnitFrames:CreateFrames()
	local units = {
		player = "player",
		target = "target",
		focus = "focus",
	}

	for frameId, unit in pairs(units) do
		local f = CreateFrame("Frame", "ActionHudUnitFrame_" .. frameId, UIParent, "BackdropTemplate")
		f.unit = unit
		f.unitId = frameId

		-- Background
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetAllPoints()

		-- Border (using Backdrop)
		f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
		f.border:SetAllPoints()

		-- Bars
		f.health = CreateUnitBar(f, "Health")
		f.health:SetClipsChildren(true)
		f.power = CreateUnitBar(f, "Power")
		f.class = CreateUnitBar(f, "Class")

		-- Health Text Elements
		f.healthElements = {
			level = CreateTextElement(f.health, "Level"),
			name = CreateTextElement(f.health, "Name"),
			value = CreateTextElement(f.health, "Value"),
			percent = CreateTextElement(f.health, "Percent"),
		}

		-- Power Text Elements
		f.powerElements = {
			value = CreateTextElement(f.power, "Value"),
			percent = CreateTextElement(f.power, "Percent"),
		}

		-- Icons
		f.icons = {
			combat = CreateIcon(f, "Combat"),
			resting = CreateIcon(f, "Resting"),
			pvp = CreateIcon(f, "PVP"),
			leader = CreateIcon(f, "Leader"),
			role = CreateIcon(f, "Role"),
			guide = CreateIcon(f, "Guide"),
			mainTank = CreateIcon(f, "MainTank"),
			mainAssist = CreateIcon(f, "MainAssist"),
			vehicle = CreateIcon(f, "Vehicle"),
			phased = CreateIcon(f, "Phased"),
			summon = CreateIcon(f, "Summon"),
			readyCheck = CreateIcon(f, "ReadyCheck"),
		}

		self.frames[frameId] = f
	end
	self:UpdateLayout()
end

function UnitFrames:UpdateLayout()
	if not self.db.profile.ufEnabled then
		for _, f in pairs(self.frames) do
			f:Hide()
		end
		return
	end

	for frameId, f in pairs(self.frames) do
		local db = self.db.profile.ufConfig[frameId]
		if not db then
			return
		end

		if not db.enabled then
			f:Hide()
		else
			f:Show()
			f:SetSize(db.width, db.height)
			f:ClearAllPoints()
			f:SetPoint("CENTER", UIParent, "CENTER", db.xOffset, db.yOffset)

			-- Visuals
			f.bg:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgOpacity)
			f.border:SetBackdrop({
				edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = db.borderSize,
			})
			f.border:SetBackdropBorderColor(db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderOpacity)
			-- Fix: border must be above bars
			f.border:SetFrameLevel(f:GetFrameLevel() + 10)

			-- Recalculate bar heights
			local hH = db.height
			local pH = db.powerBarEnabled and db.powerBarHeight or 0
			local cH = (frameId == "player" and db.classBarEnabled) and db.classBarHeight or 0

			local healthActualH = hH - pH - cH
			if healthActualH < 1 then
				healthActualH = 1
			end

			f.health:SetHeight(healthActualH)
			f.health:SetPoint("TOPLEFT", f, "TOPLEFT")
			f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT")

			f.power:SetHeight(pH)
			f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT")
			f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT")
			f.power:SetShown(pH > 0)

			f.class:SetHeight(cH)
			f.class:SetPoint("TOPLEFT", f.power, "BOTTOMLEFT")
			f.class:SetPoint("TOPRIGHT", f.power, "BOTTOMRIGHT")
			f.class:SetShown(cH > 0)

			-- Apply Typography
			local textGroups = {
				{ cat = "healthText", elements = f.healthElements, bar = f.health },
				{ cat = "powerText", elements = f.powerElements, bar = f.power },
			}

			for _, group in ipairs(textGroups) do
				local catDb = db[group.cat]
				for typeId, element in pairs(group.elements) do
					local config = catDb[typeId]
					if config then
						ApplyTextStyle(element.fontString, config, f.unit)
						-- Fix: SetShown based on enable setting
						element.fontString:SetShown(config.enabled)

						-- Position
						local pos = config.position
						local x, y = config.xOffset, config.yOffset
						local padH, padV = db.textPaddingH, db.textPaddingV

						element.fontString:ClearAllPoints()
						if pos == "TopLeft" then
							element.fontString:SetPoint("TOPLEFT", group.bar, "TOPLEFT", padH + x, -padV + y)
						elseif pos == "TopCenter" then
							element.fontString:SetPoint("TOP", group.bar, "TOP", x, -padV + y)
						elseif pos == "TopRight" then
							element.fontString:SetPoint("TOPRIGHT", group.bar, "TOPRIGHT", -padH + x, -padV + y)
						elseif pos == "Left" then
							element.fontString:SetPoint("LEFT", group.bar, "LEFT", padH + x, y)
						elseif pos == "Center" then
							element.fontString:SetPoint("CENTER", group.bar, "CENTER", x, y)
						elseif pos == "Right" then
							element.fontString:SetPoint("RIGHT", group.bar, "RIGHT", -padH + x, y)
						elseif pos == "BottomLeft" then
							element.fontString:SetPoint("BOTTOMLEFT", group.bar, "BOTTOMLEFT", padH + x, padV + y)
						elseif pos == "BottomCenter" then
							element.fontString:SetPoint("BOTTOM", group.bar, "BOTTOM", x, padV + y)
						elseif pos == "BottomRight" then
							element.fontString:SetPoint("BOTTOMRIGHT", group.bar, "BOTTOMRIGHT", -padH + x, padV + y)
						end
					end
				end
			end

			-- Force an immediate value update
			self:UpdateFrameValues(f)
		end
	end
end

function UnitFrames:UpdateAll()
	for _, f in pairs(self.frames) do
		self:UpdateFrameValues(f)
	end
end

function UnitFrames:UpdateFrameEvent(event, unit)
	for _, f in pairs(self.frames) do
		if f.unit == unit then
			self:UpdateFrameValues(f)
		end
	end
end

function UnitFrames:UpdateFrameValues(f)
	local unit = f.unit
	if not UnitExists(unit) then
		f:Hide()
		return
	end

	local db = self.db.profile.ufConfig[f.unitId]
	if not db or not db.enabled then
		f:Hide()
		return
	end
	f:Show()

	-- 1. Health Bar (Native Passthrough)
	local curH = UnitHealth(unit) -- @scan-ignore: midnight-friendly-unit
	local maxH = UnitHealthMax(unit) -- @scan-ignore: midnight-friendly-unit
	f.health:SetMinMaxValues(0, Pass(maxH, 1))
	f.health:SetValue(Pass(curH, 0))

	-- 2. Power Bar
	local curP = UnitPower(unit) -- @scan-ignore: midnight-friendly-unit
	local maxP = UnitPowerMax(unit) -- @scan-ignore: midnight-friendly-unit
	f.power:SetMinMaxValues(0, Pass(maxP, 1))
	f.power:SetValue(Pass(curP, 0))

	-- Visibility logic for Power
	if db.powerBarEnabled then
		if
			Utils.IsValueSecret(curP)
			or Utils.IsValueSecret(maxP)
			or type(curP) ~= "number"
			or type(maxP) ~= "number"
		then
			-- If either is secret, we must show the bar (since we can't compare)
			f.power:Show()
		else
			f.power:SetShown(maxP > 0)
		end
	else
		f.power:Hide()
	end

	-- 3. Class Bar (Conditional)
	local showClass = false
	if f.unitId == "player" and db.classBarEnabled then
		local _, powerToken = UnitPowerType("player")
		-- Basic check: if it's not a primary resource, show class bar
		if
			powerToken
			and powerToken ~= "MANA"
			and powerToken ~= "RAGE"
			and powerToken ~= "FOCUS"
			and powerToken ~= "ENERGY"
		then
			showClass = true
		end
	end
	f.class:SetShown(showClass)
	if showClass then
		local curC = UnitPower("player", nil, true) -- @scan-ignore: midnight-player-only
		local maxC = UnitPowerMax("player", nil, true) -- @scan-ignore: midnight-player-only
		f.class:SetMinMaxValues(0, Pass(maxC, 1))
		f.class:SetValue(Pass(curC, 0))
	end

	-- 4. Heal Prediction & Absorbs
	if db.healthText.value.enabled or f.health.predict:IsShown() or f.health.absorb:IsShown() then
		local h1, h2, h3, h4, unitAbsorb = Utils.GetUnitHealsSafe(unit, self.healCalculator)
		local incomingHeals = h1

		-- Heal Prediction
		if IsActive(incomingHeals) then
			f.health.predict:Show()
			if
				type(incomingHeals) == "number"
				and not Utils.IsValueSecret(incomingHeals)
				and type(curH) == "number"
				and not Utils.IsValueSecret(curH)
			then
				f.health.predict:SetMinMaxValues(0, Pass(maxH, 1))
				f.health.predict:SetValue(curH + incomingHeals)
			else
				-- Secret mode: anchor to current health texture end
				f.health.predict:SetWidth(f.health:GetWidth())
				f.health.predict:ClearAllPoints()
				f.health.predict:SetPoint("LEFT", f.health:GetStatusBarTexture(), "RIGHT")
				f.health.predict:SetPoint("TOP", f.health, "TOP")
				f.health.predict:SetPoint("BOTTOM", f.health, "BOTTOM")
			end
		else
			f.health.predict:Hide()
		end

		-- Absorbs
		if IsActive(unitAbsorb) then
			f.health.absorb:Show()
			f.health.absorb:SetMinMaxValues(0, Pass(maxH, 1))
			f.health.absorb:SetValue(Pass(unitAbsorb, 0))
		else
			f.health.absorb:Hide()
		end
	end

	-- 5. Text Display (The "Gold Standard" Pattern)
	-- Health Text
	local displayH = UnitHealth(unit, true) -- @scan-ignore: midnight-friendly-unit
	local displayMaxH = UnitHealthMax(unit, true) -- @scan-ignore: midnight-friendly-unit

	if db.healthText.name.enabled then
		pcall(function()
			f.healthElements.name.fontString:SetText(GetUnitName(unit, true))
		end)
	end

	if db.healthText.level.enabled then
		pcall(function()
			f.healthElements.level.fontString:SetText(UnitLevel(unit))
		end)
	end

	if db.healthText.value.enabled then
		local hStr = FormatValue(displayH)
		local mStr = FormatValue(displayMaxH)
		pcall(function()
			f.healthElements.value.fontString:SetFormattedText("%s/%s", hStr, mStr)
		end)
	end

	if db.healthText.percent.enabled then
		pcall(function()
			local pct = UnitHealthPercent(unit, true, 100) -- CurveConstants.ScaleTo100 is 100
			if type(pct) == "nil" then
				-- Fallback to manual calc if displayable values are non-secret numbers
				if
					type(displayMaxH) == "number"
					and not Utils.IsValueSecret(displayMaxH)
					and displayMaxH > 0
					and type(displayH) == "number"
					and not Utils.IsValueSecret(displayH)
				then
					pct = math.floor((displayH / displayMaxH) * 100)
				else
					pct = "???"
				end
			end
			f.healthElements.percent.fontString:SetFormattedText("%s%%", pct)
		end)
	end

	-- Power Text
	local _, powerToken = UnitPowerType(unit)
	local displayP = UnitPower(unit, nil, true) -- @scan-ignore: midnight-friendly-unit
	local displayMaxP = UnitPowerMax(unit, nil, true) -- @scan-ignore: midnight-friendly-unit

	if db.powerText.value.enabled then
		local pStr = FormatValue(displayP)
		local pmStr = FormatValue(displayMaxP)
		pcall(function()
			f.powerElements.value.fontString:SetFormattedText("%s/%s", pStr, pmStr)
		end)
	end

	-- 6. Status Icons (Basic placeholder for now)
	for iconId, tex in pairs(f.icons) do
		local config = db.icons[iconId]
		if config and config.enabled then
			local show = false
			local atlas = nil

			if iconId == "combat" then
				show = UnitAffectingCombat(unit)
				atlas = "orderhalltalents-done-check"
			elseif iconId == "resting" then
				show = (unit == "player" and IsResting())
				atlas = "RestingIcon"
			end

			if show then
				tex:Show()
				tex:SetSize(config.size, config.size)
				if atlas then
					tex:SetAtlas(atlas)
				end
				-- Position logic...
			else
				tex:Hide()
			end
		else
			tex:Hide()
		end
	end
end
