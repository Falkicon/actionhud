local _, ns = ...

local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local Utils = ns.Utils
local Catalog = {}
ns.BlizzardBuffCatalog = Catalog

local cachedEntries, candidatesByID = {}, {}
local cacheValid = false
local MAX_ID = 2147483647
local MAX_CATEGORY_ITEMS, MAX_LINKED_IDS = 512, 32

-- Blizzard maintains this list in the client; no spell list is copied into ActionHud.
-- Reviewed against Retail 12.1.0 build 69587, wow-ui-source commit:
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/CooldownViewerDocumentation.lua
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/CooldownViewerConstantsDocumentation.lua
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettingsDataProvider.lua
-- User's live warrior catalog dump (2026-09-06) includes known self auras
-- with hasAura=false: Spell Reflection, Shield Wall, and Ignore Pain. Shield
-- Block has selfAura=false in Essential but true in TrackedBar. Only tracked
-- categories describe eligible buffs; hasAura is not an eligibility gate.
-- For each season/expansion, revalidate categories, selfAura/isKnown,
-- and GetAssociatedAuraSpellPriority in these files against the target build.
-- The latter accepts linked, tooltip override, override, and base spell IDs;
-- linkedSpellIDs[1] is NOT an authoritative aura replacement for the cast ID.
-- GroupBuff/equipment entries have separate item/slot semantics and are omitted.
local CATEGORY_NAMES = {
	"TrackedBuff", "TrackedBar", "SpecAgnosticTracked",
}

-- Verified cast-to-aura exceptions, not a catalog of trackable spells.
-- Rallying Cry: SimulationCraft's Midnight warrior rallying_cry_t uses aura
-- 97463 and reads the cast's health effect from 97462 (reviewed 2026-09-06).
-- https://github.com/simulationcraft/simc/blob/midnight/engine/class_modules/sc_warrior.cpp
-- The live dump above marks its tracked entry selfAura=false, hasAura=true.
local AURA_SPELL_IDS = {
	[97462] = 97463,
}

local function IsSecret(value)
	return Utils.IsValueSecret(value)
end

local function IsInteger(value, minimum, maximum)
	return not IsSecret(value) and type(value) == "number"
		and value >= minimum and value <= maximum and value == math.floor(value)
end

local function PublicTable(value)
	return not IsSecret(value) and type(value) == "table"
end

local function PublicBoolean(value, expected)
	return not IsSecret(value) and type(value) == "boolean" and value == expected
end

local function PublicString(value)
	if not IsSecret(value) and type(value) == "string" and value ~= "" then return value end
end

local function SafeCall(func, ...)
	if type(func) ~= "function" then return nil end
	local ok, result = pcall(func, ...)
	if ok and not IsSecret(result) then return result end
end

local function ReadCatalogAPI(func, ...)
	local ok, result = pcall(func, ...)
	if not ok or IsSecret(result) then return false end
	return true, result
end

local function CanRefresh()
	-- Fail closed if the combat API errors or its result cannot be read.
	return PublicBoolean(SafeCall(InCombatLockdown), false)
end

function Catalog:ResolveAuraSpellID(spellID)
	if not IsInteger(spellID, 1, MAX_ID) then return nil end
	return AURA_SPELL_IDS[spellID] or spellID
end

function Catalog:IsAvailable()
	return PublicTable(C_CooldownViewer)
		and type(C_CooldownViewer.GetCooldownViewerCategorySet) == "function"
		and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function"
		and PublicTable(Enum) and PublicTable(Enum.CooldownViewerCategory)
end

function Catalog:Describe(id)
	if not IsInteger(id, 1, MAX_ID) then return nil end
	local name, icon, description
	if PublicTable(C_Spell) then
		local info = SafeCall(C_Spell.GetSpellInfo, id)
		if PublicTable(info) then
			name = PublicString(info.name)
			if IsInteger(info.iconID, 1, MAX_ID) then icon = info.iconID end
		end
		description = PublicString(SafeCall(C_Spell.GetSpellDescription, id))
	end
	return { id = id, name = name or string.format(L["Spell %d"], id),
		icon = icon or 134400, description = description or "" }
end

function Catalog:Refresh()
	-- Invalidation is public bookkeeping; existing data remains usable in combat.
	cacheValid = false
end

local function AddCandidate(candidates, id)
	if IsInteger(id, 1, MAX_ID) then candidates[id] = true end
end

local function AddInfo(entries, byID, info)
	if not PublicTable(info) or not PublicBoolean(info.isKnown, true)
		or not PublicBoolean(info.isInvisible, false) or not IsInteger(info.spellID, 1, MAX_ID)
	then return end

	local id = info.spellID
	if not PublicBoolean(info.selfAura, true)
		and not (PublicBoolean(info.selfAura, false) and AURA_SPELL_IDS[id])
	then return end
	local candidates = byID[id]
	if not candidates then
		candidates = {}
		byID[id] = candidates
		local entry = Catalog:Describe(id)
		entry.candidateSpellIDs = candidates
		entries[#entries + 1] = entry
	end
	AddCandidate(candidates, id)
	AddCandidate(candidates, info.overrideSpellID)
	AddCandidate(candidates, info.overrideTooltipSpellID)
	if PublicTable(info.linkedSpellIDs) then
		for index = 1, MAX_LINKED_IDS do
			local linked = info.linkedSpellIDs[index]
			if not IsSecret(linked) and linked == nil then break end
			AddCandidate(candidates, linked)
		end
	end
end

function Catalog:GetEntries()
	if cacheValid or not CanRefresh() then return cachedEntries end
	-- Consume this attempt even on failure. A data event or explicit Refresh
	-- retries; repeated settings getters/native slots must not hammer the API.
	cacheValid = true
	if not self:IsAvailable() then return cachedEntries end
	local entries, byID, seenCooldowns, seenCategories = {}, {}, {}, {}
	for _, name in ipairs(CATEGORY_NAMES) do
		local category = Enum.CooldownViewerCategory[name]
		if IsInteger(category, 0, 100) and not seenCategories[category] then
			seenCategories[category] = true
			local ok, ids = ReadCatalogAPI(C_CooldownViewer.GetCooldownViewerCategorySet, category, false)
			if not ok or not PublicTable(ids) then return cachedEntries end
			if PublicTable(ids) then
				for index = 1, MAX_CATEGORY_ITEMS do
					local id = ids[index]
					if not IsSecret(id) and id == nil then break end
					if IsInteger(id, 1, MAX_ID) and not seenCooldowns[id] then
						seenCooldowns[id] = true
						local readable, info = ReadCatalogAPI(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
						-- MayReturnNothing permits nil (e.g. stale cooldown ID).
						-- Errors/opaque or malformed results cannot replace a good snapshot.
						if not readable or (info ~= nil and not PublicTable(info)) then return cachedEntries end
						AddInfo(entries, byID, info)
					end
				end
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.name == b.name then return a.id < b.id end
		return a.name < b.name
	end)
	cachedEntries, candidatesByID, cacheValid = entries, byID, true
	return cachedEntries
end

-- Returns a read-only public ID set for catalog base IDs, nil for other IDs.
-- An explicitly selected observed aura keeps its exact identity instead of
-- expanding to unrelated alternate auras just because they share a cast.
function Catalog:GetCandidateSpellIDs(id)
	if not IsInteger(id, 1, MAX_ID) then return nil end
	self:GetEntries()
	return candidatesByID[id]
end
