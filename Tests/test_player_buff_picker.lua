local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
local addon, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local recent, catalog = ns.RecentPlayerBuffs, ns.BlizzardBuffCatalog

local recentEntries = {}
for id = 1, 10 do recentEntries[id] = { id = id } end
recentEntries[#recentEntries + 1] = { id = 132404 }
local catalogEntries = {
	{ id = 23920, name = "Spell Reflection", icon = 135453, candidateSpellIDs = { [23920] = true } },
	{ id = 97462, name = "Rallying Cry", icon = 132333, candidateSpellIDs = { [97462] = true } },
	{ id = 2565, name = "Shield Block", icon = 132110, candidateSpellIDs = { [2565] = true, [132404] = true } },
}
local metadata = {
	[23920] = { id = 23920, name = "Spell Reflection", icon = 135453 },
	[97462] = { id = 97462, name = "Rallying Cry", icon = 132333 },
	[97463] = { id = 97463, name = "Rallying Cry", icon = 132333 },
	[2565] = { id = 2565, name = "Shield Block", icon = 132110 },
	[132404] = { id = 132404, name = "Shield Block Aura", icon = 132110 },
}
for id = 1, 10 do metadata[id] = { id = id, name = "Ability " .. id, icon = 134400 } end

local recentStatus, recentGets, recentRefreshes, recentClears = "ready", 0, 0, 0
local catalogAvailable, catalogGets, catalogRefreshes, describeCalls = true, 0, 0, 0
function recent:GetEntries() recentGets = recentGets + 1; return recentEntries end
function recent:GetStatus() return recentStatus end
function recent:Refresh() recentRefreshes = recentRefreshes + 1 end
function recent:Clear() recentClears = recentClears + 1; recentEntries = {} end
function catalog:IsAvailable() return catalogAvailable end
function catalog:GetEntries() catalogGets = catalogGets + 1; return catalogEntries end
function catalog:Refresh() catalogRefreshes = catalogRefreshes + 1 end
function catalog:Describe(id)
	describeCalls = describeCalls + 1
	return metadata[id] or { id = id, name = "Spell " .. id, icon = 134400 }
end
function catalog:GetCandidateSpellIDs(id)
	if id == 2565 then return { [2565] = true, [132404] = true } end
	return nil
end

local options = ns.Settings.BuildPlayerBuffsOptions(addon).args
local browser, selected = options.browser.args, options.selected.args
local function flush() host:Flush(); host:AssertNoErrors() end
local function values() return assert(addon:GetModule("PlayerBuffs"):ParseSpellIDs(addon.db.profile.playerBuffsSpellIDs)) end

LibStub("AceConfigRegistry-3.0"):ValidateOptionsTable({ name = "picker", type = "group", args = options }, "picker")
assert(options.spellIDsGroup.hidden())
options.advanced.set(nil, true)
assert(not options.spellIDsGroup.hidden())

-- Recent Buffs is the default, and repeated AceConfig getters reuse the local
-- filtered cache while the backend's stable entry array and query are unchanged.
assert(browser.source.get() == "recent")
assert(browser.source.values.recent == "Recent Buffs" and browser.source.values.catalog == "Blizzard Catalog")
assert(not browser.clearHistory.hidden())
assert(browser.sourceNote.name():find("readable helpful buffs", 1, true))
assert(browser.spellLabel1.name() == "Ability 1")
local describedAfterBuild = describeCalls
assert(browser.spellLabel1.image() == 134400)
assert(browser.spellLabel1.tooltipHyperlink() == "spell:1")
browser.status.name()
assert(describeCalls == describedAfterBuild, "stable getters must not rebuild filtered results")

-- Refresh invalidates even if a backend retains the same stable entry array.
browser.refresh.func()
assert(recentRefreshes == 1)
assert(browser.spellLabel1.name() == "Ability 1")
assert(describeCalls > describedAfterBuild)

-- Search uses locally described names and IDs, including catalog candidates.
browser.search.set(nil, "ability 2")
assert(browser.spellLabel1.name() == "Ability 2")
browser.search.set(nil, "2")
assert(browser.spellLabel1.name() == "Ability 2")
browser.source.set(nil, "catalog")
assert(browser.clearHistory.hidden())
assert(browser.sourceNote.name():find("not a complete list", 1, true))
browser.search.set(nil, "132404")
assert(browser.spellLabel1.name() == "Shield Block")
browser.refresh.func()
assert(catalogRefreshes == 1 and catalogGets > 0)
catalogAvailable = false
assert(browser.status.name():find("unavailable", 1, true))
catalogAvailable = true

-- Base spells and their observed aura IDs are reciprocal duplicates, without
-- rewriting the profile's chosen representation.
addon.db.profile.playerBuffsSpellIDs = "132404"
assert(browser.spell1.disabled() and browser.spell1.name() == "Added")
browser.spell1.func()
assert(addon.db.profile.playerBuffsSpellIDs == "132404")
addon.db.profile.playerBuffsSpellIDs = "2565"
browser.source.set(nil, "recent")
browser.search.set(nil, "132404")
assert(browser.spell1.disabled() and browser.spell1.name() == "Added")
browser.spell1.func()
assert(addon.db.profile.playerBuffsSpellIDs == "2565")

-- Restricted/unavailable status is reported without forcing a result rebuild.
recentStatus = "restricted"
local getsBeforeStatus = recentGets
assert(browser.status.name():find("restricted", 1, true))
assert(recentGets == getsBeforeStatus)
recentStatus = "unavailable"
assert(browser.status.name():find("unavailable", 1, true))
recentStatus = "ready"

-- Clearing affects only history and leaves the selected profile untouched.
browser.clearHistory.func()
assert(recentClears == 1 and browser.spell1.hidden())
assert(addon.db.profile.playerBuffsSpellIDs == "2565")
recentEntries = {}
for id = 1, 10 do recentEntries[id] = { id = id } end
recentEntries[#recentEntries + 1] = { id = 132404 }
browser.refresh.func()
browser.search.set(nil, "")

-- Existing paging, resolved aliases, selected controls, and preview remain.
addon.db.profile.playerBuffsSpellIDs = ""
browser.next.func()
assert(browser.spellLabel1.name() == "Ability 9" and not browser.spellLabel3.hidden())
browser.previous.func()
browser.source.set(nil, "catalog")
browser.search.set(nil, "rallying")
browser.spell1.func(); flush()
assert(addon.db.profile.playerBuffsSpellIDs == "97463", "picker selections must save the resolved aura ID")
assert(browser.spell1.disabled() and browser.spell1.name() == "Added")
assert(#native.containers == 0, "adding a mapped buff must not enable the feature")
addon.db.profile.playerBuffsSpellIDs = "97462"
assert(browser.spell1.disabled() and browser.spell1.name() == "Added", "legacy cast IDs must match their resolved aura")
browser.spell1.func()
assert(addon.db.profile.playerBuffsSpellIDs == "97462", "a duplicate selection must not rewrite the profile")
addon.db.profile.playerBuffsSpellIDs = ""
browser.search.set(nil, "reflection")
browser.spell1.func(); flush()
assert(values()[1] == 23920)
assert(selected.slot1.args.label.name():find("Spell Reflection", 1, true))
assert(selected.slot1.args.label.tooltipHyperlink() == "spell:23920")
assert(options.preview.args.icons.name():find("135453", 1, true))

browser.source.set(nil, "recent")
browser.search.set(nil, "")
browser.spell1.func(); browser.spell2.func(); flush()
assert(#values() == 3 and values()[2] == 1 and values()[3] == 2)
selected.slot3.args.up.func(); flush()
assert(values()[2] == 2 and values()[3] == 1)
selected.slot1.args.down.func(); flush()
assert(values()[1] == 2 and values()[2] == 23920)
selected.slot1.args.remove.func(); flush()
assert(#values() == 2 and values()[1] == 23920)
options.sizingGroup.args.columns.set(nil, 1); flush()
assert(options.preview.args.icons.name():find("\n", 1, true))
browser.search.set(nil, "no matches")
assert(browser.spell1.hidden())

-- Mutations always read the latest profile; stale closures do not overwrite a
-- profile switch or silently discard an invalid advanced list.
addon.db:SetProfile("new-picker-profile"); flush()
browser.search.set(nil, "")
assert(selected.slot1.hidden())
browser.spell1.func(); flush()
assert(#values() == 1 and values()[1] == 1)
addon.db.profile.playerBuffsSpellIDs = "invalid"
assert(browser.spell1.disabled())
browser.spell2.func()
assert(addon.db.profile.playerBuffsSpellIDs == "invalid")
options.spellIDsGroup.args.spellIDs.set(nil, "1 2 3 4 5 6 7 8 9 10 11 12"); flush()
browser.source.set(nil, "catalog")
browser.search.set(nil, "reflection")
assert(browser.spell1.disabled())
browser.spell1.func()
assert(#values() == 12)
selected.slot12.args.remove.func(); flush()
assert(not browser.spell1.disabled())

options.enable.set(nil, true); flush()
host:SetCombat(true)
local writes = native.writes
browser.spell1.func(); flush()
assert(values()[12] == 23920 and native.writes == writes)
host:SetCombat(false)
assert(native.containers[1].slots.selected12.filters.includeSpellIDs[23920])

-- Build the real embedded widget used for selected spell names/icons.
local methods = getmetatable(UIParent).__index
function methods:SetTexture(value) self.texture = value end
function methods:GetTexture() return self.texture end
function methods:GetStringHeight() return 12 end
local gui = LibStub("AceGUI-3.0")
local label = gui:Create("InteractiveLabel")
label:SetWidth(500)
label:SetText(selected.slot12.args.label.name())
label:SetImage(selected.slot12.args.label.image())
label:SetImageSize(24, 24)
assert(label.imageshown and label.label:GetText():find("Spell Reflection", 1, true))
gui:Release(label)
host:AssertNoErrors()
print("SUCCESS: recent/catalog picker sources, cache, search, paging, duplicates, profiles and combat deferral")
