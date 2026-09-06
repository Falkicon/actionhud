local secret = setmetatable({}, { __index = function() error("secret indexed") end,
	__tostring = function() error("secret formatted") end })
local ns = { Utils = { IsValueSecret = function(value) return rawequal(value, secret) end } }
LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, key) return key end }) end } end
assert(loadfile("Core/ConsumableItems.lua"))("ActionHud", ns)
local items = ns.ConsumableItems
assert(table.concat(items:ParseItemIDs("12, 4 12\n5"), ",") == "12,4,5")
assert(#items:ParseItemIDs("  ") == 0)
for _, text in ipairs({ "0", "-1", "1.2", ",", "2147483648", "12 bad" }) do
	local ids, reason = items:ParseItemIDs(text)
	assert(ids == nil and reason == "invalid")
end
assert(items:ParseItemIDs(secret) == nil)
local ids, reason = items:ParseItemIDs("1 2 3 4 5 6 7 8 9 10 11 12 13")
assert(ids == nil and reason == "too_many")

local count, start, duration, enabled = 3, 100, 30, true
local names = { [12] = "Potion", [4] = "Food" }
C_Item = {
	GetItemCount = function(id, bank, uses, reagent, account)
		assert(id == 12 and bank == false and uses == true and reagent == false and account == false)
		return count
	end,
	GetItemCooldown = function(id) assert(id == 12); return start, duration, enabled end,
	GetItemInfo = function(id) return names[id] end,
	GetItemIconByID = function() return 123 end,
	GetItemInfoInstant = function(id) return id, nil, nil, nil, 123, id == 9 and 2 or 0 end,
}
assert(items:GetCount(12) == 3, "count includes uses, excludes banks")
local a, b, c = items:GetCooldown(12)
assert(a == 100 and b == 30 and c == true)
enabled = false
a, b, c = items:GetCooldown(12)
assert(a == 100 and b == 30 and c == false, "disabled cooldown is preserved")
enabled = 1
assert(items:GetCooldown(12) == nil, "only documented boolean accepted")
enabled = secret
assert(items:GetCooldown(12) == nil)
enabled, start = true, secret
assert(items:GetCooldown(12) == nil)
start, duration = 0, secret
assert(items:GetCooldown(12) == nil)
duration, count = 0, secret
assert(items:GetCount(12) == nil)
count = -1
assert(items:GetCount(12) == nil)
count = 0
assert(items:GetCount(12) == 0)
assert(items:GetCount(secret) == nil and items:GetCooldown(secret) == nil)
names[12] = secret
C_Item.GetItemIconByID = function() return secret end
local info = items:Describe(12)
assert(info.name == "Item 12" and info.icon == 134400)
assert(items:Describe(secret) == nil)

local scans = 0
C_Container = {
	GetContainerNumSlots = function(bag)
		scans = scans + 1
		assert(bag >= 0 and bag <= 5)
		if bag == 1 then return secret end
		return bag == 0 and 5 or 0
	end,
	GetContainerItemID = function(_, slot) return ({12, 4, 12, 9, secret})[slot] end,
}
local entries = items:GetBagItems()
assert(#entries == 2 and entries[1].id == 4 and entries[2].id == 12)
assert(scans == 6)
items:GetBagItems()
assert(scans == 6, "picker cache avoids repeated bag scans")
items:Refresh()
items:GetBagItems()
assert(scans == 12)
C_Item.GetItemCooldown = function() error("unavailable") end
C_Item.GetItemCount = function() error("unavailable") end
assert(items:GetCooldown(12) == nil and items:GetCount(12) == nil)
C_Item = nil
C_Container = nil
items:Refresh()
assert(#items:GetBagItems() == 0)
assert(items:GetCount(12) == nil and items:GetCooldown(12) == nil)
assert(items:Describe(12).name == "Item 12")
print("Consumable item safety tests passed")
