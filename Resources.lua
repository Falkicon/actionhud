local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Resources = addon:NewModule("Resources", "AceEvent-3.0")
ns.Resources = Resources -- For backward compatibility with other modules referencing it

-- Local upvalues for performance
local UnitClass = UnitClass
local UnitHealth = UnitHealth -- @scan-ignore: midnight-upvalue
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower -- @scan-ignore: midnight-upvalue
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer

local main
local container
local playerGroup, targetGroup
local playerHealth, playerPower, playerClassBar
local targetHealth, targetPower
local classSegments = {}
local healCalculator -- Shared calculator for Royal clients

local Utils = ns.Utils

-- Flat bar texture (solid color, no gradient)
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Configuration Cache
local RCFG = {
	enabled = true,
	healthEnabled = true,
	powerEnabled = true,
	classEnabled = true,
	healthHeight = 6,
	powerHeight = 6,
	classHeight = 4,
	spacing = 1,
	gap = 5,
	showTarget = true,
}

local ClassBarColors = {
	[Enum.PowerType.ComboPoints] = { r = 0.9, g = 0.3, b = 0.3 }, -- Rogue/Feral Red
	[Enum.PowerType.Chi] = { r = 0.6, g = 0.9, b = 0.8 }, -- Monk Seafoam
	[Enum.PowerType.HolyPower] = { r = 0.9, g = 0.8, b = 0.3 }, -- Paladin Gold
	[Enum.PowerType.SoulShards] = { r = 0.6, g = 0.45, b = 0.65 }, -- Warlock Purple
	[Enum.PowerType.ArcaneCharges] = { r = 0.3, g = 0.5, b = 0.9 }, -- Mage Blue
	[Enum.PowerType.Essence] = { r = 0.3, g = 0.7, b = 0.6 }, -- Evoker Teal
	[Enum.PowerType.Runes] = { r = 0.77, g = 0.12, b = 0.23 }, -- Death Knight Red
}

local RuneSpecColors = {
	[1] = { r = 0.77, g = 0.12, b = 0.23 }, -- Blood (Red)
	[2] = { r = 0.1, g = 0.6, b = 0.8 }, -- Frost (Blue)
	[3] = { r = 0.3, g = 0.7, b = 0.3 }, -- Unholy (Green)
}

local function CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.5)

	-- Add Predict/Absorb overlays if this is a health bar
	-- We'll initialize them later in CreateBar if type is set, or just always for safety
	bar.predict = CreateFrame("StatusBar", nil, bar)
	bar.predict:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar.predict:SetAllPoints()
	bar.predict:SetAlpha(0.4)
	bar.predict:SetStatusBarColor(0, 0.8, 0) -- Green for heals
	bar.predict:SetFrameLevel(bar:GetFrameLevel() + 1)
	bar.predict:Hide()

	bar.absorb = CreateFrame("StatusBar", nil, bar)
	bar.absorb:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar.absorb:SetAlpha(0.6) -- Higher alpha for visibility
	bar.absorb:SetStatusBarColor(0, 1, 1) -- Brighter teal for absorbs
	bar.absorb:SetFrameLevel(bar:GetFrameLevel() + 2) -- Top layer
	if bar.absorb.SetReverseFill then
		bar.absorb:SetReverseFill(true)
	end
	bar.absorb:Hide()

	return bar
end

local function GetClassPowerType()
	local _, class = UnitClass("player")
	if class == "ROGUE" or class == "DRUID" then
		return Enum.PowerType.ComboPoints
	elseif class == "PALADIN" then
		return Enum.PowerType.HolyPower
	elseif class == "WARLOCK" then
		return Enum.PowerType.SoulShards
	elseif class == "MAGE" then
		return Enum.PowerType.ArcaneCharges
	elseif class == "MONK" then
		return Enum.PowerType.Chi
	elseif class == "EVOKER" then
		return Enum.PowerType.Essence
	elseif class == "DEATHKNIGHT" then
		return Enum.PowerType.Runes
	end
	return nil
end

