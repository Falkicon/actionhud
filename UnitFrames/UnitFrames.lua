-- UnitFrames.lua
-- Implements ActionHud's unit frames with Midnight compatibility

local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")
local Utils = ns.Utils

local UnitFrames = ActionHud:NewModule("UnitFrames", "AceEvent-3.0")

-- Unit identity APIs may return restricted values in 12.1 instances. Keep every
-- comparison, boolean conversion, and table lookup behind this guard. Exposing
-- the helper on the addon namespace also lets the focused Lua test exercise the
-- same resolver used in game.
local IdentitySafety = {}
ns.UnitFrameIdentitySafety = IdentitySafety

function IdentitySafety.Get(value)
	if Utils.IsValueSecret(value) then
		return nil, false
	end
	return value, true
end

function IdentitySafety.IsTruthy(value)
	local safeValue, isSafe = IdentitySafety.Get(value)
	if not isSafe then
		return false, false
	end
	return not not safeValue, true
end

local function PromoteIfTruthy(current, value)
	local active, isSafe = IdentitySafety.IsTruthy(value)
	if isSafe and active then
		return true
	end
	return current
end

local ICON_TEXCOORDS = {
	combat = { 0.5, 1.0, 0, 0.49 },
	resting = { 0, 0.5, 0, 0.49 },
	roleTank = { 0, 0.3, 0.3, 0.65 },
	roleHealer = { 0.3, 0.59375, 0, 0.3 },
	roleDamage = { 0.3, 0.59375, 0.3, 0.65 },
}

function IdentitySafety.HasSecondaryPower(unit)
	local _, rawPowerToken = UnitPowerType(unit)
	local powerToken, isSafe = IdentitySafety.Get(rawPowerToken)
	if not isSafe then
		return false, false
	end
	if powerToken == nil then
		return false, true
	end
	return powerToken ~= "MANA" and powerToken ~= "RAGE" and powerToken ~= "FOCUS" and powerToken ~= "ENERGY", true
end

function IdentitySafety.GetUnitColor(unit, barType, mult)
	mult = mult or 1
	if barType == "HEALTH" then
		local isPlayer, playerIdentityAvailable = IdentitySafety.IsTruthy(UnitIsPlayer(unit))
		if not playerIdentityAvailable then
			return 0.5 * mult, 0.5 * mult, 0.5 * mult
		end
		if isPlayer then
			local _, rawClass = UnitClass(unit)
			local class, classAvailable = IdentitySafety.Get(rawClass)
			if classAvailable and class ~= nil then
				local classColor = RAID_CLASS_COLORS[class]
				if classColor then
					return classColor.r * mult, classColor.g * mult, classColor.b * mult
				end
			end
			return 0, 0.8 * mult, 0
		end

		local isEnemy, enemyIdentityAvailable = IdentitySafety.IsTruthy(UnitIsEnemy("player", unit))
		if not enemyIdentityAvailable then
			return 0.5 * mult, 0.5 * mult, 0.5 * mult
		end
		if isEnemy then
			return 0.8 * mult, 0, 0
		end

		local isFriend, friendIdentityAvailable = IdentitySafety.IsTruthy(UnitIsFriend("player", unit))
		if not friendIdentityAvailable then
			return 0.5 * mult, 0.5 * mult, 0.5 * mult
		end
		if isFriend then
			return 0, 0.8 * mult, 0
		end
		return 0.8 * mult, 0.8 * mult, 0
	elseif barType == "POWER" or barType == "MANA" then
		local _, rawPowerToken, rawAltR, rawAltG, rawAltB = UnitPowerType(unit)
		local powerToken, tokenAvailable = IdentitySafety.Get(rawPowerToken)
		if tokenAvailable and powerToken ~= nil then
			local info = PowerBarColor[powerToken]
			if info then
				return info.r * mult, info.g * mult, info.b * mult
			end
		end

		local altR, altRAvailable = IdentitySafety.Get(rawAltR)
		local altG, altGAvailable = IdentitySafety.Get(rawAltG)
		local altB, altBAvailable = IdentitySafety.Get(rawAltB)
		if altRAvailable and altGAvailable and altBAvailable and altR ~= nil then
			return altR * mult, altG * mult, altB * mult
		end
		return 0, 0, 0.8 * mult
	end
	return 1, 1, 1
