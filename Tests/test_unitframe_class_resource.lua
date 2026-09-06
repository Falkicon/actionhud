-- Full-TOC class-resource routing and deferred secure layout regression.
local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()
local class, spec, primaryType = "ROGUE", 1, Enum.PowerType.Energy
local current, maximum = 3, 5
local reads = {}
UnitClass = function() return class, class, 1 end
GetSpecialization = function() return spec end
UnitPowerType = function() return primaryType, "ENERGY" end
UnitPower = function(unit, powerType, unmodified)
	if powerType ~= nil then
		reads[#reads + 1] = { unit, powerType, unmodified, "current" }
		return current
	end
	return 80
end
UnitPowerMax = function(unit, powerType, unmodified)
	if powerType ~= nil then
		reads[#reads + 1] = { unit, powerType, unmodified, "maximum" }
		return maximum
	end
	return 100
end
local addon = boot(host)
addon.db.profile.resEnabled = false
addon.db.profile.ufEnabled = true
addon:OnProfileChanged()
host:Flush()
local uf = addon:GetModule("UnitFrames")
local frame = uf.frames.player
local config = addon.db.profile.ufConfig.player
local function assertPool(powerType)
	reads = {}
	host:Fire("UNIT_POWER_UPDATE", "player")
	assert(frame.class:IsShown(), "eligible class bar must be visible")
	assert(rawequal(frame.class.value, current) and rawequal(frame.class.high, maximum))
	assert(frame.power.value == 80 and frame.power.high == 100, "primary power must stay distinct")
	assert(#reads == 2, "class update must query its current and maximum")
	for _, read in ipairs(reads) do
		assert(read[1] == "player" and read[2] == powerType and read[3] == true, "wrong class power units")
	end
end
assertPool(Enum.PowerType.ComboPoints)
current = 0
assertPool(Enum.PowerType.ComboPoints)
assert(frame._classHeight == config.classBarHeight, "depleted resource must retain its space")

class, primaryType, current, maximum = "DEATHKNIGHT", 6, 2, 6
host:Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
host:Flush()
assertPool(Enum.PowerType.Runes)
current = 4
reads = {}
host:Fire("RUNE_POWER_UPDATE", 1, true)
assert(frame.class.value == 4 and frame.class.high == 6, "rune event must refresh available runes")
assert(#reads == 2 and reads[1][2] == Enum.PowerType.Runes and reads[2][2] == Enum.PowerType.Runes)
assert(#host.timers == 0, "rune values must not request geometry")

class, current, maximum = "WARLOCK", 17, 50
host:Fire("PLAYER_TALENT_UPDATE")
host:Flush()
assertPool(Enum.PowerType.SoulShards)
local secret = setmetatable({}, {
	__tostring = function() error("secret conversion") end,
	__div = function() error("secret division") end,
	__mul = function() error("secret multiplication") end,
	__lt = function() error("secret comparison") end,
})
current, maximum = secret, secret
assertPool(Enum.PowerType.SoulShards)
current, maximum = 2, 5

class, spec = "MAGE", 2
host:Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
host:Flush()
assert(not frame.class:IsShown() and frame._classHeight == 0, "non-Arcane mage must hide class bar")
spec = 1
host:Fire("PLAYER_TALENT_UPDATE")
host:Flush()
assertPool(Enum.PowerType.ArcaneCharges)
config.classBarEnabled = false
addon:RefreshLayout()
host:Flush()
assert(not frame.class:IsShown() and frame._classHeight == 0)
config.classBarEnabled = true

class, primaryType = "DRUID", Enum.PowerType.Energy
host:Fire("UPDATE_SHAPESHIFT_FORM")
host:Flush()
assertPool(Enum.PowerType.ComboPoints)
local healthHeight = frame.health:GetHeight()
host:SetCombat(true)
primaryType = Enum.PowerType.Rage
host:Fire("UPDATE_SHAPESHIFT_FORM")
host:Flush()
assert(frame.health:GetHeight() == healthHeight, "form layout must wait until combat ends")
host:SetCombat(false)
assert(not frame.class:IsShown() and frame._classHeight == 0)
primaryType = Enum.PowerType.Energy
host:Fire("UPDATE_SHAPESHIFT_FORM")
host:Flush()
assertPool(Enum.PowerType.ComboPoints)

host:SetCombat(true)
config.classBarEnabled = false
config.height = config.height + 10
addon:OnProfileChanged()
host:Flush()
assert(frame.class:IsShown(), "profile geometry must remain deferred in combat")
host:SetCombat(false)
assert(not frame.class:IsShown() and frame._classHeight == 0)
assert(uf.frames.player == frame, "profile reconciliation must reuse secure frames")
host:AssertNoErrors()
print("SUCCESS: explicit unit-frame class pools, native passthrough, form/spec and combat profile layout verified")
