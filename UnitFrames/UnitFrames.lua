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
	bar:SetStatusBarColor(0.5, 0.5, 0.5, 1) -- Neutral gray default, will be colored in UpdateFrameValues
	-- Disable mouse so clicks pass through to parent SecureUnitButton
	bar:EnableMouse(false)

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
	bar.predict:EnableMouse(false)
	bar.predict:Hide() -- Hidden by default, shown when heal prediction is active

	-- Absorb Overlay
	bar.absorb = CreateFrame("StatusBar", nil, bar)
	bar.absorb:SetAllPoints()
	bar.absorb:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar.absorb:SetStatusBarColor(0, 0.8, 1, 0.6)
	bar.absorb:SetFrameLevel(bar:GetFrameLevel() + 2)
	bar.absorb:EnableMouse(false)
	bar.absorb:Hide() -- Hidden by default, shown when absorb shield is present
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
	-- Use OVERLAY with sublevel 7 to ensure icons appear above status bars
	local tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	tex:SetSize(16, 16) -- Default size
	tex:Hide() -- Start hidden
	return tex
end

local function ApplyTextStyle(fontString, config, unit, frameFont)
	if not fontString or not config then
		return
	end

	-- Use frame-level font if set, otherwise fall back to element config, then default
	local fontName = frameFont or config.font or "Arial Narrow"
	local fontPath = LSM:Fetch("font", fontName) or "Fonts\\ARIALN.TTF"
	local fontSize = config.size or config.fontSize or 11 -- Default to 11
	local outline = config.outline or config.fontOutline or "NONE"
	fontString:SetFont(fontPath, fontSize, outline ~= "NONE" and outline or nil)

	-- Default to white
	local r, g, b = 1, 1, 1
	if config.colorMode == "custom" and config.color then
		r, g, b = config.color.r or 1, config.color.g or 1, config.color.b or 1
	elseif config.colorMode == "class" then
		local _, class = UnitClass(unit)
		local classColor = class and RAID_CLASS_COLORS[class]
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

	-- Apply hide Blizzard frames setting
	self:ApplyBlizzardFrameVisibility()
end

function UnitFrames:ApplyBlizzardFrameVisibility()
	local hide = self.db.profile.ufHideBlizzard
	if hide then
		if PlayerFrame then
			PlayerFrame:SetAlpha(0)
			PlayerFrame:EnableMouse(false)
		end
		if TargetFrame then
			TargetFrame:SetAlpha(0)
			TargetFrame:EnableMouse(false)
		end
		if FocusFrame then
			FocusFrame:SetAlpha(0)
			FocusFrame:EnableMouse(false)
		end
	else
		if PlayerFrame then
			PlayerFrame:SetAlpha(1)
			PlayerFrame:EnableMouse(true)
		end
		if TargetFrame then
			TargetFrame:SetAlpha(1)
			TargetFrame:EnableMouse(true)
		end
		if FocusFrame then
			FocusFrame:SetAlpha(1)
			FocusFrame:EnableMouse(true)
		end
	end
end

