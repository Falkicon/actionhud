local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local AB = ActionHud:NewModule("ActionBars", "AceEvent-3.0")

local Utils = ns.Utils

-- Local upvalues for performance (hot-path optimization)
local ipairs = ipairs
local GetTime = GetTime
local GetActionBarPage = Utils.GetActionBarPageSafe -- @scan-ignore: midnight-normalized
local GetBonusBarOffset = GetBonusBarOffset
local GetActionInfo = GetActionInfo
local GetActionTexture = Utils.GetActionTextureSafe -- @scan-ignore: midnight-normalized
local GetActionCooldown = Utils.GetActionCooldownSafe -- @scan-ignore: midnight-normalized
local GetActionCount = Utils.GetActionDisplayCountSafe -- @scan-ignore: midnight-normalized
local GetMacroSpell = GetMacroSpell
local IsUsableAction = Utils.IsUsableActionSafe -- @scan-ignore: midnight-normalized
local IsActionInRange = Utils.IsActionInRangeSafe -- @scan-ignore: midnight-normalized
local math_floor = math.floor

local buttons = {}
local container = nil -- ActionBars container frame
local layoutCache = {} -- Cache for Edit Mode settings to avoid frequent API calls

-- Helper to fetch Edit Mode settings for a bar
function AB:GetEditModeSettings(barID)
	-- Default to 6x2 (compact) if not syncing or API fails
	local settings = { numRows = 2, numIcons = 12, orientation = 0 }

	-- In Midnight, avoid C_EditMode in instances/combat to prevent secret value errors and taint
	if Utils.IS_MIDNIGHT then
		local inInstance, instanceType = IsInInstance()
		if
			InCombatLockdown()
			or (inInstance and (instanceType == "raid" or instanceType == "party" or instanceType == "arena"))
		then
			if layoutCache[barID] then
				return layoutCache[barID]
			end
			return settings
		end
	end

	-- Primary method: Find the system frame directly from Edit Mode Manager
	-- This is the most reliable way as it works for both Preset and User layouts.
	if EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames then
		for _, frame in ipairs(EditModeManagerFrame.registeredSystemFrames) do
			if frame.system == Enum.EditModeSystem.ActionBar and frame.systemIndex == barID then
				if frame.GetSettingValue then
					local rows = frame:GetSettingValue(Enum.EditModeActionBarSetting.NumRows)
					local icons = frame:GetSettingValue(Enum.EditModeActionBarSetting.NumIcons)
					local orient = frame:GetSettingValue(Enum.EditModeActionBarSetting.Orientation)

					if not Utils.IsValueSecret(rows) then
						settings.numRows = rows
					end
					if not Utils.IsValueSecret(icons) then
						settings.numIcons = icons
					end
					if not Utils.IsValueSecret(orient) then
						settings.orientation = orient
					end

					layoutCache[barID] = settings
					return settings
				end
			end
		end
	end

	-- Secondary method: Parse GetLayouts()
	if not C_EditMode or not C_EditMode.GetLayouts then
		return settings
	end

	local ok, layouts = pcall(C_EditMode.GetLayouts)
	if not ok or not layouts then
		return settings
	end

	-- Find the active layout (could be User or Preset)
	local activeLayout
	if layouts.activeLayoutType == Enum.EditModeLayoutType.Preset then
		-- Presets are handled by the Manager, not returned in the layouts list
		-- We'll try to find it in the manager's combined list if available
		if EditModeManagerFrame and EditModeManagerFrame.layoutInfo then
			activeLayout = EditModeManagerFrame.layoutInfo.layouts[layouts.activeLayoutIndex]
		end
	else
		activeLayout = layouts.layouts[layouts.activeLayoutIndex]
	end

	if activeLayout then
		for _, systemInfo in ipairs(activeLayout.systems) do
			if systemInfo.system == Enum.EditModeSystem.ActionBar and systemInfo.systemIndex == barID then
				for _, settingInfo in ipairs(systemInfo.settings) do
					local val = settingInfo.value
					if not Utils.IsValueSecret(val) then
						if settingInfo.setting == Enum.EditModeActionBarSetting.NumRows then
							settings.numRows = val
						elseif settingInfo.setting == Enum.EditModeActionBarSetting.NumIcons then
							settings.numIcons = val
						elseif settingInfo.setting == Enum.EditModeActionBarSetting.Orientation then
							settings.orientation = val
						end
					end
				end
				break
			end
		end
	end

	-- Update cache
	layoutCache[barID] = settings
	return settings
