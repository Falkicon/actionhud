local secret = setmetatable({}, { __index = function() error("secret indexed") end })
local combat, restricted, calls, messages = false, false, 0, 0
local auras, timers = {}, {}
local addon = { db = { char = { playerBuffRecentIDs = { 30, 30, -1, 40 } }, profile = {} } }
function addon:NewModule(name)
	assert(name == "RecentPlayerBuffs")
	return {
		RegisterEvent = function(self, event, callback) self.events[event] = callback end,
		UnregisterAllEvents = function(self) self.events = {} end,
		SendMessage = function(_, message)
			assert(message == "ACTIONHUD_RECENT_BUFFS_CHANGED")
			messages = messages + 1
		end,
		events = {},
	}
end
LibStub = function() return { GetAddon = function() return addon end } end
InCombatLockdown = function() return combat end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
C_Secrets = { ShouldAurasBeSecret = function() return restricted end }
C_UnitAuras = {
	GetUnitAuras = function(unit, filter, maxCount)
		assert(unit == "player" and filter == "HELPFUL" and maxCount == 255)
		assert(combat == false and restricted == false, "restricted aura scan")
		calls = calls + 1
		return auras
	end,
	AuraIsPrivate = function(id)
		assert(type(id) == "number", "private query received secret ID")
		if id == 60 then return true end
		if id == 70 then return secret end
		if id == 80 then error("private metadata unavailable") end
		return false
	end,
}
local router = {
	Register = function(_, owner, event, callback, unit)
		assert(event == "UNIT_AURA" and unit == "player")
		owner.unitCallback = callback
	end,
	UnregisterAll = function(_, owner) owner.unitCallback = nil end,
}
local ns = { Utils = { IsValueSecret = function(value) return rawequal(value, secret) end }, UnitEventRouter = router }
local function load()
	assert(loadfile("Core/RecentPlayerBuffs.lua"))("ActionHud", ns)
	return ns.RecentPlayerBuffs
end
local function flush()
	local pending = timers
	timers = {}
	for _, callback in ipairs(pending) do callback() end
end
local function ids(module)
	local result = {}
	for _, entry in ipairs(module:GetEntries()) do result[#result + 1] = entry.id end
	return table.concat(result, ",")
end
local recent = load()
assert(ids(recent) == "30,40", "saved history sanitized")
auras = { { spellId = 10 }, { spellId = 30 }, { spellId = 10 }, secret,
	{ spellId = secret }, { spellId = 60 }, { spellId = 70 }, { spellId = 80 }, { spellId = -2 } }
recent:OnEnable()
recent:Refresh()
assert(#timers == 1, "coalesce startup and refresh")
flush()
assert(ids(recent) == "10,30,40", "discover eligible IDs while display disabled")
local entries, saved = recent:GetEntries(), addon.db.char.playerBuffRecentIDs
local messagesBefore = messages
recent:Refresh()
flush()
assert(recent:GetEntries() == entries and addon.db.char.playerBuffRecentIDs == saved, "unchanged scans remain stable")
assert(messages == messagesBefore, "unchanged scans do not refresh the UI")
auras = { { spellId = 10 }, { spellId = 40 } }
recent:Refresh()
flush()
assert(ids(recent) == "40,10,30", "reappearing buff becomes most recent")
local before = calls
recent:OnUnitAura("UNIT_AURA", "target", secret)
recent:OnUnitAura("UNIT_AURA", secret, secret)
flush()
assert(calls == before, "foreign and secret unit tokens ignored")
recent:OnUnitAura("UNIT_AURA", "player", secret)
combat = true
flush()
assert(calls == before and recent:GetStatus() == "restricted", "callback rechecks combat")
combat = false
for _, value in ipairs({ true, secret, "false" }) do
	restricted = value
	recent:Refresh()
	flush()
	assert(calls == before and recent:GetStatus() == "restricted")
end
restricted = false
combat = secret
recent:Refresh()
flush()
assert(calls == before, "secret combat gate fails closed")
combat = false
local predicate = C_Secrets.ShouldAurasBeSecret
C_Secrets.ShouldAurasBeSecret = nil
recent:Refresh()
assert(recent:GetStatus() == "unavailable" and #timers == 0)
C_Secrets.ShouldAurasBeSecret = function() error("predicate failure") end
recent:Refresh()
assert(recent:GetStatus() == "restricted" and #timers == 0)
C_Secrets.ShouldAurasBeSecret = predicate
local private = C_UnitAuras.AuraIsPrivate
C_UnitAuras.AuraIsPrivate = nil
recent:Refresh()
assert(recent:GetStatus() == "unavailable" and #timers == 0)
C_UnitAuras.AuraIsPrivate = private
local enumerate = C_UnitAuras.GetUnitAuras
C_UnitAuras.GetUnitAuras = nil
recent:Refresh()
assert(recent:GetStatus() == "unavailable" and #timers == 0)
C_UnitAuras.GetUnitAuras = function() error("enumeration unavailable") end
recent:Refresh()
flush()
assert(recent:GetStatus() == "unavailable" and ids(recent) == "40,10,30")
C_UnitAuras.GetUnitAuras = enumerate
auras = secret
recent:Refresh()
flush()
assert(recent:GetStatus() == "unavailable" and ids(recent) == "40,10,30", "secret result ignored")
auras = {}
for index = 1, 300 do auras[index] = { spellId = 1000 + index } end
recent:Refresh()
flush()
assert(#recent:GetEntries() == 100 and #addon.db.char.playerBuffRecentIDs == 100, "bounded storage")
assert(recent:GetEntries()[1].id == 1001 and recent:GetEntries()[100].id == 1100)
saved = ids(recent)
addon.db.profile = { playerBuffsEnabled = false }
assert(ids(recent) == saved, "profile changes retain character history")
recent:Refresh()
before = calls
recent:OnDisable()
flush()
assert(calls == before and recent.unitCallback == nil and next(recent.events) == nil, "disable cancels pending scan and events")
recent:Refresh()
assert(#timers == 0, "disabled refresh cannot queue")
auras = {}
for index, id in ipairs(addon.db.char.playerBuffRecentIDs) do auras[index] = { spellId = id } end
recent = load()
assert(ids(recent) == saved, "reload preserves recency")
recent:OnEnable()
flush()
assert(ids(recent) == saved, "startup scan preserves saved ordering")
recent:Refresh()
before, messagesBefore = calls, messages
recent:Clear()
flush()
assert(calls == before and messages == messagesBefore + 1, "Clear notifies and cancels pending discovery")
assert(#recent:GetEntries() == 0 and #addon.db.char.playerBuffRecentIDs == 0)
auras = { setmetatable({ spellId = 900 }, { __index = function() error("unneeded aura field read") end }) }
recent:Refresh()
recent:OnDisable()
recent:OnEnable()
flush()
assert(ids(recent) == "900", "stale callback does not cancel the new enable generation")
print("Recent player buffs tests passed")
