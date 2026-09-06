local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Resources = addon:NewModule("Resources", "AceEvent-3.0")
ns.Resources = Resources -- For backward compatibility with other modules referencing it

-- Local upvalues for performance
local UnitHealth = UnitHealth -- @scan-ignore: midnight-upvalue
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower -- @scan-ignore: midnight-upvalue
local UnitPowerMax = UnitPowerMax
local UnitExists = UnitExists

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

local function UnitExistsSafe(unit)
	local exists = UnitExists(unit)
	if Utils.IsValueSecret(exists) then
		return false
	end
	return exists == true
end

local function SafeNumber(value)
	if Utils.IsValueSecret(value) or type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function CreateBar(parent, withHealthOverlays)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.5)

	if withHealthOverlays then
		bar.predict = CreateFrame("StatusBar", nil, bar)
		bar.predict:SetStatusBarTexture(FLAT_BAR_TEXTURE)
		bar.predict:SetAllPoints()
		bar.predict:SetAlpha(0.4)
		bar.predict:SetStatusBarColor(0, 0.8, 0) -- Green for heals
		bar.predict:SetFrameLevel(bar:GetFrameLevel() + 1)
		bar.predict:Hide()

		bar.absorb = CreateFrame("StatusBar", nil, bar)
		bar.absorb:SetStatusBarTexture(FLAT_BAR_TEXTURE)
		bar.absorb:SetAllPoints()
		bar.absorb:SetAlpha(0.6) -- Higher alpha for visibility
		bar.absorb:SetStatusBarColor(0, 1, 1) -- Brighter teal for absorbs
		bar.absorb:SetFrameLevel(bar:GetFrameLevel() + 2) -- Top layer
		if bar.absorb.SetReverseFill then
			bar.absorb:SetReverseFill(true)
		end
		bar.absorb:Hide()
	end

	return bar
end

local function GetClassPowerType()
	return Utils.GetPlayerClassPowerTypeSafe()
end

local function CanShowClassPower()
	local pType = GetClassPowerType()
	if not pType then
		return false
	end
	local max = UnitPowerMax("player", pType) -- @scan-ignore: midnight-player-only
	local maxNum = SafeNumber(max)
	if maxNum then
		-- Eligibility and capacity control layout; spending the last point does not.
		return Utils.SafeCompare(maxNum, 0, ">"), pType, maxNum, max
	end
	return Utils.IsValueSecret(max), pType, nil, max
end

local function GetClassPowerValue(pType, maxNum, max)
	local ok, cur = pcall(UnitPower, "player", pType) -- @scan-ignore: midnight-player-only
	if not ok or (not Utils.IsValueSecret(cur) and type(cur) ~= "number") then
		return nil
	end

	-- Keep Destruction shards in native raw units. Public interval endpoints can
	-- be scaled; an opaque current value must never be divided in Lua.
	if pType == Enum.PowerType.SoulShards and Utils.GetSpecializationSafe() == 3 and maxNum then
		local mod = UnitPowerDisplayMod and SafeNumber(UnitPowerDisplayMod(pType))
		if mod and Utils.SafeCompare(mod, 0, ">") then
			local rawOk, raw = pcall(UnitPower, "player", pType, true) -- @scan-ignore: midnight-player-only
			if rawOk and (Utils.IsValueSecret(raw) or type(raw) == "number") then
				return raw, mod, maxNum * mod
			end
		end
	elseif pType == Enum.PowerType.Essence and UnitPartialPower then
		local partialOk, partial = pcall(UnitPartialPower, "player", pType)
		local curNum = SafeNumber(cur)
		local partialNum = partialOk and SafeNumber(partial)
		if curNum and partialNum then
			-- Blizzard's Essence partial value uses thousandths of one point.
			cur = curNum + partialNum / 1000
		end
	end
	return cur, 1, max
end