end

function IdentitySafety.GetStatusIconState(iconId, unit, showAllIcons)
	local show = showAllIcons == true
	local texture
	local texCoord

	if iconId == "combat" then
		show = PromoteIfTruthy(show, UnitAffectingCombat(unit))
		texture = "Interface\\CharacterFrame\\UI-StateIcon"
		texCoord = ICON_TEXCOORDS.combat
	elseif iconId == "resting" then
		if unit == "player" then
			show = PromoteIfTruthy(show, IsResting())
		end
		texture = "Interface\\CharacterFrame\\UI-StateIcon"
		texCoord = ICON_TEXCOORDS.resting
	elseif iconId == "pvp" then
		show = PromoteIfTruthy(show, UnitIsPVP(unit))
		local rawFaction = UnitFactionGroup(unit)
		local faction, factionAvailable = IdentitySafety.Get(rawFaction)
		if factionAvailable and faction == "Horde" then
			texture = "Interface\\PVPFrame\\PVP-Currency-Horde"
		else
			texture = "Interface\\PVPFrame\\PVP-Currency-Alliance"
		end
	elseif iconId == "leader" then
		show = PromoteIfTruthy(show, UnitIsGroupLeader(unit))
		texture = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
	elseif iconId == "role" then
		local rawRole = UnitGroupRolesAssigned(unit)
		local role, roleAvailable = IdentitySafety.Get(rawRole)
		texture = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
		if roleAvailable and role == "TANK" then
			show = true
			texCoord = ICON_TEXCOORDS.roleTank
		elseif roleAvailable and role == "HEALER" then
			show = true
			texCoord = ICON_TEXCOORDS.roleHealer
		elseif roleAvailable and role == "DAMAGER" then
			show = true
			texCoord = ICON_TEXCOORDS.roleDamage
		else
			texCoord = ICON_TEXCOORDS.roleTank
		end
	elseif iconId == "guide" then
		show = PromoteIfTruthy(show, UnitIsGroupAssistant(unit))
		texture = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
	elseif iconId == "mainTank" then
		show = PromoteIfTruthy(show, GetPartyAssignment("MAINTANK", unit))
		texture = "Interface\\GroupFrame\\UI-Group-MainTankIcon"
	elseif iconId == "mainAssist" then
		show = PromoteIfTruthy(show, GetPartyAssignment("MAINASSIST", unit))
		texture = "Interface\\GroupFrame\\UI-Group-MainAssistIcon"
	elseif iconId == "vehicle" then
		show = PromoteIfTruthy(show, UnitInVehicle(unit))
		texture = "Interface\\Vehicles\\UI-Vehicles-Raid-Icon"
	elseif iconId == "phased" then
		show = PromoteIfTruthy(show, UnitPhaseReason(unit))
		texture = "Interface\\TargetingFrame\\UI-PhasingIcon"
	elseif iconId == "summon" then
		texture = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
		if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
			local rawStatus = C_IncomingSummon.IncomingSummonStatus(unit)
			local status, statusAvailable = IdentitySafety.Get(rawStatus)
			if statusAvailable and status == Enum.SummonStatus.Pending then
				show = true
			elseif statusAvailable and status == Enum.SummonStatus.Accepted then
				show = true
				texture = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted"
			elseif statusAvailable and status == Enum.SummonStatus.Declined then
				show = true
				texture = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined"
			end
		elseif C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then
			show = PromoteIfTruthy(show, C_IncomingSummon.HasIncomingSummon(unit))
		end
	elseif iconId == "readyCheck" then
		local rawStatus = GetReadyCheckStatus(unit)
		local status, statusAvailable = IdentitySafety.Get(rawStatus)
		texture = "Interface\\RaidFrame\\ReadyCheck-Ready"
		if statusAvailable and status == "ready" then
			show = true
		elseif statusAvailable and status == "notready" then
			show = true
			texture = "Interface\\RaidFrame\\ReadyCheck-NotReady"
		elseif statusAvailable and status == "waiting" then
			show = true
			texture = "Interface\\RaidFrame\\ReadyCheck-Waiting"
		end
	end

	return show, texture, texCoord
