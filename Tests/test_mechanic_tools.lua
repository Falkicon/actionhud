-- Mechanic buttons must use the same settings and lifecycle paths as the addon UI.
local buttons = {}
local function NewFrame(kind)
	local frame = { scripts = {} }
	function frame:SetPoint() end
	function frame:SetSize() end
	function frame:SetText(text)
		self.text = text
		if kind == "Button" then buttons[text] = self end
	end
	function frame:SetScript(event, handler) self.scripts[event] = handler end
	function frame:RegisterEvent() end
	function frame:CreateFontString() return NewFrame("FontString") end
	return frame
end
CreateFrame = NewFrame

local applied, layouts, settings = {}, 0, 0
local addon = { db = { profile = { resEnabled = true, trinketsEnabled = false } } }
local modules = {
	LayoutManager = { TriggerLayoutUpdate = function() layouts = layouts + 1 end },
}
for name, key in pairs({ Resources = "resEnabled", Trinkets = "trinketsEnabled" }) do
	modules[name] = { ApplyEnabledState = function() applied[name] = addon.db.profile[key] end }
end
function addon:GetModule(name) return modules[name] end
function addon:OpenSettings() settings = settings + 1 end
LibStub = function(name)
	if name == "MechanicLib-1.0" then return {} end
	if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
	if name == "AceLocale-3.0" then
		return { GetLocale = function() return setmetatable({}, { __index = function(_, key) return key end }) end }
	end
	error("Unexpected library " .. name)
end

local ns = {}
assert(loadfile("Core/Performance.lua"))("ActionHud", ns)
assert(loadfile("Mechanic.lua"))("ActionHud", ns)
ActionHudMechanic:CreateToolsPanel(NewFrame("Frame"))
buttons.Settings.scripts.OnClick()
assert(settings == 1, "settings button must use the addon's combat-aware settings helper")
buttons.Resources.scripts.OnClick()
assert(applied.Resources == false and layouts == 1, "resource disable must update lifecycle and layout")
buttons.Trinkets.scripts.OnClick()
assert(applied.Trinkets == true and layouts == 2, "trinket enable must initialize the module immediately")
assert(not buttons.Cooldowns, "dormant modules must not expose an enable button")
assert(not ns.RecordPerformance and #ActionHudMechanic:GetPerformanceSubMetrics() == 0,
	"loading Mechanic must not opt in to profiling")
ns.Performance:SetEnabled(true)
ActionHudMechanic:RecordPerfMetric("LayoutRecalc", 2)
ActionHudMechanic:RecordPerfMetric("LayoutRecalc", 5)
local row = ActionHudMechanic:GetPerformanceSubMetrics()[1]
assert(row.ms == 3.5 and row.description:find("2 calls", 1, true)
	and row.description:find("7.000 ms total", 1, true)
	and row.description:find("5.000 ms peak", 1, true), "Mechanic must display aggregate measurements")
print("SUCCESS: Mechanic tools use current settings and module lifecycle")
