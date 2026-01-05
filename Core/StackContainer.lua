-- Core/StackContainer.lua
-- Container for modules positioned within the HUD stack
-- Provides full-width overlays with alignment options

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

local StackContainer = {}
ns.StackContainer = StackContainer

-- Module colors for overlays (shared with DraggableContainer)
local MODULE_COLORS = {
	actionbars = { r = 1, g = 0.5, b = 0 }, -- Orange
	resources = { r = 0, g = 1, b = 0 }, -- Green
	cooldowns = { r = 0, g = 0.5, b = 1 }, -- Blue (legacy)
	essentialCooldowns = { r = 0, g = 0.5, b = 1 }, -- Blue
	utilityCooldowns = { r = 0.5, g = 0, b = 0.8 }, -- Deep Purple
	trinkets = { r = 0.8, g = 0, b = 1 }, -- Purple
	buffs = { r = 0, g = 1, b = 1 }, -- Cyan
}

-- Module display labels
local MODULE_LABELS = {
	actionbars = L["Action Bars"],
	resources = L["Resource Bars"],
	cooldowns = L["Cooldowns"],
	essentialCooldowns = L["Essential Cooldowns"],
	utilityCooldowns = L["Utility Cooldowns"],
	trinkets = L["Trinkets"],
	buffs = L["Tracked Buffs"],
}

-- Export colors for shared use
StackContainer.MODULE_COLORS = MODULE_COLORS
StackContainer.MODULE_LABELS = MODULE_LABELS

-- Active containers registry
local activeContainers = {}

--[[
	Create a stack container for a module
	
	@param opts table
		- moduleId: string (e.g., "resources", "cooldowns")
		- parent: Frame (usually ActionHudFrame)
		- db: AceDB profile reference
		- contentWidth: number (width of actual content, for alignment)
		- contentHeight: number (height of content)
		
	@return Frame container
]]
function StackContainer:Create(opts)
	local moduleId = opts.moduleId
	local parent = opts.parent or _G["ActionHudFrame"]
	local db = opts.db
	local contentWidth = opts.contentWidth or 100
	local contentHeight = opts.contentHeight or 30

	if not parent then
		return nil
	end

	-- Create container frame (full width of parent)
	local container = CreateFrame("Frame", "ActionHud" .. moduleId .. "StackContainer", parent)
	container:SetHeight(contentHeight)
	container.moduleId = moduleId

	-- Create overlay (colored background, no border)
	container.overlay = container:CreateTexture(nil, "BACKGROUND")
	container.overlay:SetAllPoints()
	local color = MODULE_COLORS[moduleId] or { r = 0.5, g = 0.5, b = 0.5 }
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
	container._contentWidth = contentWidth
	container._contentHeight = contentHeight

	-- Register in active containers
	activeContainers[moduleId] = container

	return container
end

-- Update container to match parent width
function StackContainer:UpdateSize(container)
	if not container then
		return
	end

	local parent = container:GetParent()
	if parent then
		container:SetWidth(parent:GetWidth())
	end
end

-- Apply alignment to content within the container
-- alignment: "LEFT", "CENTER", "RIGHT"
function StackContainer:UpdateAlignment(container, contentFrame, alignment)
	if not container or not contentFrame then
		return
	end

	alignment = alignment or "CENTER"
	contentFrame:ClearAllPoints()

	if alignment == "LEFT" then
		contentFrame:SetPoint("LEFT", container, "LEFT", 0, 0)
	elseif alignment == "RIGHT" then
		contentFrame:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	else -- CENTER
		contentFrame:SetPoint("CENTER", container, "CENTER", 0, 0)
	end
end

-- Check if global layout is unlocked
function StackContainer:IsUnlocked(db)
	return db and db.profile and db.profile.layoutUnlocked
end

-- Update overlay visibility based on lock state
function StackContainer:UpdateOverlay(container)
	if not container then
		return
	end

	local isUnlocked = StackContainer:IsUnlocked(container._db)

	if isUnlocked then
		container.overlay:Show()
		container.label:Show()
	else
		container.overlay:Hide()
		container.label:Hide()
	end
end

-- Update all container overlays (called when lock state changes)
function StackContainer:UpdateAllOverlays()
	for _, container in pairs(activeContainers) do
		StackContainer:UpdateOverlay(container)
	end
end

-- Get container by module ID
function StackContainer:GetContainer(moduleId)
	return activeContainers[moduleId]
end

-- Unregister container (when module removed from stack)
function StackContainer:Unregister(moduleId)
	activeContainers[moduleId] = nil
end
