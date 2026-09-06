local spellType = 1
local bank = 0
local inCombat = false
local scanCount = 0
local itemCalls = 0
local secret = {}

Enum = {
	SpellBookSpellBank = { Player = bank, Pet = 1 },
	SpellBookItemType = { None = 0, Spell = spellType, FutureSpell = 2, PetAction = 3, Flyout = 4 },
}

local lines = {
	{ itemIndexOffset = 0, numSpellBookItems = 8, isGuild = false, shouldHide = false },
	{ itemIndexOffset = 8, numSpellBookItems = 1, isGuild = false, shouldHide = true },
	{ itemIndexOffset = 9, numSpellBookItems = 1, isGuild = true, shouldHide = false },
	{ itemIndexOffset = 10, numSpellBookItems = 1, isGuild = false, shouldHide = false, offSpecID = 72 },
	{ itemIndexOffset = 11, numSpellBookItems = 1, isGuild = false, shouldHide = false },
}

local items = {
	[1] = { actionID = 10, spellID = 110, itemType = spellType, name = "Base Name", iconID = 10,
		isPassive = false, isOffSpec = false },
	[2] = { actionID = 110, spellID = 110, itemType = spellType, name = "Duplicate", iconID = 11,
		isPassive = false, isOffSpec = false },
	[3] = { actionID = 20, spellID = 220, itemType = spellType, name = "Beta Ward", iconID = 22,
		isPassive = true, isOffSpec = false },
	[4] = { actionID = 30, spellID = 330, itemType = spellType, name = "Fallback", iconID = 33,
		isPassive = false, isOffSpec = false },
	[5] = { actionID = 40, spellID = 440, itemType = Enum.SpellBookItemType.FutureSpell, name = "Future",
		iconID = 44, isPassive = false, isOffSpec = false },
	[6] = { actionID = 50, itemType = Enum.SpellBookItemType.Flyout, name = "Flyout", iconID = 55,
		isPassive = false, isOffSpec = false },
	[7] = { actionID = 60, spellID = 660, itemType = Enum.SpellBookItemType.PetAction, name = "Pet",
		iconID = 66, isPassive = false, isOffSpec = false },
	[8] = { actionID = 70, spellID = 770, itemType = spellType, name = "Offspec Item", iconID = 77,
		isPassive = false, isOffSpec = true },
	[9] = { actionID = 80, spellID = 880, itemType = spellType, name = "Hidden", iconID = 88,
		isPassive = false, isOffSpec = false },
	[10] = { actionID = 90, spellID = 990, itemType = spellType, name = "Guild", iconID = 99,
		isPassive = false, isOffSpec = false },
	[11] = { actionID = 100, spellID = 1010, itemType = spellType, name = "Offspec Line", iconID = 100,
		isPassive = false, isOffSpec = false },
	[12] = { actionID = 120, spellID = 331, itemType = spellType, name = "Fallback", iconID = 121,
		isPassive = false, isOffSpec = false },
}

C_SpellBook = {
	GetNumSpellBookSkillLines = function()
		scanCount = scanCount + 1
		return #lines
	end,
	GetSpellBookSkillLineInfo = function(index)
		return lines[index]
	end,
	GetSpellBookItemInfo = function(slot, requestedBank)
		assert(requestedBank == bank, "player spell bank must be used")
		itemCalls = itemCalls + 1
		return items[slot]
	end,
}

local metadata = {
	[110] = { name = "Alpha Guard", iconID = 111 },
	[220] = { name = "Beta Ward", iconID = 222 },
}
C_Spell = {
	GetSpellInfo = function(id)
		if id == 999 then error("metadata failure") end
		if id == 555 then return { name = secret, iconID = secret } end
		return metadata[id]
	end,
	GetSpellDescription = function(id)
		if id == 110 then return "Alpha description" end
		if id == 999 then error("description failure") end
		if id == 555 then return secret end
		return nil
	end,
}

InCombatLockdown = function() return inCombat end
LibStub = function(name)
	assert(name == "AceLocale-3.0")
	return {
		GetLocale = function()
			return setmetatable({ ["Spell %d"] = "Spell %d" }, { __index = function(_, key) return key end })
		end,
	}
end