local function GetReadyRuneCount()
	local count = 0
	for i = 1, 6 do
		local _, _, ready = GetRuneCooldown(i)
		if ready then
			count = count + 1
		end
	end
	return count
end

local function GetClassPowerFractional(unit, pType)
	local cur = UnitPower(unit, pType)
	local max = UnitPowerMax(unit, pType)

	if pType == Enum.PowerType.SoulShards then
		local _, class = UnitClass(unit)
		if class == "WARLOCK" then
			local spec = Utils.GetSpecializationSafe()
			-- Destruction Warlocks (Spec 3) have partial shards
			if spec == 3 then
				local raw = UnitPower(unit, pType, true)
				local mod = (UnitPowerDisplayMod and UnitPowerDisplayMod(pType)) or 100
				if mod ~= 0 then
					return raw / mod
				end
			end
		end
	elseif pType == Enum.PowerType.Essence then
		local partial = UnitPartialPower and UnitPartialPower(unit, pType) or 0
		return cur + (partial / 1000.0)
	end

	return cur
end

local function CanShowClassPower()
	local pType = GetClassPowerType()
	if not pType then
		return false, nil, 0
	end

	local max = UnitPowerMax("player", pType)
	local cur = GetClassPowerFractional("player", pType)

	-- Handle Midnight secret values
	local maxIsSecret = Utils.IsValueSecret(max)
	local curIsSecret = Utils.IsValueSecret(cur)

	-- If it's a known safe power type, ignore the secret flag for VISUAL purposes
	local isSafeType = Utils.IsPowerTypeSafe(pType)
	if isSafeType then
		curIsSecret = false
		maxIsSecret = false
	end

	local maxNum = tonumber(max)
	local curNum = tonumber(cur)

	-- Normalize internal units (some clients return 300 for 3 shards)
	if maxNum and maxNum > 10 then
		maxNum = math.floor(maxNum / 100)
	end
	if curNum and curNum > 10 then
		curNum = curNum / 100
	end

	if maxIsSecret or curIsSecret or (not maxNum) then
		-- Fallback for secret OR non-numeric values
		return true, pType, 5
	end

	if maxNum <= 0 then
		return false, pType, 0
	end

	-- For Warlocks, always show bar if in combat
	local _, class = UnitClass("player")
	if class == "WARLOCK" and UnitAffectingCombat("player") then
		return true, pType, maxNum
	end

	-- Show if we have any power (including partials)
	if not curNum or curNum <= 0.01 then
		return false, pType, 0
	end

	return true, pType, maxNum
end