local function PrepareClassPower(maxNum)
	-- Only the layout scheduler creates and positions segments. An unknown
	-- maximum cannot determine geometry and is displayed by the continuous bar.
	local count = maxNum and Utils.SafeCompare(maxNum, math.floor(maxNum), "==") and maxNum or 0
	local width = playerClassBar:GetWidth()
	local height = playerClassBar:GetHeight()
	local segWidth = count > 0 and math.max(1, (width - (count - 1)) / count) or 0
	playerClassBar._segmentMax = count
	for i = 1, count do
		local seg = classSegments[i]
		if not seg then
			seg = CreateBar(playerClassBar, false)
			classSegments[i] = seg
		end
		seg:ClearAllPoints()
		seg:SetSize(segWidth, height)
		if i == 1 then
			seg:SetPoint("LEFT", playerClassBar, "LEFT", 0, 0)
		else
			seg:SetPoint("LEFT", classSegments[i - 1], "RIGHT", 1, 0)
		end
	end
	for i = count + 1, #classSegments do
		classSegments[i]:Hide()
	end
end

local function UpdateClassPower()
	if not playerClassBar then
		return false
	end
	local wasShown = playerClassBar:IsShown()
	if not RCFG.classEnabled then
		playerClassBar:Hide()
		return wasShown
	end
	local show, pType, maxNum, max = CanShowClassPower()
	if not show then
		playerClassBar:Hide()
		return wasShown
	end
	local cur, units, nativeMax = GetClassPowerValue(pType, maxNum, max)
	if not Utils.IsValueSecret(cur) and type(cur) ~= "number" then
		playerClassBar:Hide()
		return wasShown
	end

	local baseColor = ClassBarColors[pType]
	if pType == Enum.PowerType.Runes then
		baseColor = RuneSpecColors[Utils.GetSpecializationSafe()] or baseColor
	end
	local count = maxNum and Utils.SafeCompare(maxNum, math.floor(maxNum), "==") and maxNum or 0
	local layoutChanged = playerClassBar._segmentMax ~= count
	playerClassBar:Show()
	if count == 0 or layoutChanged then
		-- Never reuse a stale pip count. While a public capacity change awaits
		-- layout (including combat deferral), the existing native bar is accurate.
		for _, seg in ipairs(classSegments) do seg:Hide() end
		local bar = playerClassBar.continuous
		bar:SetMinMaxValues(0, nativeMax)
		bar:SetValue(cur)
		bar:SetStatusBarColor(baseColor.r, baseColor.g, baseColor.b)
		bar:Show()
		if layoutChanged then Resources:UpdateLayout() end
	else
		playerClassBar.continuous:Hide()
		for i = 1, count do
			local seg = classSegments[i]
			-- The native status bar clamps the same opaque current into each
			-- public interval. No Lua fill arithmetic or inferred fullness.
			seg:SetMinMaxValues((i - 1) * units, i * units)
			seg:SetValue(cur)
			seg:SetStatusBarColor(baseColor.r, baseColor.g, baseColor.b)
			seg:Show()
		end
	end
	return not wasShown
end

local function UpdateBarColor(bar, unit)
	if not bar or not UnitExistsSafe(unit) then
		return
	end

	local r, g, b = Utils.GetUnitColor(unit, bar.type, 0.85)
	bar:SetStatusBarColor(r, g, b)
end

local function SafeSetMinMax(targetBar, minVal, maxVal)
	if Utils.IsValueSecret(maxVal) then
		-- Keep the native range in the same units as the raw current value.
		-- Opaque maxima cannot be normalized or compared with cached ranges.
		targetBar._safeMin = nil
		targetBar._safeMax = nil
		targetBar:SetMinMaxValues(minVal, maxVal)
		return
	end
	local normalizedMax = 1
	local numMax = tonumber(maxVal)
	if numMax and numMax > 0 then
		normalizedMax = numMax
	end
	if targetBar._safeMin ~= minVal or targetBar._safeMax ~= normalizedMax then
		targetBar._safeMin = minVal
		targetBar._safeMax = normalizedMax
		targetBar:SetMinMaxValues(minVal, normalizedMax)
	end
end

local function GetRawUnitAbsorb(unit)
	if not UnitGetTotalAbsorbs then
		return 0
	end
	local value = UnitGetTotalAbsorbs(unit)
	if type(value) == "nil" then
		return 0
	end
	return value
end

local function IsActive(value)
	if type(value) == "nil" then
		return false
	end
	if Utils.IsValueSecret(value) then
		return true
	end
	return type(value) == "number" and value > 0
end

