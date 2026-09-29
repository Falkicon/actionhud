local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

-- Explains why a selected buff is (or is not) expected to work, and records the
-- player's own confirmations. Evidence describes public configuration and
-- readable history only; it never reports live aura state or a guaranteed
-- combat result, and it never treats a missing entry as an invalid ID.
local Evidence = {}
ns.BuffEvidence = Evidence

local MAX_TESTS = 24
local RESULTS = { appeared = true, missing = true, sounded = true, silent = true }

local function IsID(value)
	return type(value) == "number" and value >= 1 and value <= 2147483647 and value == math.floor(value)
end

local function Contains(set, needle)
	if not set then return false end
	for key, value in pairs(set) do
		if key == needle or value == needle then return true end
	end
	return false
end

local function SpellName(id)
	local info = ns.BlizzardBuffCatalog:Describe(id)
	return info and info.name or string.format(L["Spell %d"], id)
end

-- Ordered list of evidence keys for a selected aura ID.
function Evidence:Classify(id)
	local found = {}
	if not IsID(id) then return found end
	local recent = ns.RecentPlayerBuffs
	if recent then
		for _, entry in ipairs(recent:GetEntries()) do
			if entry.id == id then found[#found + 1] = "observed"; break end
		end
	end
	local catalog = ns.BlizzardBuffCatalog
	if catalog:GetMappingInfo(id) then found[#found + 1] = "documented" end
	local isCatalog = catalog:GetCandidateSpellIDs(id) ~= nil
	if not isCatalog then
		for _, entry in ipairs(catalog:GetEntries()) do
			if Contains(entry.candidateSpellIDs, id) then isCatalog = true; break end
		end
	end
	if isCatalog then found[#found + 1] = "catalog" end
	if #found == 0 then found[1] = "manual" end
	return found
end

local STATUS_LABELS = {
	disabled = L["Disabled"], unavailable = L["Unavailable"], error = L["Error"], invalid = L["Invalid ID list"],
	empty = L["No buffs selected"], pending = L["Waiting for combat to end"], active = L["Active"],
}

local LABELS = {
	observed = L["Seen on you"],
	documented = L["Documented mapping"],
	catalog = L["Blizzard Catalog"],
	manual = L["Unverified ID"],
}

function Evidence:Describe(id)
	local labels = {}
	for index, key in ipairs(self:Classify(id)) do labels[index] = LABELS[key] end
	return table.concat(labels, ", ")
end

-- Plain-language notes, one per line. Unverified IDs are explicitly still usable.
function Evidence:Explain(id)
	local lines = {}
	local catalog = ns.BlizzardBuffCatalog
	for _, key in ipairs(self:Classify(id)) do
		if key == "observed" then
			lines[#lines + 1] = L["This buff was readable on you earlier. That shows the ID exists, not that it will show in combat."]
		elseif key == "documented" then
			local info = catalog:GetMappingInfo(id)
			lines[#lines + 1] = string.format(
				L["The spell you cast (%s, %d) applies a different buff (%s, %d). ActionHud tracks the buff. Source reviewed %s on build %s."],
				SpellName(info.castID), info.castID, SpellName(info.auraID), info.auraID, info.reviewed, info.build)
		elseif key == "catalog" then
			local candidates = catalog:GetCandidateSpellIDs(id)
			local count = 0
			for _ in pairs(candidates or {}) do count = count + 1 end
			if count > 1 then
				lines[#lines + 1] = string.format(
					L["Blizzard lists %d related spell IDs for this buff and picks the active one. ActionHud does not guess which is the buff."], count)
			else
				lines[#lines + 1] = L["Blizzard's catalog lists this buff for your character."]
			end
		else
			lines[#lines + 1] = L["ActionHud has no evidence for this ID yet. It still works if it is the buff's own spell ID. Buffs you cast can use a different ID than the spell."]
		end
	end
	return table.concat(lines, "\n")
end

-- Why discovery might be empty, and what to do about it.
function Evidence:DiscoveryNote()
	local recent, catalog = ns.RecentPlayerBuffs, ns.BlizzardBuffCatalog
	local status = recent and recent:GetStatus() or "unavailable"
	if status == "restricted" then
		return L["Recent Buffs pauses in combat and while aura data is restricted. Leave combat, gain the buff, then press Refresh. An ID missing from history is not invalid."]
	elseif status == "unavailable" then
		return L["Recent Buffs is unavailable on this client. Enter the spell ID under Advanced: Spell IDs. An ID is not invalid just because discovery is unavailable."]
	elseif not catalog:IsAvailable() then
		return L["Blizzard Catalog is unavailable. Use Recent Buffs or enter the spell ID under Advanced: Spell IDs."]
	end
	return L["Search history or the catalog. A buff missing from both can still be tracked by its spell ID."]
end

-- Player-confirmed results, kept apart from observed facts and bounded.
local function Store()
	local char = addon.db and addon.db.char
	if not char then return nil end
	if type(char.playerBuffSetup) ~= "table" then char.playerBuffSetup = { version = 1, tests = {} } end
	local setup = char.playerBuffSetup
	if type(setup.tests) ~= "table" then setup.tests = {} end
	return setup
end

local function Context()
	local _, class = UnitClass("player")
	local version, build = GetBuildInfo()
	return { class = type(class) == "string" and class or "?", client = tostring(version) .. " (" .. tostring(build) .. ")" }
end

function Evidence:Record(id, kind, ok)
	if not IsID(id) or (kind ~= "appearance" and kind ~= "sound") then return false end
	local setup = Store()
	if not setup then return false end
	local key = tostring(id)
	local entry = setup.tests[key]
	if not entry then
		entry = {}
		setup.tests[key] = entry
		setup.order = setup.order or {}
		setup.order[#setup.order + 1] = key
		while #setup.order > MAX_TESTS do
			setup.tests[table.remove(setup.order, 1)] = nil
		end
	end
	local context = Context()
	entry[kind] = ok == true and (kind == "sound" and "sounded" or "appeared") or (kind == "sound" and "silent" or "missing")
	entry.class, entry.client = context.class, context.client
	return true
end

function Evidence:GetResult(id)
	local setup = Store()
	local entry = setup and setup.tests[tostring(id)]
	if not entry then return nil end
	local appearance = RESULTS[entry.appearance] and entry.appearance or nil
	local sound = RESULTS[entry.sound] and entry.sound or nil
	return { appearance = appearance, sound = sound, class = entry.class, client = entry.client }
end

function Evidence:Forget(id)
	local setup = Store()
	if not setup then return end
	local key = tostring(id)
	setup.tests[key] = nil
	for index, value in ipairs(setup.order or {}) do
		if value == key then table.remove(setup.order, index); break end
	end
end

function Evidence:DescribeResult(id)
	local result = self:GetResult(id)
	if not result then return L["No setup check recorded for this buff."] end
	local parts = {}
	if result.appearance == "appeared" then parts[#parts + 1] = L["You confirmed it appeared."]
	elseif result.appearance == "missing" then parts[#parts + 1] = L["You reported it did not appear."] end
	if result.sound == "sounded" then parts[#parts + 1] = L["You confirmed it sounded."]
	elseif result.sound == "silent" then parts[#parts + 1] = L["You reported it did not sound."] end
	return string.format(L["%s (Recorded by you on %s, client %s.)"], table.concat(parts, " "),
		tostring(result.class), tostring(result.client))
end

-- Public checks only. These never infer whether the aura is active.
function Evidence:Diagnose(id)
	local rows = {}
	local playerBuffs = addon:GetModule("PlayerBuffs", true)
	local catalog = ns.BlizzardBuffCatalog
	rows[#rows + 1] = string.format(L["Resolved name: %s (ID %d)"], SpellName(id), id)
	local candidates = catalog:GetCandidateSpellIDs(id)
	local count = 0
	for _ in pairs(candidates or {}) do count = count + 1 end
	rows[#rows + 1] = string.format(L["Configured candidate IDs: %d"], math.max(1, count))
	local status = playerBuffs and playerBuffs:GetStatus() or "unavailable"
	rows[#rows + 1] = string.format(L["Player Buffs state: %s"], STATUS_LABELS[status] or STATUS_LABELS.error)
	if playerBuffs and playerBuffs._pendingEnabledState then
		rows[#rows + 1] = L["Some changes are waiting for combat to end."]
	end
	rows[#rows + 1] = self:DiscoveryNote()
	return rows
end

function Evidence:NextSteps(kind)
	if kind == "sound" then
		return L["Check that the master sound switch and this buff's mute are off, that a sound is chosen, and that the sound rule is not marked ambiguous. Then leave combat, reload if a change was pending, and try again."]
	end
	return L["Check that Player Buffs is enabled and showing a slot for this buff. Make changes outside combat, then obtain the buff again. If Blizzard lists several related IDs, try adding the buff's own aura ID under Advanced: Spell IDs."]
end
