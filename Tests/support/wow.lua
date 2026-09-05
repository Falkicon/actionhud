-- Deterministic host for the real addon and embedded libraries. This models
-- events, timers and protected geometry, not native taint or secret values.
local host = { frames = {}, timers = {}, errors = {}, now = 1, combat = false, loggedIn = false }
local noop = function() end
local nativeXpcall = xpcall
-- WoW extends Lua 5.1 xpcall with argument forwarding.
xpcall = function(fn, handler, ...)
	local args, count = { ... }, select("#", ...)
	return nativeXpcall(function() return fn(unpack(args, 1, count)) end, handler)
end
geterrorhandler = function() return function(err) host.errors[#host.errors + 1] = tostring(err) end end
securecallfunction = function(fn, ...) return fn(...) end
function host:AssertNoErrors()
	assert(#self.errors == 0, table.concat(self.errors, "\n"))
end
function host:Fire(event, ...)
	local receivers = {}
	for _, frame in ipairs(self.frames) do
		local units = frame.events[event]
		if units and (units == true or units[select(1, ...)]) then receivers[#receivers + 1] = frame end
	end
	for _, frame in ipairs(receivers) do
		local handler = frame.scripts.OnEvent
		if handler and frame.events[event] then handler(frame, event, ...) end
	end
	self:AssertNoErrors()
end
function host:Flush()
	local passes = 0
	while #self.timers > 0 do
		passes = passes + 1
		assert(passes <= 30, "timer queue did not settle (possible recursive layout)")
		local pending = self.timers
		self.timers = {}
		for _, timer in ipairs(pending) do
			self.now = math.max(self.now, timer.at)
			if not timer.cancelled then timer.callback() end
		end
		self:AssertNoErrors()
	end
end
function host:SetCombat(value)
	self.combat = value
	self:Fire(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
	self:Flush()
end
C_Timer = { After = function(delay, callback)
	host.timers[#host.timers + 1] = { at = host.now + delay, callback = callback }
end }
function C_Timer.NewTimer(delay, callback)
	local timer = { at = host.now + delay, callback = callback, Cancel = function(self) self.cancelled = true end }
	host.timers[#host.timers + 1] = timer
	return timer
end

local methods = {}
local function protect(frame)
	assert(not frame.protected or not host.combat, "protected mutation in combat: " .. (frame.name or frame.kind))
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event, callback)
	local previous = self.scripts[event]
	self.scripts[event] = function(...) if previous then previous(...) end; callback(...) end
end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:RegisterUnitEvent(event, ...)
	local units = {}
	for i = 1, select("#", ...) do units[select(i, ...)] = true end
	self.events[event] = units
end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:UnregisterAllEvents() self.events = {} end
function methods:IsEventRegistered(event) return self.events[event] ~= nil end
function methods:SetPoint(...) protect(self); self.point = { ... } end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 }) end
function methods:ClearAllPoints() protect(self); self.point = nil end
function methods:SetSize(width, height) protect(self); self.width, self.height = width, height end
function methods:SetWidth(width) protect(self); self.width = width end
function methods:SetHeight(height) protect(self); self.height = height end
function methods:GetWidth() return self.width or 120 end
function methods:GetHeight() return self.height or 40 end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end
function methods:GetCenter() return 500, 300 end
function methods:GetEffectiveScale() return 1 end
function methods:GetScale() return 1 end
function methods:GetParent() return self.parent end
function methods:SetParent(parent) protect(self); self.parent = parent end
function methods:Show() protect(self); self.shown = true end
function methods:Hide() protect(self); self.shown = false end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetAttribute(key, value) protect(self); self.attributes[key] = value end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameStrata() return self.strata or "MEDIUM" end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:GetName() return self.name end
function methods:GetObjectType() return self.kind end
function methods:IsObjectType(kind) return self.kind == kind end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text or "" end
function methods:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function methods:GetStringWidth() return #self:GetText() * 6 end
function methods:GetStringHeight() return 12 end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function methods:SetValue(value) self.value = value end
function methods:GetValue() return self.value or 0 end
function methods:SetMinMaxValues(low, high) self.low, self.high = low, high end
function methods:GetMinMaxValues() return self.low or 0, self.high or 100 end
function methods:GetRegions() return unpack(self.regions) end
function methods:GetChildren() return unpack(self.children) end
function methods:GetStatusBarTexture()
	if not self.barTexture then self.barTexture = self:CreateTexture() end
	return self.barTexture
end
function methods:GetNormalTexture() return self:GetStatusBarTexture() end
function methods:GetPushedTexture() return self:GetStatusBarTexture() end
function methods:GetHighlightTexture() return self:GetStatusBarTexture() end
function methods:CreateTexture(name)
	local region = CreateFrame("Texture", name, self)
	self.regions[#self.regions + 1] = region
	return region
end
function methods:CreateFontString(name)
	local region = CreateFrame("FontString", name, self)
	self.regions[#self.regions + 1] = region
	return region
end
function methods:EnableMouse(value) protect(self); self.mouseEnabled = value end
function methods:IsMouseEnabled() return self.mouseEnabled end
function methods:StartMoving() protect(self); self.moving = true end
function methods:StopMovingOrSizing() protect(self); self.moving = false end
-- Presentation-only methods deliberately do not emulate native rendering.
for name in string.gmatch([[SetAllPoints SetAlpha SetBackdrop SetBackdropColor SetBackdropBorderColor
SetClampedToScreen SetMovable RegisterForDrag RegisterForClicks SetStatusBarTexture SetStatusBarColor
SetReverseFill SetOrientation SetDrawEdge SetDrawSwipe SetDrawBling SetHideCountdownNumbers
SetCooldown SetCooldownFromDurationObject Clear SetTexture SetTexCoord SetColorTexture SetVertexColor
SetFont SetFontObject SetJustifyH SetJustifyV SetTextColor SetWordWrap SetShadowColor SetShadowOffset
SetBlendMode SetDesaturated SetAtlas SetFrameRef SetNormalTexture SetPushedTexture SetHighlightTexture
SetDisabledTexture SetResizable SetResizeBounds SetToplevel EnableKeyboard EnableMouseWheel
SetHitRectInsets SetClipsChildren SetCooldownUNIX SetSwipeColor SetBlingTexture SetEdgeTexture
SetSwipeTexture SetUseCircularEdge SetDrawLayer SetFlattensRenderLayers SetPropagateMouseClicks
SetPropagateMouseMotion SetFixedFrameStrata SetFixedFrameLevel SetNormalFontObject SetHighlightFontObject
SetDisabledFontObject SetTextInsets SetCountdownFont]], "%S+") do methods[name] = noop end
CreateFrame = function(kind, name, parent, template)
	local frame = setmetatable({ kind = kind or "Frame", name = name, parent = parent,
		scripts = {}, events = {}, attributes = {}, regions = {}, children = {}, shown = true,
		protected = template and template:find("Secure", 1, true) ~= nil }, { __index = methods })
	host.frames[#host.frames + 1] = frame
	if frame.protected then
		local ancestor = parent
		while ancestor and ancestor ~= UIParent do ancestor.protected = true; ancestor = ancestor.parent end
	end
	if parent then parent.children[#parent.children + 1] = frame end
	if name then _G[name] = frame end
	return frame
end
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1000, 600)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
DEFAULT_CHAT_FRAME = { AddMessage = noop }
SlashCmdList, hash_SlashCmdList, UISpecialFrames = {}, {}, {}
local categories = {}
local function registerCategory(frame, name)
	local category = { ID = name, GetID = function() return name end }
	categories[name] = category
	return category
end
Settings = {
	RegisterCanvasLayoutCategory = registerCategory,
	RegisterCanvasLayoutSubcategory = function(_, frame, name) return registerCategory(frame, name) end,
	GetCategory = function(name) return categories[name] end,
	RegisterAddOnCategory = noop, OpenToCategory = noop,
}
InterfaceOptions_AddCategory = noop
RegisterUnitWatch = function(frame) protect(frame); frame.unitWatch = true end
UnregisterUnitWatch = function(frame) protect(frame); frame.unitWatch = nil end
SecureUnitButton_OnLoad = noop
hooksecurefunc = function(target, method, callback)
	if type(target) == "string" then callback, method, target = method, target, _G end
	local original = target[method] or noop
	target[method] = function(...) local result = { original(...) }; callback(...); return unpack(result) end
end
issecurevariable = function() return true end
issecretvalue = function() return false end
InCombatLockdown = function() return host.combat end
IsLoggedIn = function() return host.loggedIn end
GetTime = function() return host.now end
debugprofilestop = function() return host.now * 1000 end
GetBuildInfo = function() return "12.1.0", "0", "", 120100 end
GetLocale = function() return "enUS" end
GetRealmName = function() return "Test Realm" end
GetCurrentRegion = function() return 1 end
GetCVar = function() return "0" end
GetCVarBool = function() return false end
UnitName = function() return "Tester" end
GetUnitName = UnitName
UnitRace = function() return "Human", "Human" end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitFactionGroup = function() return "Alliance" end
UnitLevel = function() return 80 end
UnitExists = function(unit) return unit == "player" or unit == "target" or unit == "targettarget" or unit == "focus" end
UnitHealth = function() return 80 end
UnitHealthMax = function() return 100 end
UnitPower = function() return 30 end
UnitPowerMax = function() return host.maxPower or 100 end
UnitPowerType = function() return 1, "RAGE" end
UnitIsPlayer = function() return true end
UnitIsEnemy = function() return false end
UnitIsFriend = function() return true end
UnitGetTotalAbsorbs = function() return 0 end
UnitGetIncomingHeals = function() return 0 end
UnitAffectingCombat = function() return host.combat end
IsResting = function() return false end
IsInInstance = function() return false, "none" end
GetSpecialization = function() return 1 end
GetActionBarPage = function() return host.actionPage or 1 end
GetBonusBarOffset = function() return host.bonusOffset or 0 end
GetActionInfo = function(slot) return "spell", 1000 + slot end
GetActionTexture = function() return 123 end
GetActionDisplayCount = function() return "" end
GetActionCount = function() return 0 end
GetActionCooldown = function() return 0, 0, 1 end
GetActionCharges = function() return nil end
IsUsableAction = function() return true, false end
IsActionInRange = function() return true end
HasAction = function() return true end
GetInventoryItemID = function(_, slot) return slot + 100 end
GetInventoryItemCooldown = function() return 0, 0, 1 end
GetItemSpell = function() return "Test Trinket", 111 end
AbbreviateNumbers = tostring
UnitIsPVP, UnitIsGroupLeader, UnitIsGroupAssistant, GetPartyAssignment, UnitInVehicle = function() return false end, function() return false end, function() return false end, function() return false end, function() return false end
UnitGroupRolesAssigned = function() return "DAMAGER" end
UnitPhaseReason, GetReadyCheckStatus = noop, noop
RAID_CLASS_COLORS = { WARRIOR = { r = 0.8, g = 0.6, b = 0.4 } }
PowerBarColor = { RAGE = { r = 1, g = 0, b = 0 } }
Enum = { PowerType = { ComboPoints = 4, Chi = 12, HolyPower = 9, SoulShards = 7,
	ArcaneCharges = 16, Essence = 19, Runes = 5 }, SummonStatus = { Pending = 1, Accepted = 2, Declined = 3 } }
C_AddOns = { GetAddOnMetadata = function() return "test" end, IsAddOnLoaded = function() return false end }
C_Item = { GetItemIconByID = function() return 456 end, GetItemSpell = GetItemSpell }
C_Spell = { IsSpellUsable = function() return true end }
C_ActionBar = { EnableActionRangeCheck = noop }
AssistedCombatManager = { SetAssistedHighlightFrameShown = noop }
EditModeManagerFrame = { ExitEditMode = noop }
wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end; return tbl end
table.wipe = wipe
CopyTable = function(tbl)
	local copy = {}
	for key, value in pairs(tbl) do copy[key] = type(value) == "table" and CopyTable(value) or value end
	return copy
end
bit = { band = function(a, b)
	local result, place = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then result = result + place end
		a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
	end
	return result
end }
strmatch, strfind, strsplit, format = string.match, string.find, function(separator, value) return value:match("([^" .. separator .. "]+)") end, string.format
string.trim = function(value) return value:match("^%s*(.-)%s*$") end
return host