function UnitFrames:CreateFrames()
	local main = _G["ActionHudFrame"]
	if not main then
		return
	end

	local DraggableContainer = ns.DraggableContainer

	local units = {
		player = { unit = "player", moduleId = "ufPlayer", defaultX = -200, defaultY = 50 },
		target = { unit = "target", moduleId = "ufTarget", defaultX = 200, defaultY = 50 },
		focus = { unit = "focus", moduleId = "ufFocus", defaultX = 200, defaultY = -50 },
	}

	self.containers = self.containers or {}

	for frameId, config in pairs(units) do
		local unit = config.unit
		local db = self.db.profile.ufConfig[frameId]
		if not db then
			return
		end

		-- Create draggable container anchored to HUD
		local container
		if DraggableContainer then
			container = DraggableContainer:Create({
				moduleId = config.moduleId,
				parent = main,
				db = self.db,
				xKey = "uf" .. frameId:sub(1, 1):upper() .. frameId:sub(2) .. "XOffset",
				yKey = "uf" .. frameId:sub(1, 1):upper() .. frameId:sub(2) .. "YOffset",
				defaultX = config.defaultX,
				defaultY = config.defaultY,
				size = { width = db.width or 180, height = db.height or 40 },
			})
		end

		-- Fallback if DraggableContainer not available
		if not container then
			container = CreateFrame("Frame", "ActionHudUnitFrame_Container_" .. frameId, main)
		end

		self.containers[frameId] = container

		-- Use SecureUnitButtonTemplate for right-click menu and targeting support
		local f = CreateFrame(
			"Button",
			"ActionHudUnitFrame_" .. frameId,
			container,
			"SecureUnitButtonTemplate,BackdropTemplate"
		)
		f:SetAllPoints(container) -- Fill container
		f.unit = unit
		f.unitId = frameId
		f.container = container

		-- Set up secure unit attributes for targeting and menus
		f:SetAttribute("unit", unit)
		f:SetAttribute("type1", "target") -- Left click = target
		f:SetAttribute("type2", "togglemenu") -- Right click = context menu
		f:RegisterForClicks("AnyUp")

		-- Register unit watch for auto show/hide (target/focus only - player always exists)
		if unit ~= "player" then
			RegisterUnitWatch(f)
			-- Also register on container so it hides when no unit exists
			container:SetAttribute("unit", unit)
			RegisterUnitWatch(container)
		end

		-- Tooltip support
		f:SetScript("OnEnter", function(self)
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			if UnitExists(self.unit) then
				GameTooltip:SetUnit(self.unit)
				GameTooltip:Show()
			end
		end)
		f:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		-- Background
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetAllPoints()

		-- Border (using Backdrop)
		f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
		f.border:SetAllPoints()
		f.border:EnableMouse(false)

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

		-- Icon Overlay Frame (sits above everything)
		f.iconOverlay = CreateFrame("Frame", nil, f)
		f.iconOverlay:SetAllPoints(f)
		f.iconOverlay:SetFrameLevel(f:GetFrameLevel() + 10)

		-- Icons (created on high-level overlay frame)
		f.icons = {
			combat = CreateIcon(f.iconOverlay, "Combat"),
			resting = CreateIcon(f.iconOverlay, "Resting"),
			pvp = CreateIcon(f.iconOverlay, "PVP"),
			leader = CreateIcon(f.iconOverlay, "Leader"),
			role = CreateIcon(f.iconOverlay, "Role"),
			guide = CreateIcon(f.iconOverlay, "Guide"),
			mainTank = CreateIcon(f.iconOverlay, "MainTank"),
			mainAssist = CreateIcon(f.iconOverlay, "MainAssist"),
			vehicle = CreateIcon(f.iconOverlay, "Vehicle"),
			phased = CreateIcon(f.iconOverlay, "Phased"),
			summon = CreateIcon(f.iconOverlay, "Summon"),
			readyCheck = CreateIcon(f.iconOverlay, "ReadyCheck"),
		}

		self.frames[frameId] = f
	end
	self:UpdateLayout()
end

