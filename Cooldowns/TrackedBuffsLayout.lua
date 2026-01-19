-- Cooldowns\TrackedBuffsLayout.lua
-- Handles the custom layout for TrackedBuffs by reparenting the Blizzard viewer icon.
-- Uses early container creation to block Edit Mode interference.

local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffsLayout = addon:NewModule("TrackedBuffsLayout", "AceEvent-3.0")
local Utils = ns.Utils
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

local BLIZZARD_FRAME_NAME = "BuffIconCooldownViewer"

-- ============================================================================
-- EARLY CONTAINER CREATION
-- Create container at FILE LOAD TIME, before Blizzard's EditModeManager initializes.
-- ============================================================================
local container = CreateFrame("Frame", "ActionHud_TrackedBuffsContainer", UIParent)
container:SetSize(200, 50)
container:SetFrameStrata("LOW")
container:SetFrameLevel(10)
container:SetClampedToScreen(true)
container:SetMovable(true)
container:EnableMouse(false)
container:SetPoint("CENTER", UIParent, "CENTER", 0, -180) -- Default position

-- Add OnUpdate polling to constantly reposition Blizzard viewer (blocks Edit Mode)
-- Only runs when Edit Mode is active for performance
container:SetScript("OnUpdate", function(self)
	if not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
		return
	end

	local blizzFrame = _G[BLIZZARD_FRAME_NAME]
	if blizzFrame and blizzFrame._ActionHud_Controlled then
		if blizzFrame._ActionHud_OrigSetPoint then
			blizzFrame._ActionHud_OrigClearAllPoints(blizzFrame)
			blizzFrame._ActionHud_OrigSetPoint(blizzFrame, "CENTER", self, "CENTER")
		end
	end
end)

function TrackedBuffsLayout:OnInitialize()
	self.db = addon.db
end

function TrackedBuffsLayout:OnEnable()
	-- Initialize the container and start the reparenting process
	self:SetupContainer()
end

local function SetLayoutModified()
	if LibStub("AceConfigRegistry-3.0", true) then
		LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
	end
end

function TrackedBuffsLayout:IsLocked()
	local p = self.db and self.db.profile
	return not (p and p.layoutUnlocked)
end

function TrackedBuffsLayout:ToggleLock()
	local p = self.db and self.db.profile
	if p then
		p.layoutUnlocked = not p.layoutUnlocked
	end
	self:UpdateOverlay()
	-- Also update all other draggable containers
	local DraggableContainer = ns.DraggableContainer
	if DraggableContainer then
		DraggableContainer:UpdateAllOverlays()
	end
	SetLayoutModified()
end

function TrackedBuffsLayout:SetupContainer()
	-- Container already created at file load time
	local main = _G["ActionHudFrame"]
	if not main then
		C_Timer.After(0.5, function()
			self:SetupContainer()
		end)
		return
	end

	-- Reparent to ActionHud's main frame
	container:SetParent(main)
	container:SetScript("OnDragStart", function(s)
		s:StartMoving()
	end)
	container:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local parent = s:GetParent()
		local cx, cy = s:GetCenter()
		local px, py = parent:GetCenter()

		self.db.profile.buffsXOffset = cx - px
		self.db.profile.buffsYOffset = cy - py

		SetLayoutModified()
		addon:Log(
			string.format("TrackedBuffs saved pos: %d, %d", self.db.profile.buffsXOffset, self.db.profile.buffsYOffset),
			"layout"
		)
	end)

	-- Create drag overlay
	container.overlay = container:CreateTexture(nil, "OVERLAY")
	container.overlay:SetAllPoints()
	container.overlay:SetColorTexture(0, 1, 0, 0.4)
	container.overlay:Hide()

	local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(L["Buffs"])
	container.label = label
	label:Hide()

	-- Lay initial position from profile
	self:UpdateLayout()

	-- 2. Reparent Blizzard viewer into container
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		addon:Log("TrackedBuffsLayout: Viewer not available yet, retrying...", "discovery")
		C_Timer.After(1.0, function()
			self:SetupContainer()
		end)
		return
	end

	-- Hook SetPoint/ClearAllPoints to block EditMode interference
	self:OverrideBlizzardPositioning(blizzFrame)

	-- Hook Edit Mode to restore positioning when it closes
	if EditModeManagerFrame and not self._editModeHooked then
		EditModeManagerFrame:HookScript("OnHide", function()
			addon:Log("TrackedBuffsLayout: Edit Mode closed, restoring position", "layout")
			local frame = self:GetBlizzardFrame()
			if frame then
				frame._ActionHud_Controlled = false
				self:OverrideBlizzardPositioning(frame)
			end
			self:UpdateLayout()
		end)
		self._editModeHooked = true
	end

	-- Hook Blizzard frame's ArrangeFrames to update container size when buffs change
	-- This ensures independent mode container fits actual content dynamically
	if blizzFrame.ArrangeFrames and not blizzFrame._ActionHud_ArrangeHooked then
		hooksecurefunc(blizzFrame, "ArrangeFrames", function()
			-- Only update in independent mode to avoid circular calls
			local LM = addon:GetModule("LayoutManager", true)
			local inStack = LM and LM:IsModuleInStack("trackedBuffs")
			if not inStack then
				-- Defer to ensure we run AFTER Blizzard's layout completes
				C_Timer.After(0, function()
					self:UpdateLayout()
				end)
			end
		end)
		blizzFrame._ActionHud_ArrangeHooked = true
		addon:Log("TrackedBuffsLayout: Hooked ArrangeFrames for dynamic sizing", "layout")
	end

	addon:Log("TrackedBuffsLayout: Container setup and reparenting complete", "layout")
