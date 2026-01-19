-- Core/DraggableContainer.lua
-- Shared utility for creating draggable module containers
-- Used by modules when positioned independently (outside HUD stack)

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

local DraggableContainer = {}
ns.DraggableContainer = DraggableContainer

-- Module colors for drag overlays
local MODULE_COLORS = {
	resources = { r = 0, g = 1, b = 0 }, -- Green
	cooldowns = { r = 0, g = 0.5, b = 1 }, -- Blue (legacy)
	essentialCooldowns = { r = 0, g = 0.5, b = 1 }, -- Blue
	utilityCooldowns = { r = 0.5, g = 0, b = 0.8 }, -- Deep Purple
	trinkets = { r = 0.8, g = 0, b = 1 }, -- Purple
	buffs = { r = 0, g = 1, b = 1 }, -- Cyan
	ufPlayer = { r = 0, g = 0.8, b = 0.3 }, -- Green
	ufTarget = { r = 1, g = 0.2, b = 0.2 }, -- Red
	ufFocus = { r = 1, g = 0.6, b = 0 }, -- Orange
}

-- Module display labels
local MODULE_LABELS = {
	resources = L["Resource Bars"],
	cooldowns = L["Cooldowns"],
	essentialCooldowns = L["Essential Cooldowns"],
	utilityCooldowns = L["Utility Cooldowns"],
	trinkets = L["Trinkets"],
	buffs = L["Tracked Buffs"],
	ufPlayer = L["Player Frame"],
	ufTarget = L["Target Frame"],
	ufFocus = L["Focus Frame"],
}

-- Active containers registry
local activeContainers = {}

--[[
	Create a draggable container for a module
	
	@param opts table
		- moduleId: string (e.g., "resources", "cooldowns")
		- parent: Frame (usually ActionHudFrame)
		- db: AceDB profile reference
		- xKey: string (profile key for X offset, e.g., "resourcesXOffset")
		- yKey: string (profile key for Y offset)
		- defaultX: number (default X position)
		- defaultY: number (default Y position)
		- size: table { width, height } (optional, default 40x40)
		
	@return Frame container
]]
function DraggableContainer:Create(opts)
	local moduleId = opts.moduleId
	local parent = opts.parent or _G["ActionHudFrame"]
	local db = opts.db
	local xKey = opts.xKey
	local yKey = opts.yKey
	local defaultX = opts.defaultX or 0
	local defaultY = opts.defaultY or -100
	local size = opts.size or { width = 40, height = 40 }

	if not parent then
		return nil
	end

	-- Create container frame
	local container = CreateFrame("Frame", "ActionHud" .. moduleId .. "Container", parent)
	container:SetSize(size.width, size.height)
	container:SetMovable(true)
	container:SetClampedToScreen(true)
	container.moduleId = moduleId

	-- Drag handlers
	container:SetScript("OnDragStart", function(self)
		if DraggableContainer:IsUnlocked(db) then
			self:StartMoving()
		end
	end)

	container:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()

		-- Calculate offset from parent center
		local cx, cy = self:GetCenter()
		local px, py = parent:GetCenter()
		local xOffset = cx - px
		local yOffset = cy - py

		-- Save to profile
		db.profile[xKey] = xOffset
		db.profile[yKey] = yOffset

		-- Notify settings UI
		if LibStub("AceConfigRegistry-3.0", true) then
			LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
		end
	end)

	-- Create drag overlay (colored background, no border)
	container.overlay = container:CreateTexture(nil, "BACKGROUND")
	container.overlay:SetAllPoints()
	local color = MODULE_COLORS[moduleId] or { r = 1, g = 1, b = 1 }
	container.overlay:SetColorTexture(color.r, color.g, color.b, 0.4)
	container.overlay:Hide()

	-- Create label (Arial with outline, centered)
	container.label = container:CreateFontString(nil, "OVERLAY")
	container.label:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	container.label:SetPoint("CENTER")
	container.label:SetText(MODULE_LABELS[moduleId] or moduleId)
	container.label:Hide()

	-- Store references
	container._db = db
	container._xKey = xKey
	container._yKey = yKey
	container._defaultX = defaultX
	container._defaultY = defaultY

	-- Register in active containers
	activeContainers[moduleId] = container

	-- Apply initial position
	DraggableContainer:UpdatePosition(container)
	DraggableContainer:UpdateOverlay(container)

	return container
end

-- Check if global layout is unlocked
function DraggableContainer:IsUnlocked(db)
	return db and db.profile and db.profile.layoutUnlocked
end

-- Update container position from profile
function DraggableContainer:UpdatePosition(container)
	if not container then
		return
	end

	local db = container._db
	local xOffset = db.profile[container._xKey] or container._defaultX
	local yOffset = db.profile[container._yKey] or container._defaultY

	container:ClearAllPoints()
	container:SetPoint("CENTER", container:GetParent(), "CENTER", xOffset, yOffset)
end

-- Update overlay visibility based on lock state
function DraggableContainer:UpdateOverlay(container)
	if not container then
		return
	end

	local isUnlocked = DraggableContainer:IsUnlocked(container._db)

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

-- Reset position to defaults
function DraggableContainer:ResetPosition(container)
	if not container then
		return
	end

	local db = container._db
	db.profile[container._xKey] = container._defaultX
	db.profile[container._yKey] = container._defaultY

	DraggableContainer:UpdatePosition(container)

	-- Notify settings UI
	if LibStub("AceConfigRegistry-3.0", true) then
		LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
	end
end

-- Update all container overlays (called when lock state changes)
function DraggableContainer:UpdateAllOverlays()
	for _, container in pairs(activeContainers) do
		DraggableContainer:UpdateOverlay(container)
	end
end

-- Get container by module ID
function DraggableContainer:GetContainer(moduleId)
	return activeContainers[moduleId]
end
