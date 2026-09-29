local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local PlayerBuffs = addon:NewModule("PlayerBuffs", "AceEvent-3.0")
local Utils = ns.Utils

local MAX_SPELLS = 12

-- Call only with validated public configuration or catalog IDs.
function PlayerBuffs:ResolveAuraSpellID(spellID)
	return ns.BlizzardBuffCatalog:ResolveAuraSpellID(spellID)
end

-- Only saved public configuration is parsed here. Aura identities and values
-- stay inside Blizzard's CustomAuraContainer and CustomAuraButton delegates.
function PlayerBuffs:ParseSpellIDs(text)
	if type(text) ~= "string" then return nil, "invalid" end
	if text:match("^%s*$") then return {} end
	if text:find("[^%d,%s]") then return nil, "invalid" end
	local ids, seen = {}, {}
	for token in text:gmatch("[^,%s]+") do
		local id = tonumber(token)
		if not id or id < 1 or id > 2147483647 or id ~= math.floor(id) then
			return nil, "invalid"
		end
		-- Resolve on read so existing profiles work without rewriting SavedVariables.
		id = self:ResolveAuraSpellID(id)
		if not seen[id] then
			ids[#ids + 1] = id
			seen[id] = true
			if #ids > MAX_SPELLS then return nil, "too_many" end
		end
	end
	if #ids == 0 then return nil, "invalid" end
	return ids
end

local function PublicInteger(value, fallback, minimum, maximum)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.max(minimum, math.min(maximum, math.floor(value)))
end

-- Text style lives in addon-owned Font objects. The native buttons reference them
-- once during their initializer, so later size/outline changes reach the
-- restricted widgets without the addon ever touching those widgets again.
local TIMER_FONT, COUNT_FONT = "ActionHudPlayerBuffTimerFont", "ActionHudPlayerBuffCountFont"
local FONT_PATH = "Fonts\\ARIALN.TTF"

function PlayerBuffs:EnsureFonts()
	if self.timerFont then return end
	self.timerFont = CreateFont(TIMER_FONT)
	self.countFont = CreateFont(COUNT_FONT)
end

function PlayerBuffs:IsAvailable()
	local api = _G["C_AuraContainerUtil"]
	return type(api) == "table" and type(api.ProcessCustomAuraButtonApplicationCountOptions) == "function"
end

function PlayerBuffs:GetStatus()
	if not self.db or self.db.profile.playerBuffsEnabled ~= true then return "disabled" end
	if not self:IsAvailable() then return "unavailable" end
	if self._initializationError then return "error" end
	local ids = self:ParseSpellIDs(self.db.profile.playerBuffsSpellIDs or "")
	if not ids then return "invalid" end
	if #ids == 0 then return "empty" end
	if self._pendingEnabledState then return "pending" end
	return self._runtimeActive and "active" or "pending"
end

function PlayerBuffs:OnInitialize()
	self.db = addon.db
	self:EnsureFonts()
	self:ApplyStyle()
	self.slots = {}
	self.layoutWidth, self.layoutHeight = 0, 0
end

function PlayerBuffs:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCatalogChanged")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnCatalogChanged")
	self:RegisterEvent("SPELLS_CHANGED", "OnCatalogChanged")
	self:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED", "OnCatalogChanged")
	self:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED", "OnCatalogChanged")
	self:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", "OnCatalogChanged")
	ns.BlizzardBuffCatalog:Refresh()
	self:ApplyEnabledState()
end

function PlayerBuffs:OnCatalogChanged()
	-- Payloads are irrelevant: rebuild public configuration at the next safe pass.
	ns.BlizzardBuffCatalog:Refresh()
	self:UpdateLayout()
end

function PlayerBuffs:OnDisable()
	self:UnregisterAllEvents()
	self:StopRuntime()
	if ns.AuraSounds then ns.AuraSounds:Sync() end
end

function PlayerBuffs:ApplyEnabledState()
	self._desiredEnabled = self.db.profile.playerBuffsEnabled == true
	if InCombatLockdown() then
		self._pendingEnabledState = true
		self:UpdateLayout()
		return
	end
	self._pendingEnabledState = nil
	local ids = self:ParseSpellIDs(self.db.profile.playerBuffsSpellIDs or "")
	if self:IsEnabled() and self._desiredEnabled and self:IsAvailable()
		and not self._initializationError and ids and #ids > 0 then
		self.spellIDs = ids
		self:StartRuntime()
	else
		self:StopRuntime()
	end
	-- Sound rules follow the same lifecycle: retire on disable/profile change.
	if ns.AuraSounds then ns.AuraSounds:Sync() end
end

