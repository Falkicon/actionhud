local _, ns = ...

local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local Utils = ns.Utils

ns.PlayerBuffSpellbook = {}
local Spellbook = ns.PlayerBuffSpellbook

local QUESTION_MARK_ICON = 134400
local MAX_SKILL_LINES = 128
local MAX_ITEMS_PER_LINE = 512
local MAX_TOTAL_ITEMS = 4096
local MAX_SLOT_INDEX = 100000

local cachedEntries = {}
local cacheValid = false

local function IsSecret(value)
	return Utils and type(Utils.IsValueSecret) == "function" and Utils.IsValueSecret(value)
end

local function IsInteger(value, minimum, maximum)
	return not IsSecret(value)
		and type(value) == "number"
		and value == math.floor(value)
		and value >= minimum
		and value <= maximum
end

local function ReadableString(value)
	if IsSecret(value) or type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function SafeCall(func, ...)
	if type(func) ~= "function" then
		return nil
	end
	local ok, value = pcall(func, ...)
	if not ok or IsSecret(value) then
		return nil
	end
	return value
end

local function IsInCombat()
	local value = SafeCall(InCombatLockdown)
	return type(value) == "boolean" and value
end

local function GetConstants()
	local banks = Enum and Enum.SpellBookSpellBank
	local types = Enum and Enum.SpellBookItemType
	local bank = banks and banks.Player
	local spellType = types and types.Spell
	if not IsInteger(bank, 0, 100) or not IsInteger(spellType, 0, 100) then
		return nil, nil
	end
	return bank, spellType
end

local function ReadSpellMetadata(spellID)
	local spellAPI = C_Spell
	if type(spellAPI) ~= "table" then
		return nil, nil, nil
	end

	local info = SafeCall(spellAPI.GetSpellInfo, spellID)
	local name, icon
	if type(info) == "table" and not IsSecret(info) then
		name = ReadableString(info.name)
		if IsInteger(info.iconID, 1, 2147483647) then
			icon = info.iconID
		end
	end

	local description = SafeCall(spellAPI.GetSpellDescription, spellID)
	if IsSecret(description) or type(description) ~= "string" then
		description = nil
	end
	return name, icon, description
end

local function UnknownName(spellID)
	return string.format(L["Spell %d"], spellID)
end

function Spellbook:IsAvailable()
	local bank, spellType = GetConstants()
	return bank ~= nil
		and spellType ~= nil
		and type(C_SpellBook) == "table"
		and type(C_SpellBook.GetNumSpellBookSkillLines) == "function"
		and type(C_SpellBook.GetSpellBookSkillLineInfo) == "function"
		and type(C_SpellBook.GetSpellBookItemInfo) == "function"
		and type(C_Spell) == "table"
		and type(C_Spell.GetSpellInfo) == "function"
		and type(C_Spell.GetSpellDescription) == "function"
end

function Spellbook:Refresh()
	cacheValid = false
end

function Spellbook:Describe(spellID)
	if not IsInteger(spellID, 1, 2147483647) then
		return nil
	end
	local name, icon, description = ReadSpellMetadata(spellID)
	return {
		id = spellID,
		name = name or UnknownName(spellID),
		icon = icon or QUESTION_MARK_ICON,
		description = description or "",
	}
end

local function BuildEntries()
	local bank, spellType = GetConstants()
	local count = SafeCall(C_SpellBook.GetNumSpellBookSkillLines)
	if not IsInteger(count, 0, MAX_SKILL_LINES) then
		return {}
	end

	local entries, seen = {}, {}
	local visited = 0
	for lineIndex = 1, count do
		local line = SafeCall(C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
		if type(line) == "table" and not IsSecret(line)
			and type(line.shouldHide) == "boolean" and not IsSecret(line.shouldHide)
			and type(line.isGuild) == "boolean" and not IsSecret(line.isGuild)
			and not line.shouldHide and not line.isGuild
			and not IsSecret(line.offSpecID) and line.offSpecID == nil
			and IsInteger(line.itemIndexOffset, 0, MAX_SLOT_INDEX)
			and IsInteger(line.numSpellBookItems, 0, MAX_ITEMS_PER_LINE)
		then
			for relativeIndex = 1, line.numSpellBookItems do
				if visited >= MAX_TOTAL_ITEMS then break end
				visited = visited + 1
				local slot = line.itemIndexOffset + relativeIndex
				local info = SafeCall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
				if type(info) == "table" and not IsSecret(info)
					and not IsSecret(info.itemType) and info.itemType == spellType
					and type(info.isOffSpec) == "boolean" and not IsSecret(info.isOffSpec)
					and type(info.isPassive) == "boolean" and not IsSecret(info.isPassive)
					and not info.isOffSpec
					and IsInteger(info.spellID, 1, 2147483647)
					and not seen[info.spellID]
				then
					local spellID = info.spellID
					local name, icon, description = ReadSpellMetadata(spellID)
					name = name or ReadableString(info.name) or UnknownName(spellID)
					if not icon and IsInteger(info.iconID, 1, 2147483647) then
						icon = info.iconID
					end
					seen[spellID] = true
					entries[#entries + 1] = {
						id = spellID,
						name = name,
						icon = icon or QUESTION_MARK_ICON,
						description = description or "",
						isPassive = info.isPassive,
					}
				end
			end
		end
		if visited >= MAX_TOTAL_ITEMS then break end
	end

	table.sort(entries, function(a, b)
		local aName, bName = string.lower(a.name), string.lower(b.name)
		if aName == bName then return a.id < b.id end
		return aName < bName
	end)
	return entries
end

function Spellbook:GetEntries(refresh)
	if not self:IsAvailable() then
		cachedEntries = {}
		cacheValid = false
		return cachedEntries
	end
	if refresh then cacheValid = false end
	if IsInCombat() then return cachedEntries end
	if not cacheValid then
		cachedEntries = BuildEntries()
		cacheValid = true
	end
	return cachedEntries
end

function Spellbook:Search(query, includePassive)
	if IsSecret(query) or type(query) ~= "string" then query = "" end
	query = string.lower(query)
	local results = {}
	for _, entry in ipairs(self:GetEntries()) do
		local matches = query == ""
			or string.find(string.lower(entry.name), query, 1, true) ~= nil
			or string.find(tostring(entry.id), query, 1, true) ~= nil
		if matches and (includePassive == true or not entry.isPassive) then
			results[#results + 1] = entry
		end
	end
	return results
end