local function SetPredictionAnchor(bar, anchoredToValue)
	local prediction = bar.predict
	local mode = anchoredToValue and "value" or "bar"
	if prediction._anchorMode == mode then
		if anchoredToValue then
			local width = bar:GetWidth()
			if prediction._barWidth ~= width then
				prediction._barWidth = width
				prediction:SetWidth(width)
			end
		end
		return true
	end

	prediction._anchorMode = mode
	prediction:ClearAllPoints()
	if anchoredToValue then
		local texture = bar:GetStatusBarTexture()
		if texture then
			prediction:SetPoint("TOPLEFT", texture, "TOPRIGHT")
			prediction:SetPoint("BOTTOMLEFT", texture, "BOTTOMRIGHT")
			local width = bar:GetWidth()
			prediction._barWidth = width
			prediction:SetWidth(width)
			return true
		end
		return false
	end
	prediction:SetAllPoints()
	return true
end

local function SafeDebugValue(value)
	if Utils.IsValueSecret(value) then
		return "<secret>"
	end
	return tostring(value)
end

local function UpdateBarValue(bar, unit)
	if not bar or not UnitExistsSafe(unit) then
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
		max = UnitHealthMax(unit) -- @scan-ignore: midnight-passthrough
	else
		cur = UnitPower(unit) -- @scan-ignore: midnight-passthrough
		max = UnitPowerMax(unit) -- @scan-ignore: midnight-passthrough
	end

	-- PASSTHROUGH: Update the main bar value FIRST.
	-- StatusBars in 12.0 handle secret values correctly.
	-- Doing this first ensures basic health/power display works even if prediction fails.
	local bMax = max
	if type(bMax) == "nil" then
		bMax = 1
	end
	local bVal = cur
	if type(bVal) == "nil" then
		bVal = 0
	end

	SafeSetMinMax(bar, 0, bMax)
	bar:SetValue(bVal)

	-- Update Predict/Absorb for health bars
	if bar.type == "HEALTH" and (RCFG.showPredict or RCFG.showAbsorbs) then
		local incomingHeals, _, _, _, calcAbsorb = Utils.GetUnitHealsSafe(unit, healCalculator)

		local unitAbsorb = GetRawUnitAbsorb(unit)

		-- 1. Heal Prediction (Incoming Heals)
		if RCFG.showPredict and IsActive(incomingHeals) then
			SafeSetMinMax(bar.predict, 0, max)
			if Utils.IsValueSecret(cur) then
				-- Royal: Anchor to current health texture and fill to the right
				if SetPredictionAnchor(bar, true) then
					bar.predict:SetValue(incomingHeals)
					bar.predict:Show()
				end
			else
				-- Legacy: Stack but cap at max
				SetPredictionAnchor(bar, false)
				if
					not Utils.IsValueSecret(cur)
					and not Utils.IsValueSecret(incomingHeals)
					and not Utils.IsValueSecret(max)
					and type(cur) == "number"
					and type(incomingHeals) == "number"
					and type(max) == "number"
				then
					bar.predict:SetValue(math.min(max, cur + incomingHeals))
				else
					-- If secret, just pass the prediction value directly.
					-- Without knowing 'cur', we can't reliably stack it, so we anchor it.
					if SetPredictionAnchor(bar, true) then
						bar.predict:SetValue(incomingHeals)
					else
						bar.predict:SetValue(incomingHeals)
					end
				end
				bar.predict:Show()
			end
		else
			bar.predict:Hide()
		end

		-- 2. Absorbs (Shields) - Reverse Fill from Right
		if RCFG.showAbsorbs and (IsActive(calcAbsorb) or IsActive(unitAbsorb)) then
			SafeSetMinMax(bar.absorb, 0, max)

			-- Prefer secret value for pass-through, or max of numbers
			local absorbValue
			if Utils.IsValueSecret(calcAbsorb) then
				absorbValue = calcAbsorb
			elseif Utils.IsValueSecret(unitAbsorb) then
				absorbValue = unitAbsorb
			else
				local calcNum = 0
				local unitNum = 0
				if not Utils.IsValueSecret(calcAbsorb) then
					calcNum = tonumber(calcAbsorb) or 0
				end
				if not Utils.IsValueSecret(unitAbsorb) then
					unitNum = tonumber(unitAbsorb) or 0
				end
				absorbValue = math.max(calcNum, unitNum)
			end

			bar.absorb:SetValue(absorbValue)
			bar.absorb:Show()
		else
			bar.absorb:Hide()
		end

		-- Debug logging (Safe)
		if addon.db.profile.debugResources then
			pcall(function()
				addon:Log(
					string.format(
						"Resources: %s Health update: cur=%s max=%s predict=%s absorb=%s",
						unit,
						SafeDebugValue(cur),
						SafeDebugValue(max),
						SafeDebugValue(incomingHeals),
						SafeDebugValue(IsActive(calcAbsorb) and calcAbsorb or unitAbsorb)
					),
					"resources"
				)
			end)
		end
	end
