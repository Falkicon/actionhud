-- LayoutManager.lua
-- Central layout system for ActionHud vertical stack positioning

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LayoutManager = addon:NewModule("LayoutManager", "AceEvent-3.0")
ns.LayoutManager = LayoutManager

-- Module registry: modules that CAN be in the stack
-- Each module has a display name, default includeInStack, and profile key for the toggle
local MODULE_REGISTRY = {
	resources = {
		displayName = L["Resource Bars"],
		defaultInStack = true,
		profileKey = "resourcesIncludeInStack",
		moduleName = "Resources",
	},
	actionBars = {
		displayName = L["Action Bars"],
		defaultInStack = true,
		profileKey = "actionBarsIncludeInStack",
		moduleName = "ActionBars",
	},
	-- DISABLED 2026-01-18: TweaksUI handles these better. Blizzard frame reskinning too fragile.
	-- essentialCooldowns = {
	-- 	displayName = L["Essential Cooldowns"],
	-- 	defaultInStack = true,
	-- 	profileKey = "essentialCooldownsIncludeInStack",
	-- 	moduleName = "EssentialCooldownsLayout",
	-- },
	-- utilityCooldowns = {
	-- 	displayName = L["Utility Cooldowns"],
	-- 	defaultInStack = true,
	-- 	profileKey = "utilityCooldownsIncludeInStack",
	-- 	moduleName = "UtilityCooldownsLayout",
	-- },
	trinkets = {
		displayName = L["Trinkets"],
		defaultInStack = false,
		profileKey = "trinketsIncludeInStack",
		moduleName = "Trinkets",
	},
	-- trackedBuffs = {
	-- 	displayName = L["Tracked Buffs"],
	-- 	defaultInStack = false,
	-- 	profileKey = "trackedBuffsIncludeInStack",
	-- 	moduleName = "TrackedBuffsLayout",
	-- },
}

-- Default stack order and gaps (only modules with defaultInStack=true)
local DEFAULT_STACK = { "resources", "actionBars" }
local DEFAULT_GAPS = { 4, 0 }

-- Complete measurement snapshot owned by the layout pass.
local moduleHeights = {}
local moduleWidths = {}
local pendingLayoutUpdate = false
local layoutScheduled = false
local layoutGeneration = 0
local layoutRunning = false
local layoutPhase

function LayoutManager:OnInitialize()
	-- Nothing needed here - we use addon.db directly
end

function LayoutManager:OnEnable()
	-- Ensure layout data exists
	self:EnsureLayoutData()
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
	self:RequestLayout("enable")
end

function LayoutManager:OnDisable()
	layoutGeneration = layoutGeneration + 1
	layoutScheduled = false
	pendingLayoutUpdate = false
	self:UnregisterAllEvents()
end

function LayoutManager:OnPlayerRegenEnabled()
	if pendingLayoutUpdate then self:RequestLayout("combat ended") end
end

-- One generation-bound callback owns every module's layout work. Requests made
-- during reconciliation are already represented by the pass about to run.
function LayoutManager:RequestLayout()
	if not self:IsEnabled() then return end
	if layoutPhase == "reconcile" then return end
	pendingLayoutUpdate = true
	if InCombatLockdown() or layoutScheduled or layoutRunning then return end
	layoutScheduled = true
	local generation = layoutGeneration
	C_Timer.After(0, function()
		if generation ~= layoutGeneration then return end
		layoutScheduled = false
		if not self:IsEnabled() or not pendingLayoutUpdate then return end
		if InCombatLockdown() then return end
		self:RunLayoutPass()
	end)
end

function LayoutManager:TriggerLayoutUpdate()
	self:RequestLayout("legacy request")
end

-- Get profile safely (addon.db may not be set during very early calls)
local function GetProfile()
	if addon.db and addon.db.profile then
		return addon.db.profile
	end
	return nil
end

