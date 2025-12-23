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

local Utils = ns.Utils

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
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.5)

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

local function CanShowClassPower()
	local pType = GetClassPowerType()
	if not pType then
		return false, nil, 0
	end

	local max = UnitPowerMax("player", pType)
	local cur
	if pType == Enum.PowerType.Runes then
		cur = GetReadyRuneCount()
	else
		cur = UnitPower("player", pType, true) -- @scan-ignore: midnight-passthrough
	end

	-- Handle Midnight secret values
	local maxIsSecret = Utils.IsValueSecret(max)
	local curIsSecret = Utils.IsValueSecret(cur)

	if maxIsSecret or curIsSecret then
		return true, pType, maxIsSecret and 5 or max
	end

	local maxNum = tonumber(max)
	local curNum = tonumber(cur)

	if not maxNum or maxNum <= 0 then
		return false, pType, 0
	end
	if not curNum or curNum <= 0 then
		return false, pType, 0
	end

	return true, pType, max
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

	local cur
	if pType == Enum.PowerType.Runes then
		cur = GetReadyRuneCount()
	else
		cur = UnitPower("player", pType, true) -- @scan-ignore: midnight-passthrough
	end
	local curIsSecret = Utils.IsValueSecret(cur)

	playerClassBar:Show()

	-- Ensure segments exist
	for i = 1, max do
		if not classSegments[i] then
			local f = playerClassBar:CreateTexture(nil, "ARTWORK")
			f:SetTexture("Interface\\Buttons\\WHITE8x8")
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
		-- Fallback to container width if bar hasn't been sized yet
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

		-- Color / Alpha - handle Midnight secret values
		if curIsSecret then
			seg:SetAlpha(0.6)
			local c = baseColor
			if c then
				seg:SetColorTexture(c.r * 0.8, c.g * 0.8, c.b * 0.8)
			else
				seg:SetColorTexture(0.8, 0.8, 0)
			end
		elseif i <= cur then
			seg:SetAlpha(1)
			local c = baseColor
			if c then
				seg:SetColorTexture(c.r, c.g, c.b)
			else
				seg:SetColorTexture(1, 1, 0)
			end
		else
			seg:SetAlpha(0.3)
			local c = baseColor
			if c then
				seg:SetColorTexture(c.r * 0.5, c.g * 0.5, c.b * 0.5)
			else
				seg:SetColorTexture(0.5, 0.5, 0.5)
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

	-- Passthrough: StatusBars in 12.0 handle secret values correctly
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
end

function Resources:OnInitialize()
	self.db = addon.db
end

function Resources:OnEnable()
	main = _G["ActionHudFrame"]
	if not main then
		return
	end

	if not container then
		container = CreateFrame("Frame", "ActionHudResources", main)
		playerGroup = CreateFrame("Frame", nil, container)
		targetGroup = CreateFrame("Frame", nil, container)

		playerHealth = CreateBar(playerGroup)
		playerHealth.type = "HEALTH"
		playerPower = CreateBar(playerGroup)
		playerPower.type = "POWER"

		playerClassBar = CreateFrame("Frame", nil, playerGroup)

		targetHealth = CreateBar(targetGroup)
		targetHealth.type = "HEALTH"
		targetPower = CreateBar(targetGroup)
		targetPower.type = "POWER"
	end

	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnEvent")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")
	self:RegisterEvent("UNIT_HEALTH", "OnEvent")
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
	elseif event == "UNIT_HEALTH" then
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

	local yOffset = LM:GetModulePosition("resources")
	container:ClearAllPoints()
	-- Center horizontally within main frame
	container:SetPoint("TOP", main, "TOP", 0, yOffset)
	container:Show()

	UpdateClassPower()

	addon:Log(string.format("Resources positioned: yOffset=%d", yOffset), "layout")
end

function Resources:UpdateLayout()
	if not container or not addon then
		return
	end

	local db = addon.db.profile

	-- Debug Container Visual
	addon:UpdateFrameDebug(container, { r = 1, g = 0, b = 0 }) -- Red for Resources
	addon:UpdateLayoutOutline(container, "Resource Bars")

	RCFG.enabled = db.resEnabled == true
	RCFG.healthEnabled = db.resHealthEnabled ~= false
	RCFG.powerEnabled = db.resPowerEnabled ~= false
	RCFG.classEnabled = db.resClassEnabled ~= false
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

	-- Get width from ActionBars
	local AB = addon:GetModule("ActionBars", true)
	local hudWidth = 120
	if AB and AB.GetLayoutWidth then
		hudWidth = AB:GetLayoutWidth()
	end

	container:SetSize(hudWidth, totalHeight)

	-- Report height to LayoutManager
	local LM = addon:GetModule("LayoutManager", true)
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
