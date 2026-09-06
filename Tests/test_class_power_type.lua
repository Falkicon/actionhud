-- Class-resource eligibility must follow public identity, never current power.
local host = assert(loadfile("Tests/support/wow.lua"))()
local class, spec, activePower = "WARRIOR", 1, Enum.PowerType.Rage
UnitClass = function() return "Test Class", class, 1 end
UnitPowerType = function() return activePower, "TEST" end
GetSpecialization = function() return spec end
local hasPower, queryCount = true, 0
UnitHasPowerType = function(unit, powerType)
	assert(unit == "player" and type(powerType) == "number")
	queryCount = queryCount + 1
	return hasPower
end
local _, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local getType = ns.Utils.GetPlayerClassPowerTypeSafe
local powers = Enum.PowerType
UnitPower = function() error("eligibility must not inspect current power") end
UnitPowerMax = function() error("eligibility must not inspect maximum power") end
for name, expected in pairs({ ROGUE = powers.ComboPoints, PALADIN = powers.HolyPower,
	WARLOCK = powers.SoulShards, EVOKER = powers.Essence, DEATHKNIGHT = powers.Runes }) do
	class = name
	local actual, available = getType()
	assert(actual == expected and available)
end
class, spec = "MAGE", 1
assert(getType() == powers.ArcaneCharges)
spec = 2
assert(getType() == nil)
class, spec = "MONK", 3
assert(getType() == powers.Chi)
spec = 1
assert(getType() == nil)
class, activePower = "DRUID", powers.Energy
assert(getType() == powers.ComboPoints)
activePower = powers.Rage
assert(getType() == nil)
activePower = powers.Mana
assert(getType() == nil)
class = "WARRIOR"
local before = queryCount
local actual, available = getType()
assert(actual == nil and available and queryCount == before)

class, hasPower = "ROGUE", false
actual, available = getType()
assert(actual == nil and available, "an unavailable resource must not create a class row")
UnitHasPowerType = function() error("API unavailable") end
actual, available = getType()
assert(actual == nil and not available)
local secret = setmetatable({}, { __tostring = function() error("restricted identity conversion") end })
issecretvalue = function(value) return rawequal(value, secret) end
UnitHasPowerType = function() return secret end
actual, available = getType()
assert(actual == nil and not available)
UnitHasPowerType = nil
assert(getType() == powers.ComboPoints, "older clients retain public class eligibility")
class = secret
actual, available = getType()
assert(actual == nil and not available)
class, activePower = "DRUID", secret
actual, available = getType()
assert(actual == nil and not available)
class, spec = "MAGE", nil
actual, available = getType()
assert(actual == nil and not available)
print("SUCCESS: class-resource eligibility follows public class, specialization, form, and native availability")