end

function Resources:OnInitialize()
	self.db = addon.db
end

function Resources:CreateFrames()
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

		playerHealth = CreateBar(playerGroup, true)
		playerHealth.type = "HEALTH"
		playerHealth:SetClipsChildren(true)
		playerPower = CreateBar(playerGroup, false)
		playerPower.type = "POWER"

		playerClassBar = CreateFrame("Frame", nil, playerGroup)
		playerClassBar.continuous = CreateBar(playerClassBar, false)
		playerClassBar.continuous:SetAllPoints()
		playerClassBar.continuous:Hide()

		targetHealth = CreateBar(targetGroup, true)
		targetHealth.type = "HEALTH"
		targetHealth:SetClipsChildren(true)
		targetPower = CreateBar(targetGroup, false)
		targetPower.type = "POWER"
	end

end

function Resources:OnEnable()
	self:ApplyEnabledState()
end

function Resources:RegisterRuntimeEvents()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnEvent")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "UpdateCombatVisibility")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateCombatVisibility")
	for _, event in ipairs({
		"UNIT_HEALTH",
		"UNIT_MAXHEALTH",
		"UNIT_HEAL_PREDICTION",
		"UNIT_ABSORB_AMOUNT_CHANGED",
		"UNIT_POWER_UPDATE",
		"UNIT_DISPLAYPOWER",
		"UNIT_MAXPOWER",
	}) do
		ns.UnitEventRouter:Register(self, event, "OnEvent", "player", "target")
	end
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnEvent")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnEvent")
	self:RegisterEvent("RUNE_POWER_UPDATE", "OnEvent")
end

function Resources:StartRuntime()
	if self._runtimeActive then self:UpdateLayout(); return end
	self:CreateFrames()
	if not container then return end
	self._runtimeActive = true
	self:RegisterRuntimeEvents()
	self:UpdateLayout()
end

function Resources:OnDisable()
	self._pendingEnabledState = nil
	self:StopRuntime()
end

function Resources:StopRuntime()
	self._runtimeActive = false
	RCFG.enabled = false
	self:UnregisterAllEvents()
	if ns.UnitEventRouter then
		ns.UnitEventRouter:UnregisterAll(self)
	end
	if container then
		container:Hide()
	end
	self:UpdateLayout()
end

function Resources:ApplyEnabledState()
	self._desiredEnabled = self.db.profile.resEnabled == true
	if InCombatLockdown() then
		self._pendingEnabledState = true
		self:UpdateLayout()
		return
	end
	self._pendingEnabledState = nil
	if self:IsEnabled() and self._desiredEnabled then self:StartRuntime() else self:StopRuntime() end
end

-- Show or hide resource bars based on combat state and resHideOutOfCombat setting
function Resources:UpdateCombatVisibility(event)
	if not container or not RCFG.enabled then
		return
	end
	local p = addon.db.profile
	if not p.resHideOutOfCombat then
		container:SetAlpha(1)
		return
	end
	-- Use the event name directly to avoid InCombatLockdown() timing issues
	if event == "PLAYER_REGEN_DISABLED" then
		container:SetAlpha(1)
	elseif event == "PLAYER_REGEN_ENABLED" then
		container:SetAlpha(0)
	else
		-- Manual call (settings change, PLAYER_ENTERING_WORLD, etc.)
		if InCombatLockdown() then
			container:SetAlpha(1)
		else
			container:SetAlpha(0)
		end
	end
end

