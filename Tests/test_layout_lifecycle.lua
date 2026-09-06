InCombatLockdown = function() return false end
local addon = { db = { profile = {} } }
local modules = {}
function addon:NewModule(name)
	local module = { db = self.db }
	function module:UnregisterAllEvents() end
	function module:IsEnabled() return true end
	modules[name] = module
	return module
end
function addon:GetModule(name) return modules[name] end
function addon:IterateModules() return pairs({}) end
function addon:RegisterEvent(event, method) self.pendingEvent = { event, method } end
function addon:UnregisterEvent() self.pendingEvent = nil end
function addon:Log() end
function addon:Logf() end
LibStub = function(name)
	if name == "AceAddon-3.0" then
		return { GetAddon = function() return addon end, NewAddon = function() return addon end }
	elseif name == "AceLocale-3.0" then
		return { GetLocale = function() return {} end }
	end
end
local secretMax = {}
local ns = { Utils = { IsValueSecret = function(value) return rawequal(value, secretMax) end } }
local maximumHealth = secretMax
UnitExists = function() return true end
UnitHealth = function() return 80 end
UnitHealthMax = function() return maximumHealth end
Enum = { PowerType = { ComboPoints = 4, Chi = 12, HolyPower = 9, SoulShards = 7,
	ArcaneCharges = 16, Essence = 19, Runes = 5 } }
UnitClass = function() return "Warrior", "WARRIOR" end
assert(loadfile("Resources.lua"))("ActionHud", ns)
local resources = modules.Resources
local function setUpvalue(fn, name, value)
	for i = 1, 100 do
		local key = debug.getupvalue(fn, i)
		if not key then break end
		if key == name then debug.setupvalue(fn, i, value); return end
	end
	error("Missing upvalue " .. name)
end
local frame = { shown = true }
function frame:Hide() self.shown = false end
setUpvalue(resources.StopRuntime, "container", frame)
local profile = addon.db.profile
profile.resEnabled, profile.resHealthEnabled, profile.resPowerEnabled = true, true, true
local requested
modules.LayoutManager = { RequestLayout = function() requested = true end }
assert(resources:CalculateHeight() > 0)
profile.resEnabled = false
resources:ApplyEnabledState()
resources:ApplyLayoutPosition()
assert(not frame.shown and requested and resources:CalculateHeight() == 0,
	"disabled resources must stay hidden and release their stack space")
modules.ActionBars = { GetLayoutWidth = function() return 240 end }
assert(resources:GetLayoutWidth() == 240, "automatic width must follow Edit Mode action bar width")
profile.resBarWidth = 180
assert(resources:GetLayoutWidth() == 180, "fixed resource width must win")
setUpvalue(resources.ApplyLayoutPosition, "RCFG", { enabled = true })
function frame:ClearAllPoints() end
function frame:SetSize(width, height) self.width, self.height = width, height end
function frame:SetPoint() end
function frame:EnableMouse() end
function frame:Show() self.shown = true end
function modules.LayoutManager:IsModuleInStack() return true end
function modules.LayoutManager:GetModulePosition() return 0 end
resources:ApplyLayoutPosition()
assert(frame.width == 180, "stack positioning must preserve the configured resource width")
profile.resHealthEnabled, profile.resPowerEnabled, profile.resClassEnabled = false, false, false
frame.shown = true
resources:ApplyLayoutPosition()
assert(not frame.shown, "resources with every bar disabled must remain hidden")

local unitEvents = {}
ns.UnitEventRouter = { Register = function(_, _, event, _, ...) unitEvents[event] = { ... } end }
function resources:RegisterEvent() end
resources:RegisterRuntimeEvents()
assert(unitEvents.UNIT_MAXHEALTH[1] == "player" and unitEvents.UNIT_MAXHEALTH[2] == "target",
	"maximum health updates must be registered for both displayed units")
local function bar()
	return setmetatable({
		SetValue = function(self, value) self.value = value end,
		SetMinMaxValues = function(self, _, value) self.maximum = value end,
		GetWidth = function() return 180 end,
		GetStatusBarTexture = function() return {} end,
	}, { __index = function() return function() end end })