end

function AB:ClearLayoutCache()
	wipe(layoutCache)
end

function AB:OnEnable()
	-- Create container frame
	local parent = ActionHud.frame
	if not parent then
		return
	end

	if not container then
		container = CreateFrame("Frame", "ActionHudActionBars", parent)
	end

	-- Create Buttons if not already existing
	if #buttons == 0 then
		self:CreateButtons(container)
	end

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshAll")
	self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
		-- Clear cache and delay update to ensure Blizzard's internal state is fully saved
		AB:ClearLayoutCache()
		C_Timer.After(0.5, function()
			AB:UpdateLayout()
		end)
	end)
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "RefreshAll")
	self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "RefreshAll")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "UpdateStateAll")
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "UpdateStateAll")
	self:RegisterEvent("ACTIONBAR_UPDATE_STATE", "UpdateStateAll")
	self:RegisterEvent("ACTIONBAR_UPDATE_USABLE", "UpdateStateAll")
	self:RegisterEvent("SPELL_UPDATE_CHARGES", "UpdateStateAll")

	-- Hook Edit Mode exit to force a layout refresh
	if EditModeManagerFrame then
		hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
			AB:ClearLayoutCache()
			AB:UpdateLayout()
		end)
	end

	self:UpdateLayout()
	self:RefreshAll()
end

-- Get container frame
function AB:GetContainer()
	return container
end

-- Calculate the height of this module for LayoutManager
function AB:CalculateHeight()
	if not self:IsEnabled() then
		return 0
	end
	local p = ActionHud.db.profile

	local bar1 = self:GetEditModeSettings(1)
	local bar6 = self:GetEditModeSettings(2)

	local rows1 = math.max(tonumber(bar1.numRows) or 2, 1)
	local rows6 = math.max(tonumber(bar6.numRows) or 2, 1)

	local h1 = rows1 * p.iconHeight
	local h2 = rows6 * p.iconHeight
	local gap = 0 -- No gap between blocks

	return h1 + h2 + gap
end

-- Get the width of this module for LayoutManager
function AB:GetLayoutWidth()
	local p = ActionHud.db.profile

	local bar1 = self:GetEditModeSettings(1)
	local bar6 = self:GetEditModeSettings(2)

	local icons1 = tonumber(bar1.numIcons) or 12
	local rows1 = math.max(tonumber(bar1.numRows) or 2, 1)
	local icons6 = tonumber(bar6.numIcons) or 12
	local rows6 = math.max(tonumber(bar6.numRows) or 2, 1)

	local w1 = math.ceil(icons1 / rows1) * p.iconWidth
	local w2 = math.ceil(icons6 / rows6) * p.iconWidth

	return math.max(w1, w2)
end

-- Apply position from LayoutManager
function AB:ApplyLayoutPosition()
	if not container then
		return
	end
	local LM = ActionHud:GetModule("LayoutManager", true)
	if not LM then
		return
	end

	-- Check if we're in stack mode
	local inStack = LM:IsModuleInStack("actionBars")
	local main = ActionHud.frame

	container:ClearAllPoints()

	if inStack then
		-- Stack mode: use full HUD width and position from LayoutManager
		local containerWidth = LM:GetMaxWidth()
		local containerHeight = self:CalculateHeight()
		if containerWidth > 0 and containerHeight > 0 then
			container:SetSize(containerWidth, containerHeight)
		end
		local yOffset = LM:GetModulePosition("actionBars")
		container:SetPoint("TOP", main, "TOP", 0, yOffset)
		container:EnableMouse(false)
	else
		-- Independent mode: DraggableContainer handles positioning
		local DraggableContainer = ns.DraggableContainer
		if DraggableContainer then
			-- Setup draggable if not already
			if not container._db then
				container._db = ActionHud.db
				container._xKey = "actionBarsXOffset"
				container._yKey = "actionBarsYOffset"
				container._defaultX = 0
				container._defaultY = 0
				container.moduleId = "actionbars"
				container:SetMovable(true)
				container:SetClampedToScreen(true)
				
				if not container.overlay then
					container.overlay = container:CreateTexture(nil, "OVERLAY")
					container.overlay:SetAllPoints()
					container.overlay:SetColorTexture(1, 0.5, 0, 0.4)
					container.overlay:Hide()
				end
				if not container.label then
					container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
					container.label:SetPoint("CENTER")
					container.label:SetText("Action Bars")
					container.label:Hide()
				end
				
				container:SetScript("OnDragStart", function(self)
					if DraggableContainer:IsUnlocked(self._db) then
						self:StartMoving()
					end
				end)
				container:SetScript("OnDragStop", function(self)
					self:StopMovingOrSizing()
					local cx, cy = self:GetCenter()
					local px, py = main:GetCenter()
					self._db.profile[self._xKey] = cx - px
					self._db.profile[self._yKey] = cy - py
					if LibStub("AceConfigRegistry-3.0", true) then
						LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
					end
				end)
			end
			DraggableContainer:UpdatePosition(container)
			DraggableContainer:UpdateOverlay(container)
		else
			-- Fallback positioning
			local p = ActionHud.db.profile
			local xOffset = p.actionBarsXOffset or 0
			local yOffset = p.actionBarsYOffset or 0
			container:SetPoint("CENTER", main, "CENTER", xOffset, yOffset)
		end
	end

	container:Show()
	ActionHud:Log(string.format("ActionBars positioned: inStack=%s", tostring(inStack)), "layout")
