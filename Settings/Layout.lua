-- Settings/Layout.lua
-- Layout and Stack Order settings

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

-- Helper to get LayoutManager
local function GetLayoutManager()
	return ActionHud:GetModule("LayoutManager", true)
end

-- Build dynamic layout options based on current stack order
local function BuildLayoutArgs()
	local args = {}
	local LM = GetLayoutManager()
	if not LM then
		return args
	end

	-- HUD Stack Section (first)
	args.stackHeader = { type = "header", name = L["HUD Stack Order"], order = 1 }
	args.unlockPositions = {
		name = L["Unlock Module Positions"],
		desc = L["Unlock all modules for drag-and-drop positioning. Modules outside the HUD Stack can be dragged to new positions."],
		type = "toggle",
		order = 1.5,
		width = "full",
		get = function()
			return ActionHud.db.profile.layoutUnlocked
		end,
		set = function(_, val)
			ActionHud.db.profile.layoutUnlocked = val
			-- Also sync the main HUD lock state
			ActionHud.db.profile.locked = not val
			ActionHud:UpdateLockState()
			-- Update all draggable containers
			local DraggableContainer = ns.DraggableContainer
			if DraggableContainer then
				DraggableContainer:UpdateAllOverlays()
			end
			-- Also update TrackedBuffsLayout (has its own container)
			local TrackedBuffsLayout = ActionHud:GetModule("TrackedBuffsLayout", true)
			if TrackedBuffsLayout and TrackedBuffsLayout.UpdateOverlay then
				TrackedBuffsLayout:UpdateOverlay()
			end
			-- Trigger layout update for all modules to show overlays
			ActionHud:RefreshLayout()
		end,
	}
	args.stackDesc = {
		type = "description",
		order = 2,
		name = L["Arrange modules from top to bottom. Use arrows to reorder. Gap defines spacing after each module.\n "],
	}

	local stack = LM:GetStack()
	local baseOrder = 10

	-- Filter modules for the UI list: must be ENABLED and IN STACK
	local activeModules = {}
	for i, moduleId in ipairs(stack) do
		local moduleName = LM:GetAceModuleName(moduleId)
		local m = ActionHud:GetModule(moduleName, true)
		
		local isEnabled = false
		if moduleId == "resources" then
			isEnabled = ActionHud.db.profile.resEnabled
		elseif moduleId == "cooldowns" then
			isEnabled = ActionHud.db.profile.cdEnabled
				and LibStub("AceAddon-3.0"):GetAddon("ActionHud"):GetModule("Cooldowns"):IsEnabled()
		elseif m and m.IsEnabled then
			isEnabled = m:IsEnabled()
		end

		-- MUST be in stack to be shown here
		if isEnabled and LM:IsModuleInStack(moduleId) then
			table.insert(activeModules, { id = moduleId, stackIdx = i })
		end
	end

	for i, modInfo in ipairs(activeModules) do
		local moduleId = modInfo.id
		local stackIdx = modInfo.stackIdx
		local moduleName = LM:GetModuleName(moduleId)
		local orderBase = baseOrder + (i * 10)

		-- Module row header with position number
		args["mod_" .. i .. "_header"] = {
			type = "description",
			order = orderBase,
			name = string.format("|cffffcc00%d.|r |cffffffff%s|r", i, moduleName),
			fontSize = "medium",
			width = "full",
		}

		-- Move Up button
		args["mod_" .. i .. "_up"] = {
			name = L["Up"],
			desc = string.format(L["Move %s up in the stack"], moduleName),
			type = "execute",
			order = orderBase + 1,
			width = 0.4,
			disabled = function()
				return i == 1
			end,
			func = function()
				LM:MoveModule(moduleId, "up")
				LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
			end,
		}

		-- Move Down button
		args["mod_" .. i .. "_down"] = {
			name = L["Down"],
			desc = string.format(L["Move %s down in the stack"], moduleName),
			type = "execute",
			order = orderBase + 2,
			width = 0.4,
			disabled = function()
				return i == #activeModules
			end,
			func = function()
				LM:MoveModule(moduleId, "down")
				LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
			end,
		}

		-- Gap slider (not shown for last ACTIVE module)
		if i < #activeModules then
			args["mod_" .. i .. "_gap"] = {
				name = L["Gap After"],
				desc = string.format(L["Space between %s and the next module."], moduleName),
				type = "range",
				min = 0,
				max = 50,
				step = 1,
				order = orderBase + 3,
				width = 1.0,
				get = function()
					local g = LM:GetGaps()
					return g[stackIdx] or 0
				end,
				set = function(_, val)
					LM:SetGap(stackIdx, val)
				end,
			}
		end

		-- Spacer line
		args["mod_" .. i .. "_spacer"] = {
			type = "description",
			order = orderBase + 5,
			name = " ",
			width = "full",
		}
	end

	-- Reset button (inside HUD Stack section)
	args.resetBtn = {
		name = L["Reset to Default Order"],
		desc = L["Restore the default module order and gap values."],
		type = "execute",
		order = 99,
		width = "double",
		func = function()
			LM:ResetToDefault()
			LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
		end,
	}

	return args
end

-- Returns a function that builds the layout options dynamically
-- This allows AceConfig to rebuild it each time for UI reordering
function ns.Settings.BuildLayoutOptions(self)
	return function()
		return {
			name = L["Layout"],
			handler = ActionHud,
			type = "group",
			args = BuildLayoutArgs(),
		}
	end
end
