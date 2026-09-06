local _, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Recent = addon:NewModule("RecentPlayerBuffs", "AceEvent-3.0")
ns.RecentPlayerBuffs = Recent

local MAX_HISTORY = 100
local MAX_AURAS = 255

local function IsSecret(value)
	return ns.Utils.IsValueSecret(value)
end

local function IsSpellID(value)
	return not IsSecret(value) and type(value) == "number"
		and value >= 1 and value <= 2147483647 and value == math.floor(value)
end

local function Read(func, ...)
	local ok, value = pcall(func, ...)
	if not ok or IsSecret(value) then return nil end
	return value
end

-- API source: Blizzard 12.1.0 build 69587, reviewed 2026-09-06.
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua
-- GetUnitAuras requires unit aura access and can return secret contents. There
-- is no public CanAccessUnitAuras predicate in this build. Fail closed unless
-- ShouldAurasBeSecret explicitly returns false, additionally excluding combat.
-- Recheck these definitions when updating the target season/expansion.
local function AccessStatus()
	if type(ns.Utils) ~= "table" or type(ns.Utils.IsValueSecret) ~= "function"
		or type(InCombatLockdown) ~= "function" or type(C_Secrets) ~= "table"
		or type(C_Secrets.ShouldAurasBeSecret) ~= "function" or type(C_UnitAuras) ~= "table"
		or type(C_UnitAuras.GetUnitAuras) ~= "function" or type(C_UnitAuras.AuraIsPrivate) ~= "function" then
		return "unavailable"
	end
	if Read(InCombatLockdown) ~= false or Read(C_Secrets.ShouldAurasBeSecret) ~= false then
		return "restricted"
	end
	return "ready"
end

function Recent:GetStatus()
	local status = AccessStatus()
	if status ~= "ready" then return status end
	return self._scanFailed and "unavailable" or status
end

function Recent:LoadHistory()
	if self.entries then return end
	self.entries, self.previousIDs = {}, {}
	local saved = addon.db and addon.db.char and addon.db.char.playerBuffRecentIDs
	if type(saved) == "table" then
		for index = 1, MAX_HISTORY do
			local id = saved[index]
			if IsSpellID(id) and not self.previousIDs[id] then
				self.entries[#self.entries + 1] = { id = id }
				self.previousIDs[id] = true
			end
		end
	end
	self:SaveHistory()
end

function Recent:SaveHistory()
	if not addon.db or not addon.db.char then return end
	local ids = {}
	for index, entry in ipairs(self.entries) do ids[index] = entry.id end
	addon.db.char.playerBuffRecentIDs = ids
end

function Recent:GetEntries()
	self:LoadHistory()
	return self.entries
end

function Recent:Clear()
	-- Invalidate already queued discovery so Clear stays empty until a new event.
	self._generation = (self._generation or 0) + 1
	self._scheduled = false
	self.entries, self.previousIDs = {}, {}
	self:SaveHistory()
	self:SendMessage("ACTIONHUD_RECENT_BUFFS_CHANGED")
end

function Recent:Scan()
	if not self._runtimeActive or AccessStatus() ~= "ready" then return end
	local failedBefore = self._scanFailed
	self._scanFailed = false
	self:LoadHistory()
	local auras = Read(C_UnitAuras.GetUnitAuras, "player", "HELPFUL", MAX_AURAS)
	if type(auras) ~= "table" then
		self._scanFailed = true
		if not failedBefore then self:SendMessage("ACTIONHUD_RECENT_BUFFS_CHANGED") end
		return
	end
	local current, additions = {}, {}
	-- Fixed bounds avoid deriving loop limits or keys from restricted data.
	for index = 1, MAX_AURAS do
		local aura = auras[index]
		if not IsSecret(aura) and type(aura) == "table" then
			local id = aura.spellId
			if IsSpellID(id) and not current[id] and Read(C_UnitAuras.AuraIsPrivate, id) == false then
				current[id] = true
				if not self.previousIDs[id] then additions[#additions + 1] = { id = id } end
			end
		end
	end
	self.previousIDs = current
	if #additions == 0 then
		if failedBefore then self:SendMessage("ACTIONHUD_RECENT_BUFFS_CHANGED") end
		return
	end
	local entries, added = {}, {}
	-- Simultaneous discoveries keep API order; newly observed batches lead.
	for _, entry in ipairs(additions) do
		if #entries < MAX_HISTORY then
			entries[#entries + 1], added[entry.id] = entry, true
		end
	end
	for _, entry in ipairs(self.entries) do
		if #entries < MAX_HISTORY and not added[entry.id] then entries[#entries + 1] = entry end
	end
	self.entries = entries
	self:SaveHistory()
	self:SendMessage("ACTIONHUD_RECENT_BUFFS_CHANGED")
end

function Recent:Refresh()
	if not self._runtimeActive or self._scheduled then return end
	if AccessStatus() ~= "ready" then return end
	self._scheduled = true
	local generation = self._generation
	C_Timer.After(0, function()
		if generation ~= self._generation then return end
		self._scheduled = false
		self:Scan()
	end)
end

function Recent:OnUnitAura(_, unit)
	-- Never examine updateInfo, including when the event is restricted.
	if not IsSecret(unit) and type(unit) == "string" and unit == "player" then self:Refresh() end
end

function Recent:OnEnable()
	self._generation = (self._generation or 0) + 1
	self._runtimeActive = true
	self:LoadHistory()
	ns.UnitEventRouter:Register(self, "UNIT_AURA", "OnUnitAura", "player")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "Refresh")
	self:Refresh()
end

function Recent:OnDisable()
	self._runtimeActive = false
	self._generation = (self._generation or 0) + 1
	self._scheduled = false
	ns.UnitEventRouter:UnregisterAll(self)
	self:UnregisterAllEvents()
end
