-- Full-TOC restricted combat: every module receives secret timing, counts,
-- health, power and prediction through the real Utils/FenUI wrappers. Lua must
-- never inspect those values (arithmetic, ordering, indexing, formatting).
local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()
local Secret = host.Secret

local addon, ns = boot(host)
local profile = addon.db.profile
profile.ufEnabled = true
profile.ufConfig.focus.enabled, profile.ufConfig.targettarget.enabled = true, true
profile.resEnabled, profile.resShowTarget, profile.trinketsEnabled = true, true, true
profile.consumablesEnabled, profile.consumablesItemIDs = true, "5512,241304"
profile.playerBuffsEnabled, profile.playerBuffsSpellIDs = true, "23920"
addon:OnProfileChanged()
host:Flush()
host:AssertNoErrors()

local health
for _, frame in ipairs(host.frames) do
	if frame.type == "HEALTH" and frame.kind == "StatusBar" and not health then health = frame end
end
assert(health, "resource health bar must exist")

local function burst()
	for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "ACTIONBAR_UPDATE_STATE",
		"ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_ICON", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
		"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
		host:Fire(event)
	end
	host:Fire("ACTIONBAR_SLOT_CHANGED", 1)
	host:Fire("ACTIONBAR_SLOT_CHANGED", 61)
	host:Fire("ACTION_RANGE_CHECK_UPDATE", 1, false, true)
	host:Fire("PLAYER_EQUIPMENT_CHANGED", 13, false)
	for _, unit in ipairs({ "player", "target", "targettarget", "focus" }) do
		for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
			"UNIT_DISPLAYPOWER", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_PREDICTION", "UNIT_AURA" }) do
			host:Fire(event, unit)
		end
	end
	host:Fire("UNIT_TARGET", "target")
	host:Flush()
	host:AssertNoErrors()
end

Secret.Reset()
host:SetCombat(true)
host:SetRestricted(true)
host.actionCooldowns[1] = { startTime = 10, duration = 30 }
burst()
Secret.AssertUntouched("secret combat values were used in Lua")
assert(Secret.is(health.value), "restricted health must reach the status bar as native passthrough")

-- Layout passes (e.g. after a settings change) must also tolerate secrets.
host:SetCombat(false)
addon:RefreshLayout()
host:Flush()
burst()
Secret.AssertUntouched("secret values were used in Lua during layout")

host:SetRestricted(false)
host.actionCooldowns[1] = nil
ns.Performance:SetEnabled(true)
ns.Performance:Reset()
burst()
addon:RefreshLayout()
host:Flush()
ns.Performance:SetEnabled(false)
local recorded = {}
for _, metric in ipairs(ns.Performance:GetMetrics()) do recorded[metric.name] = metric.calls end
for _, name in ipairs({ "ActionBarsState", "ActionBarsUsable", "ActionBarsCharges", "ActionBarsIcon",
	"ActionBarsSlotChanged", "CooldownsUpdate", "ConsumablesRefresh",
	"ResourcesUpdate", "UnitFramesUpdate", "TrinketsUpdate", "LayoutRecalc" }) do
	assert(recorded[name], "profiling must record " .. name)
end
assert(not Secret.is(health.value), "readable health returns once restrictions lift")
host:AssertNoErrors()
print("SUCCESS: restricted combat values pass through every module without Lua inspection")
