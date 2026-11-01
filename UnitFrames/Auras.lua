-- Native debuff groups. Aura data, sorting, child visibility and timers stay
-- inside Blizzard's delegates; only public configuration reaches this file.
local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local UnitFrames = addon:GetModule("UnitFrames")
local ICON_SIZE = 24
local GROUP_KEY = "debuffs"

-- Reviewed 2026-10-19: Retail and Forever share this inbound API and flow layout.
-- https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua
-- https://github.com/Gethe/wow-ui-source/blob/172a387e3ab85b26e6640d3058d5ec1e6ccd4c63/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua
-- Revalidate on future clients. Never add spell-ID filters to friendly debuffs:
-- native identity filtering rejects secret friendly harmful auras outright.
function UnitFrames:IsDebuffDisplayAvailable()
	local api, sort, direction, anchors = _G["C_AuraContainerUtil"], _G["AuraContainerSortMethod"],
		_G["AuraContainerSortDirection"], _G["AnchorUtil"]
	return type(api) == "table" and type(api.ProcessCustomAuraButtonApplicationCountOptions) == "function"
		and type(sort) == "table" and sort.UnitFrameDebuff ~= nil
		and type(direction) == "table" and direction.Normal ~= nil
		and type(anchors) == "table" and type(anchors.FlowDirection) == "table"
		and anchors.FlowDirection.Right ~= nil and anchors.FlowDirection.Down ~= nil and anchors.FlowDirection.Up ~= nil
end