function Resources:OnEvent(event, unit)
	if not self._runtimeActive or not RCFG.enabled then
		return
	end
	local perfStart = ns.RecordPerformance and debugprofilestop()
	-- addon:Log(string.format("Resources: %s (unit=%s)", event, tostring(unit)), "events") -- Disabled: too verbose

	if event == "PLAYER_ENTERING_WORLD" then
		UpdateClassPower()
		self:UpdateLayout()
	elseif event == "PLAYER_TARGET_CHANGED" then
		self:UpdateLayout()
		UpdateBarColor(targetHealth, "target")
		UpdateBarColor(targetPower, "target")
		UpdateBarValue(targetHealth, "target")
		UpdateBarValue(targetPower, "target")
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		if unit == "player" then
			UpdateBarValue(playerHealth, "player")
		end
		if unit == "target" then
			UpdateBarValue(targetHealth, "target")
		end
	elseif event == "UNIT_POWER_UPDATE" then
		if unit == "player" then
			UpdateBarValue(playerPower, "player")
			if UpdateClassPower() then
				self:UpdateLayout()
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
			self:UpdateLayout()
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
	elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_SPECIALIZATION_CHANGED" then
		UpdateClassPower()
		self:UpdateLayout()
	elseif event == "RUNE_POWER_UPDATE" then
		UpdateClassPower()
	end
	if perfStart then
		ns.RecordPerformance("ResourcesUpdate", perfStart)
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
	end

	return totalHeight
end

-- Get the width of this module for LayoutManager
function Resources:GetLayoutWidth()
	local p = addon.db.profile
	if p.resBarWidth and p.resBarWidth > 0 then
		return p.resBarWidth
	end
	local AB = addon:GetModule("ActionBars", true)
	return AB and AB.GetLayoutWidth and AB:GetLayoutWidth() or 120
end

-- Apply position from LayoutManager
function Resources:ApplyLayoutPosition()
	if not container then
		return
	end
	if not RCFG.enabled or self:CalculateHeight() <= 0 then
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
		-- Stack mode: use ActionBars width for tight fit, anchor based on alignment
		local containerWidth = self:GetLayoutWidth()
		local containerHeight = self:CalculateHeight()
		if containerWidth > 0 and containerHeight > 0 then
			container:SetSize(containerWidth, containerHeight)
		end
		local yOffset = LM:GetModulePosition("resources")

		-- Anchor based on alignment within HUD
		local p = addon.db.profile
		local align = p.resourcesAlignment or "CENTER"
		if align == "LEFT" then
			container:SetPoint("TOPLEFT", main, "TOPLEFT", 0, yOffset)
		elseif align == "RIGHT" then
			container:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, yOffset)
		else -- CENTER
			container:SetPoint("TOP", main, "TOP", 0, yOffset)
		end
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

	addon:Logf("layout", "Resources positioned: inStack=%s", inStack and "true" or "false")
end

function Resources:PrepareLayout()
	if not container or not addon then
		return
	end

	local db = addon.db.profile

	-- Debug Container Visual
	addon:UpdateLayoutOutline(container, "Resource Bars", "resources")

	RCFG.enabled = self._runtimeActive == true and db.resEnabled == true
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
		return
	end

	local hasClassBar, _, maxClassPower = CanShowClassPower()
	local showClass = RCFG.classEnabled and hasClassBar

	-- Calculate total height based on enabled bars
	local totalHeight = self:CalculateHeight()

	if totalHeight <= 0 then
		container:Hide()
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
	local hudWidth = self:GetLayoutWidth()

	container:SetSize(hudWidth, totalHeight)

	local useSplit = false
	if RCFG.showTarget and UnitExistsSafe("target") then
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
		PrepareClassPower(maxClassPower)
	else
		playerClassBar:Hide()
	end
end

function Resources:GetContainer()
	return container
end

function Resources:UpdateLayout()
	local manager = addon:GetModule("LayoutManager", true)
	if manager then manager:RequestLayout("resources") end
end

function Resources:RenderLayout()
	UpdateBarColor(playerHealth, "player")
	UpdateBarColor(playerPower, "player")
	UpdateBarValue(playerHealth, "player")
	UpdateBarValue(playerPower, "player")
	UpdateBarColor(targetHealth, "target")
	UpdateBarColor(targetPower, "target")
	UpdateBarValue(targetHealth, "target")
	UpdateBarValue(targetPower, "target")
	UpdateClassPower()
	self:UpdateCombatVisibility()
end
