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
	LayoutManager = { enabled = true, IsEnabled = function(self) return self.enabled end, UnregisterAllEvents = function() end }
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

addon.db.profile.resourcesIncludeInStack = false
assert(LayoutManager:GetStackHeight() == 5, "profile changes must ignore cached heights of excluded modules")
assert(LayoutManager:GetModulePosition("trinkets") == 0, "excluded modules must not shift active modules")

local combat = false
InCombatLockdown = function() return combat end
local pending = {}
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
local function flush()
	local callbacks = pending
	pending = {}
	for _, callback in ipairs(callbacks) do callback() end
end
function addon:Log() end
function addon:GetModule() return nil end
LayoutManager:TriggerLayoutUpdate()
flush()
assert(LayoutManager:GetStackHeight() == 0, "missing modules must release old height reservations")

local updated, positioned = false, false
local independent = {
	_runtimeActive = true, IsEnabled = function() return true end,
	PrepareLayout = function() updated = true end,
	ApplyLayoutPosition = function() assert(updated); positioned = true end,
}
function addon:GetModule(name)
	if name == "Resources" then return independent end
end
LayoutManager:TriggerLayoutUpdate()
flush()
assert(positioned, "moving a module outside the stack must apply its independent anchor")

-- Bursts coalesce, consume the latest profile, and never recurse.
local passes, latest = 0
independent.PrepareLayout = function() passes = passes + 1; latest = addon.db.profile.testValue end
addon.db.profile.testValue = 1
LayoutManager:RequestLayout("first")
addon.db.profile.testValue = 2
LayoutManager:RequestLayout("second")
assert(#pending == 1, "same-frame requests must coalesce")
flush()
assert(passes == 1 and latest == 2 and #pending == 0, "a pass must use latest state without rescheduling itself")
combat = true
LayoutManager:RequestLayout("combat")
assert(#pending == 0, "combat work must wait for the regen event")
combat = false
LayoutManager:OnPlayerRegenEnabled()
flush()
assert(passes == 2, "combat work must resume once")
LayoutManager:RequestLayout("old lifecycle")
local stale = pending[1]
pending = {}
LayoutManager.enabled = false
LayoutManager:OnDisable()
LayoutManager.enabled = true
LayoutManager:RequestLayout("new lifecycle")
stale()
assert(#pending == 1 and passes == 2, "stale callback must not clear new scheduled state")
flush()
assert(passes == 3, "new lifecycle must still run")
local rendered = 0
independent.RenderLayout = function()
	rendered = rendered + 1
	if rendered == 1 then
		addon.db.profile.testValue = 3
		LayoutManager:RequestLayout("changed during rendering")
	end
end
LayoutManager:RequestLayout("render change")
flush()
assert(#pending == 1, "changes during a pass must schedule one follow-up")
flush()
assert(latest == 3 and #pending == 0 and rendered == 2, "follow-up must consume the change and settle")

combat = true
independent._pendingEnabledState = true
local reconciled
independent.ApplyEnabledState = function(self)
	reconciled = addon.db.profile.testValue
	self._pendingEnabledState = nil
	LayoutManager:RequestLayout("reconciled lifecycle")
end
LayoutManager:RequestLayout("deferred lifecycle")
addon.db.profile.testValue = 4
combat = false
LayoutManager:OnPlayerRegenEnabled()
flush()
assert(reconciled == 4 and latest == 4 and #pending == 0,
	"regen must reconcile latest desired state before preparing without a redundant pass")
print("SUCCESS: layout ordering, coalescing, combat deferral, and lifecycle cancellation")
