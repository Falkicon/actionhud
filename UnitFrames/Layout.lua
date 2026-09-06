-- Frame construction, styling, and scheduled geometry.
local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local UnitFrames = ActionHud:GetModule("UnitFrames")
local IdentitySafety = ns.UnitFrameIdentitySafety
local LSM = LibStub("LibSharedMedia-3.0")
local FLAT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"

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

function UnitFrames:ApplyLayoutPosition()
	local DraggableContainer = ns.DraggableContainer
	if InCombatLockdown() then
		self:ApplyEnabledState()
		return
	end

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
			-- This pass reapplies configured dimensions; invalidate the computed layout.
			f._actualFrameHeight = nil
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

			-- Values are refreshed once, in the manager's render phase.
		end
	end
end