-- Public style values only. Font objects are addon-owned, so updating them is
-- safe at any time; nothing here touches native aura widgets.
function PlayerBuffs:ApplyStyle()
	self:EnsureFonts()
	local p = self.db.profile
	local flags = p.playerBuffsTextOutline == false and "" or "OUTLINE"
	local count = PublicInteger(p.playerBuffsCountFontSize, 12, 8, 32)
	self.countFont:SetFont(FONT_PATH, count, flags)
	local timerSize = PublicInteger(p.playerBuffsTimerFontSize, 0, 0, 32)
	if timerSize == 0 then
		-- Native small timer font, exactly as before these options existed.
		local name = Utils.GetTimerFont("small")
		pcall(self.timerFont.SetFontObject, self.timerFont, _G[name] or name)
	else
		self.timerFont:SetFont(FONT_PATH, timerSize, flags)
	end
end

local BORDER_EDGES = 4

local function CreateDecoration(anchor)
	local bg = anchor:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(anchor)
	-- Above the native child yet below the drag overlay's level offset.
	local frame = CreateFrame("Frame", nil, anchor)
	frame:SetAllPoints(anchor)
	frame:EnableMouse(false)
	frame:SetFrameLevel(anchor:GetFrameLevel() + 5)
	local edges = {}
	for index = 1, BORDER_EDGES do edges[index] = frame:CreateTexture(nil, "OVERLAY") end
	return { background = bg, edges = edges }
end

-- Slot decoration is static and tied to the configured slot, not to whether a
-- buff is active, so an inactive slot stays as visible as an active one.
function PlayerBuffs:StyleSlot(slot)
	local p = self.db.profile
	slot.decoration = slot.decoration or CreateDecoration(slot.anchor)
	local decoration = slot.decoration
	local opacity = math.max(0, math.min(1, tonumber(p.playerBuffsBackgroundOpacity) or 0))
	decoration.background:SetColorTexture(0, 0, 0, opacity)
	local border = PublicInteger(p.playerBuffsBorderSize, 0, 0, 6)
	local top, bottom, left, right = unpack(decoration.edges)
	for _, edge in ipairs(decoration.edges) do
		edge:SetColorTexture(1, 1, 1, 0.95)
		if border > 0 then edge:Show() else edge:Hide() end
	end
	local thickness = math.max(border, 1)
	top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(thickness)
	bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(thickness)
	left:ClearAllPoints(); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(thickness)
	right:ClearAllPoints(); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(thickness)
end

function PlayerBuffs:CreateFrames()
	if self.container then return end
	local main = _G["ActionHudFrame"]
	if not main then return end
	local defaults = self.db.defaults.profile
	self.container = ns.DraggableContainer:Create({
		moduleId = "playerBuffs",
		parent = main,
		db = self.db,
		xKey = "playerBuffsXOffset",
		yKey = "playerBuffsYOffset",
		defaultX = defaults.playerBuffsXOffset,
		defaultY = defaults.playerBuffsYOffset,
		size = { width = 1, height = 1 },
	})
	self.container:Hide()
	self.auraContainer = CreateFrame("AuraContainer", nil, self.container, "CustomAuraContainerTemplate")
	self.auraContainer:SetEnabled(false)
	self.auraContainer:SetUnit("player")
	self.auraContainer:SetPoint("TOPLEFT", self.container, "TOPLEFT")
	self.auraContainer:SetSize(1, 1)
	self.auraContainer:EnableMouse(false)
end

function PlayerBuffs:FailInitialization(message)
	self._initializationError = tostring(message)
	self._runtimeActive = false
	self.layoutWidth, self.layoutHeight = 0, 0
	-- This is a public native delegate, not access to an aura child.
	if self.auraContainer and self.auraContainer.SetEnabled then self.auraContainer:SetEnabled(false) end
	if self.container then self.container:Hide() end
	addon:Logf("playerBuffs", "Native player buff initialization failed: %s", self._initializationError)
end

function PlayerBuffs:StartRuntime()
	if InCombatLockdown() then
		self._pendingEnabledState = true
		self:UpdateLayout()
		return
	end
	if self._runtimeActive then return end
	local ok, message = pcall(self.CreateFrames, self)
	if not ok then self:FailInitialization(message); return end
	if not self.auraContainer then return end
	self._runtimeActive = true
	self:UpdateLayout()
end

function PlayerBuffs:StopRuntime()
	if InCombatLockdown() then
		self._pendingEnabledState = true
		self:UpdateLayout()
		return
	end
	self._runtimeActive = false
	self._pendingEnabledState = nil
	self.layoutWidth, self.layoutHeight = 0, 0
	if self.auraContainer and self.auraContainer.SetEnabled then self.auraContainer:SetEnabled(false) end
	if self.container then self.container:Hide() end
	self:UpdateLayout()
end

