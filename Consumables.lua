local _, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local Consumables = addon:NewModule("Consumables", "AceEvent-3.0")
local Items, Utils = ns.ConsumableItems, ns.Utils

local function Setting(value, fallback, minimum, maximum)
	if Utils.IsValueSecret(value) or type(value) ~= "number" or value ~= value then return fallback end
	return math.max(minimum, math.min(maximum, math.floor(value)))
end

function Consumables:OnInitialize()
	self.db, self.slots = addon.db, {}
	self.layoutWidth, self.layoutHeight = 0, 0
end

function Consumables:OnEnable()
	self:ApplyEnabledState()
end

function Consumables:OnDisable()
	self:UnregisterAllEvents()
	self:StopRuntime()
end

function Consumables:GetStatus()
	if not self.db.profile.consumablesEnabled then return "disabled" end
	local ids = Items:ParseItemIDs(self.db.profile.consumablesItemIDs)
	if not ids then return "invalid" end
	if #ids == 0 then return "empty" end
	if self._pendingEnabledState then return "pending" end
	return self._runtimeActive and "active" or "pending"
end

function Consumables:ApplyEnabledState()
	self._desiredEnabled = self.db.profile.consumablesEnabled == true
	if InCombatLockdown() then
		self._pendingEnabledState = true
		self:UpdateLayout()
		return
	end
	self._pendingEnabledState = nil
	local ids = Items:ParseItemIDs(self.db.profile.consumablesItemIDs)
	if self:IsEnabled() and self._desiredEnabled and ids and #ids > 0 then
		self.itemIDs = ids
		self:StartRuntime()
	else
		self:StopRuntime()
	end
end

function Consumables:StartRuntime()
	if InCombatLockdown() then self._pendingEnabledState = true; self:UpdateLayout(); return end
	if self._runtimeActive then return end
	if not self.container then
		local defaults = self.db.defaults.profile
		self.container = ns.DraggableContainer:Create({
			moduleId = "consumables", parent = _G["ActionHudFrame"], db = self.db,
			xKey = "consumablesXOffset", yKey = "consumablesYOffset",
			defaultX = defaults.consumablesXOffset, defaultY = defaults.consumablesYOffset,
			size = { width = 1, height = 1 },
		})
		if not self.container then return end
		self.container:Hide()
	end
	self._runtimeActive = true
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN",
		"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED" }) do
		self:RegisterEvent(event, "OnDataChanged")
	end
	Items:Refresh()
	self:UpdateLayout()
end

function Consumables:StopRuntime()
	if InCombatLockdown() then self._pendingEnabledState = true; self:UpdateLayout(); return end
	self:UnregisterAllEvents()
	self._runtimeActive, self._pendingEnabledState = false, nil
	self.layoutWidth, self.layoutHeight = 0, 0
	if self.container then self.container:Hide() end
	self:UpdateLayout()
end

function Consumables:OnDataChanged(event)
	if event ~= "SPELL_UPDATE_COOLDOWN" and event ~= "BAG_UPDATE_COOLDOWN" then Items:Refresh() end
	if self._runtimeActive then self:RefreshValues() end
end

local function CreateSlot(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:EnableMouse(false)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:EnableMouse(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(false)
	cooldown:SetCountdownFont(Utils.GetTimerFont("medium"))
	-- Sibling overlay stays visible when the native cooldown hides at zero and
	-- draws inventory/status text above the swipe while a cooldown is running.
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	overlay:EnableMouse(false)
	local count = overlay:CreateFontString(nil, "OVERLAY")
	count:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	local unavailable = overlay:CreateFontString(nil, "OVERLAY")
	unavailable:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE")
	unavailable:SetPoint("CENTER", frame, "CENTER")
	return { frame = frame, icon = icon, cooldown = cooldown, count = count, unavailable = unavailable }
end

function Consumables:PrepareLayout()
	if not self._runtimeActive or InCombatLockdown() then return end
	local p = self.db.profile
	local size = Setting(p.consumablesIconSize, 28, 16, 64)
	local columns = Setting(p.consumablesColumns, 4, 1, 12)
	local spacing = Setting(p.consumablesSpacing, 2, 0, 20)
	local count = #self.itemIDs
	self.layoutWidth = math.min(columns, count) * (size + spacing) - spacing
	self.layoutHeight = math.ceil(count / columns) * (size + spacing) - spacing
	self.container:SetSize(self.layoutWidth, self.layoutHeight)
	for index, id in ipairs(self.itemIDs) do
		local slot = self.slots[index] or CreateSlot(self.container)
		self.slots[index], slot.itemID = slot, id
		slot.frame:ClearAllPoints()
		slot.frame:SetSize(size, size)
		slot.frame:SetPoint("TOPLEFT", self.container, "TOPLEFT",
			((index - 1) % columns) * (size + spacing), -math.floor((index - 1) / columns) * (size + spacing))
		slot.count:SetFont("Fonts\\ARIALN.TTF", Setting(p.consumablesCountFontSize, 12, 8, 32), "OUTLINE")
		slot.cooldown:SetCountdownFont(Utils.GetTimerFont(p.consumablesTimerFontSize or "medium"))
		if slot.cooldown.SetCountdownMillisecondsThreshold then
			slot.cooldown:SetCountdownMillisecondsThreshold(Setting(p.cooldownDecimalThreshold, 3, 0, 60))
		end
		slot.frame:Show()
	end
	for index = count + 1, #self.slots do
		self.slots[index].itemID = nil
		self.slots[index].frame:Hide()
	end
end

function Consumables:RefreshValues()
	for _, slot in ipairs(self.slots) do
		if slot.itemID then
			local info = Items:Describe(slot.itemID)
			local count = Items:GetCount(slot.itemID)
			local start, duration, enabled = Items:GetCooldown(slot.itemID)
			slot.icon:SetTexture(info.icon)
			slot.count:SetText(count == nil and L["?"] or tostring(count))
			-- All values reaching this branch have passed the helper's public guards.
			local available = count ~= nil and count > 0 and enabled == true and start ~= nil
			slot.icon:SetDesaturated(not available)
			slot.icon:SetAlpha(available and 1 or 0.4)
			slot.unavailable:SetText((start == nil or enabled ~= true) and L["?"] or "")
			if available then slot.cooldown:SetCooldown(start, duration) else slot.cooldown:Clear() end
		end
	end
end

function Consumables:ApplyLayoutPosition()
	if not self._runtimeActive or not self.container or InCombatLockdown() then return end
	local manager = addon:GetModule("LayoutManager", true)
	self.container:ClearAllPoints()
	local inStack = manager and manager:IsModuleInStack("consumables")
	if inStack then
		self.container:SetPoint("TOP", _G["ActionHudFrame"], "TOP", 0, manager:GetModulePosition("consumables"))
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

function Consumables:RenderLayout()
	if not self._runtimeActive or InCombatLockdown() then return end
	self:RefreshValues()
	self.container:Show()
end
function Consumables:CalculateHeight() return self._runtimeActive and self.layoutHeight or 0 end
function Consumables:GetLayoutWidth() return self._runtimeActive and self.layoutWidth or 0 end
function Consumables:GetContainer() return self.container end
function Consumables:UpdateLayout()
	local manager = addon:GetModule("LayoutManager", true)
	if manager then manager:RequestLayout("consumables") end
end