end

-- Constants
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- Helper to safely return a value or a default, avoiding boolean tests on secrets
local function Pass(v, default)
	if type(v) == "nil" then
		return default or 0
	end
	return v
end

-- Format large numbers (1000 -> 1K) safely
function IdentitySafety.FormatValue(val)
	if type(val) == "nil" then
		return "???"
	end
	if Utils.IsValueSecret(val) then
		return val
	end

	-- If it's a number, we can use AbbreviateNumbers
	if type(val) == "number" then
		local ok, res = pcall(AbbreviateNumbers, val)
		if ok then
			return res
		end
		local stringifyOk, text = pcall(tostring, val)
		if stringifyOk then
			return text
		end
		return "???"
	end

	-- If it's a secret value, AbbreviateNumbers might crash.
	-- We return it as-is for %s formatting later.
	return val
end

local FormatValue = IdentitySafety.FormatValue

-- Create a single status bar with overlays
local function CreateUnitBar(parent, withHealthOverlays)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT_BAR_TEXTURE)
	bar:SetStatusBarColor(0.5, 0.5, 0.5, 1) -- Neutral gray default, will be colored in UpdateFrameValues
	-- Disable mouse so clicks pass through to parent SecureUnitButton
	bar:EnableMouse(false)

	-- Background for the bar
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

	if withHealthOverlays then
		bar.predict = CreateFrame("StatusBar", nil, bar)
		bar.predict:SetAllPoints()
		bar.predict:SetStatusBarTexture(FLAT_BAR_TEXTURE)
		bar.predict:SetStatusBarColor(0, 1, 0, 0.4)
		bar.predict:SetFrameLevel(bar:GetFrameLevel() + 1)
		bar.predict:EnableMouse(false)
		bar.predict:Hide()

		bar.absorb = CreateFrame("StatusBar", nil, bar)
		bar.absorb:SetAllPoints()
		bar.absorb:SetStatusBarTexture(FLAT_BAR_TEXTURE)
		bar.absorb:SetStatusBarColor(0, 0.8, 1, 0.6)
		bar.absorb:SetFrameLevel(bar:GetFrameLevel() + 2)
		bar.absorb:EnableMouse(false)
		bar.absorb:Hide()
		if bar.absorb.SetReverseFill then
			bar.absorb:SetReverseFill(true)
		end
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