local ns = {
	Utils = {
		IsValueSecret = function(value) return rawequal(value, secret) end,
	},
}
assert(loadfile("Settings/PlayerBuffSpellbook.lua"))("ActionHud", ns)
local spellbook = ns.PlayerBuffSpellbook

assert(spellbook:IsAvailable(), "complete spellbook API should be available")
local entries = spellbook:GetEntries()
assert(scanCount == 1 and itemCalls == 9, "only visible, current-spec lines should be scanned")
assert(#entries == 4, "duplicates and unsupported spellbook item types should be removed")
assert(entries[1].id == 110 and entries[1].name == "Alpha Guard" and entries[1].icon == 111)
assert(entries[1].description == "Alpha description" and entries[1].isPassive == false)
assert(entries[2].id == 220 and entries[2].isPassive == true)
assert(entries[3].id == 330 and entries[3].name == "Fallback" and entries[3].icon == 33,
	"unloaded C_Spell metadata should fall back to spellbook metadata")
assert(entries[3].description == "")
assert(entries[4].id == 331 and entries[4].name == "Fallback",
	"equal names should be ordered by spell ID")
assert(items[1].actionID ~= entries[1].id, "override spellID must be retained instead of actionID")

assert(spellbook:GetEntries() == entries and scanCount == 1, "entries should remain cached")
spellbook:Refresh()
assert(spellbook:GetEntries() ~= entries and scanCount == 2, "Refresh should invalidate the cache")

local search = spellbook:Search("ALPHA", false)
assert(#search == 1 and search[1].id == 110, "name search should be case-insensitive")
search = spellbook:Search("10", false)
assert(#search == 1 and search[1].id == 110, "ID search should use literal text")
search = spellbook:Search(".", true)
assert(#search == 0, "search terms must not be interpreted as Lua patterns")
search = spellbook:Search("", false)
assert(#search == 3 and search[1].id == 110 and search[2].id == 330 and search[3].id == 331,
	"passives should be excluded from search results by default")
search = spellbook:Search("", true)
assert(#search == 4 and search[2].id == 220, "passives should be available on request")

local description = spellbook:Describe(110)
assert(description.id == 110 and description.name == "Alpha Guard" and description.icon == 111)
description = spellbook:Describe(999)
assert(description.id == 999 and description.name == "Spell 999" and description.icon == 134400
	and description.description == "", "unknown and failing metadata should use stable fallbacks")
description = spellbook:Describe(555)
assert(description.name == "Spell 555" and description.icon == 134400 and description.description == "",
	"restricted metadata values must not be formatted or retained")
assert(spellbook:Describe(secret) == nil, "restricted IDs must not be formatted or passed to C_Spell")

local beforeCombat = spellbook:GetEntries()
spellbook:Refresh()
items[13] = { actionID = 130, spellID = 1200, itemType = spellType, name = "Combat Added", iconID = 130,
	isPassive = false, isOffSpec = false }
lines[6] = { itemIndexOffset = 12, numSpellBookItems = 1, isGuild = false, shouldHide = false }
inCombat = true
assert(spellbook:GetEntries(true) == beforeCombat and scanCount == 2,
	"combat refreshes should retain and return the previous cache")
inCombat = false
local afterCombat = spellbook:GetEntries()
assert(afterCombat ~= beforeCombat and scanCount == 3, "deferred refresh should run after combat")
assert(#afterCombat == 5 and afterCombat[3].id == 1200, "post-combat scan should include new spells in name order")

local savedAPI = C_SpellBook
C_SpellBook = nil
assert(not spellbook:IsAvailable(), "missing spellbook API should be unavailable")
assert(#spellbook:GetEntries() == 0, "missing spellbook API should return an empty list")
C_SpellBook = savedAPI

local savedSpellAPI = C_Spell
C_Spell = nil
assert(not spellbook:IsAvailable(), "missing metadata API should be unavailable")
assert(#spellbook:GetEntries() == 0, "missing metadata API should return an empty list")
C_Spell = savedSpellAPI

local savedCount = C_SpellBook.GetNumSpellBookSkillLines
C_SpellBook.GetNumSpellBookSkillLines = function() return 1000000 end
spellbook:Refresh()
assert(#spellbook:GetEntries() == 0, "unbounded native line counts must be rejected")
C_SpellBook.GetNumSpellBookSkillLines = savedCount

print("player buff spellbook helper tests passed")