end
local health = bar()
health.type, health.predict, health.absorb = "HEALTH", bar(), bar()
setUpvalue(resources.OnEvent, "playerHealth", health)
setUpvalue(resources.OnEvent, "targetHealth", health)
setUpvalue(resources.OnEvent, "RCFG", { enabled = true, showPredict = true, showAbsorbs = false })
resources._runtimeActive = true
ns.Utils.GetUnitHealsSafe = function() return 30 end
resources:OnEvent("UNIT_HEALTH", "player")
assert(health.value == 80 and health.predict.value == 30 and health.predict._anchorMode == "value",
	"secret maximum health must use anchored prediction without arithmetic")
maximumHealth = 100
resources:OnEvent("UNIT_MAXHEALTH", "target")
assert(health.maximum == 100 and health.predict.value == 100,
	"maximum health events must refresh ranges and cap ordinary prediction values")

assert(loadfile("Core/Defaults.lua"))("ActionHud", ns)
assert(loadfile("ActionHud.lua"))("ActionHud", ns)
local combat = false
InCombatLockdown = function() return combat end
UIParent = { GetCenter = function() return 500, 300 end, GetEffectiveScale = function() return 1 end }
local scripts = {}
local main = {
	SetScript = function(_, key, value) scripts[key] = value end,
	GetCenter = function() return 580, 220 end,
	GetEffectiveScale = function() return 1 end,
	SetPoint = function(self, ...) self.point = { ... } end,
	StartMoving = function(self) self.moving = true end,
	StopMovingOrSizing = function(self) assert(not combat); self.moving = false end,
}
local noop = function() end
setmetatable(main, { __index = function() return noop end })
CreateFrame = function() return main end
main.CreateTexture = function() return setmetatable({}, { __index = function() return noop end }) end
addon:CreateMainFrame()
scripts.OnDragStop(main)
assert(profile.xOffset == 80 and profile.yOffset == -80, "drag must persist center-relative coordinates")
assert(main.point[1] == "CENTER" and main.point[4] == 80, "drag must normalize its anchor immediately")
addon.UpdateLockState = noop
modules.LayoutManager = nil
profile.xOffset, profile.yOffset = 10, 20
addon:OnProfileChanged()
assert(main.point[4] == 10 and main.point[5] == 20, "profile switch must restore root position")
combat = true
profile.xOffset = 99
addon:OnProfileChanged()
assert(main.point[4] == 10 and addon.pendingEvent, "combat profile changes must defer root movement")
combat = false
addon[addon.pendingEvent[2]](addon)
assert(main.point[4] == 99 and not addon.pendingEvent, "deferred root position must apply after combat")
scripts.OnDragStart(main)
assert(main.moving)
combat = true
scripts.OnDragStop(main)
assert(main.moving and addon.pendingEvent, "combat drag stops must be deferred")
combat = false
addon[addon.pendingEvent[2]](addon)
assert(not main.moving and not addon.pendingEvent, "root dragging must stop after combat")

assert(loadfile("Core/DraggableContainer.lua"))("ActionHud", ns)
profile.layoutUnlocked = true
main.GetParent = function() return UIParent end
main.CreateFontString = main.CreateTexture
main.RegisterEvent = function(self, event) self.waiting = event end
main.UnregisterEvent = function(self) self.waiting = nil end
local independent = ns.DraggableContainer:Create({ moduleId = "resources", parent = UIParent,
	db = addon.db, xKey = "resourcesXOffset", yKey = "resourcesYOffset" })
scripts.OnDragStart(independent)
combat = true
scripts.OnDragStop(independent)
assert(independent.moving and independent.waiting == "PLAYER_REGEN_ENABLED")
combat = false
scripts.OnEvent(independent, "PLAYER_REGEN_ENABLED")
assert(not independent.moving and rawget(independent, "waiting") == nil,
	"independent dragging must stop after combat")
assert(profile.resourcesXOffset == 80 and profile.resourcesYOffset == -80)
print("SUCCESS: resource lifecycle, width, drag persistence, and profile positions")