local function PositionIcon(tex, frame, frameConfig, iconConfig)
	local size = iconConfig.size or 16
	local pos = iconConfig.position or "TopLeft"
	local x = iconConfig.offsetX or 0
	local y = iconConfig.offsetY or 0
	local margin = frameConfig.iconMargin or 2

	tex:SetSize(size, size)
	tex:ClearAllPoints()
	if pos == "TopLeft" then
		tex:SetPoint("TOPLEFT", frame, "TOPLEFT", margin + x, -margin + y)
	elseif pos == "TopCenter" then
		tex:SetPoint("TOP", frame, "TOP", x, -margin + y)
	elseif pos == "TopRight" then
		tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -margin + x, -margin + y)
	elseif pos == "Left" then
		tex:SetPoint("LEFT", frame, "LEFT", margin + x, y)
	elseif pos == "Center" then
		tex:SetPoint("CENTER", frame, "CENTER", x, y)
	elseif pos == "Right" then
		tex:SetPoint("RIGHT", frame, "RIGHT", -margin + x, y)
	elseif pos == "BottomLeft" then
		tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", margin + x, margin + y)
	elseif pos == "BottomCenter" then
		tex:SetPoint("BOTTOM", frame, "BOTTOM", x, margin + y)
	elseif pos == "BottomRight" then
		tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -margin + x, margin + y)
	end
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
		local _, rawClass = UnitClass(unit)
		local class, classAvailable = IdentitySafety.Get(rawClass)
		if classAvailable and class ~= nil then
			local classColor = RAID_CLASS_COLORS[class]
			if classColor then
				r, g, b = classColor.r, classColor.g, classColor.b
			end
		end
	elseif config.colorMode == "reaction" then
		local rr, gg, bb = IdentitySafety.GetUnitColor(unit, "HEALTH")
		if rr then
			r, g, b = rr, gg, bb
		end
	end
	fontString:SetTextColor(r, g, b)
end

function UnitFrames:OnInitialize()
	self.db = ActionHud.db
	self.frames = {}
	self.framesByUnit = {}
end

function UnitFrames:OnEnable()
	self:ApplyEnabledState()
end

function UnitFrames:OnDisable()
	self:StopRuntime()
end

function UnitFrames:RegisterRuntimeEvents()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateAll")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "UpdateAll")
	for _, event in ipairs({
		"GROUP_ROSTER_UPDATE",
		"PARTY_LEADER_CHANGED",
		"PLAYER_ROLES_ASSIGNED",
		"PLAYER_FLAGS_CHANGED",
		"PLAYER_UPDATE_RESTING",
		"READY_CHECK",
		"READY_CHECK_CONFIRM",
		"READY_CHECK_FINISHED",
	}) do
		self:RegisterEvent(event, "UpdateStatusAll")
	end

	local router = ns.UnitEventRouter
	router:Register(self, "UNIT_TARGET", "OnUnitTarget", "target")
	for _, event in ipairs({ "UNIT_FLAGS", "UNIT_FACTION", "UNIT_PHASE" }) do
		router:Register(self, event, "UpdateStatusEvent", "player", "target", "targettarget", "focus")
	end
	for _, event in ipairs({
		"UNIT_HEALTH",
		"UNIT_MAXHEALTH",
		"UNIT_POWER_UPDATE",
		"UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER",
		"UNIT_ABSORB_AMOUNT_CHANGED",
		"UNIT_HEAL_PREDICTION",
	}) do
		router:Register(self, event, "UpdateFrameEvent", "player", "target", "targettarget", "focus")
	end
end

function UnitFrames:StartRuntime()
	if self._runtimeActive then
		self:UpdateLayout()
		self:UpdateAll()
		self:ApplyBlizzardFrameVisibility()
		return
	end

	self._runtimeActive = true
	if not next(self.frames) then
		self:CreateFrames()
	end
	self:RegisterRuntimeEvents()
	self:UpdateLayout()
	self:UpdateAll()
	self:ApplyBlizzardFrameVisibility()
end

function UnitFrames:HideFrames()
	if InCombatLockdown() then
		return
	end
	for frameId, f in pairs(self.frames) do
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

function UnitFrames:StopRuntime()
	self._runtimeActive = false
	self:UnregisterAllEvents()
	if ns.UnitEventRouter then
		ns.UnitEventRouter:UnregisterAll(self)
	end
	self:HideFrames()
	self:ApplyBlizzardFrameVisibility()
end

function UnitFrames:ApplyPendingEnabledState()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self._pendingEnabledState = nil
	self:ApplyEnabledState()
end

