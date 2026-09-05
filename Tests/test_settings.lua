-- ActionHud settings behavior tests

local locale = setmetatable({}, { __index = function(_, key) return key end })
local notified
local registry = {
	NotifyChange = function(_, key)
		notified = key
	end,
}

local calls = {}
local modules = {
	ActionBars = {
		ApplyEnabledState = function() calls.actionBarsApplied = true end,
		UpdateLayout = function() calls.actionBarsUpdated = true end,
		IsEnabled = function() return true end,
	},
	Resources = { IsEnabled = function() return true end },
	Trinkets = {
		ApplyEnabledState = function() calls.trinketsApplied = true end,
		UpdateLayout = function() calls.trinketsUpdated = true end,
		IsEnabled = function() return true end,
	},
	UnitFrames = {
		UpdateLayout = function() calls.unitFramesUpdated = true end,
		IsEnabled = function() return true end,
	},
}

local layoutManager = {
	GetStack = function()
		return { "resources", "trinkets", "actionBars" }
	end,
	GetAceModuleName = function(_, id)
		return ({ resources = "Resources", actionBars = "ActionBars", trinkets = "Trinkets" })[id]
	end,
	GetModuleName = function(_, id)
		return id
	end,
	IsModuleInStack = function()
		return true
	end,
	MoveModule = function(_, id, direction)
		calls.movedId, calls.movedDirection = id, direction
		calls.moveCount = (calls.moveCount or 0) + 1
	end,
	GetGaps = function()
		return { 4, 4, 0 }
	end,
	SetGap = function() end,
	ResetToDefault = function()
		calls.layoutReset = true
	end,
}
modules.LayoutManager = layoutManager

local profile = {
	actionBarsEnabled = true,
	actionBarsIncludeInStack = false,
	actionBarsXOffset = 99,
	actionBarsYOffset = 99,
	resEnabled = true,
	trinketsEnabled = true,
	trinketsXOffset = 150,
	trinketsYOffset = 0,
	ufConfig = {
		player = {},
		target = {},
		targettarget = {},
		focus = {},
	},
}

local defaults = {
	profile = {
		actionBarsXOffset = 0,
		actionBarsYOffset = 0,
		trinketsXOffset = 80,
		trinketsYOffset = 23,
		ufConfig = {
			player = { xOffset = -189, yOffset = 13 },
			target = { xOffset = 210, yOffset = 13 },
			targettarget = { xOffset = 370, yOffset = 13 },
			focus = { xOffset = -353, yOffset = 19 },
		},
	},
}

local addon = { db = { profile = profile, defaults = defaults } }
function addon:GetModule(name)
	return modules[name]
end
function addon:RefreshLayout()
	calls.refreshed = true
end

LibStub = function(name)
	if name == "AceLocale-3.0" then
		return { GetLocale = function() return locale end }
	elseif name == "AceAddon-3.0" then
		return { GetAddon = function() return addon end }
	elseif name == "AceConfigRegistry-3.0" then
		return registry
	elseif name == "LibSharedMedia-3.0" then
		return { HashTable = function() return {} end }
	end
	error("unexpected library: " .. tostring(name))
end

local ns = { Settings = {}, Utils = { DeepCopy = function(value) return value end } }
assert(loadfile("Settings/ActionBars.lua"))("ActionHud", ns)
assert(loadfile("Settings/Trinkets.lua"))("ActionHud", ns)
assert(loadfile("Settings/UnitFrames.lua"))("ActionHud", ns)
assert(loadfile("Settings/Layout.lua"))("ActionHud", ns)

local actionOptions = ns.Settings.BuildActionBarsOptions(addon)
actionOptions.args.enable.set(nil, false)
assert(profile.actionBarsEnabled == false and calls.actionBarsApplied and calls.refreshed,
	"Action Bars toggle must persist and apply its runtime state")
actionOptions.args.resetPosition.func()
assert(profile.actionBarsXOffset == 0 and profile.actionBarsYOffset == 0 and calls.actionBarsUpdated,
	"Action Bars reset must use profile defaults")

calls.refreshed = false
local trinketOptions = ns.Settings.BuildTrinketsOptions(addon)
trinketOptions.args.enable.set(nil, false)
assert(profile.trinketsEnabled == false and calls.trinketsApplied and calls.refreshed,
	"Trinkets toggle must immediately apply its runtime state")
trinketOptions.args.resetPosition.func()
assert(profile.trinketsXOffset == 80 and profile.trinketsYOffset == 23,
	"Trinkets reset must use profile defaults")

local unitOptions = ns.Settings.BuildUnitFramesOptions(addon)
unitOptions.args.focus.args.dimensions.args.resetPosition.func()
assert(profile.ufConfig.focus.xOffset == -353 and profile.ufConfig.focus.yOffset == 19,
	"Unit frame reset must restore that frame's profile defaults")

profile.actionBarsEnabled = true
profile.trinketsEnabled = false
local layoutOptions = ns.Settings.BuildLayoutOptions(addon)()
layoutOptions.args.mod_2_up.func()
assert(calls.movedId == "actionBars" and calls.movedDirection == "up",
	"Layout move controls must target the displayed module")
assert(calls.moveCount == 2, "Layout controls must move across modules hidden from the active list")
assert(notified == "ActionHud_Layout", "Layout changes must refresh the registered Layout options table")

print("SUCCESS: settings toggles, resets, and layout refresh behavior")
