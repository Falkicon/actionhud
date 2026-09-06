-- UnitFrames module lifecycle and scoped event routing.
local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local UnitFrames = ActionHud:NewModule("UnitFrames", "AceEvent-3.0")

function UnitFrames:OnInitialize()
	self.db = ActionHud.db
	self.frames = {}
	self.framesByUnit = {}
end

function UnitFrames:OnEnable()
	self:ApplyEnabledState()
end

function UnitFrames:OnDisable()
	self:StopRuntime()
end

function UnitFrames:RegisterRuntimeEvents()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateAll")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "UpdateAll")
	self:RegisterEvent("RUNE_POWER_UPDATE", "UpdatePlayerClassPower")
	for _, event in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "UPDATE_SHAPESHIFT_FORM" }) do
		self:RegisterEvent(event, "UpdateLayout")
	end
	for _, event in ipairs({
		"GROUP_ROSTER_UPDATE",
		"PARTY_LEADER_CHANGED",
		"PLAYER_ROLES_ASSIGNED",
		"PLAYER_FLAGS_CHANGED",
		"PLAYER_UPDATE_RESTING",
		"READY_CHECK",
		"READY_CHECK_CONFIRM",
		"READY_CHECK_FINISHED",
	}) do
		self:RegisterEvent(event, "UpdateStatusAll")
	end

	local router = ns.UnitEventRouter
	router:Register(self, "UNIT_TARGET", "OnUnitTarget", "target")
	for _, event in ipairs({ "UNIT_FLAGS", "UNIT_FACTION", "UNIT_PHASE" }) do
		router:Register(self, event, "UpdateStatusEvent", "player", "target", "targettarget", "focus")
	end
	for _, event in ipairs({
		"UNIT_HEALTH",
		"UNIT_MAXHEALTH",
		"UNIT_POWER_UPDATE",
		"UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER",
		"UNIT_ABSORB_AMOUNT_CHANGED",
		"UNIT_HEAL_PREDICTION",
	}) do
		router:Register(self, event, "UpdateFrameEvent", "player", "target", "targettarget", "focus")
	end
end

function UnitFrames:StartRuntime()
	if self._runtimeActive then self:UpdateLayout(); return end
	self._runtimeActive = true
	if not next(self.frames) then self:CreateFrames() end
	self:RegisterRuntimeEvents()
	self:UpdateLayout()
end

function UnitFrames:HideFrames()
	if InCombatLockdown() then
		return
	end
	for frameId, f in pairs(self.frames) do
		if frameId ~= "player" then
			UnregisterUnitWatch(f)
		end
		local container = self.containers and self.containers[frameId]
		if container then
			if frameId ~= "player" then
				UnregisterUnitWatch(container)
			end
			container:Hide()
		end
		f:Hide()
	end
end

function UnitFrames:StopRuntime()
	self._runtimeActive = false
	self:UnregisterAllEvents()
	if ns.UnitEventRouter then
		ns.UnitEventRouter:UnregisterAll(self)
	end
	if InCombatLockdown() then
		self._pendingEnabledState = true
	else
		self._pendingEnabledState = nil
		self:HideFrames()
		self:ApplyBlizzardFrameVisibility()
	end
	self:UpdateLayout()
end

function UnitFrames:ApplyEnabledState()
	self._desiredEnabled = self.db.profile.ufEnabled == true
	if InCombatLockdown() then
		self._pendingEnabledState = true
		self:UpdateLayout()
		return
	end
	self._pendingEnabledState = nil
	if self:IsEnabled() and self._desiredEnabled then self:StartRuntime() else self:StopRuntime() end
end

function UnitFrames:ApplyBlizzardFrameVisibility()
	local hide = self._runtimeActive and self.db.profile.ufEnabled and self.db.profile.ufHideBlizzard
	if hide then
		if PlayerFrame then
			PlayerFrame:SetAlpha(0)
			PlayerFrame:EnableMouse(false)
		end
		if TargetFrame then
			TargetFrame:SetAlpha(0)
			TargetFrame:EnableMouse(false)
		end
		if FocusFrame then
			FocusFrame:SetAlpha(0)
			FocusFrame:EnableMouse(false)
		end
		-- Hide Blizzard's Target of Target frame
		if TargetFrameToT then
			TargetFrameToT:SetAlpha(0)
			TargetFrameToT:EnableMouse(false)
		end
	else
		if PlayerFrame then
			PlayerFrame:SetAlpha(1)
			PlayerFrame:EnableMouse(true)
		end
		if TargetFrame then
			TargetFrame:SetAlpha(1)
			TargetFrame:EnableMouse(true)
		end
		if FocusFrame then
			FocusFrame:SetAlpha(1)
			FocusFrame:EnableMouse(true)
		end
		if TargetFrameToT then
			TargetFrameToT:SetAlpha(1)
			TargetFrameToT:EnableMouse(true)
		end
	end
end

function UnitFrames:UpdateAll()
	if not self._runtimeActive then
		return
	end
	for _, f in pairs(self.frames) do
		self:UpdateFrameValues(f)
	end
end

function UnitFrames:UpdateFrameEvent(event, unit)
	if not self._runtimeActive then
		return
	end
	local f = self.framesByUnit[unit]
	if f then
		local updateKind = "health"
		if event == "UNIT_POWER_UPDATE" then
			updateKind = "power"
		elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
			updateKind = "powerLayout"
		end
		self:UpdateFrameValues(f, updateKind)
	end
end

function UnitFrames:UpdatePlayerClassPower()
	if self._runtimeActive and self.frames.player then
		self:UpdateFrameValues(self.frames.player, "power")
	end
end

function UnitFrames:UpdateStatusEvent(event, unit)
	if not self._runtimeActive then
		return
	end
	local f = self.framesByUnit[unit]
	if f then
		self:UpdateFrameValues(f, "status")
	end
end

function UnitFrames:UpdateStatusAll()
	if not self._runtimeActive then
		return
	end
	for _, f in pairs(self.frames) do
		self:UpdateFrameValues(f, "status")
	end
end

-- When any unit's target changes, update targettarget frame
function UnitFrames:OnUnitTarget(event, unit)
	if self._runtimeActive and unit == "target" then
		-- Target's target changed, update the targettarget frame
		local f = self.frames.targettarget
		if f then
			self:UpdateFrameValues(f)
		end
	end
end

function UnitFrames:UpdateLayout()
	local manager = ActionHud:GetModule("LayoutManager", true)
	if manager then manager:RequestLayout("unit frames") end
end
