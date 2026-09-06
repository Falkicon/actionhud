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
	Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 2,
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
		return { 1, 2, 3, 4, 5, 6, 7, 8, 9, secret, "bad", -1 }
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
assert(#entries == 1 and entries[1].id == 100)
assert(entries[1].name == "Buff" and entries[1].icon == 456)
assert(entries[1].description == "Description")
assert(categoryCalls[2] == 1, "duplicate category enumerations must not repeat")
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
assert(#catalog:GetEntries() == 2)

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
assert(catalog:GetEntries() ~= prior and #catalog:GetEntries() == 2, "explicit refresh recovers")
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
print("Blizzard buff catalog tests passed")