end

function AB:CreateButtons(parent)
	-- Create 24 buttons (max for 2 bars)
	for i = 1, 24 do
		local btn = CreateFrame("Frame", nil, parent)

		-- Icon
		btn.icon = btn:CreateTexture(nil, "BACKGROUND")
		btn.icon:SetAllPoints()
		btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		-- Cooldown
		btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		btn.cd:SetAllPoints()
		btn.cd:SetDrawEdge(true)

		-- Count
		btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		btn.count:SetPoint("BOTTOMRIGHT", 0, 0)
		btn.count:SetJustifyH("RIGHT")

		-- Proc Glow (Yellow)
		btn.glow = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		btn.glow:SetAllPoints()
		btn.glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		btn.glow:SetBackdropBorderColor(1, 1, 0, 1)
		btn.glow:SetFrameLevel(btn:GetFrameLevel() + 12)
		btn.glow:Hide()

		buttons[i] = btn
	end

	-- Setup Assist Hook
	if AssistedCombatManager then
		hooksecurefunc(AssistedCombatManager, "SetAssistedHighlightFrameShown", function(mgr, actionButton, shown)
			if not actionButton or not actionButton.action then
				return
			end

			local targetID = actionButton.action
			-- Handle secret value comparison in Midnight
			if Utils.IsValueSecret(targetID) then
				return
			end

			for _, b in ipairs(buttons) do
				if Utils.SafeCompare(b.actionID, targetID, "==") then
					if not b.assistGlow then
						b.assistGlow = CreateFrame("Frame", nil, b, "BackdropTemplate")
						b.assistGlow:SetAllPoints()
						b.assistGlow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
						b.assistGlow:SetBackdropBorderColor(0, 0.8, 1, 1)
						b.assistGlow:SetFrameLevel(b:GetFrameLevel() + 5)
						b.assistGlow:Hide()
					end
					if b.assistGlow then
						-- Apply Alpha
						b.assistGlow:SetBackdropBorderColor(0, 0.8, 1, ActionHud.db.profile.assistGlowAlpha)
						if shown then
							b.assistGlow:Show()
						else
							b.assistGlow:Hide()
						end
					end
				end
			end
		end)
	end
end

