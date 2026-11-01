local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
local addon, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local frames = addon:GetModule("UnitFrames")
local options = ns.Settings.BuildUnitFramesOptions(addon).args
host:Flush()
native.failGroupCreation = true
options.enable.set(nil, true)
options.player.args.debuffs.args.enabled.set(nil, true)
host:Flush()
host:AssertNoErrors()
local display = frames.frames.player.debuffDisplay
assert(display.error and not display.enabled and not native.containers[1].enabled)
assert(not display.anchor:IsShown() and frames.frames.player:IsShown())
assert(options.player.args.debuffs.args.note.name() == "The debuff display could not initialize. Reload the UI to try again.")
frames:UpdateLayout(); host:Flush()
assert(#native.containers == 1, "failed initialization must not create an unbounded retry loop")
-- Blizzard invokes initialization through securecallfunction, so a widget
-- setup error must be captured inside the callback as well as AddAuraGroup.
native.failGroupCreation, native.failButtonInitialization = false, true
options.target.args.debuffs.args.enabled.set(nil, true); host:Flush()
local target = frames.frames.target.debuffDisplay
assert(target.error and not target.enabled and not native.containers[2].enabled)
assert(not target.anchor:IsShown() and frames.frames.target.unitWatch)
assert(options.target.args.debuffs.args.note.name() == "The debuff display could not initialize. Reload the UI to try again.")
options.enable.set(nil, false); host:Flush()
host:AssertNoErrors()
print("SUCCESS: native debuff initialization errors leave unit frames usable and displays disabled")
