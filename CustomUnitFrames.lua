local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local CustomUnitFrames = addon:NewModule("CustomUnitFrames", "AceEvent-3.0")

local Utils = ns.Utils
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

-- Upvalues
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitExists = UnitExists
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClass = UnitClass

local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local playerFrame, targetFrame
local healCalculator

local function CreateUnitBar(parent, barType)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.type = barType

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.5)

	if barType == "HEALTH" then
		-- Heal Prediction
		bar.predict = CreateFrame("StatusBar", nil, bar)
		bar.predict:SetStatusBarTexture(FLAT_BAR_TEXTURE)
		bar.predict:SetAllPoints()
		bar.predict:SetAlpha(0.4)
		bar.predict:SetStatusBarColor(0, 0.8, 0)
		bar.predict:SetFrameLevel(bar:GetFrameLevel() + 1)
		bar.predict:Hide()

		-- Absorbs
		bar.absorb = CreateFrame("StatusBar", nil, bar)
		bar.absorb:SetStatusBarTexture(FLAT_BAR_TEXTURE)
		bar.absorb:SetAlpha(0.6)
		bar.absorb:SetStatusBarColor(0, 1, 1)
		bar.absorb:SetFrameLevel(bar:GetFrameLevel() + 2)
		if bar.absorb.SetReverseFill then
			bar.absorb:SetReverseFill(true)
		end
		bar.absorb:Hide()
	end

	return bar
end

local function CreateUnitFrame(unit)
	local f = CreateFrame("Frame", "ActionHudCustomUnitFrame_" .. unit, UIParent)
	f.unit = unit
	f:SetSize(200, 45) -- Default size
	f:Hide()

	-- Health Bar
	f.health = CreateUnitBar(f, "HEALTH")
	f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.health:SetHeight(30)
	f.health:SetClipsChildren(true)

	-- Power Bar
	f.power = CreateUnitBar(f, "POWER")
	f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1)
	f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -1)
	f.power:SetHeight(10)

	-- Power Value Text
	f.powerValueText = f.power:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.powerValueText:SetPoint("CENTER", f.power, "CENTER", 0, 0)
	f.powerValueText:SetJustifyH("CENTER")

	-- Name Text
	f.nameText = f.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.nameText:SetPoint("TOPLEFT", f.health, "TOPLEFT", 5, -2)
	f.nameText:SetJustifyH("LEFT")

	-- Level Text
	f.levelText = f.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.levelText:SetPoint("TOPLEFT", f.health, "TOPLEFT", 5, -2) -- Will be adjusted in Update
	f.levelText:SetTextColor(1, 0.8, 0)

	-- Value Text (Numeric)
	f.valueText = f.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.valueText:SetPoint("CENTER", f.health, "CENTER", 0, -2)
	f.valueText:SetJustifyH("CENTER")

	-- Percentage Text
	f.percentText = f.health:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.percentText:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", -2, 2)
	f.percentText:SetJustifyH("RIGHT")

	return f
end

local function FormatValue(val)
	-- Must use pcall for comparisons since val could be a secret value
	local ok, result = pcall(function()
		if type(val) ~= "number" then
			return ""
		end
		if val >= 1000000 then
			return string.format("%.1fM", val / 1000000)
		elseif val >= 1000 then
			return string.format("%.1fK", val / 1000)
		else
			return tostring(math.floor(val))
		end
	end)
	
	if ok then
		return result
	end
	return "???"
end