local lastUpdate = 0
function AB:UpdateLayout()
	-- Throttle updates to once per frame max, and avoid during sensitive Edit Mode events if possible
	local now = GetTime()
	if now == lastUpdate then
		return
	end
	lastUpdate = now

	local p = ActionHud.db.profile
	if not container then
		return
	end

	-- Debug Container Visual
	ActionHud:UpdateLayoutOutline(container, "Action Bars", "actionbars")

	-- Hide all buttons initially
	for _, btn in ipairs(buttons) do
		btn:Hide()
	end

	-- Fetch settings for Bar 1 and Bar 2
	local bar1 = self:GetEditModeSettings(1)
	local bar6 = self:GetEditModeSettings(2)

	ActionHud:Log(
		string.format("Layout Sync: Bar1(%dx%d) Bar6(%dx%d)", bar1.numIcons, bar1.numRows, bar6.numIcons, bar6.numRows),
		"layout"
	)

	local blocks = {}
	if p.barPriority == "bar6" then
		table.insert(blocks, { settings = bar6, startSlot = 61, id = "bar6" })
		table.insert(blocks, { settings = bar1, startSlot = 1, id = "bar1" })
	else
		table.insert(blocks, { settings = bar1, startSlot = 1, id = "bar1" })
		table.insert(blocks, { settings = bar6, startSlot = 61, id = "bar6" })
	end

	local totalHeight = self:CalculateHeight()
	local contentWidth = self:GetLayoutWidth()

	-- Report height to LayoutManager
	local LM = ActionHud:GetModule("LayoutManager", true)
	if LM then
		LM:SetModuleHeight("actionBars", totalHeight)
	end

	-- Get actual container width (HUD width when in stack, content width otherwise)
	local inStack = LM and LM:IsModuleInStack("actionBars")
	local containerWidth = contentWidth
	if inStack and LM then
		containerWidth = LM:GetMaxWidth()
	end
	container:SetSize(containerWidth, totalHeight)

	local currentY = 0
	local buttonIdx = 1
	local gapBetweenBlocks = 0

	for _, block in ipairs(blocks) do
		local s = block.settings
		local numIcons = tonumber(s.numIcons) or 12
		local numRows = math.max(tonumber(s.numRows) or 2, 1)
		local iconsPerRow = math.ceil(numIcons / numRows)
		local blockWidth = iconsPerRow * p.iconWidth
		local blockHeight = numRows * p.iconHeight

		-- Alignment X Offset (use container width for centering within HUD-width container)
		local xOffset = 0
		if p.barAlignment == "CENTER" then
			xOffset = (containerWidth - blockWidth) / 2
		elseif p.barAlignment == "RIGHT" then
			xOffset = containerWidth - blockWidth
		end

		for i = 1, numIcons do
			local btn = buttons[buttonIdx]
			if btn then
				btn:SetSize(p.iconWidth, p.iconHeight)

				local col = (i - 1) % iconsPerRow
				local row = math_floor((i - 1) / iconsPerRow)

				local visualRow = numRows - 1 - row
				local slotOffset = i - 1

				btn:ClearAllPoints()
				btn:SetPoint(
					"TOPLEFT",
					container,
					"TOPLEFT",
					xOffset + (col * p.iconWidth),
					-(currentY + (visualRow * p.iconHeight))
				)
				btn:Show()
				btn:EnableMouse(false)

				btn.baseSlot = block.startSlot + slotOffset
				btn.actionID = btn.baseSlot

				-- Visuals
				Utils.ApplyIconCrop(btn.icon, p.iconWidth, p.iconHeight)
				local font = "Fonts\\FRIZQT__.TTF"
				if btn.count then
					btn.count:SetFont(font, p.countFontSize, "OUTLINE")
				end
				if btn.cd then
					for _, r in ipairs({ btn.cd:GetRegions() }) do
						if r:GetObjectType() == "FontString" then
							r:SetFont(font, p.cooldownFontSize, "OUTLINE")
						end
					end
				end
				if btn.glow then
					btn.glow:SetBackdropBorderColor(1, 1, 0, p.procGlowAlpha)
				end
				if btn.assistGlow then
					btn.assistGlow:SetBackdropBorderColor(0, 0.8, 1, p.assistGlowAlpha)
				end

				buttonIdx = buttonIdx + 1
			end
		end
		currentY = currentY + blockHeight + gapBetweenBlocks
	end

	-- Update action data for all shown buttons
	self:RefreshAll()
	self:UpdateOpacity()

	-- Trigger LayoutManager to reposition other modules if our height changed
	if LM then
		LM:TriggerLayoutUpdate()
	end
end

function AB:UpdateOpacity()
	local alpha = ActionHud.db.profile.opacity
	for _, btn in ipairs(buttons) do
		if btn.icon and not btn.hasAction then
			btn.icon:SetColorTexture(0, 0, 0, alpha)
		end
	end
end

function AB:OnDisable()
	if container then
		container:Hide()
	end
	for _, btn in ipairs(buttons) do
		btn:Hide()
	end
end

function AB:RefreshAll()
	if not self:IsEnabled() then
		return
	end
	ActionHud:Log("ActionBars: RefreshAll", "events")
	for _, btn in ipairs(buttons) do
		if btn:IsShown() then
			self:UpdateAction(btn)
			self:UpdateCooldown(btn)
			self:UpdateState(btn)
		end
	end