local function UpdateClassPower()
	if not playerClassBar then
		return
	end

	local show, pType, max = CanShowClassPower()
	if not show then
		playerClassBar:Hide()
		return
	end

	-- Get fractional power (3.4 shards, 5.2 essence, etc)
	local curFractional = GetClassPowerFractional("player", pType)
	local curIsSecret = Utils.IsValueSecret(curFractional)

	-- If it's a known safe power type, ignore the secret flag
	if Utils.IsPowerTypeSafe(pType) then
		curIsSecret = false
	end

	-- Force max to be numeric for the loop
	max = tonumber(max) or 5

	playerClassBar:Show()

	-- Ensure segments exist as StatusBars
	for i = 1, max do
		if not classSegments[i] then
			local f = CreateFrame("StatusBar", nil, playerClassBar)
			f:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
			f:SetMinMaxValues(0, 1)
			
			f.bg = f:CreateTexture(nil, "BACKGROUND")
			f.bg:SetAllPoints()
			f.bg:SetColorTexture(0, 0, 0, 0.3)
			
			classSegments[i] = f
		elseif not classSegments[i].SetStatusBarColor then
			-- Conversion safety: if it was a texture, we need to replace it
			-- This shouldn't happen after the first reload but good for dev
			classSegments[i]:Hide()
			local f = CreateFrame("StatusBar", nil, playerClassBar)
			f:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
			f:SetMinMaxValues(0, 1)
			f.bg = f:CreateTexture(nil, "BACKGROUND")
			f.bg:SetAllPoints()
			f.bg:SetColorTexture(0, 0, 0, 0.3)
			classSegments[i] = f
		end
	end

	-- Hide extra
	for i = max + 1, #classSegments do
		classSegments[i]:Hide()
	end

	-- Layout
	local width = playerClassBar:GetWidth()
	if width <= 0 then
		width = container:GetWidth()
	end

	local spacing = 1
	local segWidth = (width - ((max - 1) * spacing)) / max
	if segWidth < 1 then
		segWidth = 1
	end

	local baseColor = ClassBarColors[pType]
	if pType == Enum.PowerType.Runes then
		local spec = Utils.GetSpecializationSafe()
		baseColor = RuneSpecColors[spec] or ClassBarColors[pType]
	end

	for i = 1, max do
		local seg = classSegments[i]
		seg:ClearAllPoints()
		seg:SetWidth(segWidth)
		seg:SetHeight(playerClassBar:GetHeight())

		if i == 1 then
			seg:SetPoint("LEFT", playerClassBar, "LEFT", 0, 0)
		else
			seg:SetPoint("LEFT", classSegments[i - 1], "RIGHT", spacing, 0)
		end

		-- Calculate fill for this specific segment (0.0 to 1.0)
		local fill = 0
		if not curIsSecret then
			fill = math.max(0, math.min(1, curFractional - (i - 1)))
		end

		seg:SetValue(fill)

		-- Color / Alpha
		if curIsSecret then
			seg:SetAlpha(0.6)
			local c = baseColor
			if c then
				seg:SetStatusBarColor(c.r * 0.8, c.g * 0.8, c.b * 0.8)
			else
				seg:SetStatusBarColor(0.8, 0.8, 0)
			end
		else
			seg:SetAlpha(fill > 0 and 1 or 0.3)
			local c = baseColor
			if c then
				seg:SetStatusBarColor(c.r, c.g, c.b)
			else
				seg:SetStatusBarColor(1, 1, 0)
			end
		end
		seg:Show()
	end
end

local function UpdateBarColor(bar, unit)
	if not bar or not UnitExists(unit) then
		return
	end

	local r, g, b = Utils.GetUnitColor(unit, bar.type, 0.85)
	bar:SetStatusBarColor(r, g, b)
end