local function UpdateFrameValues(f)
	local unit = f.unit
	if not UnitExists(unit) then
		f:Hide()
		return
	end

	f:Show()

	-- Health
	local curH = UnitHealth(unit)
	local maxH = UnitHealthMax(unit)
	local displayH = UnitHealth(unit, true)
	local displayMax = UnitHealthMax(unit, true)
	f.health:SetMinMaxValues(0, maxH)
	f.health:SetValue(curH)

	-- Prediction & Absorbs
	local incomingHeals, _, _, _, calcAbsorb = Utils.GetUnitHealsSafe(unit, healCalculator)
	local unitAbsorb = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
	
	-- Helper to check if a numeric value is active (non-zero or secret)
	-- Strictly safe for Midnight secret values
	local function IsActive(v)
		if type(v) == "nil" then return false end
		local ok, result = pcall(function() return v > 0 end)
		return not ok or result
	end

	-- Heal Predict
	if IsActive(incomingHeals) then
		f.health.predict:SetMinMaxValues(0, maxH)
		f.health.predict:ClearAllPoints()
		
		local numHeals = tonumber(incomingHeals)
		local numCur = tonumber(curH)
		
		-- Use type and IsValueSecret together for absolute safety
		local canArithmetic = (type(numHeals) == "number" and not Utils.IsValueSecret(numHeals)) and
		                      (type(numCur) == "number" and not Utils.IsValueSecret(numCur))
		
		if canArithmetic then
			f.health.predict:SetAllPoints()
			f.health.predict:SetValue(math.min(maxH, numCur + numHeals))
		else
			-- Secret: anchor to bar edge for passthrough
			local tex = f.health:GetStatusBarTexture()
			if tex then
				f.health.predict:ClearAllPoints()
				f.health.predict:SetPoint("TOPLEFT", tex, "TOPRIGHT")
				f.health.predict:SetPoint("BOTTOMLEFT", tex, "BOTTOMRIGHT")
				-- Set width to full health bar width to ensure correct SetValue scaling
				f.health.predict:SetWidth(f.health:GetWidth())
				f.health.predict:SetValue(incomingHeals)
			end
		end
		f.health.predict:Show()
	else
		f.health.predict:Hide()
	end

	-- Absorb
	if IsActive(calcAbsorb) or IsActive(unitAbsorb) then
		f.health.absorb:SetMinMaxValues(0, maxH)
		f.health.absorb:ClearAllPoints()
		f.health.absorb:SetAllPoints()
		if f.health.absorb.SetReverseFill then
			f.health.absorb:SetReverseFill(true)
		end
		
		local absorbValue = 0
		if Utils.IsValueSecret(calcAbsorb) then 
			absorbValue = calcAbsorb
		elseif Utils.IsValueSecret(unitAbsorb) then 
			absorbValue = unitAbsorb
		else
			local n1 = tonumber(calcAbsorb) or 0
			local n2 = tonumber(unitAbsorb) or 0
			-- Extra safety check since tonumber(secret) returns secret
			if Utils.IsValueSecret(n1) then absorbValue = n1
			elseif Utils.IsValueSecret(n2) then absorbValue = n2
			else absorbValue = math.max(n1, n2) end
		end
		
		f.health.absorb:SetValue(absorbValue)
		f.health.absorb:Show()
	else
		f.health.absorb:Hide()
	end

	-- Power
	local curP = UnitPower(unit)
	local maxP = UnitPowerMax(unit)
	
	-- Bar Update (Always Passthrough)
	-- Use type checks instead of 'or' to avoid boolean tests on secrets
	local barMax = maxP
	if type(barMax) == "nil" then barMax = 1 end
	local barVal = curP
	if type(barVal) == "nil" then barVal = 0 end
	
	f.power:SetMinMaxValues(0, barMax)
	f.power:SetValue(barVal)
	
	if IsActive(maxP) then
		f.power:Show()
	else
		f.power:Hide()
	end

	-- Power Text
	pcall(function()
		local val = UnitPower(unit, nil, true)
		local total = UnitPowerMax(unit, nil, true)

		-- Use type checks for presence instead of boolean tests
		if type(val) ~= "nil" and type(total) ~= "nil" then
			local ok, pStr = pcall(function() return AbbreviateNumbers and AbbreviateNumbers(val) or val end)
			local ok2, mStr = pcall(function() return AbbreviateNumbers and AbbreviateNumbers(total) or total end)
			
			if ok and ok2 then
				f.powerValueText:SetFormattedText("%s/%s", pStr, mStr)
			else
				f.powerValueText:SetFormattedText("%s/%s", val, total)
			end
		else
			f.powerValueText:SetText("")
		end
	end)

	-- Colors
	local r, g, b = Utils.GetUnitColor(unit, "HEALTH", 0.85)
	f.health:SetStatusBarColor(r, g, b)
	
	r, g, b = Utils.GetUnitColor(unit, "POWER", 0.85)
	f.power:SetStatusBarColor(r, g, b)

	-- Texts
	pcall(function()
		local level = UnitLevel(unit)
		if level and level > 0 then
			f.levelText:SetText(level)
			f.levelText:Show()
			f.nameText:SetPoint("TOPLEFT", f.levelText, "TOPRIGHT", 4, 0)
		else
			f.levelText:Hide()
			f.nameText:SetPoint("TOPLEFT", f.health, "TOPLEFT", 5, -2)
		end
		f.nameText:SetText(UnitName(unit) or "Unknown")
	end)
	
	-- Numeric Values
	pcall(function()
		local val = UnitHealth(unit, true)
		local total = UnitHealthMax(unit, true)

		if type(val) ~= "nil" and type(total) ~= "nil" then
			-- Try to abbreviate. If these are secret, AbbreviateNumbers will throw,
			-- and we'll catch it in the pcall to fallback to raw string formatting.
			local ok, hStr = pcall(function() return AbbreviateNumbers and AbbreviateNumbers(val) or val end)
			local ok2, mStr = pcall(function() return AbbreviateNumbers and AbbreviateNumbers(total) or total end)
			
			if ok and ok2 then
				f.valueText:SetFormattedText("%s/%s", hStr, mStr)
			else
				-- If abbreviation failed, it's a secret. 
				-- SetFormattedText with %s is the "Gold Standard" for secret values.
				f.valueText:SetFormattedText("%s/%s", val, total)
			end
		else
			f.valueText:SetText("???")
		end
	end)

	-- Percentage
	pcall(function()
		if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
			local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
			f.percentText:SetFormattedText("%.0f%%", pct)
		else
			local pct = UnitHealthPercent(unit) -- Try legacy/non-curve
			if pct then
				f.percentText:SetFormattedText("%.0f%%", pct)
			else
				f.percentText:SetText("")
			end
		end
	end)
