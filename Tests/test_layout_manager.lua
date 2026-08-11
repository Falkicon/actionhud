--[[
	ActionHud - Layout manager tests
	Run from addon root: lua Tests/test_layout_manager.lua
]]

_G = _G or {}

local LayoutManager
local addon = {
	db = {
		profile = {
			layout = {
				stack = { "resources", "actionBars", "trinkets" },
				gaps = { 4, 99, 0 },
			},
			resourcesIncludeInStack = true,
			actionBarsIncludeInStack = true,
			trinketsIncludeInStack = true,
		},
	},
}

function addon:NewModule()
	LayoutManager = {}
	return LayoutManager
end

LibStub = function(name)
	if name == "AceAddon-3.0" then
		return {
			GetAddon = function()
				return addon
			end,
		}
	elseif name == "AceLocale-3.0" then
		return {
			GetLocale = function()
				return setmetatable({}, { __index = function(_, key) return key end })
			end,
		}
	end
	error("unexpected library: " .. tostring(name))
end

assert(loadfile("LayoutManager.lua"))("ActionHud", {})

LayoutManager:SetModuleHeight("resources", 10)
LayoutManager:SetModuleHeight("actionBars", 0)
LayoutManager:SetModuleHeight("trinkets", 5)

assert(LayoutManager:GetStackHeight() == 19, "hidden trailing modules must not add their gaps")
assert(LayoutManager:GetModulePosition("trinkets") == -14, "visible module position changed")

print("SUCCESS: layout gaps apply only between visible modules")