function UnitFrames:ApplyEnabledState()
	if InCombatLockdown() then
		if not self._pendingEnabledState then
			self._pendingEnabledState = true
			self:RegisterEvent("PLAYER_REGEN_ENABLED", "ApplyPendingEnabledState")
		end
		return
	end

	self._pendingEnabledState = nil
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if self.db.profile.ufEnabled then
		self:StartRuntime()
	else
		self:StopRuntime()
	end
end

function UnitFrames:ApplyBlizzardFrameVisibility()
	local hide = self.db.profile.ufEnabled and self.db.profile.ufHideBlizzard
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
		-- Hide Blizzard's Target of Target frame
		if TargetFrameToT then
			TargetFrameToT:SetAlpha(0)
			TargetFrameToT:EnableMouse(false)
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
		if TargetFrameToT then
			TargetFrameToT:SetAlpha(1)
			TargetFrameToT:EnableMouse(true)
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
		targettarget = { unit = "targettarget", moduleId = "ufTargettarget", defaultX = 370, defaultY = 50 },
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
			local unitExists, identityAvailable = IdentitySafety.IsTruthy(UnitExists(self.unit))
			if identityAvailable and unitExists then
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
		f.health = CreateUnitBar(f, true)
		f.health:SetClipsChildren(true)
		f.power = CreateUnitBar(f, false)
		f.class = CreateUnitBar(f, false)

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
		self.framesByUnit[unit] = f
	end
	self:UpdateLayout()
end

function UnitFrames:UpdateLayout()
	local DraggableContainer = ns.DraggableContainer

	if not self.db.profile.ufEnabled then
		self:HideFrames()
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
				local hasSecondaryPower = IdentitySafety.HasSecondaryPower("player")
				if hasSecondaryPower then
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

			for iconId, tex in pairs(f.icons) do
				local iconConfig = db.icons and db.icons[iconId]
				if iconConfig and iconConfig.enabled then
					PositionIcon(tex, f, db, iconConfig)
				else
					tex:Hide()
					tex._shown = false
				end
			end

			-- Force an immediate value update
			self:UpdateFrameValues(f)
		end
	end
end

function UnitFrames:UpdateAll()
	if not self._runtimeActive then
		return
	end
	for _, f in pairs(self.frames) do
		self:UpdateFrameValues(f)
	end
end

function UnitFrames:UpdateFrameEvent(event, unit)
	if not self._runtimeActive then
		return
	end
	local f = self.framesByUnit[unit]
	if f then
		local updateKind = "health"
		if event == "UNIT_POWER_UPDATE" then
			updateKind = "power"
		elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
			updateKind = "powerLayout"
		end
		self:UpdateFrameValues(f, updateKind)
	end
end

function UnitFrames:UpdateStatusEvent(event, unit)
	if not self._runtimeActive then
		return
	end
	local f = self.framesByUnit[unit]
	if f then
		self:UpdateFrameValues(f, "status")
	end
end

function UnitFrames:UpdateStatusAll()
	if not self._runtimeActive then
		return
	end
	for _, f in pairs(self.frames) do
		self:UpdateFrameValues(f, "status")
	end
end

-- When any unit's target changes, update targettarget frame
function UnitFrames:OnUnitTarget(event, unit)
	if self._runtimeActive and unit == "target" then
		-- Target's target changed, update the targettarget frame
		local f = self.frames.targettarget
		if f then
			self:UpdateFrameValues(f)
		end
	end
end