local function UpdateBarValue(bar, unit)
	if not bar or not UnitExists(unit) then
		bar:SetValue(0)
		if bar.predict then
			bar.predict:Hide()
		end
		if bar.absorb then
			bar.absorb:Hide()
		end
		return
	end

	local cur, max
	if bar.type == "HEALTH" then
		cur = UnitHealth(unit) -- @scan-ignore: midnight-passthrough
		max = UnitHealthMax(unit)
	else
		cur = UnitPower(unit) -- @scan-ignore: midnight-passthrough
		max = UnitPowerMax(unit)
	end

		-- PASSTHROUGH: Update the main bar value FIRST. 
		-- StatusBars in 12.0 handle secret values correctly. 
		-- Doing this first ensures basic health/power display works even if prediction fails.
		local bMax = max
		if type(bMax) == "nil" then bMax = 1 end
		local bVal = cur
		if type(bVal) == "nil" then bVal = 0 end
		
		bar:SetMinMaxValues(0, bMax)
		bar:SetValue(bVal)

	-- Update Predict/Absorb for health bars
	if bar.type == "HEALTH" and (RCFG.showPredict or RCFG.showAbsorbs) then
		local incomingHeals, _, _, _, calcAbsorb = Utils.GetUnitHealsSafe(unit, healCalculator)
		
		-- Use a safe helper for direct API calls that might return secret values
		local function GetRawUnitAbsorb(u)
			if not UnitGetTotalAbsorbs then return 0 end
			local val = UnitGetTotalAbsorbs(u)
			if type(val) == "nil" then return 0 end
			return val
		end

		local unitAbsorb = GetRawUnitAbsorb(unit)
		
		-- Helper to check if a value is "active" (non-zero or secret)
		-- Helper to check if a numeric value is active (non-zero or secret)
		-- Strictly safe for Midnight secret values
		local function IsActive(v)
			if type(v) == "nil" then return false end
			local ok, result = pcall(function() return v > 0 end)
			return not ok or result
		end

		-- 1. Heal Prediction (Incoming Heals)
		if RCFG.showPredict and IsActive(incomingHeals) then
			bar.predict:SetMinMaxValues(0, max)
			if Utils.IsValueSecret(cur) then
				-- Royal: Anchor to current health texture and fill to the right
				local tex = bar:GetStatusBarTexture()
				if tex then
					bar.predict:ClearAllPoints()
					bar.predict:SetPoint("TOPLEFT", tex, "TOPRIGHT")
					bar.predict:SetPoint("BOTTOMLEFT", tex, "BOTTOMRIGHT")
					-- Set width to full bar width to ensure correct SetValue scaling
					bar.predict:SetWidth(bar:GetWidth())
					bar.predict:SetValue(incomingHeals)
					bar.predict:Show()
				end
			else
				-- Legacy: Stack but cap at max
				bar.predict:ClearAllPoints()
				bar.predict:SetAllPoints()
				local curNum = tonumber(cur)
				if type(curNum) ~= "number" then curNum = 0 end
				local healNum = tonumber(incomingHeals)
				if type(healNum) ~= "number" then healNum = 0 end
				bar.predict:SetValue(math.min(max, curNum + healNum))
				bar.predict:Show()
			end
		else
			bar.predict:Hide()
		end

		-- 2. Absorbs (Shields) - Reverse Fill from Right
		if RCFG.showAbsorbs and (IsActive(calcAbsorb) or IsActive(unitAbsorb)) then
			bar.absorb:SetMinMaxValues(0, max)
			bar.absorb:ClearAllPoints()
			bar.absorb:SetAllPoints()
			
			-- Force reverse fill state
			if bar.absorb.SetReverseFill then
				bar.absorb:SetReverseFill(true)
			end

			-- Prefer secret value for pass-through, or max of numbers
			local absorbValue = 0
			if Utils.IsValueSecret(calcAbsorb) then
				absorbValue = calcAbsorb
			elseif Utils.IsValueSecret(unitAbsorb) then
				absorbValue = unitAbsorb
			else
				absorbValue = math.max(tonumber(calcAbsorb) or 0, tonumber(unitAbsorb) or 0)
			end

			bar.absorb:SetValue(absorbValue)
			bar.absorb:Show()
		else
			bar.absorb:Hide()
		end

		-- Debug logging (Safe)
		if addon.db.profile.debugResources then
			local function s(v)
				return Utils.IsValueSecret(v) and "<secret>" or tostring(v)
			end
			addon:Log(
				string.format(
					"Resources: %s Health update: cur=%s max=%s predict=%s absorb=%s",
					unit,
					s(cur),
					s(max),
					s(incomingHeals),
					s(calcAbsorb ~= 0 and calcAbsorb or unitAbsorb)
				),
				"resources"
			)
		end
	end
end

function Resources:OnInitialize()
	self.db = addon.db
end