end

function TrackedBuffsLayout:UpdateOverlay()
	if not container then
		return
	end

	local isUnlocked = not self:IsLocked()

	if isUnlocked then
		container:EnableMouse(true)
		container:RegisterForDrag("LeftButton")
		container.overlay:Show()
		container.label:Show()
		container:SetFrameStrata("HIGH")
	else
		container:EnableMouse(false)
		container:RegisterForDrag()
		container.overlay:Hide()
		container.label:Hide()
		container:SetFrameStrata("MEDIUM")
	end
end

function TrackedBuffsLayout:GetBlizzardFrame()
	return _G[BLIZZARD_FRAME_NAME]
end

function TrackedBuffsLayout:OverrideBlizzardPositioning(blizzFrame)
	if not blizzFrame then
		return
	end

	-- Store original data (only once)
	if not blizzFrame._ActionHud_OrigSetPoint then
		blizzFrame._ActionHud_OrigParent = blizzFrame:GetParent()
		blizzFrame._ActionHud_OrigSetPoint = blizzFrame.SetPoint
		blizzFrame._ActionHud_OrigClearAllPoints = blizzFrame.ClearAllPoints

		-- Hook SetPoint to block Edit Mode interference
		blizzFrame.SetPoint = function(self, ...)
			if self._ActionHud_Controlled then
				return
			end
			return self._ActionHud_OrigSetPoint(self, ...)
		end

		-- Hook ClearAllPoints to block Edit Mode interference
		blizzFrame.ClearAllPoints = function(self, ...)
			if self._ActionHud_Controlled then
				return
			end
			return self._ActionHud_OrigClearAllPoints(self, ...)
		end
	end

	-- Reparent viewer to our container (key for Edit Mode blocking)
	blizzFrame:SetParent(container)

	-- Position within container
	blizzFrame._ActionHud_Controlled = false
	blizzFrame:ClearAllPoints()
	blizzFrame:SetPoint("CENTER", container, "CENTER")
	blizzFrame._ActionHud_Controlled = true

	blizzFrame:SetAlpha(1)
	blizzFrame:Show()
end

function TrackedBuffsLayout:ApplyInternalPosition(blizzFrame)
	if not blizzFrame then
		return
	end

	-- Use original functions to bypass our blocking hooks
	blizzFrame._ActionHud_Controlled = false
	if blizzFrame._ActionHud_OrigClearAllPoints then
		blizzFrame._ActionHud_OrigClearAllPoints(blizzFrame)
	else
		blizzFrame:ClearAllPoints()
	end
	if blizzFrame._ActionHud_OrigSetPoint then
		blizzFrame._ActionHud_OrigSetPoint(blizzFrame, "CENTER", container, "CENTER")
	else
		blizzFrame:SetPoint("CENTER", container, "CENTER")
	end
	blizzFrame._ActionHud_Controlled = true
end

