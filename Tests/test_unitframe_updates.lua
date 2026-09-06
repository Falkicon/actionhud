-- Unit-frame rendering must recover from combat-deferred geometry and secret health.
local unitFrames = {}
local layoutRequested = false
local manager = { RequestLayout = function() layoutRequested = true end }
local addon = { NewModule = function() return unitFrames end, GetModule = function(_, name) return name == "UnitFrames" and unitFrames or manager end }
LibStub = function(name)
	if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
	if name == "AceLocale-3.0" then return { GetLocale = function() return {} end } end
	if name == "LibSharedMedia-3.0" then return {} end
	error("Unexpected library " .. name)
end
local secret = {}
local ns = { Utils = { IsValueSecret = function(value) return rawequal(value, secret) end } }
for _, file in ipairs({ "Identity.lua", "UnitFrames.lua", "Layout.lua", "Rendering.lua" }) do
	assert(loadfile("UnitFrames/" .. file))("ActionHud", ns)
end
local combat, health, maxPower = false, 70, 0
InCombatLockdown = function() return combat end
UnitExists = function() return true end
UnitHealth = function() return health end
UnitHealthMax = function() return 100 end
UnitPower = function() return 0 end
UnitPowerMax = function() return maxPower end
UnitPowerType = function() return 0, "MANA" end
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }
UnitGetIncomingHeals = function() return 20 end
local function noop() end
local function region(secure)
	return setmetatable({
		SetValue = function(self, value) self.value = value end,
		SetHeight = function(self, value)
			assert(not secure or not combat, "protected height was changed in combat")
			self.height = value
		end,
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
	}, { __index = function(_, key) if key:match("^[A-Z]") then return noop end end })
end
local frame = region(true)
frame.unit, frame.unitId = "target", "target"
frame.health, frame.power, frame.class = region(), region(), region()
frame.health.absorb, frame.health.predict = region(), region()
frame.healthElements, frame.powerElements, frame.icons = {}, {}, {}
frame._showPower = false
local config = {
	enabled = true, height = 40, powerBarEnabled = true, powerBarHeight = 10,
	classBarEnabled = false,
	healthText = { value = { enabled = false } }, powerText = { value = { enabled = false } },
}
unitFrames.db = { profile = { ufEnabled = true, ufConfig = { target = config } } }
unitFrames.containers = { target = region(true) }
local events = {}
function unitFrames:IsEnabled() return true end
function unitFrames:RegisterEvent(event, handler) events[event] = handler end
function unitFrames:UnregisterEvent(event) events[event] = nil end

unitFrames:UpdateFrameValues(frame, "powerLayout")
assert(frame.height == 30 and frame._actualFrameHeight == 30)
combat, maxPower = true, 100
unitFrames:UpdateFrameValues(frame, "powerLayout")
assert(frame.height == 30, "secure height must stay unchanged in combat")
assert(frame._actualFrameHeight == nil, "unapplied geometry must not be cached as complete")
assert(layoutRequested and unitFrames._pendingEnabledState, "geometry needs a scheduled out-of-combat retry")
combat = false
function unitFrames:StartRuntime() self:UpdateFrameValues(frame, "powerLayout") end
unitFrames:ApplyEnabledState()
assert(frame.height == 40 and unitFrames.containers.target.height == 40,
	"deferred geometry must apply without another power change")
assert(not unitFrames._pendingEnabledState)

unitFrames:UpdateFrameValues(frame, "health")
assert(frame.health.predict.shown and frame.health.predict.value == 90)
health = secret
unitFrames:UpdateFrameValues(frame, "health")
assert(not frame.health.predict.shown, "unavailable health must not show stale prediction values")

combat = true
unitFrames:UpdateLayout()
assert(layoutRequested, "settings layout must request the manager to defer protected mutations")
print("SUCCESS: unit-frame deferred geometry and prediction freshness verified")