-- Ensure layout table exists with valid data
function LayoutManager:EnsureLayoutData()
	local p = GetProfile()
	if not p then
		return
	end -- DB not ready yet
	if not p.layout then
		p.layout = {
			stack = CopyTable(DEFAULT_STACK),
			gaps = CopyTable(DEFAULT_GAPS),
		}
	end

	-- Validate stack has all registered modules (not just DEFAULT_STACK)
	local hasModule = {}
	for _, id in ipairs(p.layout.stack) do
		hasModule[id] = true
	end

	-- Add any missing registered modules (including trinkets when enabled)
	for moduleId in pairs(MODULE_REGISTRY) do
		if not hasModule[moduleId] then
			-- Add the module to the stack array so it can be positioned
			table.insert(p.layout.stack, moduleId)
			table.insert(p.layout.gaps, 0)
		end
	end

	-- Ensure gaps array matches stack length
	while #p.layout.gaps < #p.layout.stack do
		table.insert(p.layout.gaps, 0)
	end
end

-- Get the ordered stack
function LayoutManager:GetStack()
	self:EnsureLayoutData()
	local p = GetProfile()
	if p and p.layout then
		return p.layout.stack
	end
	return CopyTable(DEFAULT_STACK) -- Return default if not ready
end

-- Get gaps array
function LayoutManager:GetGaps()
	self:EnsureLayoutData()
	local p = GetProfile()
	if p and p.layout then
		return p.layout.gaps
	end
	return CopyTable(DEFAULT_GAPS) -- Return default if not ready
end

-- Get display name for a module
function LayoutManager:GetModuleName(moduleId)
	local info = MODULE_REGISTRY[moduleId]
	return info and info.displayName or moduleId
end

-- Get actual module name (for addon:GetModule())
function LayoutManager:GetAceModuleName(moduleId)
	local info = MODULE_REGISTRY[moduleId]
	return info and info.moduleName or moduleId
end

-- Get all registered module IDs
function LayoutManager:GetAllModuleIds()
	local ids = {}
	for id in pairs(MODULE_REGISTRY) do
		table.insert(ids, id)
	end
	return ids
end

-- Check if a module is currently included in the stack
function LayoutManager:IsModuleInStack(moduleId)
	local info = MODULE_REGISTRY[moduleId]
	if not info then
		return false
	end

	-- ActionBars is always in stack (anchor)
	if not info.profileKey then
		return true
	end

	local p = GetProfile()
	if p and p[info.profileKey] ~= nil then
		return p[info.profileKey]
	end
	return info.defaultInStack
end

-- Set whether a module is included in the stack
function LayoutManager:SetModuleInStack(moduleId, inStack)
	local info = MODULE_REGISTRY[moduleId]
	if not info or not info.profileKey then
		return
	end -- Can't change ActionBars

	local p = GetProfile()
	if not p then
		return
	end

	p[info.profileKey] = inStack

	-- If adding to stack and not already in stack order, add it
	if inStack then
		local stack = self:GetStack()
		local found = false
		for _, id in ipairs(stack) do
			if id == moduleId then
				found = true
				break
			end
		end
		if not found then
			table.insert(stack, moduleId)
			local gaps = self:GetGaps()
			table.insert(gaps, 0)
		end
	else
		-- When removing from stack, clear the stored height so space is reclaimed
		self:SetModuleHeight(moduleId, 0)
	end

	self:TriggerLayoutUpdate()
end

-- Get active stack (only modules with includeInStack=true)
function LayoutManager:GetActiveStack()
	local stack = self:GetStack()
	local active = {}
	for _, moduleId in ipairs(stack) do
		if self:IsModuleInStack(moduleId) then
			table.insert(active, moduleId)
		end
	end
	return active
end

-- Get the profile key for a module's includeInStack toggle
function LayoutManager:GetModuleProfileKey(moduleId)
	local info = MODULE_REGISTRY[moduleId]
	return info and info.profileKey
end

-- Internal measurement storage; runtime modules must not publish measurements.
function LayoutManager:SetModuleHeight(moduleId, height)
	moduleHeights[moduleId] = height or 0
end

-- Get height for a module
function LayoutManager:GetModuleHeight(moduleId)
	if not self:IsModuleInStack(moduleId) then
		return 0
	end
	return moduleHeights[moduleId] or 0
end

-- Calculate the Y position for a module (offset from container TOP)
-- Returns: yOffset (negative value, since we anchor from TOP going down)
function LayoutManager:GetModulePosition(moduleId)
	local stack = self:GetStack()
	local gaps = self:GetGaps()

	local yOffset = 0
	for i, id in ipairs(stack) do
		if id == moduleId then
			return -yOffset -- Return negative for TOPLEFT anchoring
		end
		-- Add this module's height + the gap after it (only if module has height)
		local h = self:GetModuleHeight(id)
		if h > 0 then
			yOffset = yOffset + h + (gaps[i] or 0)
		end
	end

	-- Module not found, return 0
	return 0
