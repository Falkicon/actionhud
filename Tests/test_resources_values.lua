local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()

-- Opaque tokens check passthrough and cache handling, not native secret-value safety.
local secretValues = {}
local function forbidden() error("secret value inspected") end
local secretMeta = { __eq = forbidden, __lt = forbidden, __le = forbidden,
	__add = forbidden, __sub = forbidden, __div = forbidden, __tostring = forbidden }
local function secret(value)
	local token = setmetatable({}, secretMeta)
	secretValues[token] = value
	return token
end
issecretvalue = function(value) return secretValues[value] ~= nil end
local health, maxHealth, power, maxPower = 45, 100, 20, 100
UnitHealth = function(unit) if unit == "target" then return health end; return 80 end
UnitHealthMax = function(unit) if unit == "target" then return maxHealth end; return 100 end
UnitPower = function(unit) if unit == "target" then return power end; return 30 end
UnitPowerMax = function(unit) if unit == "target" then return maxPower end; return 100 end
UnitGetIncomingHeals = function() return 10 end
UnitGetTotalAbsorbs = function() return 15 end
local addon = boot(host)
local container = addon:GetModule("Resources"):GetContainer()
local healthBar, powerBar
for _, frame in ipairs(host.frames) do
	if frame.parent and frame.parent.parent == container then
		if frame.type == "HEALTH" and frame.value == 45 then healthBar = frame end
		if frame.type == "POWER" and frame.value == 20 then powerBar = frame end
	end
end
assert(healthBar and powerBar, "target resource bars must render at startup")
local bars = { healthBar, powerBar, healthBar.predict, healthBar.absorb }
for _, bar in ipairs(bars) do
	local nativeSetMinMax = bar.SetMinMaxValues
	bar.rangeCalls = 0
	bar.SetMinMaxValues = function(self, low, high)
		self.rangeCalls = self.rangeCalls + 1
		nativeSetMinMax(self, low, high)
	end
end
local function update()
	host:Fire("UNIT_HEALTH", "target")
	host:Fire("UNIT_POWER_UPDATE", "target")
end
local function assertRange(expected)
	for _, bar in ipairs(bars) do
		assert(bar.low == 0 and rawequal(bar.high, expected), "target bars must receive the actual maximum")
	end
end
update()
assertRange(100)
for _, bar in ipairs(bars) do assert(bar.rangeCalls == 0, "readable ranges should remain cached") end

maxHealth = secret(100)
maxPower = maxHealth
update()
assertRange(maxHealth)
assert(healthBar.value == 45 and powerBar.value == 20, "readable currents must keep the opaque range")
assert(healthBar.predict.value == 10, "prediction must avoid arithmetic against an opaque maximum")
health, power = secret(45), secret(20)
update()
assertRange(maxHealth)
assert(rawequal(healthBar.value, health) and rawequal(powerBar.value, power), "current values must pass through")
for _, bar in ipairs(bars) do
	assert(bar._safeMin == nil and bar._safeMax == nil, "secret updates must invalidate readable range caches")
end

-- A changed maximum must reach every native bar, even during combat events.
host:SetCombat(true)
maxHealth = secret(200)
maxPower = maxHealth
host:Fire("UNIT_MAXHEALTH", "target")
host:Fire("UNIT_POWER_UPDATE", "target")
assertRange(maxHealth)
local calls = healthBar.rangeCalls
update()
assert(healthBar.rangeCalls > calls, "opaque ranges must be forwarded on every update")
host:SetCombat(false)

-- Returning to the same readable maximum must restore the pre-secret range.
health, maxHealth, power, maxPower = 45, 100, 20, 100
update()
assertRange(100)
calls = healthBar.rangeCalls
update()
assert(healthBar.rangeCalls == calls, "readable caching must resume")
for _, current in ipairs({ 75, 25, 0, 100 }) do
	health = current
	host:Fire("UNIT_HEALTH", "target")
	assert(healthBar.value / healthBar.high == current / 100, "health must retain its partial fill")
end
for _, invalid in ipairs({ 0, -10, "invalid", false }) do
	maxHealth, maxPower = invalid, invalid
	update()
	assertRange(1)
end
maxHealth, maxPower = nil, nil
update()
assertRange(1)
host:AssertNoErrors()
print("SUCCESS: target resource values preserve opaque ranges, overlays, and readable cache transitions")
