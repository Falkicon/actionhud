local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local AuraSounds = addon:NewModule("AuraSounds", "AceEvent-3.0")
ns.AuraSounds = AuraSounds

-- Optional sounds for selected Player Buffs using Blizzard's native aura-sound
-- rules (C_UnitAuras.AddAuraSound). The game evaluates the event; ActionHud
-- never reads aura state, and a preview is only an audition of the file.
-- Reviewed against Retail 12.1.0 build 69587:
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitConstantsDocumentation.lua
-- AddAuraSound is a restricted call: defer during combat. Triggers are Added,
-- ApplicationsIncreased, and Removed; only Added is offered until the others are
-- verified in game. Revalidate unit tokens and restrictions each season.
local BUNDLED = {
	{ key = "bundle:raid", name = L["Raid Warning"], path = [[Sound\Interface\RaidWarning.ogg]] },
	{ key = "bundle:ready", name = L["Ready Check"], path = [[Sound\Interface\ReadyCheck.ogg]] },
	{ key = "bundle:alarm", name = L["Alarm"], path = [[Sound\Interface\AlarmClockWarning3.ogg]] },
	{ key = "bundle:ping", name = L["Map Ping"], path = [[Sound\Interface\MapPing.ogg]] },
}
local DEFAULT_KEY = "bundle:raid"
local MAX_ID = 2147483647

local registered = {} -- auraID -> { soundID = number, path = string }
local statuses = {} -- auraID -> status code

function AuraSounds:GetBundled() return BUNDLED end

local function Media()
	return LibStub("LibSharedMedia-3.0", true)
end

-- Returns { key = display name } for the sound picker.
function AuraSounds:GetChoices()
	local values, order = {}, {}
	for _, sound in ipairs(BUNDLED) do values[sound.key] = sound.name; order[#order + 1] = sound.key end
	local lsm = Media()
	if lsm then
		local names = lsm:List("sound") or {}
		for _, name in ipairs(names) do
			if name ~= "None" then
				local key = "lsm:" .. name
				values[key] = name .. " " .. L["(shared media)"]
				order[#order + 1] = key
			end
		end
	end
	return values, order
end

-- A removed shared-media sound falls back to the default bundled sound.
function AuraSounds:ResolvePath(key)
	if type(key) == "string" then
		for _, sound in ipairs(BUNDLED) do
			if sound.key == key then return sound.path, key end
		end
		local name = key:match("^lsm:(.+)$")
		local lsm = Media()
		if name and lsm then
			local path = lsm:Fetch("sound", name, true)
			if type(path) == "string" or type(path) == "number" then return path, key end
		end
	end
	return BUNDLED[1].path, DEFAULT_KEY
end

function AuraSounds:GetRule(id)
	local rules = addon.db.profile.playerBuffSounds
	local rule = type(rules) == "table" and rules[tostring(id)]
	if type(rule) ~= "table" then return nil end
	return rule
end

function AuraSounds:SetRule(id, values)
	local profile = addon.db.profile
	if type(profile.playerBuffSounds) ~= "table" then profile.playerBuffSounds = {} end
	local key = tostring(id)
	local rule = profile.playerBuffSounds[key] or {}
	for field, value in pairs(values) do rule[field] = value end
	if rule.sound == false then rule.sound = nil end
	if rule.sound == nil and not rule.mute then
		profile.playerBuffSounds[key] = nil
	else
		profile.playerBuffSounds[key] = rule
	end
	self:Sync()
end

-- Audition only. This says nothing about whether the live trigger works.
function AuraSounds:Preview(key)
	local path = self:ResolvePath(key)
	if type(PlaySoundFile) == "function" then pcall(PlaySoundFile, path, "Master") end
end

function AuraSounds:IsAvailable()
	return type(C_UnitAuras) == "table" and type(C_UnitAuras.AddAuraSound) == "function"
		and type(C_UnitAuras.RemoveAuraSound) == "function"
		and type(Enum) == "table" and type(Enum.UnitAuraSoundTrigger) == "table"
		and type(Enum.UnitAuraSoundTrigger.Added) == "number"
end

-- A selection is eligible when it is one exact aura ID. Catalog entries with
-- several related IDs stay unresolved so overlapping candidates cannot double alert.
function AuraSounds:IsAmbiguous(id)
	local candidates = ns.BlizzardBuffCatalog:GetCandidateSpellIDs(id)
	if not candidates then return false end
	local distinct, count = {}, 0
	for candidate in pairs(candidates) do
		local resolved = ns.BlizzardBuffCatalog:ResolveAuraSpellID(candidate)
		if resolved and not distinct[resolved] then distinct[resolved] = true; count = count + 1 end
	end
	return count > 1
end

function AuraSounds:GetStatus(id)
	local rule = self:GetRule(id)
	if not rule or not rule.sound then return "none" end
	if rule.mute then return "muted" end
	if addon.db.profile.playerBuffsSoundEnabled ~= true then return "off" end
	if not self:IsAvailable() then return "unavailable" end
	if self:IsAmbiguous(id) then return "ambiguous" end
	return statuses[id] or "pending"
end

local function Retire(id)
	local entry = registered[id]
	if not entry then return end
	registered[id] = nil
	if entry.soundID and type(C_UnitAuras) == "table" and type(C_UnitAuras.RemoveAuraSound) == "function" then
		pcall(C_UnitAuras.RemoveAuraSound, entry.soundID)
	end
end

-- Registers exactly the sounds wanted by the active profile and retires the rest.
function AuraSounds:Sync()
	if InCombatLockdown() then
		self._pending = true
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
		return
	end
	self._pending = nil
	local wanted = {}
	local playerBuffs = addon:GetModule("PlayerBuffs", true)
	local profile = addon.db.profile
	if playerBuffs and playerBuffs._runtimeActive and playerBuffs.spellIDs
		and profile.playerBuffsSoundEnabled == true and self:IsAvailable() then
		for _, id in ipairs(playerBuffs.spellIDs) do
			local rule = self:GetRule(id)
			if rule and rule.sound and not rule.mute and not self:IsAmbiguous(id) and id <= MAX_ID then
				local path, resolvedKey = self:ResolvePath(rule.sound)
				wanted[id] = path
				if resolvedKey ~= rule.sound then rule.sound = resolvedKey end
			end
		end
	end
	for id in pairs(registered) do
		if wanted[id] == nil or registered[id].path ~= wanted[id] then Retire(id) end
	end
	for id, path in pairs(wanted) do
		if not registered[id] then
			local info = { unitToken = "player", spellID = id }
			if type(path) == "number" then info.soundFileID = path else info.soundFileName = path end
			local ok, soundID = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, info)
			if ok and type(soundID) == "number" then
				registered[id] = { soundID = soundID, path = path }
				statuses[id] = "active"
			else
				statuses[id] = "failed"
			end
		else
			statuses[id] = "active"
		end
	end
	for id in pairs(statuses) do
		if not wanted[id] then statuses[id] = nil end
	end
	self:SendMessage("ACTIONHUD_AURA_SOUNDS_CHANGED")
end

function AuraSounds:OnRegenEnabled()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if self._pending then self:Sync() end
end

function AuraSounds:GetRegisteredCount()
	local count = 0
	for _ in pairs(registered) do count = count + 1 end
	return count
end

function AuraSounds:OnEnable()
	self:Sync()
end

function AuraSounds:OnDisable()
	self:RetireAll()
end

function AuraSounds:RetireAll()
	if InCombatLockdown() then
		self._pending = true
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
		return
	end
	for id in pairs(registered) do Retire(id) end
	statuses = {}
end