function UnitFrames:UpdateFrameValues(f, updateKind)
	local updateAll = updateKind == nil
	local updateHealth = updateAll or updateKind == "health"
	local updatePower = updateAll or updateKind == "power" or updateKind == "powerLayout"
	local updatePowerLayout = updateAll or updateKind == "powerLayout"
	local updateStatus = updateAll or updateKind == "status"
	local unit = f.unit
	local unitExists, identityAvailable = IdentitySafety.IsTruthy(UnitExists(unit))
	if not identityAvailable then
		-- Do not drive ordinary frame state from a restricted identity result.
		return
	end
	if not unitExists then
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

	local curH, maxH
	if updateHealth then
		curH = UnitHealth(unit) -- @scan-ignore: midnight-friendly-unit
		maxH = UnitHealthMax(unit) -- @scan-ignore: midnight-friendly-unit
		f.health:SetMinMaxValues(0, Pass(maxH, 1))
		f.health:SetValue(Pass(curH, 0))
	end
	if updateStatus then
		local r, g, b = IdentitySafety.GetUnitColor(unit, "HEALTH", 0.85)
		f.health:SetStatusBarColor(r, g, b)
	end

	-- 2. Power Bar
	local curP, maxP
	if updatePower then
		curP = UnitPower(unit) -- @scan-ignore: midnight-friendly-unit
		maxP = UnitPowerMax(unit) -- @scan-ignore: midnight-friendly-unit
		f.power:SetMinMaxValues(0, Pass(maxP, 1))
		f.power:SetValue(Pass(curP, 0))
	end
	if updateStatus or updatePowerLayout then
		local powerR, powerG, powerB = IdentitySafety.GetUnitColor(unit, "POWER", 0.85)
		f.power:SetStatusBarColor(powerR, powerG, powerB)
	end

	-- Power visibility and anchors only change when max/display power changes.
	if updatePowerLayout or f._showPower == nil then
		local showPower = false
		local hasPower = false
		if db.powerBarEnabled then
			if
				Utils.IsValueSecret(curP)
				or Utils.IsValueSecret(maxP)
				or type(curP) ~= "number"
				or type(maxP) ~= "number"
			then
				showPower = true
				hasPower = true
			else
				showPower = maxP > 0
				hasPower = maxP > 0
			end
		end
		if f._showPower ~= showPower then
			f._showPower = showPower
			f.power:SetShown(showPower)
		end

		local powerHeight = (db.powerBarEnabled and hasPower) and db.powerBarHeight or 0
		local classHeight = 0
		if f.unitId == "player" and db.classBarEnabled then
			local hasSecondaryPower = IdentitySafety.HasSecondaryPower("player")
			if hasSecondaryPower then
				classHeight = db.classBarHeight or 0
			end
		end

		local actualFrameHeight = db.height
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

		if
			f._actualFrameHeight ~= actualFrameHeight
			or f._healthHeight ~= healthHeight
			or f._powerHeight ~= powerHeight
			or f._classHeight ~= classHeight
		then
			f._actualFrameHeight = actualFrameHeight
			f._healthHeight = healthHeight
			f._powerHeight = powerHeight
			f._classHeight = classHeight
			if not InCombatLockdown() then
				f:SetHeight(actualFrameHeight)
				local container = self.containers and self.containers[f.unitId]
				if container then
					container:SetHeight(actualFrameHeight)
				end
			end

			f.health:ClearAllPoints()
			f.health:SetPoint("TOPLEFT", f, "TOPLEFT")
			f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT")
			f.health:SetHeight(healthHeight)

			f.power:ClearAllPoints()
			f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT")
			f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT")
			f.power:SetHeight(powerHeight)

			f.class:ClearAllPoints()
			f.class:SetPoint("TOPLEFT", f.power, "BOTTOMLEFT")
			f.class:SetPoint("TOPRIGHT", f.power, "BOTTOMRIGHT")
			f.class:SetHeight(classHeight)
		end

		local showClass = false
		if f.unitId == "player" and db.classBarEnabled then
			showClass = IdentitySafety.HasSecondaryPower("player")
		end
		if f._showClass ~= showClass then
			f._showClass = showClass
			f.class:SetShown(showClass)
		end
	end

	-- Class resource values can change on ordinary power events without needing
	-- to rebuild the surrounding unit-frame layout.
	if updatePower and f._showClass then
			local curC = UnitPower("player", nil, true) -- @scan-ignore: midnight-player-only
			local maxC = UnitPowerMax("player", nil, true) -- @scan-ignore: midnight-player-only
			f.class:SetMinMaxValues(0, Pass(maxC, 1))
			f.class:SetValue(Pass(curC, 0))
	end

	-- 4. Heal Prediction & Absorbs
	if updateHealth then
		-- Get absorbs directly like DandersFrames does (StatusBar handles secrets natively)
		local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) -- @scan-ignore: midnight-friendly-unit

		-- Show absorb values without comparing restricted numbers.
		local showAbsorb = false
		if absorbs ~= nil then
			showAbsorb = Utils.IsValueSecret(absorbs) or (type(absorbs) == "number" and absorbs ~= 0)
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
			incomingHeals = UnitGetIncomingHeals(unit) -- @scan-ignore: midnight-friendly-unit
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
	end

	-- 5. Text Display (The "Gold Standard" Pattern)
	-- Health Text
	if updateAll and db.healthText.name.enabled then
		local rawName = GetUnitName(unit, true)
		local name = IdentitySafety.Get(rawName)
		local fontString = f.healthElements.name.fontString
		pcall(fontString.SetText, fontString, name)
	end

	if updateAll and db.healthText.level.enabled then
		local rawLevel = UnitLevel(unit)
		local level = IdentitySafety.Get(rawLevel)
		local fontString = f.healthElements.level.fontString
		pcall(fontString.SetText, fontString, level)
	end

	if updateHealth and db.healthText.value.enabled then
		local displayH = UnitHealth(unit, true) -- @scan-ignore: midnight-friendly-unit
		local displayMaxH = UnitHealthMax(unit, true) -- @scan-ignore: midnight-friendly-unit
		local hStr = FormatValue(displayH)
		local mStr = FormatValue(displayMaxH)
		local fontString = f.healthElements.value.fontString
		pcall(fontString.SetFormattedText, fontString, "%s/%s", hStr, mStr)
	end

	-- Percent display is disabled due to Midnight secret value issues
	-- Keeping values only for now
	if updateAll and f.healthElements.percent then
		f.healthElements.percent.fontString:SetText("")
		f.healthElements.percent.fontString:Hide()
	end

	-- Power Text
	if updatePower and db.powerText.value.enabled and f.powerElements.value then
		local displayP = UnitPower(unit, nil, true) -- @scan-ignore: midnight-friendly-unit
		local displayMaxP = UnitPowerMax(unit, nil, true) -- @scan-ignore: midnight-friendly-unit
		local pStr = FormatValue(displayP)
		local pmStr = FormatValue(displayMaxP)
		local fontString = f.powerElements.value.fontString
		pcall(fontString.SetFormattedText, fontString, "%s/%s", pStr, pmStr)
	end

	-- Percent display is disabled due to Midnight secret value issues
	-- Keeping values only for now
	if updateAll and f.powerElements.percent then
		f.powerElements.percent.fontString:SetText("")
		f.powerElements.percent.fontString:Hide()
	end

	-- 6. Status Icons
	if updateStatus then
		local showAllIcons = self.db.profile.ufShowAllIcons or false
		for iconId, tex in pairs(f.icons) do
			local config = db.icons and db.icons[iconId]
			if config and config.enabled then
				local show, texture, texCoord = IdentitySafety.GetStatusIconState(iconId, unit, showAllIcons)
				if texCoord and tex._texCoord ~= texCoord then
					tex:SetTexCoord(unpack(texCoord))
					tex._texCoord = texCoord
				end
				if texture and tex._texture ~= texture then
					tex:SetTexture(texture)
					tex._texture = texture
				end
				if show then
					if not tex._shown then
						tex:Show()
						tex._shown = true
					end
				elseif tex._shown ~= false then
					tex:Hide()
					tex._shown = false
				end
			else
				if tex._shown ~= false then
					tex:Hide()
					tex._shown = false
				end
			end
		end
	end
end