end

function AB:ACTIONBAR_SLOT_CHANGED(event, arg1)
	ActionHud:Log(string.format("ActionBars: %s (slot=%s)", event, tostring(arg1)), "events")
	for _, btn in ipairs(buttons) do
		if
			Utils.SafeCompare(btn.baseSlot, arg1, "==")
			or Utils.SafeCompare(btn.actionID, arg1, "==")
			or Utils.SafeCompare(arg1, 0, "==")
		then
			self:UpdateAction(btn)
			self:UpdateCooldown(btn)
			self:UpdateState(btn)
		end
	end
end

function AB:SPELL_UPDATE_COOLDOWN()
	-- Only update buttons with actions (skip empty slots to reduce overhead)
	for _, btn in ipairs(buttons) do
		if btn.hasAction then
			self:UpdateCooldown(btn)
		end
	end
end

function AB:UpdateStateAll()
	ActionHud:Log("ActionBars: UpdateStateAll", "events")
	-- Only update buttons with actions (skip empty slots to reduce overhead)
	for _, btn in ipairs(buttons) do
		if btn.hasAction then
			self:UpdateState(btn)
		end
	end
end

-- Specific Update Functions
function AB:UpdateAction(btn)
	local slot = btn.baseSlot
	if not slot then
		return
	end

	local actionID = slot

	-- Paging logic
	if slot >= 1 and slot <= 12 then
		local page = GetActionBarPage() -- @scan-ignore: midnight-normalized
		local offset = GetBonusBarOffset()

		-- Use SafeCompare for Midnight compatibility
		if Utils.SafeCompare(offset, 0, ">") and Utils.SafeCompare(page, 1, "==") then
			if Utils.SafeCompare(offset, 1, "==") then
				page = 7
			elseif Utils.SafeCompare(offset, 2, "==") then
				page = 8
			elseif Utils.SafeCompare(offset, 3, "==") then
				page = 9
			elseif Utils.SafeCompare(offset, 4, "==") then
				page = 10
			elseif Utils.SafeCompare(offset, 5, "==") then
				page = 11
			elseif Utils.SafeCompare(offset, 6, "==") then
				page = 12
			end
		end

		local pageNum = tonumber(page)
		if pageNum and pageNum > 1 then
			actionID = (pageNum - 1) * 12 + slot
		end
	end

	btn.actionID = actionID
	local type, id = GetActionInfo(actionID)
	if type == "spell" then
		btn.spellID = id
	elseif type == "macro" then
		btn.spellID = GetMacroSpell(actionID)
	else
		btn.spellID = nil
	end

	local texture = GetActionTexture(actionID) -- @scan-ignore: midnight-normalized
	if texture then
		btn.hasAction = true
		btn.icon:SetTexture(texture)
		btn.icon:Show()
		btn:SetAlpha(1)
		Utils.ApplyIconCrop(btn.icon, ActionHud.db.profile.iconWidth, ActionHud.db.profile.iconHeight)
	else
		btn.hasAction = false
		btn.icon:Hide()
		btn.cd:Hide()
		btn.count:SetText("")
		btn.glow:Hide()
		if btn.assistGlow then
			btn.assistGlow:Hide()
		end
		btn.icon:SetColorTexture(0, 0, 0, ActionHud.db.profile.opacity)
		btn.icon:Show()
	end
end

-- Default cooldown info structures (same pattern as LibActionButton)
local defaultCooldownInfo = { startTime = 0, duration = 0, isEnabled = false, modRate = 1 }
local defaultChargeInfo = { currentCharges = 0, maxCharges = 0, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }
local defaultLossOfControlInfo = { startTime = 0, duration = 0, modRate = 1 }