end

function CustomUnitFrames:OnInitialize()
	self.db = addon.db
end

function CustomUnitFrames:OnEnable()
	if not self.db.profile.customUfEnabled then
		return
	end

	if not healCalculator and Utils.Cap.HasHealCalculator then
		healCalculator = Utils.CreateHealCalculator()
	end

	if not playerFrame then
		playerFrame = CreateUnitFrame("player")
		targetFrame = CreateUnitFrame("target")
		
		-- Simple positioning for now, can be made draggable later
		playerFrame:SetPoint("CENTER", UIParent, "CENTER", -250, -150)
		targetFrame:SetPoint("CENTER", UIParent, "CENTER", 250, -150)
	end

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAll")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateAll")
	self:RegisterEvent("UNIT_HEALTH", "OnUnitEvent")
	self:RegisterEvent("UNIT_POWER_UPDATE", "OnUnitEvent")
	self:RegisterEvent("UNIT_HEAL_PREDICTION", "OnUnitEvent")
	self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "OnUnitEvent")

	self:UpdateAll()
end

function CustomUnitFrames:OnDisable()
	if playerFrame then playerFrame:Hide() end
	if targetFrame then targetFrame:Hide() end
end

function CustomUnitFrames:UpdateAll()
	if not self.db.profile.customUfEnabled then return end
	UpdateFrameValues(playerFrame)
	UpdateFrameValues(targetFrame)
end

function CustomUnitFrames:OnUnitEvent(event, unit)
	if not self.db.profile.customUfEnabled then return end
	if unit == "player" then
		UpdateFrameValues(playerFrame)
	elseif unit == "target" then
		UpdateFrameValues(targetFrame)
	end
end

function CustomUnitFrames:UpdateLayout()
	if not self.db.profile.customUfEnabled then
		self:OnDisable()
		return
	end
	self:OnEnable()
	
	if playerFrame then
		playerFrame:SetSize(self.db.profile.customUfWidth or 200, (self.db.profile.customUfHealthHeight or 30) + (self.db.profile.customUfPowerHeight or 10) + 1)
		playerFrame.health:SetHeight(self.db.profile.customUfHealthHeight or 30)
		playerFrame.power:SetHeight(self.db.profile.customUfPowerHeight or 10)
		
		targetFrame:SetSize(self.db.profile.customUfWidth or 200, (self.db.profile.customUfHealthHeight or 30) + (self.db.profile.customUfPowerHeight or 10) + 1)
		targetFrame.health:SetHeight(self.db.profile.customUfHealthHeight or 30)
		targetFrame.power:SetHeight(self.db.profile.customUfPowerHeight or 10)
	end
end