local function InitializeAuraFrame(auraFrame, anchor)
	-- Called once by Blizzard before applying aura-frame access restrictions.
	-- Afterwards we retain only the ordinary public anchor, never aura widgets.
	auraFrame:SetAllPoints(anchor)
	auraFrame:EnableMouse(false)
	local icon = auraFrame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	auraFrame:SetIcon(icon)
	local cooldown = CreateFrame("Cooldown", nil, auraFrame, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:EnableMouse(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(false)
	cooldown:SetCountdownFont(TIMER_FONT)
	if cooldown.SetCountdownMillisecondsThreshold then cooldown:SetCountdownMillisecondsThreshold(3) end
	auraFrame:SetDurationCooldown(cooldown)
	local count = cooldown:CreateFontString(nil, "OVERLAY")
	count:SetFontObject(COUNT_FONT)
	count:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", -1, 1)
	auraFrame:SetApplicationCount(count, {})
end

function PlayerBuffs:ConfigureSlots()
	local p = self.db.profile
	local size = PublicInteger(p.playerBuffsIconSize, 28, 16, 64)
	local columns = PublicInteger(p.playerBuffsColumns, 4, 1, MAX_SPELLS)
	local spacing = PublicInteger(p.playerBuffsSpacing, 2, 0, 20)
	self:ApplyStyle()
	local count = #self.spellIDs
	local usedColumns = math.min(columns, count)
	local rows = math.ceil(count / columns)
	self.layoutWidth = usedColumns * size + (usedColumns - 1) * spacing
	self.layoutHeight = rows * size + (rows - 1) * spacing
	self.container:SetSize(self.layoutWidth, self.layoutHeight)
	self.auraContainer:SetEnabled(false)
	for index = 1, count do
		local slot = self.slots[index]
		if not slot then
			local anchor = CreateFrame("Frame", nil, self.container)
			anchor:EnableMouse(false)
			slot = { anchor = anchor, key = "selected" .. index }
			local initialized, initializationError
			self.auraContainer:AddAuraSlot(slot.key, "HELPFUL", {
				candidateFilters = { includeSpellIDs = {} },
				initializeFrame = function(auraFrame)
					initialized, initializationError = pcall(InitializeAuraFrame, auraFrame, anchor)
				end,
			})
			if not initialized then error(initializationError or "Native aura initialization callback did not run") end
			self.slots[index] = slot
		end
		self:StyleSlot(slot)
		-- Slot placement and footprint depend exclusively on public settings.
		-- The restricted child follows its anchors entirely within the engine.
		slot.anchor:ClearAllPoints()
		slot.anchor:SetSize(size, size)
		slot.anchor:SetPoint("TOPLEFT", self.container, "TOPLEFT",
			((index - 1) % columns) * (size + spacing), -math.floor((index - 1) / columns) * (size + spacing))
		local spellID = self.spellIDs[index]
		local candidates = ns.BlizzardBuffCatalog:GetCandidateSpellIDs(spellID)
		local includeSpellIDs = { [spellID] = true }
		-- Public catalog configuration only. Blizzard resolves which associated
		-- aura is active; addon code never reads the selected native aura.
		for candidateID in pairs(candidates or {}) do
			includeSpellIDs[self:ResolveAuraSpellID(candidateID)] = true
		end
		self.auraContainer:SetAuraSlotCandidateFilters(slot.key, { includeSpellIDs = includeSpellIDs })
	end
	for index = count + 1, #self.slots do
		self.auraContainer:SetAuraSlotCandidateFilters(self.slots[index].key, { includeSpellIDs = {} })
	end
end

function PlayerBuffs:PrepareLayout()
	if not self._runtimeActive or InCombatLockdown() then return end
	local ok, message = pcall(self.ConfigureSlots, self)
	if not ok then self:FailInitialization(message) end
end

function PlayerBuffs:ApplyLayoutPosition()
	if not self._runtimeActive or not self.container or InCombatLockdown() then return end
	local manager = addon:GetModule("LayoutManager", true)
	self.container:ClearAllPoints()
	local inStack = manager and manager:IsModuleInStack("playerBuffs")
	if inStack then
		self.container:SetPoint("TOP", _G["ActionHudFrame"], "TOP", 0, manager:GetModulePosition("playerBuffs"))
	else
		ns.DraggableContainer:UpdatePosition(self.container)
	end
	ns.DraggableContainer:UpdateOverlay(self.container)
	if inStack then
		self.container:EnableMouse(false)
		self.container.overlay:Hide()
		self.container.label:Hide()
	end
end

function PlayerBuffs:RenderLayout()
	if not self._runtimeActive or InCombatLockdown() then return end
	self.container:Show()
	self.auraContainer:SetEnabled(true)
end

function PlayerBuffs:CalculateHeight()
	return self._runtimeActive and self.layoutHeight or 0
end

function PlayerBuffs:GetLayoutWidth()
	return self._runtimeActive and self.layoutWidth or 0
end

function PlayerBuffs:GetContainer()
	return self.container
end

function PlayerBuffs:UpdateLayout()
	local manager = addon:GetModule("LayoutManager", true)
	if manager then manager:RequestLayout("playerBuffs") end
end