function Resources:OnEnable()
	main = _G["ActionHudFrame"]
	if not main then
		return
	end

	-- Initialize Royal calculator if available
	if not healCalculator and Utils.Cap.HasHealCalculator then
		healCalculator = Utils.CreateHealCalculator()
	end

	if not container then
		-- Create container using DraggableContainer for independent positioning support
		local DraggableContainer = ns.DraggableContainer
		if DraggableContainer then
			container = DraggableContainer:Create({
				moduleId = "resources",
				parent = main,
				db = self.db,
				xKey = "resourcesXOffset",
				yKey = "resourcesYOffset",
				defaultX = 0,
				defaultY = 100,
				size = { width = 120, height = 20 },
			})
		end

		-- Fallback if DraggableContainer not available
		if not container then
			container = CreateFrame("Frame", "ActionHudResources", main)
		end

		playerGroup = CreateFrame("Frame", nil, container)
		targetGroup = CreateFrame("Frame", nil, container)

		playerHealth = CreateBar(playerGroup)
		playerHealth.type = "HEALTH"
		playerHealth:SetClipsChildren(true)
		playerPower = CreateBar(playerGroup)
		playerPower.type = "POWER"

		playerClassBar = CreateFrame("Frame", nil, playerGroup)

		targetHealth = CreateBar(targetGroup)
		targetHealth.type = "HEALTH"
		targetHealth:SetClipsChildren(true)
		targetPower = CreateBar(targetGroup)
		targetPower.type = "POWER"
	end

	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnEvent")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")
	self:RegisterEvent("UNIT_HEALTH", "OnEvent")
	self:RegisterEvent("UNIT_HEAL_PREDICTION", "OnEvent")
	self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "OnEvent")
	self:RegisterEvent("UNIT_POWER_UPDATE", "OnEvent")
	self:RegisterEvent("UNIT_DISPLAYPOWER", "OnEvent")
	self:RegisterEvent("UNIT_MAXPOWER", "OnEvent")
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnEvent")
	self:RegisterEvent("RUNE_POWER_UPDATE", "OnEvent")

	UpdateBarColor(playerHealth, "player")
	UpdateBarColor(playerPower, "player")
	UpdateBarValue(playerHealth, "player")
	UpdateBarValue(playerPower, "player")
	UpdateClassPower()

	self:UpdateLayout()
end

function Resources:OnEvent(event, unit)
	if not RCFG.enabled then
		return
	end
	addon:Log(string.format("Resources: %s (unit=%s)", event, tostring(unit)), "events")

	if event == "PLAYER_ENTERING_WORLD" then
		UpdateClassPower()
		self:UpdateLayout()
	elseif event == "PLAYER_TARGET_CHANGED" then
		self:UpdateLayout()
		UpdateBarColor(targetHealth, "target")
		UpdateBarColor(targetPower, "target")
		UpdateBarValue(targetHealth, "target")
		UpdateBarValue(targetPower, "target")
	elseif event == "UNIT_HEALTH" or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		if unit == "player" then
			UpdateBarValue(playerHealth, "player")
		end
		if unit == "target" then
			UpdateBarValue(targetHealth, "target")
		end
	elseif event == "UNIT_POWER_UPDATE" then
		if unit == "player" then
			UpdateBarValue(playerPower, "player")
			local cType = GetClassPowerType()
			if cType then
				local shouldShow = CanShowClassPower()
				local isShown = playerClassBar:IsShown()
				if shouldShow ~= isShown then
					self:UpdateLayout()
				else
					if shouldShow then
						UpdateClassPower()
					end
				end
			end
		end
		if unit == "target" then
			UpdateBarValue(targetPower, "target")
		end
	elseif event == "UNIT_DISPLAYPOWER" then
		if unit == "player" then
			UpdateBarColor(playerPower, "player")
			UpdateBarValue(playerPower, "player")
			UpdateClassPower()
		end
		if unit == "target" then
			UpdateBarColor(targetPower, "target")
			UpdateBarValue(targetPower, "target")
		end
	elseif event == "UNIT_MAXPOWER" then
		if unit == "player" then
			UpdateClassPower()
			self:UpdateLayout()
		end
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		UpdateClassPower()
		self:UpdateLayout()
	elseif event == "RUNE_POWER_UPDATE" then
		UpdateClassPower()
	end
end

-- Calculate the height of this module for LayoutManager
function Resources:CalculateHeight()
	if not RCFG.enabled then
		return 0
	end

	local db = addon.db.profile
	local healthHeight = db.resHealthHeight or 6
	local powerHeight = db.resPowerHeight or 6
	local classHeight = db.resClassHeight or 4
	local spacing = db.resSpacing or 1

	local totalHeight = 0
	local visibleBars = 0

	if db.resHealthEnabled then
		totalHeight = totalHeight + healthHeight
		visibleBars = visibleBars + 1
	end

	if db.resPowerEnabled then
		totalHeight = totalHeight + (visibleBars > 0 and spacing or 0) + powerHeight
		visibleBars = visibleBars + 1
	end

	if db.resClassEnabled and CanShowClassPower() then
		totalHeight = totalHeight + (visibleBars > 0 and spacing or 0) + classHeight
		visibleBars = visibleBars + 1
	end

	return totalHeight
