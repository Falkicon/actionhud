-- Exercise the embedded widget, leaving the removed global API unavailable.
local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()
boot(host)
SetDesaturation = nil
local methods = getmetatable(UIParent).__index
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:GetTexture() return self.texture end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetDesaturated(value) self.desaturated = value end

local gui = LibStub("AceGUI-3.0")
local checkbox = gui:Create("CheckBox")
assert(checkbox:GetValue() == false and not checkbox.check:IsShown())
checkbox:SetValue(true)
assert(checkbox.check:IsShown() and not checkbox.check.desaturated)
checkbox:SetDisabled(true)
assert(not checkbox.frame.enabled and checkbox.check.desaturated)
checkbox:SetDisabled(false)
assert(checkbox.frame.enabled and not checkbox.check.desaturated)
checkbox:SetTriState(true)
checkbox:SetValue(nil)
assert(checkbox.check:IsShown() and checkbox.check.desaturated)
checkbox:SetValue(false)
assert(not checkbox.check:IsShown() and not checkbox.check.desaturated)
checkbox:SetTriState(false)
gui:Release(checkbox)
local reused = gui:Create("CheckBox")
assert(reused:GetValue() == false and not reused.check:IsShown())
host:AssertNoErrors()
print("SUCCESS: embedded AceGUI checkbox works without the removed SetDesaturation global")
