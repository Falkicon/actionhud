local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
local addon, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local book = ns.PlayerBuffSpellbook
local entries = {}
for id = 1, 10 do entries[id] = { id = id, name = "Ability " .. id, icon = 134400 } end
local reflection = { id = 23920, name = "Spell Reflection", icon = 135453 }
function book:IsAvailable() return true end
function book:GetEntries() return entries end
function book:Search(query, passive)
	if query == "reflection" then return { reflection } end
	if query == "no matches" then return {} end
	if passive then return { { id = 99, name = "Passive", icon = 134400 } } end
	return entries
end
function book:Describe(id) return id == 23920 and reflection or { id = id, name = "Ability " .. id, icon = 134400 } end
local options = ns.Settings.BuildPlayerBuffsOptions(addon).args
local browser, selected = options.browser.args, options.selected.args
local function flush() host:Flush(); host:AssertNoErrors() end
local function values() return assert(addon:GetModule("PlayerBuffs"):ParseSpellIDs(addon.db.profile.playerBuffsSpellIDs)) end
LibStub("AceConfigRegistry-3.0"):ValidateOptionsTable({ name = "picker", type = "group", args = options }, "picker")
assert(options.spellIDsGroup.hidden())
options.advanced.set(nil, true)
assert(not options.spellIDsGroup.hidden())
assert(browser.spell1.name():find("Ability 1", 1, true))
assert(browser.spell1.tooltipHyperlink() == "spell:1")
browser.next.func()
assert(browser.spell1.name():find("Ability 9", 1, true) and browser.spell3.hidden())
browser.previous.func()
browser.search.set(nil, "reflection")
assert(browser.spell2.hidden() and not browser.spell1.disabled())
browser.spell1.func(); flush()
assert(values()[1] == 23920 and browser.spell1.disabled())
browser.spell1.func(); flush()
assert(#values() == 1 and #native.containers == 0, "adding must deduplicate without enabling the feature")
assert(selected.slot1.args.label.name():find("Spell Reflection", 1, true))
assert(selected.slot1.args.label.tooltipHyperlink() == "spell:23920")
assert(options.preview.args.icons.name():find("135453", 1, true))
browser.search.set(nil, "")
browser.spell1.func(); browser.spell2.func(); flush()
assert(#values() == 3 and values()[2] == 1 and values()[3] == 2)
selected.slot3.args.up.func(); flush()
assert(values()[2] == 2 and values()[3] == 1)
selected.slot1.args.down.func(); flush()
assert(values()[1] == 2 and values()[2] == 23920)
selected.slot1.args.remove.func(); flush()
assert(#values() == 2 and values()[1] == 23920)
options.sizingGroup.args.columns.set(nil, 1); flush()
assert(options.preview.args.icons.name():find("\n", 1, true))
browser.search.set(nil, "no matches")
assert(browser.spell1.hidden())
browser.search.set(nil, "")
browser.passives.set(nil, true)
assert(browser.spell1.name():find("Passive", 1, true))
browser.passives.set(nil, false)

-- Mutations always read the latest profile; stale UI closures must not overwrite
-- another profile or silently discard an invalid advanced list.
addon.db:SetProfile("new-picker-profile"); flush()
assert(selected.slot1.hidden())
browser.spell1.func(); flush()
assert(#values() == 1 and values()[1] == 1)
addon.db.profile.playerBuffsSpellIDs = "invalid"
assert(browser.spell1.disabled())
browser.spell2.func()
assert(addon.db.profile.playerBuffsSpellIDs == "invalid")
options.spellIDsGroup.args.spellIDs.set(nil, "1 2 3 4 5 6 7 8 9 10 11 12"); flush()
browser.search.set(nil, "reflection")
assert(browser.spell1.disabled())
browser.spell1.func()
assert(#values() == 12)
selected.slot12.args.remove.func(); flush()
assert(not browser.spell1.disabled())

options.enable.set(nil, true); flush()
host:SetCombat(true)
local writes = native.writes
browser.spell1.func(); flush()
assert(values()[12] == 23920 and native.writes == writes)
host:SetCombat(false)
assert(native.containers[1].slots.selected12.filters.includeSpellIDs[23920])

-- Build the real embedded widget used for selected spell names/icons. Text
-- measurement is approximate; this is a widget contract, not visual validation.
local methods = getmetatable(UIParent).__index
function methods:SetTexture(value) self.texture = value end
function methods:GetTexture() return self.texture end
function methods:GetStringHeight() return 12 end
local gui = LibStub("AceGUI-3.0")
local label = gui:Create("InteractiveLabel")
label:SetWidth(500)
label:SetText(selected.slot12.args.label.name())
label:SetImage(selected.slot12.args.label.image())
label:SetImageSize(24, 24)
assert(label.imageshown and label.label:GetText():find("Spell Reflection", 1, true))
gui:Release(label)
host:AssertNoErrors()
print("SUCCESS: spellbook picker search, pagination, ordered edits, profiles, manual fallback and combat deferral")