end

-- Calculate total stack height
function LayoutManager:GetStackHeight()
	local stack = self:GetStack()
	local gaps = self:GetGaps()

	local totalHeight = 0
	local previousVisibleIndex
	for i, id in ipairs(stack) do
		local h = self:GetModuleHeight(id)
		if h > 0 then
			if previousVisibleIndex then
				totalHeight = totalHeight + (gaps[previousVisibleIndex] or 0)
			end
			totalHeight = totalHeight + h
			previousVisibleIndex = i
		end
	end

	return totalHeight
end

-- Get the index of a module in the stack
function LayoutManager:GetModuleIndex(moduleId)
	local stack = self:GetStack()
	for i, id in ipairs(stack) do
		if id == moduleId then
			return i
		end
	end
	return nil
end

-- Move a module up or down in the stack
-- direction: "up" (toward index 1) or "down" (toward end)
function LayoutManager:MoveModule(moduleId, direction)
	local stack = self:GetStack()
	local gaps = self:GetGaps()
	local idx = self:GetModuleIndex(moduleId)

	if not idx then
		return false
	end

	local newIdx
	if direction == "up" and idx > 1 then
		newIdx = idx - 1
	elseif direction == "down" and idx < #stack then
		newIdx = idx + 1
	else
		return false -- Can't move
	end

	-- Swap in stack
	stack[idx], stack[newIdx] = stack[newIdx], stack[idx]

	-- Swap gaps (gaps follow their modules)
	gaps[idx], gaps[newIdx] = gaps[newIdx], gaps[idx]

	-- Trigger full layout update
	self:TriggerLayoutUpdate()

	return true
end

-- Set gap after a module (by index)
function LayoutManager:SetGap(index, value)
	local gaps = self:GetGaps()
	if index >= 1 and index <= #gaps then
		gaps[index] = value
		self:TriggerLayoutUpdate()
	end
end

-- Get gap after a module (by index)
function LayoutManager:GetGap(index)
	local gaps = self:GetGaps()
	return gaps[index] or 0
end

-- Reset to default order
function LayoutManager:ResetToDefault()
	local p = GetProfile()
	if not p then
		return
	end
	p.layout = {
		stack = CopyTable(DEFAULT_STACK),
		gaps = CopyTable(DEFAULT_GAPS),
	}
	self:TriggerLayoutUpdate()
end