end

-- Get the width of this module for LayoutManager
function Resources:GetLayoutWidth()
	local p = addon.db.profile
	local cols = 6
	return cols * (p.iconWidth or 20)
end

-- Apply position from LayoutManager
function Resources:ApplyLayoutPosition()
	if not container then
		return
	end
	if not RCFG.enabled then
		container:Hide()
		return
	end

	local LM = addon:GetModule("LayoutManager", true)
	if not LM then
		return
	end

	-- Check if we're in stack mode
	local inStack = LM:IsModuleInStack("resources")

	container:ClearAllPoints()

	if inStack then
		-- Stack mode: use full HUD width and position from LayoutManager
		local containerWidth = LM:GetMaxWidth()
		local containerHeight = self:CalculateHeight()
		if containerWidth > 0 and containerHeight > 0 then
			container:SetSize(containerWidth, containerHeight)
		end
		local yOffset = LM:GetModulePosition("resources")
		container:SetPoint("TOP", main, "TOP", 0, yOffset)
		container:EnableMouse(false)
	else
		-- Independent mode: DraggableContainer handles positioning
		local DraggableContainer = ns.DraggableContainer
		if DraggableContainer then
			DraggableContainer:UpdatePosition(container)
			DraggableContainer:UpdateOverlay(container)
		else
			-- Fallback positioning
			local p = addon.db.profile
			local xOffset = p.resourcesXOffset or 0
			local yOffset = p.resourcesYOffset or 100
			container:SetPoint("CENTER", main, "CENTER", xOffset, yOffset)
		end
	end

	container:Show()
	UpdateClassPower()

	addon:Log(string.format("Resources positioned: inStack=%s", tostring(inStack)), "layout")
end

