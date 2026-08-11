local addonName, ns = ...

-- AceEvent registers unit events globally. This small router keeps high-volume
-- UNIT_* traffic scoped to only the units each ActionHud module displays.
local UnitEventRouter = {}
ns.UnitEventRouter = UnitEventRouter

local unpack = unpack or table.unpack

local function Dispatch(state, event, ...)
	local registration = state.registrations[event]
	if not registration then
		return
	end

	local owner = state.owner
	local callback = registration.callback
	if type(callback) == "string" then
		owner[callback](owner, event, ...)
	else
		callback(owner, event, ...)
	end
end

local function ApplyRegistrations(state, generation)
	state.scheduled = false
	if generation ~= state.generation then
		return
	end

	if not state.frame then
		state.frame = CreateFrame("Frame")
		state.frame:SetScript("OnEvent", function(_, event, ...)
			Dispatch(state, event, ...)
		end)
	end

	state.frame:UnregisterAllEvents()
	for event, registration in pairs(state.registrations) do
		pcall(state.frame.RegisterUnitEvent, state.frame, event, unpack(registration.units))
	end
end

local function GetState(owner)
	local state = owner.__actionHudUnitEvents
	if not state then
		state = {
			owner = owner,
			registrations = {},
			generation = 0,
		}
		owner.__actionHudUnitEvents = state
	end
	return state
end

local function Schedule(state)
	if state.scheduled then
		return
	end
	state.generation = state.generation + 1
	state.scheduled = true
	local generation = state.generation
	C_Timer.After(0, function()
		ApplyRegistrations(state, generation)
	end)
end

function UnitEventRouter:Register(owner, event, callback, ...)
	local state = GetState(owner)
	state.registrations[event] = {
		callback = callback,
		units = { ... },
	}
	Schedule(state)
end

function UnitEventRouter:UnregisterAll(owner)
	local state = owner.__actionHudUnitEvents
	if not state then
		return
	end
	wipe(state.registrations)
	state.generation = state.generation + 1
	state.scheduled = false
	if state.frame then
		state.frame:UnregisterAllEvents()
	end
end