-- Prepare content before measuring, then position from a complete size snapshot.
-- Modules never write these measurements or recursively trigger this pass.
function LayoutManager:RunLayoutPass()
	if layoutRunning or not self:IsEnabled() then return end
	if InCombatLockdown() then pendingLayoutUpdate = true; return end
	layoutRunning = true
	pendingLayoutUpdate = false
	local perfStart = ns.RecordPerformance and debugprofilestop()
	local participants = {}
	for _, id in ipairs(self:GetStack()) do
		local info = MODULE_REGISTRY[id]
		local module = info and addon:GetModule(info.moduleName, true)
		if module then participants[#participants + 1] = { id = id, module = module } end
	end
	local unitFrames = addon:GetModule("UnitFrames", true)
	if unitFrames then participants[#participants + 1] = { module = unitFrames } end

	local ok, failure = pcall(function()
		layoutPhase = "reconcile"
		for _, entry in ipairs(participants) do
			local module = entry.module
			if module._pendingEnabledState and module.ApplyEnabledState then module:ApplyEnabledState() end
		end
		layoutPhase = "prepare"
		for _, entry in ipairs(participants) do
			local module = entry.module
			if module:IsEnabled() and module._runtimeActive and module.PrepareLayout then module:PrepareLayout() end
		end
		layoutPhase = "measure"
		moduleHeights, moduleWidths = {}, {}
		for _, entry in ipairs(participants) do
			local module, id = entry.module, entry.id
			if id and self:IsModuleInStack(id) and module:IsEnabled() and module._runtimeActive then
				moduleHeights[id] = module.CalculateHeight and module:CalculateHeight() or 0
				moduleWidths[id] = module.GetLayoutWidth and module:GetLayoutWidth() or 0
			end
		end
		self:UpdateContainerSize()
		layoutPhase = "position"
		for _, entry in ipairs(participants) do
			local module = entry.module
			if module:IsEnabled() and module._runtimeActive and module.ApplyLayoutPosition then module:ApplyLayoutPosition() end
		end
		layoutPhase = "render"
		for _, entry in ipairs(participants) do
			local module = entry.module
			if module:IsEnabled() and module._runtimeActive and module.RenderLayout then module:RenderLayout() end
		end
	end)
	layoutPhase = nil
	layoutRunning = false
	if not ok then error(failure, 0) end
	if perfStart then ns.RecordPerformance("LayoutRecalc", perfStart) end
	if pendingLayoutUpdate then self:RequestLayout("changed during pass") end
end

-- Update the main HUD container size
function LayoutManager:UpdateContainerSize()
	local main = _G["ActionHudFrame"]
	if not main then
		return
	end

	if InCombatLockdown() then
		pendingLayoutUpdate = true
		return
	end

	local totalHeight = self:GetStackHeight()

	-- Width is determined by the widest visible module in stack
	local maxWidth = self:GetMaxWidth()

	-- Minimum size: 30x30 so the container can still be moved as an anchor
	-- even when no modules are in the stack
	local MIN_SIZE = 30

	if maxWidth <= 0 or totalHeight <= 0 then
		-- Empty stack: use minimum size so container remains movable
		main:SetSize(MIN_SIZE, MIN_SIZE)
		main:Show()
		return
	end

	main:SetSize(maxWidth, totalHeight)
	main:Show()
end

-- Get the maximum width of visible modules in stack
-- Heights are populated in the first layout pass so hidden modules cannot widen the HUD.
function LayoutManager:GetMaxWidth()
	local maxWidth = 0
	for _, id in ipairs(self:GetActiveStack()) do
		if self:GetModuleHeight(id) > 0 then maxWidth = math.max(maxWidth, moduleWidths[id] or 0) end
	end
	return maxWidth > 0 and maxWidth or 120
end

-- Get the main container frame
function LayoutManager:GetContainer()
	return _G["ActionHudFrame"]
end

-- Migration: Convert old position settings to new layout structure
-- Also cleans up old trackedBuffs entries (now independently positioned)
function LayoutManager:MigrateOldSettings()
	local p = GetProfile()
	if not p then
		return
	end

	-- If layout exists, clean up any old trackedBuffs entries but keep valid modules
	if p.layout then
		local cleanStack = {}
		local cleanGaps = {}
		for i, id in ipairs(p.layout.stack) do
			-- Keep all registered modules (resources, actionBars, cooldowns, trinkets)
			if MODULE_REGISTRY[id] then
				table.insert(cleanStack, id)
				table.insert(cleanGaps, p.layout.gaps[i] or 0)
			end
		end
		p.layout.stack = cleanStack
		p.layout.gaps = cleanGaps
		return
	end

	-- Build new stack based on old position settings
	local topModules = {}
	local bottomModules = {}

	-- Resources
	if p.resPosition == "TOP" or p.resPosition == nil then
		table.insert(topModules, { id = "resources", gap = p.resOffset or 1 })
	else
		table.insert(bottomModules, { id = "resources", gap = p.resOffset or 1 })
	end

	-- Cooldowns
	if p.cdPosition == "TOP" then
		table.insert(topModules, { id = "cooldowns", gap = p.cdGap or 4 })
	else
		table.insert(bottomModules, { id = "cooldowns", gap = p.cdGap or 4 })
	end

	-- Build final stack: top modules (reversed), actionBars, bottom modules
	local stack = {}
	local gaps = {}

	-- Top modules go first (furthest from actionBars to closest)
	for i = #topModules, 1, -1 do
		table.insert(stack, topModules[i].id)
		table.insert(gaps, topModules[i].gap)
	end

	-- ActionBars in the middle
	table.insert(stack, "actionBars")
	table.insert(gaps, 0) -- Gap after actionBars

	-- Bottom modules (closest to actionBars to furthest)
	for _, mod in ipairs(bottomModules) do
		table.insert(stack, mod.id)
		table.insert(gaps, mod.gap)
	end

	-- Store the new layout
	p.layout = {
		stack = stack,
		gaps = gaps,
	}

	addon:Log("Layout migration complete: " .. table.concat(stack, " -> "), "debug")
end