function Resources:UpdateLayout()
	if not container or not addon then
		return
	end

	local db = addon.db.profile

	-- Debug Container Visual
	addon:UpdateLayoutOutline(container, "Resource Bars", "resources")

	RCFG.enabled = db.resEnabled == true
	RCFG.healthEnabled = db.resHealthEnabled ~= false
	RCFG.powerEnabled = db.resPowerEnabled ~= false
	RCFG.classEnabled = db.resClassEnabled ~= false
	RCFG.showPredict = db.resShowPredict ~= false
	RCFG.showAbsorbs = db.resShowAbsorbs ~= false
	RCFG.healthHeight = db.resHealthHeight or 6
	RCFG.powerHeight = db.resPowerHeight or 6
	RCFG.classHeight = db.resClassHeight or 4
	RCFG.spacing = db.resSpacing or 1
	RCFG.gap = db.resGap or 5
	RCFG.showTarget = db.resShowTarget == true

	if not RCFG.enabled then
		container:Hide()
		local LM = addon:GetModule("LayoutManager", true)
		if LM then
			LM:SetModuleHeight("resources", 0)
		end
		return
	end

	local hasClassBar, _, _ = CanShowClassPower()
	local showClass = RCFG.classEnabled and hasClassBar

	-- Calculate total height based on enabled bars
	local totalHeight = self:CalculateHeight()

	if totalHeight <= 0 then
		container:Hide()
		local LM = addon:GetModule("LayoutManager", true)
		if LM then
			LM:SetModuleHeight("resources", 0)
		end
		return
	end

	container:Show()

	if not main then
		main = _G["ActionHudFrame"]
	end
	if not main then
		return
	end

	-- Get width: use fixed width if set, otherwise HUD width when in stack
	local LM = addon:GetModule("LayoutManager", true)
	local inStack = LM and LM:IsModuleInStack("resources")
	local db = addon.db.profile
	local hudWidth

	-- Priority: fixed width > HUD width > ActionBars width > default
	if db.resBarWidth and db.resBarWidth > 0 then
		hudWidth = db.resBarWidth
	elseif inStack and LM then
		hudWidth = LM:GetMaxWidth()
	else
		-- Fallback to ActionBars width for independent mode
		local AB = addon:GetModule("ActionBars", true)
		hudWidth = 120
		if AB and AB.GetLayoutWidth then
			hudWidth = AB:GetLayoutWidth()
		end
	end

	container:SetSize(hudWidth, totalHeight)

	-- Report height to LayoutManager
	if LM then
		LM:SetModuleHeight("resources", totalHeight)
	end

	local useSplit = false
	if RCFG.showTarget and UnitExists("target") then
		useSplit = true
	end

	playerGroup:ClearAllPoints()
	targetGroup:ClearAllPoints()
	playerGroup:SetHeight(container:GetHeight())
	targetGroup:SetHeight(container:GetHeight())

	if useSplit then
		local halfWidth = (hudWidth - RCFG.gap) / 2
		playerGroup:SetWidth(halfWidth)
		targetGroup:SetWidth(halfWidth)
		targetGroup:Show()
		playerGroup:SetPoint("LEFT", container, "LEFT", 0, 0)
		targetGroup:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	else
		playerGroup:SetWidth(hudWidth)
		targetGroup:Hide()
		playerGroup:SetPoint("CENTER", container, "CENTER", 0, 0)
	end

	-- Positioning Bars
	playerHealth:ClearAllPoints()
	playerPower:ClearAllPoints()
	playerClassBar:ClearAllPoints()
	targetHealth:ClearAllPoints()
	targetPower:ClearAllPoints()

	local function FillWidth(f, p)
		f:SetPoint("LEFT", p, "LEFT", 0, 0)
		f:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	end

	local lastPlayerBar = nil
	local lastTargetBar = nil

	-- Health
	if RCFG.healthEnabled then
		playerHealth:Show()
		playerHealth:SetHeight(RCFG.healthHeight)
		playerHealth:SetPoint("TOP", playerGroup, "TOP", 0, 0)
		FillWidth(playerHealth, playerGroup)
		lastPlayerBar = playerHealth

		if useSplit then
			targetHealth:Show()
			targetHealth:SetHeight(RCFG.healthHeight)
			targetHealth:SetPoint("TOP", targetGroup, "TOP", 0, 0)
			FillWidth(targetHealth, targetGroup)
			lastTargetBar = targetHealth
		else
			targetHealth:Hide()
		end
	else
		playerHealth:Hide()
		targetHealth:Hide()
	end

	-- Power
	if RCFG.powerEnabled then
		playerPower:Show()
		playerPower:SetHeight(RCFG.powerHeight)
		if lastPlayerBar then
			playerPower:SetPoint("TOP", lastPlayerBar, "BOTTOM", 0, -RCFG.spacing)
		else
			playerPower:SetPoint("TOP", playerGroup, "TOP", 0, 0)
		end
		FillWidth(playerPower, playerGroup)
		lastPlayerBar = playerPower

		if useSplit then
			targetPower:Show()
			targetPower:SetHeight(RCFG.powerHeight)
			if lastTargetBar then
				targetPower:SetPoint("TOP", lastTargetBar, "BOTTOM", 0, -RCFG.spacing)
			else
				targetPower:SetPoint("TOP", targetGroup, "TOP", 0, 0)
			end
			FillWidth(targetPower, targetGroup)
			lastTargetBar = targetPower
		else
			targetPower:Hide()
		end
	else
		playerPower:Hide()
		targetPower:Hide()
	end

	-- Class
	if showClass then
		playerClassBar:Show()
		playerClassBar:SetHeight(RCFG.classHeight)
		if lastPlayerBar then
			playerClassBar:SetPoint("TOP", lastPlayerBar, "BOTTOM", 0, -RCFG.spacing)
		else
			playerClassBar:SetPoint("TOP", playerGroup, "TOP", 0, 0)
		end
		FillWidth(playerClassBar, playerGroup)
		UpdateClassPower()
	else
		playerClassBar:Hide()
	end
end

function Resources:GetContainer()
	return container
end