function TrackedBuffsLayout:UpdateLayout()
	if not container then
		return
	end

	local p = self.db.profile
	local main = _G["ActionHudFrame"]
	if not main then
		return
	end

	-- Check if we're in stack mode
	local LM = addon:GetModule("LayoutManager", true)
	local inStack = LM and LM:IsModuleInStack("trackedBuffs")

	container:ClearAllPoints()

	-- Calculate container size based on content
	local contentHeight = self:CalculateHeight()
	local contentWidth = self:GetLayoutWidth()

	if inStack and LM then
		-- Stack mode: use full HUD width from LayoutManager
		local containerWidth = LM:GetMaxWidth()
		if containerWidth <= 0 then
			containerWidth = 120 -- Fallback
		end
		local yOffset = LM:GetModulePosition("trackedBuffs")
		container:SetSize(containerWidth, contentHeight)
		container:SetPoint("TOP", main, "TOP", 0, yOffset)
		container:EnableMouse(false)
		container:RegisterForDrag()

		-- Report height to LayoutManager
		LM:SetModuleHeight("trackedBuffs", contentHeight)
	else
		-- Independent mode: calculate size from actual visible icons
		local p = self.db.profile
		local iconSize = p.buffsIconSize or 36
		local spacingH = p.buffsSpacingH or 2
		local spacingV = p.buffsSpacingV or 2
		local maxCols = p.buffsColumns or 8
		local blizzFrame = self:GetBlizzardFrame()

		-- Count actual visible icons
		local visibleCount = 0
		if blizzFrame and blizzFrame.itemFramePool then
			pcall(function()
				for _ in blizzFrame.itemFramePool:EnumerateActive() do
					visibleCount = visibleCount + 1
				end
			end)
		end

		-- Calculate dimensions based on icon count
		local actualWidth, actualHeight
		if visibleCount == 0 then
			-- No buffs: minimum single icon size
			actualWidth = iconSize
			actualHeight = iconSize
		else
			local cols = math.min(visibleCount, maxCols)
			local rows = math.ceil(visibleCount / maxCols)
			actualWidth = (cols * iconSize) + ((cols - 1) * spacingH)
			actualHeight = (rows * iconSize) + ((rows - 1) * spacingV)
		end

		container:SetSize(actualWidth, actualHeight)

		-- Manually position each icon in a grid (like TweaksUI does)
		-- Blizzard's ArrangeFrames doesn't respect our settings
		if blizzFrame then
			blizzFrame:SetSize(actualWidth, actualHeight)

			-- Manually position icons in grid
			if blizzFrame.itemFramePool then
				local iconIndex = 0
				pcall(function()
					for icon in blizzFrame.itemFramePool:EnumerateActive() do
						local col = iconIndex % maxCols
						local row = math.floor(iconIndex / maxCols)
						local iconX = col * (iconSize + spacingH)
						local iconY = -row * (iconSize + spacingV)

						icon:ClearAllPoints()
						icon:SetPoint("TOPLEFT", blizzFrame, "TOPLEFT", iconX, iconY)
						icon:SetSize(iconSize, iconSize)

						iconIndex = iconIndex + 1
					end
				end)
			end
		end

		local xOff = p.buffsXOffset or 0
		local yOff = p.buffsYOffset or -180
		container:SetPoint("CENTER", main, "CENTER", xOff, yOff)
		container:EnableMouse(true)
		container:RegisterForDrag("LeftButton")

		-- Release height reservation when not in stack
		if LM then
			LM:SetModuleHeight("trackedBuffs", 0)
		end
	end

	-- Debug outline
	addon:UpdateLayoutOutline(container, "Tracked Buffs", "buffs")
end

-- Stack layout functions
function TrackedBuffsLayout:CalculateHeight()
	local p = self.db.profile
	if not p.styleTrackedBuffs then
		return 0
	end

	-- Try to get actual height from Blizzard frame
	local blizzFrame = _G[BLIZZARD_FRAME_NAME]
	if blizzFrame then
		-- Check if frame is visible and has reasonable height
		local height = blizzFrame:GetHeight()
		-- Only use if height is reasonable (not 0, not excessively large)
		-- Blizzard buff icons are typically 36-50px
		if height and height > 0 and height <= 100 then
			return height
		end
	end

	-- Fallback: Use single icon row height
	return p.buffsIconSize or 36
end

function TrackedBuffsLayout:GetLayoutWidth()
	local p = self.db.profile
	if not p.styleTrackedBuffs then
		return 0
	end

	-- Count actual visible icons
	local blizzFrame = self:GetBlizzardFrame()
	local visibleCount = 0
	if blizzFrame and blizzFrame.itemFramePool then
		pcall(function()
			for _ in blizzFrame.itemFramePool:EnumerateActive() do
				visibleCount = visibleCount + 1
			end
		end)
	end

	-- Calculate width based on visible icons, capped by maxColumns
	local iconSize = p.buffsIconSize or 36
	local spacing = p.buffsSpacingH or 2
	local maxCols = p.buffsColumns or 8
	local cols = math.min(math.max(visibleCount, 1), maxCols)
	return (iconSize * cols) + (spacing * math.max(cols - 1, 0))
end

-- Called by LayoutManager if it wants to tell us to update
function TrackedBuffsLayout:ApplyLayoutPosition()
	self:UpdateLayout()
end
