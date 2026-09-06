-- Full-TOC coverage of optional native percentage display. This host verifies
-- passthrough and lifecycle behavior, not WoW's native secret/taint handling.
local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()
local curve = {}
CurveConstants = { ScaleTo100 = curve }
local health, power, healthCalls, powerCalls = 80, 30, 0, 0
local function nativeHealth(unit, predicted, suppliedCurve)
	assert(unit == "target" and predicted == true and suppliedCurve == curve)
	healthCalls = healthCalls + 1
	return health
end
local function nativePower(unit, powerType, unmodified, suppliedCurve)
	assert(unit == "target" and powerType == nil and unmodified == false and suppliedCurve == curve)
	powerCalls = powerCalls + 1
	return power
end
UnitHealthPercent, UnitPowerPercent = nativeHealth, nativePower
local addon, ns = boot(host)
local uf = addon:GetModule("UnitFrames")
for _, id in ipairs({ "player", "target", "targettarget", "focus" }) do
	local config = addon.db.profile.ufConfig[id]
	assert(not config.healthText.percent.enabled and not config.powerText.percent.enabled)
end
addon.db.profile.ufEnabled = true
addon:OnProfileChanged()
host:Flush()
local frame = uf.frames.target
local h, p = frame.healthElements.percent.fontString, frame.powerElements.percent.fontString
assert(healthCalls == 0 and powerCalls == 0 and not h:IsShown() and not p:IsShown())
local config = addon.db.profile.ufConfig.target
local options = ns.Settings.BuildUnitFramesOptions(addon).args.target.args.text.args
options.percent.args.enabled.set(nil, true)
options.powerPercent.args.enabled.set(nil, true)
host:Flush()
assert(h.text == "80%" and p.text == "30%" and h:IsShown() and p:IsShown())
assert(uf.frames.target == frame, "enabling text must reuse the secure frame")

for _, value in ipairs({ 0, 43.2, 100 }) do
	health, power = value, value
	healthCalls, powerCalls = 0, 0
	host:Fire("UNIT_HEALTH", "target")
	assert(healthCalls == 1 and powerCalls == 0, "health event must only query health percentage")
	host:Fire("UNIT_POWER_UPDATE", "target", "RAGE")
	assert(healthCalls == 1 and powerCalls == 1, "power event must only query power percentage")
	assert(h.text == string.format("%.0f%%", value) and p.text == h.text)
end
healthCalls, powerCalls = 0, 0
host:Fire("UNIT_FLAGS", "target")
assert(healthCalls == 0 and powerCalls == 0, "status updates must not query percentages")

-- A sentinel explodes on ordinary Lua conversion/arithmetic. Only the simulated
-- native formatting boundary accepts it; public formatting uses the host method.
local secret = setmetatable({}, {
	__tostring = function() error("secret string conversion") end,
	__div = function() error("secret division") end,
	__mul = function() error("secret multiplication") end,
	__lt = function() error("secret comparison") end,
})
local formatted = 0
local originalFormat = h.SetFormattedText
local function nativeFormat(self, fmt, value)
	assert(fmt == "%.0f%%")
	if rawequal(value, secret) then
		formatted = formatted + 1
		self.text = "native secret percentage"
	else
		originalFormat(self, fmt, value)
	end
end
h.SetFormattedText, p.SetFormattedText = nativeFormat, nativeFormat
health, power = secret, secret
host:Fire("UNIT_HEALTH", "target")
host:Fire("UNIT_POWER_UPDATE", "target", "RAGE")
assert(formatted == 2 and h:IsShown() and p:IsShown())

local function assertCleared()
	assert(h.text == "" and p.text == "" and not h:IsShown() and not p:IsShown(), "stale percentages remain")
end
local function updateBoth()
	host:Fire("UNIT_HEALTH", "target")
	host:Fire("UNIT_POWER_UPDATE", "target", "RAGE")
end
UnitHealthPercent, UnitPowerPercent = nil, nil
updateBoth()
assertCleared()
UnitHealthPercent, UnitPowerPercent = function() error("unavailable") end, function() error("unavailable") end
updateBoth()
assertCleared()
UnitHealthPercent, UnitPowerPercent = nativeHealth, nativePower
health, power = nil, nil
updateBoth()
assertCleared()
health, power = 50, 60
CurveConstants = nil
updateBoth()
assertCleared()
CurveConstants = { ScaleTo100 = curve }
updateBoth()
assert(h.text == "50%" and p.text == "60%")
h.SetFormattedText, p.SetFormattedText = function() error("native formatting failed") end, function() error("failed") end
updateBoth()
assertCleared()
h.SetFormattedText, p.SetFormattedText = originalFormat, originalFormat
updateBoth()
assert(h:IsShown() and p:IsShown())

config.powerBarEnabled = false
addon:RefreshLayout()
host:Flush()
assert(p.text == "" and not p:IsShown(), "disabled power bar must suppress its percentage")
config.powerBarEnabled = true
addon:RefreshLayout()
host:Flush()
local originalExists = UnitExists
UnitExists = function(unit) return unit ~= "target" and originalExists(unit) end
updateBoth()
assertCleared()
UnitExists = originalExists
updateBoth()
assert(h:IsShown() and p:IsShown())

addon.db:SetProfile("No percentages")
addon.db.profile.ufEnabled = true
addon:OnProfileChanged()
host:Flush()
assertCleared()
addon.db:SetProfile("Default")
host:Flush()
assert(h:IsShown() and p:IsShown() and uf.frames.target == frame)
addon.db.profile.ufEnabled = false
addon:OnProfileChanged()
host:Flush()
assert(not frame:IsShown())
health, power = 25, 75
addon.db.profile.ufEnabled = true
addon:OnProfileChanged()
host:Flush()
assert(h.text == "25%" and p.text == "75%" and frame:IsShown())
print("SUCCESS: native unit-frame percentages, failures, event routing, and profile lifecycle verified")
