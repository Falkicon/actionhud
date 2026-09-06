-- Full TOC, real AceDB callbacks, and the shared scheduler. Native rendering
-- and item cooldown behavior still require an in-game smoke test.
local host = assert(loadfile("Tests/support/wow.lua"))()
local counts, cooldowns = { [101] = 4, [102] = 3 }, {}
C_Item.GetItemInfo = function(id) return "Consumable " .. id end
C_Item.GetItemCount = function(id, bank, uses, reagent, account)
	assert(bank == false and uses == true and reagent == false and account == false)
	return counts[id] or 0
end
C_Item.GetItemCooldown = function(id)
	local value = cooldowns[id] or { 0, 0, true }
	return unpack(value)
end
C_Item.GetItemInfoInstant = function(id) return id, "Consumable", "Potion", "", 456, 0, 1 end
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
	GetContainerItemID = function(_, slot) return slot + 100 end,
}
local addon, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local module = addon:GetModule("Consumables")
local manager = addon:GetModule("LayoutManager")
local options = ns.Settings.BuildConsumablesOptions(addon).args
local function flush() host:Flush(); host:AssertNoErrors() end
local function configure(ids)
	options.itemIDs.args.input.set(nil, ids); flush()
end
assert(not module._runtimeActive and not module:GetContainer(), "disabled startup must remain lazy")
LibStub("AceConfigRegistry-3.0"):ValidateOptionsTable({ name = "Consumables", type = "group", args = options }, "Consumables")
local browser = options.browser.args
assert(browser.itemLabel1.tooltipHyperlink() == "item:101")
browser.item1.func(); flush()
assert(browser.item1.disabled() and browser.item1.name() == "Added")
browser.search.set(nil, "102")
assert(browser.itemLabel1.tooltipHyperlink() == "item:102")
browser.item1.func(); flush()
assert(addon.db.profile.consumablesItemIDs == "101, 102")
options.selected.args.slot1.args.down.func(); flush()
assert(addon.db.profile.consumablesItemIDs == "102, 101")
options.selected.args.slot2.args.remove.func(); flush()
assert(addon.db.profile.consumablesItemIDs == "102")
assert(not module:GetContainer(), "picker mutations must not auto-enable the feature")
assert(options.itemIDs.args.input.validate(nil, "1,2,3,4,5,6,7,8,9,10,11,12,13") ~= true)
assert(options.itemIDs.args.input.validate(nil, "not an ID") ~= true)
browser.search.set(nil, "no match")
assert(browser.item1.hidden())
browser.refresh.func()
browser.search.set(nil, "")
assert(not browser.item1.hidden())
configure("101,102")
assert(not module:GetContainer(), "selecting items must not implicitly enable the display")
options.enable.set(nil, true); flush()
assert(module._runtimeActive and module:GetContainer():IsShown())
assert(module:GetLayoutWidth() == 58 and module:CalculateHeight() == 28)
assert(module.slots[1].count:GetText() == "4" and module.slots[2].count:GetText() == "3")
assert(not module.slots[1].frame:IsMouseEnabled(), "item display must not handle clicks")
assert(module.slots[1].cooldown.countdownThreshold == 3)

-- Updating item state in combat must not create frames, move slots, or resize.
local slot = module.slots[1]
local applied, cleared = {}, 0
slot.cooldown.SetCooldown = function(_, start, duration) applied = { start, duration } end
slot.cooldown.Clear = function() cleared = cleared + 1 end
host:SetCombat(true)
local frameCount, width = #host.frames, module:GetContainer():GetWidth()
counts[101], cooldowns[101] = 3, { 10, 60, true }
host:Fire("BAG_UPDATE_COOLDOWN"); flush()
assert(slot.count:GetText() == "3" and applied[1] == 10 and applied[2] == 60)
counts[101] = 0
host:Fire("BAG_UPDATE_DELAYED"); flush()
assert(slot.count:GetText() == "0" and slot.frame:IsShown() and cleared > 0)
assert(#host.frames == frameCount and module:GetContainer():GetWidth() == width)
addon.db.profile.consumablesColumns = 1
configure("102,101,103")
assert(#module.slots == 2 and slot.itemID == 101, "configured slots defer in combat")
host:SetCombat(false)
assert(#module.slots == 3 and slot.itemID == 102)
assert(module:GetLayoutWidth() == 28 and module:CalculateHeight() == 88)

-- Unknown data must clear a previous countdown without appearing ready.
cooldowns[102] = { 10, 60, false }
host:Fire("BAG_UPDATE_COOLDOWN"); flush()
assert(slot.unavailable:GetText() ~= "")
local api = C_Item.GetItemCooldown
C_Item.GetItemCooldown = nil
host:Fire("SPELL_UPDATE_COOLDOWN"); flush()
assert(slot.unavailable:GetText() ~= "")
C_Item.GetItemCooldown = api
cooldowns[102] = { 0, 0, true }
host:SetCombat(true)
host:SetCombat(false)
assert(slot.unavailable:GetText() == "")
assert(slot.count:GetParent() ~= slot.cooldown, "native cooldown hiding must not hide counts")

options.includeInStack.set(nil, true); flush()
assert(manager:IsModuleInStack("consumables"))
local height = ActionHudFrame:GetHeight()
counts[102] = 0
host:Fire("BAG_UPDATE_DELAYED"); flush()
assert(ActionHudFrame:GetHeight() == height, "depletion must retain stack footprint")
assert(not module.container.overlay:IsShown())
addon.db.profile.cooldownDecimalThreshold = 0
addon:RefreshLayout(); flush()
assert(slot.cooldown.countdownThreshold == 0)

-- Profile callbacks reconcile the final desired state and reuse frames.
local container = module:GetContainer()
host:SetCombat(true)
addon.db:SetProfile("Consumables off")
flush()
assert(module._pendingEnabledState)
host:SetCombat(false)
assert(not module._runtimeActive and not container:IsShown())
addon.db:SetProfile("Default"); flush()
assert(module._runtimeActive and module:GetContainer() == container)
addon.db:ResetProfile(); flush()
assert(not module._runtimeActive and not container:IsShown())
assert(module:GetLayoutWidth() == 0 and module:CalculateHeight() == 0)
local reads = 0
C_Item.GetItemCount = function() reads = reads + 1; return 0 end
host:Fire("BAG_UPDATE_DELAYED"); flush()
assert(reads == 0, "stopping the module must release item update subscriptions")
print("SUCCESS: consumables full-TOC settings, counts/cooldowns, combat layout, stack and profiles")