function UnitFrames:UpdateLayout()
	local DraggableContainer = ns.DraggableContainer

	if not self.db.profile.ufEnabled then
		-- Can't modify secure frames during combat
		if not InCombatLockdown() then
			for frameId, f in pairs(self.frames) do
				-- Unregister unit watch so it doesn't auto-show when unit exists (target/focus only)
				if frameId ~= "player" then
					UnregisterUnitWatch(f)
				end
				local container = self.containers and self.containers[frameId]
				if container then
					if frameId ~= "player" then
						UnregisterUnitWatch(container)
					end
					container:Hide()
				end
				f:Hide()
			end
		end
		return
	end

	for frameId, f in pairs(self.frames) do
		local db = self.db.profile.ufConfig[frameId]
		if not db then
			return
		end

		local container = self.containers and self.containers[frameId]

		if not db.enabled then
			-- Unregister unit watch for individual frame disable
			if frameId ~= "player" then
				UnregisterUnitWatch(f)
				if container then
					UnregisterUnitWatch(container)
				end
			end
			f:Hide()
			if container then
				container:Hide()
			end
		else
			-- Re-register unit watch for target/focus frames
			if frameId ~= "player" then
				-- Ensure unit attribute is set
				f:SetAttribute("unit", f.unit)
				RegisterUnitWatch(f)
				if container then
					container:SetAttribute("unit", f.unit)
					RegisterUnitWatch(container)
				end
			end

			-- Update container size and position
			if container then
				container:SetSize(db.width, db.height)
				if DraggableContainer then
					DraggableContainer:UpdatePosition(container)
					DraggableContainer:UpdateOverlay(container)

					-- Toggle unit frame mouse based on lock state
					-- When unlocked: disable mouse so container can be dragged
					-- When locked: enable mouse for right-click menus and targeting
					local isUnlocked = DraggableContainer:IsUnlocked(self.db)
					f:EnableMouse(not isUnlocked)
				end
				-- Only manually show player container (unit watch handles target/focus)
				if frameId == "player" then
					container:Show()
				end
			end

			-- Only manually show player frame (unit watch handles target/focus)
			if frameId == "player" then
				f:Show()
			end

			-- Visuals
			f.bg:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgOpacity)

			-- Border extends OUTSIDE the frame
			local borderInset = db.borderSize or 1
			f.border:ClearAllPoints()
			f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -borderInset, borderInset)
			f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", borderInset, -borderInset)
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

			-- Class bar: only reserve space if enabled AND class actually has a secondary resource
			local cH = 0
			if frameId == "player" and db.classBarEnabled then
				local _, powerToken = UnitPowerType("player")
				-- Only show class bar for classes with secondary resources (not mana/rage/focus/energy)
				if
					powerToken
					and powerToken ~= "MANA"
					and powerToken ~= "RAGE"
					and powerToken ~= "FOCUS"
					and powerToken ~= "ENERGY"
				then
					cH = db.classBarHeight or 0
				end
			end

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
						ApplyTextStyle(element.fontString, config, f.unit, db.font)
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
		-- Can't modify secure frames during combat
		if not InCombatLockdown() then
			f:Hide()
		end
		return
	end

	local db = self.db.profile.ufConfig[f.unitId]
	if not db or not db.enabled then
		if not InCombatLockdown() then
			f:Hide()
		end
		return
	end
	if not InCombatLockdown() then
		f:Show()
	end

	-- 1. Health Bar (Native Passthrough)
	local curH = UnitHealth(unit) -- @scan-ignore: midnight-friendly-unit
	local maxH = UnitHealthMax(unit) -- @scan-ignore: midnight-friendly-unit
	f.health:SetMinMaxValues(0, Pass(maxH, 1))
	f.health:SetValue(Pass(curH, 0))

	-- Health bar color: lower saturation (0.85) to match Resources module
	local r, g, b = Utils.GetUnitColor(unit, "HEALTH", 0.85)
	f.health:SetStatusBarColor(r, g, b)

	-- 2. Power Bar
	local curP = UnitPower(unit) -- @scan-ignore: midnight-friendly-unit
	local maxP = UnitPowerMax(unit) -- @scan-ignore: midnight-friendly-unit
	f.power:SetMinMaxValues(0, Pass(maxP, 1))
	f.power:SetValue(Pass(curP, 0))

	-- Power bar color based on power type (using lower saturation 0.85 to match Resources)
	local powerR, powerG, powerB = Utils.GetUnitColor(unit, "POWER", 0.85)
	f.power:SetStatusBarColor(powerR, powerG, powerB)

	-- Visibility logic for Power + Dynamic Height Adjustment
	local showPower = false
	local hasPower = false
	if db.powerBarEnabled then
		if
			Utils.IsValueSecret(curP)
			or Utils.IsValueSecret(maxP)
			or type(curP) ~= "number"
			or type(maxP) ~= "number"
		then
			-- If either is secret, we must show the bar (since we can't compare)
			showPower = true
			hasPower = true
		else
			showPower = maxP > 0
			hasPower = maxP > 0
		end
	end
	f.power:SetShown(showPower)

	-- Dynamic height adjustment: collapse power bar space when unit has no power
	local powerHeight = (db.powerBarEnabled and hasPower) and db.powerBarHeight or 0
	local classHeight = 0
	if f.unitId == "player" and db.classBarEnabled then
		local _, powerToken = UnitPowerType("player")
		if
			powerToken
			and powerToken ~= "MANA"
			and powerToken ~= "RAGE"
			and powerToken ~= "FOCUS"
			and powerToken ~= "ENERGY"
		then
			classHeight = db.classBarHeight or 0
		end
	end

	-- Calculate actual frame height based on visible bars
	local actualFrameHeight = db.height
	-- Subtract power bar height if no power
	if not hasPower and db.powerBarEnabled then
		actualFrameHeight = actualFrameHeight - db.powerBarHeight
	end
	if actualFrameHeight < 1 then
		actualFrameHeight = 1
	end

	local healthHeight = actualFrameHeight - powerHeight - classHeight
	if healthHeight < 1 then
		healthHeight = 1
	end

	-- Resize the frame and container (only outside combat)
	if not InCombatLockdown() then
		f:SetHeight(actualFrameHeight)
		-- Also resize the container if it exists
		local container = self.containers and self.containers[f.unitId]
		if container then
			container:SetHeight(actualFrameHeight)
		end
	end

	-- Apply dynamic heights and re-anchor
	f.health:ClearAllPoints()
	f.health:SetPoint("TOPLEFT", f, "TOPLEFT")
	f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT")
	f.health:SetHeight(healthHeight)

	f.power:ClearAllPoints()
	f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT")
	f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT")
	f.power:SetHeight(powerHeight)

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
	-- Get absorbs directly like DandersFrames does (StatusBar handles secrets natively)
	local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) -- @scan-ignore: midnight-friendly-unit

	-- Show absorb bar if we have any absorb value (use pcall to handle secret comparison)
	local showAbsorb = false
	if absorbs ~= nil then
		-- Safe comparison: if pcall fails (secret value), assume active and show bar
		local ok, isZero = pcall(function()
			return absorbs == 0
		end)
		if not ok or not isZero then
			showAbsorb = true
		end
	end

	if showAbsorb then
		f.health.absorb:SetMinMaxValues(0, Pass(maxH, 1))
		f.health.absorb:SetValue(absorbs)
		f.health.absorb:Show()
	else
		f.health.absorb:Hide()
	end

	-- Heal Prediction (only for incoming heals, not absorbs)
	local incomingHeals = 0
	if UnitGetIncomingHeals then
		incomingHeals = UnitGetIncomingHeals(unit) or 0 -- @scan-ignore: midnight-friendly-unit
	end

	if type(incomingHeals) == "number" and not Utils.IsValueSecret(incomingHeals) and incomingHeals > 0 then
		if type(curH) == "number" and not Utils.IsValueSecret(curH) and type(maxH) == "number" then
			f.health.predict:SetMinMaxValues(0, Pass(maxH, 1))
			f.health.predict:SetValue(curH + incomingHeals)
		end
		f.health.predict:Show()
	else
		f.health.predict:Hide()
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

	-- Percent display is disabled due to Midnight secret value issues
	-- Keeping values only for now
	if f.healthElements.percent then
		f.healthElements.percent.fontString:SetText("")
		f.healthElements.percent.fontString:Hide()
	end

	-- Power Text
	local _, powerToken = UnitPowerType(unit)
	local displayP = UnitPower(unit, nil, true) -- @scan-ignore: midnight-friendly-unit
	local displayMaxP = UnitPowerMax(unit, nil, true) -- @scan-ignore: midnight-friendly-unit

	if db.powerText.value.enabled and f.powerElements.value then
		local pStr = FormatValue(displayP)
		local pmStr = FormatValue(displayMaxP)
		pcall(function()
			f.powerElements.value.fontString:SetFormattedText("%s/%s", pStr, pmStr)
		end)
	end

	-- Percent display is disabled due to Midnight secret value issues
	-- Keeping values only for now
	if f.powerElements.percent then
		f.powerElements.percent.fontString:SetText("")
		f.powerElements.percent.fontString:Hide()
	end

	-- 6. Status Icons
	local showAllIcons = self.db.profile.ufShowAllIcons or false
	for iconId, tex in pairs(f.icons) do
		local config = db.icons and db.icons[iconId]
		if config and config.enabled then
			local show = showAllIcons
			local atlas = nil
			local texture = nil

			-- Check each icon type's condition
			if iconId == "combat" then
				show = show or UnitAffectingCombat(unit)
				texture = "Interface\\CharacterFrame\\UI-StateIcon" -- Combat swords
				tex:SetTexCoord(0.5, 1.0, 0, 0.49) -- Top-right quadrant (combat icon)
			elseif iconId == "resting" then
				show = show or (unit == "player" and IsResting())
				texture = "Interface\\CharacterFrame\\UI-StateIcon" -- Resting ZZZ
				tex:SetTexCoord(0, 0.5, 0, 0.49) -- Top-left quadrant (resting icon)
			elseif iconId == "pvp" then
				show = show or UnitIsPVP(unit)
				local faction = UnitFactionGroup(unit)
				if faction == "Horde" then
					texture = "Interface\\PVPFrame\\PVP-Currency-Horde"
				else
					texture = "Interface\\PVPFrame\\PVP-Currency-Alliance"
				end
			elseif iconId == "leader" then
				show = show or UnitIsGroupLeader(unit)
				texture = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
			elseif iconId == "role" then
				local role = UnitGroupRolesAssigned(unit)
				texture = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
				if role == "TANK" then
					show = true
					tex:SetTexCoord(0, 0.3, 0.3, 0.65) -- Tank
				elseif role == "HEALER" then
					show = true
					tex:SetTexCoord(0.3, 0.59375, 0, 0.3) -- Healer
				elseif role == "DAMAGER" then
					show = true
					tex:SetTexCoord(0.3, 0.59375, 0.3, 0.65) -- DPS
				else
					show = showAllIcons
					tex:SetTexCoord(0, 0.3, 0.3, 0.65) -- Tank as default
				end
			elseif iconId == "guide" then
				show = show or UnitIsGroupAssistant(unit)
				texture = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
			elseif iconId == "mainTank" then
				local role = GetPartyAssignment("MAINTANK", unit)
				show = show or role
				texture = "Interface\\GroupFrame\\UI-Group-MainTankIcon"
			elseif iconId == "mainAssist" then
				local role = GetPartyAssignment("MAINASSIST", unit)
				show = show or role
				texture = "Interface\\GroupFrame\\UI-Group-MainAssistIcon"
			elseif iconId == "vehicle" then
				show = show or UnitInVehicle(unit)
				texture = "Interface\\Vehicles\\UI-Vehicles-Raid-Icon"
			elseif iconId == "phased" then
				show = show or UnitPhaseReason(unit)
				texture = "Interface\\TargetingFrame\\UI-PhasingIcon"
			elseif iconId == "summon" then
				-- Check for incoming summon with different states
				if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
					local summonStatus = C_IncomingSummon.IncomingSummonStatus(unit)
					if summonStatus == Enum.SummonStatus.Pending then
						show = true
						texture = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
					elseif summonStatus == Enum.SummonStatus.Accepted then
						show = true
						texture = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted"
					elseif summonStatus == Enum.SummonStatus.Declined then
						show = true
						texture = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined"
					else
						show = showAllIcons
						texture = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
					end
				else
					-- Fallback for older API
					show = show
						or (
							C_IncomingSummon
							and C_IncomingSummon.HasIncomingSummon
							and C_IncomingSummon.HasIncomingSummon(unit)
						)
					texture = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
				end
			elseif iconId == "readyCheck" then
				local status = GetReadyCheckStatus(unit)
				if status == "ready" then
					show = true
					texture = "Interface\\RaidFrame\\ReadyCheck-Ready"
				elseif status == "notready" then
					show = true
					texture = "Interface\\RaidFrame\\ReadyCheck-NotReady"
				elseif status == "waiting" then
					show = true
					texture = "Interface\\RaidFrame\\ReadyCheck-Waiting"
				else
					show = showAllIcons
					texture = "Interface\\RaidFrame\\ReadyCheck-Ready"
				end
			end

			if show then
				tex:SetSize(config.size or 16, config.size or 16)
				-- Apply texture (prioritize texture path over atlas)
				if texture then
					tex:SetTexture(texture)
				elseif atlas then
					tex:SetAtlas(atlas)
				end

				-- Position based on config
				tex:ClearAllPoints()
				local pos = config.position or "TopLeft"
				local xOff = config.offsetX or 0
				local yOff = config.offsetY or 0
				local margin = db.iconMargin or 2

				if pos == "TopLeft" then
					tex:SetPoint("TOPLEFT", f, "TOPLEFT", margin + xOff, -margin + yOff)
				elseif pos == "TopCenter" then
					tex:SetPoint("TOP", f, "TOP", xOff, -margin + yOff)
				elseif pos == "TopRight" then
					tex:SetPoint("TOPRIGHT", f, "TOPRIGHT", -margin + xOff, -margin + yOff)
				elseif pos == "Left" then
					tex:SetPoint("LEFT", f, "LEFT", margin + xOff, yOff)
				elseif pos == "Center" then
					tex:SetPoint("CENTER", f, "CENTER", xOff, yOff)
				elseif pos == "Right" then
					tex:SetPoint("RIGHT", f, "RIGHT", -margin + xOff, yOff)
				elseif pos == "BottomLeft" then
					tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", margin + xOff, margin + yOff)
				elseif pos == "BottomCenter" then
					tex:SetPoint("BOTTOM", f, "BOTTOM", xOff, margin + yOff)
				elseif pos == "BottomRight" then
					tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -margin + xOff, margin + yOff)
				end

				tex:Show()
			else
				tex:Hide()
			end
		else
			tex:Hide()
		end
	end
end
