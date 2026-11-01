local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
host.combat = true
local boot = assert(loadfile("Tests/support/load_addon.lua"))()
local addon = boot(host, { profiles = { Default = { ufEnabled = true,
	ufConfig = { player = { debuffs = { enabled = true } }, target = { debuffs = { enabled = true } } },
} } })
local uf, ab = addon:GetModule("UnitFrames"), addon:GetModule("ActionBars")
assert(not next(uf.frames) and not ab:GetContainer(), "combat startup must defer runtime frame creation")
assert(uf._pendingEnabledState and ab._pendingEnabledState)
assert(#native.containers == 0, "combat startup must defer native debuff containers too")
host:SetCombat(false)
assert(uf._runtimeActive and uf.frames.player:IsShown())
assert(ab._runtimeActive and ab:GetContainer():IsShown())
assert(#native.containers == 2 and native.containers[1].enabled and native.containers[2].enabled)
print("SUCCESS: real combat startup defers and resumes feature lifecycles")