local function InitializeDebuffButton(button)
	-- The engine may allocate another batch during combat. This one-time native
	-- callback is the only place addon code may touch the button or its children.
	button:SetSize(ICON_SIZE, ICON_SIZE)
	-- AuraButton's intrinsic enter/leave handlers own the restricted tooltip.
	-- Enable hover without consuming clicks or installing addon scripts.
	button:SetMouseMotionEnabled(true)
	button:SetMouseClickEnabled(false)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetIcon(icon)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:EnableMouse(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(false)
	cooldown:SetCountdownFont(ns.Utils.GetTimerFont("small"))
	if cooldown.SetCountdownMillisecondsThreshold then cooldown:SetCountdownMillisecondsThreshold(3) end
	button:SetDurationCooldown(cooldown)
	local count = cooldown:CreateFontString(nil, "OVERLAY")
	count:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	button:SetApplicationCount(count, {})
end

-- Saved settings and defaults only; never pass game API values here.
local function ConfigInteger(value, fallback, minimum, maximum)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		value = fallback
	end
	return math.max(minimum, math.min(maximum, math.floor(value)))
end

function UnitFrames:SetFrameDebuffsEnabled(frame, enabled)
	local display = frame.debuffDisplay
	if not display then return end
	if display.container then display.container:SetEnabled(enabled) end
	display.anchor:SetShown(enabled)
	display.enabled = enabled
end

function UnitFrames:ConfigureFrameDebuffs(frame)
	local config = self.db.profile.ufConfig[frame.unitId]
	local settings = config.debuffs
	if not config.enabled or not settings or not settings.enabled or not self:IsDebuffDisplayAvailable() then
		self:SetFrameDebuffsEnabled(frame, false)
		return
	end
	local display = frame.debuffDisplay
	if display and display.error then return end
	local defaults = self.db.defaults.profile.ufConfig[frame.unitId].debuffs
	local size = ConfigInteger(settings.iconSize, defaults.iconSize, 16, 48)
	local spacing = ConfigInteger(settings.spacing, defaults.spacing, 0, 12)
	local limit = ConfigInteger(settings.maxCount, defaults.maxCount, 1, 24)
	local gap = ConfigInteger(settings.gap, defaults.gap, 0, 30)
	local width = ConfigInteger(config.width, self.db.defaults.profile.ufConfig[frame.unitId].width, 1, 1000)
	local columns = math.max(1, math.min(limit, math.floor((width + spacing) / (size + spacing))))
	local rows = math.ceil(limit / columns)
	local scale = size / ICON_SIZE
	local above = settings.position == "ABOVE"
	if not display then
		display = { anchor = CreateFrame("Frame", nil, frame) }
		frame.debuffDisplay = display
		display.anchor:EnableMouse(false)
		display.scaled = CreateFrame("Frame", nil, display.anchor)
		display.scaled:EnableMouse(false)
		display.container = CreateFrame("AuraContainer", nil, display.scaled, "CustomAuraContainerTemplate")
		display.container:SetEnabled(false)
		display.container:EnableMouse(false)
		display.container:SetSize(1, 1)
	end
	self:SetFrameDebuffsEnabled(frame, false)
	-- The public wrapper has a fixed footprint based on settings, never on the
	-- native container's secret size. Scale the ordinary parent so existing and
	-- future buttons resize without revisiting restricted children.
	display.anchor:ClearAllPoints()
	display.anchor:SetSize(columns * size + (columns - 1) * spacing, rows * size + (rows - 1) * spacing)
	display.anchor:SetPoint(above and "BOTTOMLEFT" or "TOPLEFT", frame,
		above and "TOPLEFT" or "BOTTOMLEFT", 0, above and gap or -gap)
	display.scaled:SetScale(scale)
	display.scaled:SetSize(1, 1)
	display.scaled:ClearAllPoints()
	display.scaled:SetPoint(above and "BOTTOMLEFT" or "TOPLEFT", display.anchor, above and "BOTTOMLEFT" or "TOPLEFT")
	local native = display.container
	native:ClearAllPoints()
	native:SetPoint(above and "BOTTOMLEFT" or "TOPLEFT", display.scaled, above and "BOTTOMLEFT" or "TOPLEFT")
	native:SetFlowLayoutAnchorPoint(above and "BOTTOMLEFT" or "TOPLEFT")
	local directions = _G["AnchorUtil"].FlowDirection
	native:SetFlowLayoutGrowthDirection(directions.Right, above and directions.Up or directions.Down)
	native:SetFlowLayoutMaximumLineSize((columns * size + (columns - 1) * spacing) / scale)
	local layout = { elementWidth = ICON_SIZE, elementHeight = ICON_SIZE,
		elementSpacing = spacing / scale, lineSpacing = spacing / scale }
	if not display.groupAdded then
		native:AddAuraGroup(GROUP_KEY, "HARMFUL", {
			maxFrameCount = limit,
			candidateFilters = {},
			sortMethod = _G["AuraContainerSortMethod"].UnitFrameDebuff,
			sortDirection = _G["AuraContainerSortDirection"].Normal,
			layout = layout,
			initializeFrame = function(button)
				-- Native securecallfunction consumes callback errors, so capture
				-- setup failures here, including in later combat-time batches.
				local ok, message = pcall(InitializeDebuffButton, button)
				if not ok and not display.error then
					display.error = tostring(message)
					addon:Logf("unitFrames", "Native %s debuff widget initialization failed: %s", frame.unit, display.error)
					self:UpdateLayout()
				end
			end,
		})
		display.groupAdded = true
		native:SetUnit(frame.unit)
	else
		native:SetAuraGroupMaxFrameCount(GROUP_KEY, limit)
		native:SetAuraGroupLayout(GROUP_KEY, layout)
	end
end

function UnitFrames:PrepareLayout()
	if not self._runtimeActive or InCombatLockdown() then return end
	for _, unit in ipairs({ "player", "target" }) do
		local frame = self.frames[unit]
		if frame then
			local ok, message = pcall(self.ConfigureFrameDebuffs, self, frame)
			if not ok then
				if frame.debuffDisplay then
					frame.debuffDisplay.error = tostring(message)
					self:SetFrameDebuffsEnabled(frame, false)
				end
				addon:Logf("unitFrames", "Native %s debuff initialization failed: %s", unit, tostring(message))
			end
		end
	end
end

function UnitFrames:RenderDebuffs()
	if InCombatLockdown() then return end
	for _, frame in pairs(self.frames) do
		local display = frame.debuffDisplay
		if display then
			local config = self.db.profile.ufConfig[frame.unitId]
			self:SetFrameDebuffsEnabled(frame, self._runtimeActive and config.enabled
				and config.debuffs and config.debuffs.enabled and self:IsDebuffDisplayAvailable() and not display.error or false)
		end
	end
end

function UnitFrames:OnTargetChanged()
	self:UpdateAll()
	local display = self.frames.target and self.frames.target.debuffDisplay
	if self._runtimeActive and display and display.enabled then
		-- Public inbound refresh, including during combat. All aura selection,
		-- visibility, and flow geometry are performed by the native container.
		display.container:UpdateAllAuras()
	end
end