function AB:UpdateCooldown(btn)
	if not btn.hasAction then
		return
	end

	-- Get cooldown info using C_ActionBar.GetActionCooldown (returns ActionBarCooldownInfo table)
	local cooldownInfo = defaultCooldownInfo
	local chargeInfo = defaultChargeInfo
	local lossOfControlInfo = defaultLossOfControlInfo

	-- Primary cooldown info from C_ActionBar
	if C_ActionBar and C_ActionBar.GetActionCooldown then
		local ok, info = pcall(C_ActionBar.GetActionCooldown, btn.actionID)
		if ok and info then
			cooldownInfo = info
		end
	end

	-- Charge info
	if C_ActionBar and C_ActionBar.GetActionCharges then
		local ok, info = pcall(C_ActionBar.GetActionCharges, btn.actionID)
		if ok and info then
			chargeInfo = info
		end
	end

	-- Loss of control info
	if C_ActionBar and C_ActionBar.GetActionLossOfControlCooldown then
		local ok, start, dur = pcall(C_ActionBar.GetActionLossOfControlCooldown, btn.actionID)
		if ok then
			lossOfControlInfo = { startTime = start or 0, duration = dur or 0, modRate = cooldownInfo.modRate or 1 }
		end
	end

	-- Use Blizzard's ActionButton_ApplyCooldown if available (12.0+ helper)
	-- Requires valid cooldown frames - create chargeCooldown on demand if needed
	if ActionButton_ApplyCooldown then
		-- Create chargeCooldown frame on demand (same pattern as LibActionButton)
		if not btn.chargeCooldown then
			btn.chargeCooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
			btn.chargeCooldown:SetHideCountdownNumbers(true)
			btn.chargeCooldown:SetDrawSwipe(false)
			btn.chargeCooldown:SetAllPoints(btn.cd)
			btn.chargeCooldown:SetFrameLevel(btn:GetFrameLevel())
		end
		ActionButton_ApplyCooldown(btn.cd, cooldownInfo, btn.chargeCooldown, chargeInfo, nil, lossOfControlInfo)
		return
	end

	-- Fallback for pre-12.0: Direct passthrough
	local start = cooldownInfo.startTime
	local duration = cooldownInfo.duration
	local isEnabled = cooldownInfo.isEnabled

	-- Check if we have a valid cooldown to display
	local hasValidDuration = duration and (Utils.IsValueSecret(duration) or Utils.SafeCompare(duration, 0, ">"))

	-- For enabled, treat secret as true (show the cooldown)
	if Utils.IsValueSecret(isEnabled) then
		isEnabled = true
	elseif isEnabled == nil then
		isEnabled = true
	end

	if isEnabled and hasValidDuration then
		btn.cd:SetDrawEdge(true)
		btn.cd:SetCooldown(start, duration)
		btn.cd:Show()

		-- Hide edge for GCD (only if duration is readable, not secret)
		if not Utils.IsValueSecret(duration) and Utils.SafeCompare(duration, 1.5, "<=") then
			btn.cd:SetDrawEdge(false)
		end
		return
	end

	-- Fallback to charges if no main cooldown
	if chargeInfo and chargeInfo.cooldownStartTime and chargeInfo.cooldownDuration then
		local cdStart = chargeInfo.cooldownStartTime
		local cdDuration = chargeInfo.cooldownDuration

		local hasChargeCooldown = cdStart
			and cdDuration
			and (Utils.IsValueSecret(cdDuration) or Utils.SafeCompare(cdDuration, 0, ">"))

		if hasChargeCooldown then
			btn.cd:SetDrawEdge(true)
			btn.cd:SetCooldown(cdStart, cdDuration)
			btn.cd:Show()
			return
		end
	end

	btn.cd:Hide()
end

function AB:UpdateState(btn)
	if not btn.hasAction then
		return
	end
	local actionID = btn.actionID

	-- Use the new native display count API (Midnight standard)
	-- This handles both charges and regular counts, and is non-secret.
	local count = Utils.GetActionDisplayCountSafe(actionID)
	btn.count:SetText(count or "")

	local isUsable, noMana = IsUsableAction(actionID) -- @scan-ignore: midnight-normalized
	if not isUsable and not noMana then
		btn.icon:SetDesaturated(true)
		btn.icon:SetVertexColor(0.4, 0.4, 0.4)
	elseif noMana then
		btn.icon:SetDesaturated(false)
		btn.icon:SetVertexColor(0.5, 0.5, 1.0)
	else
		btn.icon:SetDesaturated(false)
		btn.icon:SetVertexColor(1, 1, 1)
	end

	if ActionButton_GetInRange and ActionButton_GetInRange(actionID) == false then
		if IsActionInRange(actionID) == false then
			btn.icon:SetVertexColor(0.8, 0.1, 0.1)
		end -- @scan-ignore: midnight-normalized
	end

	local isOverlayed = false
	if btn.spellID then
		isOverlayed = Utils.IsSpellOverlayedSafe(btn.spellID)
	end
	if isOverlayed then
		btn.glow:Show()
	else
		btn.glow:Hide()
	end
end
