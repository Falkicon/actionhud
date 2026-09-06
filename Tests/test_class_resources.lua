local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()

-- Opaque sentinels detect Lua inspection; they do not model native taint.
local secretValues, secretOperations = {}, 0
local function forbidden()
	secretOperations = secretOperations + 1
	error("class resource secret inspected")
end
local secretMeta = { __eq = forbidden, __lt = forbidden, __le = forbidden,
	__add = forbidden, __sub = forbidden, __mul = forbidden, __div = forbidden,
	__mod = forbidden, __unm = forbidden, __concat = forbidden, __tostring = forbidden }
local function secret(value)
	local token = setmetatable({}, secretMeta)
	secretValues[token] = value
	return token
end
issecretvalue = function(value) return secretValues[value] ~= nil end
local class, spec, primary, available = "MAGE", 1, Enum.PowerType.Mana, true
local current, maximum, rawCurrent, displayMod, partial = 2, 4, 25, 10, 500
UnitClass = function() return class, class, 8 end
GetSpecialization = function() return spec end
UnitPowerType = function() return primary, "MANA" end
UnitHasPowerType = function() return available end
UnitPower = function(_, pType, raw)
	if pType == nil then return 30 end
	if raw then return rawCurrent end
	return current
end
UnitPowerMax = function(_, pType)
	if pType == nil then return 100 end
	return maximum
end
UnitPowerDisplayMod = function() return displayMod end
UnitPartialPower = function() return partial end
local addon = boot(host)
local resources = addon:GetModule("Resources")
local row
for _, frame in ipairs(host.frames) do
	if frame.continuous then row = frame end
end
assert(row, "class resource row must be constructed")
local function update(event, flush)
	host:Fire(event or "UNIT_POWER_UPDATE", "player")
	if flush ~= false then host:Flush() end
	host:AssertNoErrors()
end
local function segments()
	local result = {}
	for _, frame in ipairs(row.children) do
		if frame.kind == "StatusBar" and frame ~= row.continuous and frame:IsShown() then
			result[#result + 1] = frame
		end
	end
	return result
end
local function assertPips(count, value, units)
	assert(row:IsShown(), "eligible resources must remain visible")
	assert(not row.continuous:IsShown(), "prepared public capacity should use pips")
	local pips = segments()
	assert(#pips == count, "public maximum must determine the exact pip count")
	for i, pip in ipairs(pips) do
		assert(pip.low == (i - 1) * units and pip.high == i * units, "pip must use the native current's units")
		assert(rawequal(pip.value, value), "every pip must receive the actual native current")
	end
end
assertPips(4, 2, 1)
local originalHeight = resources:CalculateHeight()
for _, value in ipairs({ 0, 1, 3, 4 }) do
	current = value
	update()
	assertPips(4, value, 1)
	assert(resources:CalculateHeight() == originalHeight, "spending power must not collapse the row")
end
current = secret(2)
update()
assertPips(4, current, 1)

-- Talent/spec capacity changes must not create geometry in event callbacks.
local geometryCalls = 0
for _, pip in ipairs(segments()) do
	for _, method in ipairs({ "SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints" }) do
		local original = pip[method]
		pip[method] = function(self, ...)
			geometryCalls = geometryCalls + 1
			return original(self, ...)
		end
	end
end
host:SetCombat(true)
class, maximum, current = "DEATHKNIGHT", 6, secret(3)
local beforeFrames = #host.frames
update("UNIT_MAXPOWER", false)
assert(geometryCalls == 0 and #host.frames == beforeFrames, "value events must defer segment geometry")
assert(row.continuous:IsShown() and #segments() == 0, "changed capacity must not leave a stale pip count")
assert(row.continuous.high == 6 and rawequal(row.continuous.value, current))
host:SetCombat(false)
assertPips(6, current, 1)
current = secret(4)
update("RUNE_POWER_UPDATE")
assertPips(6, current, 1)
class, maximum, current = "ROGUE", 7, secret(4)
update("UNIT_MAXPOWER")
assertPips(7, current, 1)
class, spec, maximum, current = "MONK", 3, 6, 0
update("PLAYER_SPECIALIZATION_CHANGED")
assertPips(6, 0, 1)
class, maximum, current, partial = "EVOKER", 6, 2, 500
update("UNIT_MAXPOWER")
assertPips(6, 2.5, 1)
partial = secret(500)
update()
assertPips(6, 2, 1)
current, partial = secret(2), 500
update()
assertPips(6, current, 1)

-- Raw shard units preserve partial progress without dividing opaque power.
class, spec, maximum, current, rawCurrent = "WARLOCK", 3, 5, 2, 25
update("PLAYER_SPECIALIZATION_CHANGED")
assertPips(5, 25, 10)
rawCurrent = secret(25)
update()
assertPips(5, rawCurrent, 10)
displayMod = secret(10)
update()
assertPips(5, 2, 1)
displayMod = 10

-- Opaque capacity uses the same display units as current, with no guessed pips.
maximum, current = secret(5), secret(2)
update("UNIT_MAXPOWER")
assert(row.continuous:IsShown() and #segments() == 0)
assert(rawequal(row.continuous.high, maximum) and rawequal(row.continuous.value, current))
maximum = secret(7)
update()
assert(rawequal(row.continuous.high, maximum), "opaque maxima must never be cached")
maximum, current = 5, 2
update("UNIT_MAXPOWER")
assertPips(5, rawCurrent, 10)

-- Eligibility depends on class/spec/form, never on a nonzero hidden power pool.
local function assertHidden()
	update("PLAYER_SPECIALIZATION_CHANGED")
	assert(not row:IsShown(), "ineligible class resource must be hidden")
end
class, spec, maximum = "MAGE", 2, 4
assertHidden()
class, spec = "MONK", 1
assertHidden()
class, spec, primary, maximum = "DRUID", 2, Enum.PowerType.Mana, 5
assertHidden()
primary = Enum.PowerType.Energy
update("UPDATE_SHAPESHIFT_FORM")
assertPips(5, current, 1)
primary = Enum.PowerType.Rage
update("UNIT_DISPLAYPOWER")
assert(not row:IsShown())
class, primary, available = "ROGUE", Enum.PowerType.Energy, false
assertHidden()
available = true
maximum = 0
assertHidden()
maximum = nil
assertHidden()
assert(secretOperations == 0, "no protected arithmetic may be attempted, even inside pcall")
host:AssertNoErrors()
print("SUCCESS: class resource eligibility, capacities, depletion, native units, and opaque passthrough")
