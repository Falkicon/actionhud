local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local PlayerBuffs = addon:NewModule("PlayerBuffs", "AceEvent-3.0")
local Utils = ns.Utils

local MAX_SPELLS = 12

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
	self.slots = {}
	self.layoutWidth, self.layoutHeight = 0, 0
end

function PlayerBuffs:OnEnable()
	self:ApplyEnabledState()
end

function PlayerBuffs:OnDisable()
	self:StopRuntime()
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
	cooldown:SetCountdownFont(Utils.GetTimerFont("small"))
	if cooldown.SetCountdownMillisecondsThreshold then cooldown:SetCountdownMillisecondsThreshold(3) end
	auraFrame:SetDurationCooldown(cooldown)
	local count = cooldown:CreateFontString(nil, "OVERLAY")
	count:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", -1, 1)
	auraFrame:SetApplicationCount(count, {})
end

function PlayerBuffs:ConfigureSlots()
	local p = self.db.profile
	local size = PublicInteger(p.playerBuffsIconSize, 28, 16, 64)
	local columns = PublicInteger(p.playerBuffsColumns, 4, 1, MAX_SPELLS)
	local spacing = PublicInteger(p.playerBuffsSpacing, 2, 0, 20)
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
		-- Slot placement and footprint depend exclusively on public settings.
		-- The restricted child follows its anchors entirely within the engine.
		slot.anchor:ClearAllPoints()
		slot.anchor:SetSize(size, size)
		slot.anchor:SetPoint("TOPLEFT", self.container, "TOPLEFT",
			((index - 1) % columns) * (size + spacing), -math.floor((index - 1) / columns) * (size + spacing))
		self.auraContainer:SetAuraSlotCandidateFilters(slot.key, { includeSpellIDs = { [self.spellIDs[index]] = true } })
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
