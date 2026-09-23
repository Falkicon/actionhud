-- Full-TOC regressions for action spell resolution, proc glows, and range tint.
local host = assert(loadfile("Tests/support/wow.lua"))()
local boot = assert(loadfile("Tests/support/load_addon.lua"))()

local actions, macroSpells, overlayed = {}, {}, {}
local hostGetActionInfo = GetActionInfo
GetActionInfo = function(slot)
	local action = actions[slot]
	if action then return action[1], action[2], action[3] end
	return hostGetActionInfo(slot)
end
GetMacroSpell = function(index) return macroSpells[index] end
C_SpellActivationOverlay = { IsSpellOverlayed = function(spellID) return overlayed[spellID] == true end }
local rangeResults, registered = {}, {}
C_ActionBar.IsActionInRange = function(actionID) return rangeResults[actionID] end
C_ActionBar.EnableActionRangeCheck = function(actionID, enabled) registered[actionID] = enabled or nil end

local addon = boot(host)
host:Flush()

local function buttonsFor(actionID)
	local result = {}
	for _, frame in ipairs(host.frames) do
		if frame.glow and frame.actionID == actionID then result[#result + 1] = frame end
	end
	return result
end
local function fire(event, ...)
	host:Fire(event, ...)
	host:AssertNoErrors()
end
local button = assert(buttonsFor(1)[1], "action slot 1 must be mirrored")
assert(addon:GetModule("ActionBars")._runtimeActive, "action bars must be running")

-- Retail macros report their current spell directly: ("macro", spellID, "spell").
-- 133 is also a valid macro index; resolving it through GetMacroSpell would read
-- an unrelated macro.
actions[1] = { "macro", 133, "spell" }
macroSpells[133] = 999
fire("ACTIONBAR_SLOT_CHANGED", 1)
overlayed[133] = true
fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 133)
assert(button.glow:IsShown(), "a proc on a macro's spell must glow the macro")
overlayed[133] = nil
fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 133)
assert(not button.glow:IsShown(), "the macro glow must clear when the proc ends")

-- Other macro subtypes carry a macro index, resolved through GetMacroSpell.
actions[1] = { "macro", 7, "" }
macroSpells[7] = 100
fire("ACTIONBAR_SLOT_CHANGED", 1)
overlayed[100] = true
fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 100)
assert(button.glow:IsShown(), "index-based macros must still resolve their spell")
overlayed[100] = nil
fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 100)
assert(not button.glow:IsShown())

-- A state refresh earlier in the same frame must not hide a proc that begins
-- later in that frame (no per-frame overlay cache).
actions[1] = { "spell", 500 }
fire("ACTIONBAR_SLOT_CHANGED", 1)
fire("ACTIONBAR_UPDATE_STATE")
overlayed[500] = true
fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 500)
assert(button.glow:IsShown(), "a glow event must read the current overlay state")
fire("ACTIONBAR_UPDATE_STATE")
overlayed[500] = nil
fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 500)
assert(not button.glow:IsShown(), "a consumed proc must clear in the same frame")

-- Spell overrides change the backing spell without ACTIONBAR_SLOT_CHANGED
-- (e.g. Slam -> Heroic Strike); the glow must follow the current spell.
actions[1] = { "spell", 1464 }
fire("ACTIONBAR_SLOT_CHANGED", 1)
actions[1] = { "spell", 78 }
overlayed[78] = true
fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 78)
assert(button.glow:IsShown(), "proc glow must follow a spell override without a slot change")
overlayed[78] = nil
fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 78)
assert(not button.glow:IsShown())

-- Range results are pushed only on change. A refresh, layout pass, or page swap
-- that keeps or revisits an action must not discard a still-valid tint.
actions[1] = nil
fire("ACTIONBAR_SLOT_CHANGED", 1)
local barTwo = assert(buttonsFor(61)[1], "Action Bar 2 must mirror slot 61")
assert(registered[1] and registered[61], "visible actions must opt into range events")
fire("ACTION_RANGE_CHECK_UPDATE", 1, false, true)
fire("ACTION_RANGE_CHECK_UPDATE", 61, false, true)
assert(button._colorMode == "readyRange" and barTwo._colorMode == "readyRange")
addon:RefreshLayout()
host:Flush()
assert(button._colorMode == "readyRange", "a layout pass must keep the out-of-range tint")
host.bonusOffset = 1
fire("UPDATE_BONUS_ACTIONBAR")
host:Flush()
assert(button.actionID == 73, "stealth/form paging moves bar 1 to its bonus page")
assert(barTwo._colorMode == "readyRange", "Action Bar 2 keeps its tint when bar 1 pages")
assert(button._colorMode ~= "readyRange", "a newly paged action must not inherit the old tint")
rangeResults[1] = false
host.bonusOffset = 0
fire("UPDATE_BONUS_ACTIONBAR")
host:Flush()
assert(button.actionID == 1 and button._colorMode == "readyRange",
	"an action that becomes visible again is seeded with its current range")
fire("ACTION_RANGE_CHECK_UPDATE", 1, true, true)
assert(button._colorMode == "ready", "returning to range clears the tint")

host:AssertNoErrors()
print("SUCCESS: macro spell resolution, same-frame proc glows, override glows, and range persistence verified")
