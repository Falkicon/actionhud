--[[
	ActionHud - Unit event router tests
	Run from addon root: lua Tests/test_unit_event_router.lua
]]

_G = _G or {}
unpack = unpack or table.unpack

local pending = {}
C_Timer = {
	After = function(_, callback)
		table.insert(pending, callback)
	end,
}

wipe = function(target)
	for key in pairs(target) do
		target[key] = nil
	end
end

local createdFrames = {}
CreateFrame = function()
	local frame = { registrations = {} }
	function frame:SetScript(_, callback)
		self.callback = callback
	end
	function frame:RegisterUnitEvent(event, ...)
		self.registrations[event] = { ... }
	end
	function frame:UnregisterAllEvents()
		wipe(self.registrations)
	end
	table.insert(createdFrames, frame)
	return frame
end

local ns = {}
assert(loadfile("Core/UnitEventRouter.lua"))("ActionHud", ns)
local router = assert(ns.UnitEventRouter)

local calls = {}
local owner = {
	OnUnitEvent = function(_, event, unit)
		table.insert(calls, event .. ":" .. unit)
	end,
}

router:Register(owner, "UNIT_HEALTH", "OnUnitEvent", "player", "target")
router:Register(owner, "UNIT_POWER_UPDATE", "OnUnitEvent", "player")
assert(#pending == 1, "registrations should be coalesced into one clean timer")
pending[1]()

local frame = assert(createdFrames[1])
assert(#frame.registrations.UNIT_HEALTH == 2, "UNIT_HEALTH scope changed")
assert(frame.registrations.UNIT_HEALTH[1] == "player", "player scope missing")
assert(frame.registrations.UNIT_HEALTH[2] == "target", "target scope missing")
assert(#frame.registrations.UNIT_POWER_UPDATE == 1, "UNIT_POWER_UPDATE scope changed")

frame.callback(frame, "UNIT_HEALTH", "target")
assert(calls[1] == "UNIT_HEALTH:target", "unit event was not dispatched")

router:UnregisterAll(owner)
assert(next(frame.registrations) == nil, "unit events were not unregistered")

print("SUCCESS: unit events are scoped and cleanly unregistered")
