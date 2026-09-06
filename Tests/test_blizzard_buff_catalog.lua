local secret = {}
local combat = false
local calls = 0
local ns = { Utils = { IsValueSecret = function(value) return rawequal(value, secret) end } }
LibStub = function()
	return { GetLocale = function() return { ["Spell %d"] = "Spell %d" } end }
end
InCombatLockdown = function() return combat end
assert(loadfile("Core/BlizzardBuffCatalog.lua"))("ActionHud", ns)
local catalog = ns.BlizzardBuffCatalog
assert(not catalog:IsAvailable())
assert(#catalog:GetEntries() == 0)
assert(catalog:Describe(123).name == "Spell 123")
assert(catalog:Describe(secret) == nil)
assert(catalog:Describe(-1) == nil)
Enum = { CooldownViewerCategory = {
	Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3,
	SpecAgnosticEssential = secret, SpecAgnosticTracked = 6,
} }
local function item(id)
	return { spellID = id, hasAura = true, selfAura = true, isKnown = true,
		isInvisible = false, linkedSpellIDs = {} }
end
local info = { [1] = item(100), [2] = item(200), [3] = item(300), [4] = item(400),
	[5] = item(500), [6] = item(600), [7] = item(100), [9] = item(secret) }
info[1].overrideSpellID = 101
info[1].overrideTooltipSpellID = 102
info[1].linkedSpellIDs = { 102, 103, secret, -1, 104 }
info[2].selfAura = false
info[3].hasAura = false
info[4].isKnown = false
info[5].isInvisible = true
info[6].selfAura = secret
info[7].linkedSpellIDs = { 105 }
local categoryCalls = {}
C_CooldownViewer = {
	GetCooldownViewerCategorySet = function(category, unlearned)
		assert(unlearned == false)
		categoryCalls[category] = (categoryCalls[category] or 0) + 1
		if category == 6 then return {} end
		if category == 3 then return { 7, 1 } end
		assert(category == 2, "only buff categories belong in the picker")
		return { 1, 2, 3, 4, 5, 6, 8, 9, secret, "bad", -1 }
	end,
	GetCooldownViewerCooldownInfo = function(id)
		calls = calls + 1
		return info[id]
	end,
}
C_Spell = {
	GetSpellInfo = function(id)
		if id == 100 then return { name = "Buff", iconID = 456 } end
		if id == 200 then return { name = secret, iconID = secret } end
		error("metadata unavailable")
	end,
	GetSpellDescription = function(id)
		if id == 100 then return "Description" end
		return secret
	end,
}
assert(catalog:IsAvailable())
catalog:Refresh()
local entries = catalog:GetEntries()
assert(#entries == 2 and entries[1].id == 100)
assert(entries[1].name == "Buff" and entries[1].icon == 456)
assert(entries[1].description == "Description")
assert(categoryCalls[2] == 1 and categoryCalls[3] == 1 and categoryCalls[6] == 1)
assert(categoryCalls[0] == nil and categoryCalls[1] == nil, "cooldown categories are excluded")
assert(calls == 9, "cooldown IDs must be deduplicated before querying")
local candidates = catalog:GetCandidateSpellIDs(100)
for id = 100, 105 do assert(candidates[id], "every associated spell is a candidate") end
assert(catalog:GetCandidateSpellIDs(103) == nil, "observed linked aura retains exact identity")
assert(catalog:GetCandidateSpellIDs(secret) == nil)
assert(catalog:Describe(200).name == "Spell 200")
assert(catalog:Describe(300).description == "")
assert(catalog:GetEntries() == entries and calls == 9, "queries reuse stable cache")

combat = true
catalog:Refresh()
info[1] = item(700)
assert(catalog:GetEntries() == entries and calls == 9)
assert(catalog:GetCandidateSpellIDs(100) == candidates, "combat retains previous filters")
combat = false
assert(catalog:GetEntries() ~= entries and calls == 18)
assert(#catalog:GetEntries() == 3)

catalog:Refresh()
combat = secret
local prior = catalog:GetEntries()
assert(calls == 18, "secret combat state must fail closed")
combat = false
local api = C_CooldownViewer
C_CooldownViewer = nil
assert(catalog:GetEntries() == prior, "API absence must preserve last cache")
C_CooldownViewer = api
catalog:Refresh()
local categoryAPI, infoAPI = api.GetCooldownViewerCategorySet, api.GetCooldownViewerCooldownInfo
local failures = 0
api.GetCooldownViewerCategorySet = function()
	failures = failures + 1
	error("API failure")
end
assert(catalog:GetEntries() == prior, "API errors must preserve complete previous snapshot")
for _ = 1, 10 do
	assert(catalog:GetEntries() == prior)
	assert(catalog:GetCandidateSpellIDs(100)[105])
end
assert(failures == 1, "failed snapshot must not cause repeated getter retries")
api.GetCooldownViewerCategorySet = function() return secret end
catalog:Refresh()
assert(catalog:GetEntries() == prior, "secret categories cannot discard cached filters")
api.GetCooldownViewerCategorySet = categoryAPI
api.GetCooldownViewerCooldownInfo = function() error("info failure") end
catalog:Refresh()
assert(catalog:GetEntries() == prior, "info exceptions preserve cache")
api.GetCooldownViewerCooldownInfo = function() return secret end
catalog:Refresh()
assert(catalog:GetEntries() == prior, "secret info preserves cache")
api.GetCooldownViewerCooldownInfo = infoAPI
catalog:Refresh()
assert(catalog:GetEntries() ~= prior and #catalog:GetEntries() == 3, "explicit refresh recovers")
api.GetCooldownViewerCategorySet = function() return {} end
catalog:Refresh()
assert(#catalog:GetEntries() == 0 and catalog:GetCandidateSpellIDs(100) == nil,
	"legitimate empty categories replace old mappings")

catalog:Refresh()
local repeated = {}
for index = 1, 1000 do repeated[index] = index end
api.GetCooldownViewerCategorySet = function() return repeated end
api.GetCooldownViewerCooldownInfo = function()
	calls = calls + 1
	return nil
end
local start = calls
assert(#catalog:GetEntries() == 0)
assert(calls - start == 512, "malformed oversized category arrays must be bounded")

-- Reproduce the user's 2026-09-06 warrior dump. Cooldown IDs are fixture
-- identities; category, spell ID, and flags reflect the captured live output.
local liveInfo = {}
local function liveItem(cooldownID, spellID, selfAura, hasAura, known, invisible)
	local entry = item(spellID)
	entry.selfAura, entry.hasAura = selfAura, hasAura
	entry.isKnown, entry.isInvisible = known, invisible
	liveInfo[cooldownID] = entry
end
liveItem(10, 2565, false, false, true, false) -- Essential Shield Block
liveItem(11, 23920, true, false, true, false) -- Spell Reflection
liveItem(12, 871, true, false, true, false) -- Shield Wall
liveItem(13, 190456, true, false, true, false) -- Ignore Pain
liveItem(14, 2565, true, false, true, false) -- TrackedBar Shield Block
liveItem(15, 97462, false, true, true, false) -- Rallying Cry, verified exception
liveItem(16, 1160, false, true, true, false) -- Demoralizing Shout: target debuff
liveItem(17, 772, false, true, false, false) -- Rend: target debuff, unlearned
liveItem(18, 440989, true, false, false, false) -- unlearned self aura
-- Additional safety fixtures exercise independently public eligibility fields.
liveItem(19, 900001, true, false, true, true)
liveItem(20, 900002, secret, false, true, false)
liveItem(21, 900003, true, false, secret, false)
liveItem(22, 900004, true, false, true, secret)
liveItem(23, 900005, true, true, true, false) -- cooldown-only entry
liveItem(24, 900006, true, secret, true, false) -- hasAura is never inspected
liveItem(25, 900007, true, false, true, false) -- arbitrary spec-agnostic self buff
local liveCategories = {
	[0] = { 10, 23 }, [1] = { 15 },
	[2] = { 11, 15, 16, 17, 18, 19, 20, 21, 22 },
	[3] = { 12, 13, 14 }, [6] = { 24, 25, 11 },
}
api.GetCooldownViewerCategorySet = function(category, unlearned)
	assert(not unlearned)
	assert(category ~= 0 and category ~= 1)
	return liveCategories[category]
end
api.GetCooldownViewerCooldownInfo = function(id) return liveInfo[id] end
catalog:Refresh()
entries = catalog:GetEntries()
local found = {}
for _, entry in ipairs(entries) do found[entry.id] = true end
assert(#entries == 7)
for _, id in ipairs({ 23920, 871, 190456, 2565, 97462, 900006, 900007 }) do
	assert(found[id], "known tracked player buff must be included: " .. id)
end
assert(not found[1160] and not found[772], "hasAura must not admit target debuffs")
assert(not found[440989] and not found[900001] and not found[900002]
	and not found[900003] and not found[900004] and not found[900005])
assert(catalog:ResolveAuraSpellID(97462) == 97463)
assert(catalog:ResolveAuraSpellID(97463) == 97463)
assert(catalog:ResolveAuraSpellID(123) == 123)
assert(catalog:ResolveAuraSpellID(secret) == nil)
assert(catalog:ResolveAuraSpellID(-1) == nil)
-- Enum aliases are permitted; query each numeric tracked category only once.
Enum.CooldownViewerCategory.SpecAgnosticTracked = 3
local trackedBarCalls = 0
api.GetCooldownViewerCategorySet = function(category)
	if category == 3 then trackedBarCalls = trackedBarCalls + 1 end
	return liveCategories[category]
end
catalog:Refresh()
assert(#catalog:GetEntries() == 5 and trackedBarCalls == 1)
print("Blizzard buff catalog tests passed")
