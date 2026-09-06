local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()
local addon, ns = boot(host)
assert(addon.db:GetCurrentProfile() == "Default", "real AceDB must initialize the default profile")
assert(addon.frame and addon.frame:IsShown(), "the actual addon must create its root")
assert(addon:GetModule("ActionBars"):GetContainer():IsShown(), "action bars must render on startup")
assert(not next(addon:GetModule("UnitFrames").frames), "optional secure frames must remain lazy")

local ab = addon:GetModule("ActionBars")
local resources = addon:GetModule("Resources")
local trinkets = addon:GetModule("Trinkets")
local unitFrames = addon:GetModule("UnitFrames")
local lm = addon:GetModule("LayoutManager")
local modules = { ab, resources, trinkets, unitFrames }
local trinketCooldowns = {}
local trinketContainer = ns.DraggableContainer:GetContainer("trinkets")
for _, frame in ipairs(host.frames) do
	if frame.kind == "Cooldown" and frame.parent and frame.parent.parent == trinketContainer then
		trinketCooldowns[#trinketCooldowns + 1] = frame
		assert(frame.countdownThreshold == 3, "trinket countdown must initialize with the profile threshold")
	end
end
assert(#trinketCooldowns == 2, "both equipped trinkets must be tested")
addon.db.profile.cooldownDecimalThreshold = 0
addon:RefreshLayout()
host:Flush()
for _, frame in ipairs(trinketCooldowns) do
	assert(frame.countdownThreshold == 0, "disabling decimals must update existing trinket cooldowns")
end
addon.db.profile.cooldownDecimalThreshold = 3
addon.db.profile.ufEnabled = true
addon:OnProfileChanged()
host:Flush()
assert(unitFrames.frames.player and unitFrames.frames.target, "secure frames must initialize through the real lifecycle")
local playerFrame = unitFrames.frames.player
local actionContainer = ab:GetContainer()

-- Same-frame settings bursts must apply the final values in one measured pass.
ns.Performance:SetEnabled(true)
ns.Performance:Reset()
for width = 21, 30 do
	addon.db.profile.iconWidth = width
	addon:RefreshLayout()
end
host:Flush()
local layoutMetric
for _, metric in ipairs(ns.Performance:GetMetrics()) do
	if metric.name == "LayoutRecalc" then layoutMetric = metric end
end
assert(layoutMetric and layoutMetric.calls == 1, "a settings burst must perform exactly one layout pass")
assert(actionContainer:GetWidth() == ab:GetLayoutWidth(), "rendered width must use the final settings")

-- Create a disabled profile through real AceDB callbacks, then return to enabled.
addon.db:SetProfile("Disabled")
addon.db.profile.actionBarsEnabled, addon.db.profile.resEnabled = false, false
addon.db.profile.trinketsEnabled, addon.db.profile.ufEnabled = false, false
addon.db.profile.locked = false
addon:OnProfileChanged()
host:Flush()
for _, module in ipairs(modules) do assert(not module._runtimeActive, "disabled profile leaked active runtime") end
assert(not actionContainer:IsShown() and not playerFrame:IsShown())
addon.db:SetProfile("Default")
host:Flush()
for _, module in ipairs(modules) do assert(module._runtimeActive, "profile switch failed to resume runtime") end
assert(unitFrames.frames.player == playerFrame and ab:GetContainer() == actionContainer,
	"profile switching must reuse existing frames")

-- The latest desired profile must win after a series of combat-time changes.
host:SetCombat(true)
addon.db:SetProfile("Disabled")
addon.db:SetProfile("Default")
addon.db:SetProfile("Disabled")
host:Flush()
for _, module in ipairs(modules) do assert(module._pendingEnabledState, "combat transition must remain pending") end
host:SetCombat(false)
for _, module in ipairs(modules) do
	assert(not module._runtimeActive and not module._pendingEnabledState, "combat reconciliation used an obsolete profile")
end
assert(not playerFrame:IsShown() and not actionContainer:IsShown())
assert(addon.frame:IsMouseEnabled(), "profile lock state must also reconcile after combat")

-- Real AceEvent/UnitEventRouter must release subscriptions when disabled.
local function listenerCount(event)
	local count = 0
	for _, frame in ipairs(host.frames) do if frame.events[event] then count = count + 1 end end
	return count
end
assert(listenerCount("UNIT_HEALTH") == 0, "disabled modules must release scoped unit subscriptions")
addon.db:SetProfile("Default")
host:Flush()
local listeners = listenerCount("UNIT_HEALTH")
assert(listeners > 0)
for _ = 1, 3 do
	addon.db:SetProfile("Disabled")
	addon.db:SetProfile("Default")
	host:Flush()
end
assert(listenerCount("UNIT_HEALTH") == listeners, "re-enable cycles must not multiply event registrations")

-- A protected resize that was blocked in combat must be applied on exit.
host:SetCombat(true)
host.maxPower = 0
host:Fire("UNIT_MAXPOWER", "player")
host:Flush()
local oldHeight = playerFrame:GetHeight()
host:SetCombat(false)
assert(playerFrame:GetHeight() < oldHeight, "secure geometry was not retried after combat")
host.maxPower = 100
host:Fire("UNIT_MAXPOWER", "player")
host:Flush()

-- Profile copying/resetting must also invoke the real AceDB callback path.
addon.db:SetProfile("Copy")
addon.db:CopyProfile("Disabled")
host:Flush()
assert(not ab._runtimeActive and not unitFrames._runtimeActive)
addon.db:ResetProfile()
host:Flush()
assert(ab._runtimeActive and resources._runtimeActive and trinkets._runtimeActive)
assert(not unitFrames._runtimeActive, "reset must restore optional unit frames to their default disabled state")

-- Disabling the manager invalidates queued work, including work from an older enable.
lm:RequestLayout("test stop")
lm:Disable()
lm:Enable()
host:Flush()

-- Logging must not format messages unless both the setting and sink are active.
addon:Logf("test", "%d", {}) -- Would fail formatting if the disabled path did work.
local mechanic = LibStub:NewLibrary("MechanicLib-1.0", 1)
local logs = {}
function mechanic:IsEnabled() return true end
function mechanic:Log(_, message) logs[#logs + 1] = message end
addon.db.profile.debugDiscovery = true
addon:Logf("test", "value=%d", 7)
assert(logs[1] == "value=7")
addon.db.profile.debugDiscovery = false
addon:Logf("test", "%d", {})
assert(#logs == 1)

addon:SlashHandler("perf off")
assert(not ns.RecordPerformance, "slash control must stop recording")
addon:SlashHandler("perf on")
assert(ns.RecordPerformance and #ns.Performance:GetMetrics() == 0)
host:Fire("UNIT_HEALTH", "player")
assert(#ns.Performance:GetMetrics() > 0, "real event handlers must record samples")
addon:SlashHandler("perf report")
addon:SlashHandler("perf reset")
assert(#ns.Performance:GetMetrics() == 0)
host:AssertNoErrors()
print("SUCCESS: full TOC, real Ace profiles/events, coalesced layout, and combat transitions")
