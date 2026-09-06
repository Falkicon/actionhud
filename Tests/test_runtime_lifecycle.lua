-- Lifecycle and duplicate action-slot regression tests, without a WoW client.
local pending, hooks, frames = {}, {}, {}
local function noop() end
wipe = function(value)
	for key in pairs(value) do value[key] = nil end
end
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
hooksecurefunc = function(_, method, callback)
	hooks[method] = hooks[method] or {}
	table.insert(hooks[method], callback)
end
local methods = {}
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:GetFrameLevel() return 1 end
function methods:CreateTexture() return CreateFrame() end
function methods:CreateFontString() return CreateFrame() end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:Clear() self.cleared = true end
function methods:SetText(value) self.text = value end
function methods:SetVertexColor(...) self.color = { ... } end
function methods:GetParent() return self.parent end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:GetCenter() return self.cx or 0, self.cy or 0 end
function methods:SetPoint(...) self.point = { ... } end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:UnregisterEvent(event) if self.events then self.events[event] = nil end end
CreateFrame = function(_, name, parent)
	local frame = setmetatable({ shown = true, scripts = {}, parent = parent }, {
		__index = function(_, key)
			if methods[key] then return methods[key] end
			if key:match("^[A-Z]") then return noop end
		end,
	})
	frames[#frames + 1] = frame
	if name then _G[name] = frame end
	return frame
end
local addon = { db = { profile = {
	assistGlowAlpha = 1, opacity = 0, trinketsEnabled = true,
	trinketsIconWidth = 32, trinketsIconHeight = 32,
} }, Log = noop, Logf = noop, UpdateLayoutOutline = noop }
local modules = {}
function addon:NewModule(name)
	local module = { enabled = true, events = {} }
	function module:IsEnabled() return self.enabled end
	function module:RegisterEvent(event, callback) self.events[event] = callback end
	function module:UnregisterAllEvents() wipe(self.events) end
	function module:Enable()
		if not self.enabled then self.enabled = true; self:OnEnable() end
	end
	function module:Disable()
		if self.enabled then self.enabled = false; self:OnDisable() end
	end
	modules[name] = module
	return module
end
function addon:GetModule(name) return modules[name] end
LibStub = function(name)
	if name == "AceLocale-3.0" then
		return { GetLocale = function() return setmetatable({}, { __index = function(_, key) return key end }) end }
	end
	if name == "AceConfigRegistry-3.0" then return { NotifyChange = noop } end
	return { GetAddon = function() return addon end }
end
addon.frame = CreateFrame("Frame", "ActionHudFrame")
GetTime = function() return 1 end
GetInventoryItemID = function() return 123 end
local inCombat = false
InCombatLockdown = function() return inCombat end
IsInInstance = function() return false end
EditModeManagerFrame = {}
AssistedCombatManager = {}
C_Item = { GetItemIconByID = function() return 456 end }
C_Spell = { IsSpellUsable = function() return true end }
C_ActionBar = { EnableActionRangeCheck = noop }
local page, offset = 6, 0
local ns = { Utils = {
	IsValueSecret = function() return false end,
	SafeCompare = function(a, b, op)
		if op == "==" then return a == b end
		if op == ">" then return a > b end
		return false
	end,
	GetActionBarPageSafe = function() return page end,
	GetBonusBarOffsetSafe = function() return offset end,
	GetActionInfoSafe = function() return "spell", 100 end,
	GetActionTextureSafe = function() return 456 end,
	IsUsableActionSafe = function() return false, false end,
	GetInventoryItemCooldownSafe = function() return 0, 0, false end,
	GetItemSpellSafe = function() return "Item", 100 end,
	ApplyIconCrop = noop,
	GetTimerFont = function() return "font" end,
} }
assert(loadfile("ActionBars.lua"))("ActionHud", ns)
local ab = modules.ActionBars
local layouts = 0
local realLayout = ab.UpdateLayout
ab.UpdateLayout = function() layouts = layouts + 1 end
ab.RefreshAll = noop
ab:OnEnable()
assert(#hooks.ExitEditMode == 1, "first enable must install an Edit Mode hook")
ab.events.EDIT_MODE_LAYOUTS_UPDATED()
ab.enabled = false
ab:OnDisable()
local baseline = layouts
hooks.ExitEditMode[1]()
assert(layouts == baseline, "disabled modules must ignore deferred and permanent hooks")
assert(next(ab.events) == nil, "disable must unregister action bar events")
assert(not ab:GetContainer():IsShown(), "disable must hide the action bar container")
ab.enabled = true
ab:OnEnable()
baseline = layouts
assert(#hooks.ExitEditMode == 1, "re-enabling must reuse the permanent Edit Mode hook")
hooks.ExitEditMode[1]()
assert(layouts == baseline + 1, "current Edit Mode hook must still refresh")

local buttons = {}
for _, frame in ipairs(frames) do
	if frame.parent == ab:GetContainer() then buttons[#buttons + 1] = frame end
end
assert(#buttons == 24, "expected both action bars")
local first, mirrored = buttons[1], buttons[13]
first.baseSlot, mirrored.baseSlot = 1, 61
for _, button in ipairs({ first, mirrored }) do
	button:Show()
	ab:UpdateAction(button)
	assert(button.actionID == 61, "page six and the mirrored bar must resolve to the same slot")
end
ab:RebuildButtonIndex()
ab:ACTION_USABLE_CHANGED(nil, { { slot = 61 } })
ab:ACTION_RANGE_CHECK_UPDATE(nil, 61, false, true)
hooks.SetAssistedHighlightFrameShown[1](nil, { action = 61 }, true)
for _, button in ipairs({ first, mirrored }) do
	assert(button._isUsable == false, "usability changes must reach every mirror")
	assert(button._colorMode == "unusableRange", "range changes must reach every mirror")
	assert(button.assistGlow and button.assistGlow:IsShown(), "assist changes must reach every mirror")
end
page, offset = 1, 1
ab:UpdateAction(first)
assert(first.actionID == 73, "stance paging must preserve bonus page mapping")
page, offset = 1, 2
ab:UpdateAction(first)
assert(first.actionID == 85, "form paging must preserve bonus page mapping")
ab.enabled = false
ab:OnDisable()
realLayout(ab)
assert(not ab:GetContainer():IsShown(), "direct layout calls must not resurrect disabled action bars")
addon.db.profile.actionBarsEnabled = false
ab:Enable()
assert(not ab:IsEnabled(), "saved disabled action bars must stay disabled on startup")
addon.db.profile.actionBarsEnabled = true
ab:ApplyEnabledState()
assert(ab:IsEnabled(), "settings must enable action bars")
addon.db.profile.actionBarsEnabled = false
ab:ApplyEnabledState()
assert(not ab:IsEnabled(), "settings must disable action bars")

assert(loadfile("Trinkets.lua"))("ActionHud", ns)
local trinkets = modules.Trinkets
trinkets:OnInitialize()
trinkets:OnEnable()
local function renderTrinkets()
	trinkets:PrepareLayout()
	trinkets:ApplyLayoutPosition()
	trinkets:RenderLayout()
end
renderTrinkets()
assert(ActionHudTrinkets:IsShown(), "enabled trinkets must populate")
trinkets.enabled = false
trinkets:OnDisable()
trinkets:UpdateTrinkets()
trinkets:UpdateLayout()
assert(not ActionHudTrinkets:IsShown(), "disabled trinkets must remain hidden")
assert(next(trinkets.events) == nil, "disable must unregister trinket events")
assert(trinkets:CalculateHeight() == 0, "disabled trinkets must not reserve height")
trinkets.enabled = true
trinkets:OnEnable()
assert(not ActionHudTrinkets:IsShown(), "stale refresh must not populate a new lifecycle")
renderTrinkets()
assert(ActionHudTrinkets:IsShown(), "current refresh must populate re-enabled trinkets")
addon.db.profile.trinketsEnabled = false
trinkets:ApplyEnabledState()
assert(not trinkets:IsEnabled(), "settings must disable trinkets")
trinkets:Enable()
assert(not trinkets:IsEnabled(), "saved disabled trinkets must stay disabled on startup")
addon.db.profile.trinketsEnabled = true
trinkets:ApplyEnabledState()
renderTrinkets()
assert(trinkets:IsEnabled() and ActionHudTrinkets:IsShown(), "settings must discover trinkets in the scheduled pass")

-- Exercise the real position method through the shared draggable implementation.
assert(loadfile("Core/DraggableContainer.lua"))("ActionHud", ns)
modules.LayoutManager = { IsModuleInStack = function() return false end }
ab:GetContainer():Show()
ab:ApplyLayoutPosition()
assert(not ab:GetContainer():IsShown(), "layout manager positioning must hide disabled action bars")
addon.db.profile.actionBarsEnabled = true
ab:ApplyEnabledState()
ab.GetLayoutWidth = function() return 120 end
ab.CalculateHeight = function() return 60 end
addon.db.profile.layoutUnlocked = true
ab:ApplyLayoutPosition()
local drag = ab:GetContainer()
assert(ns.DraggableContainer:GetContainer("actionBars") == drag, "action bar reset must find its container")
addon.frame.cx, addon.frame.cy, addon.frame.scale = 100, 200, 2
drag.cx, drag.cy, drag.scale = 250, 450, 1
drag.scripts.OnDragStart(drag)
assert(drag.moving, "unlocked action bars must start dragging")
inCombat = true
drag.scripts.OnDragStop(drag)
assert(drag.moving and drag.events.PLAYER_REGEN_ENABLED, "action bar drag stop must defer during combat")
inCombat = false
drag.scripts.OnEvent(drag, "PLAYER_REGEN_ENABLED")
assert(not drag.moving, "deferred drag must finish after combat")
assert(addon.db.profile.actionBarsXOffset == 50 and addon.db.profile.actionBarsYOffset == 50,
	"action bars must save offsets in the child frame's coordinate scale")
assert(drag.point[4] == 50 and drag.point[5] == 50, "drag stop must restore the parent-relative anchor")
ns.DraggableContainer:ResetPosition(ns.DraggableContainer:GetContainer("actionBars"))
assert(drag.point[4] == 0 and drag.point[5] == 0, "registered action bars must reset without a layout refresh")
print("SUCCESS: runtime lifecycle and mirrored action-slot events verified")
