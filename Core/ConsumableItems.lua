local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local Items = {}
ns.ConsumableItems = Items
local MAX_ID = 2147483647
local cachedBags

-- Reviewed Retail 12.1 API signatures (revalidate for future seasons):
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua
-- https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua
-- GetItemCooldown returns numbers and a boolean, NOT a duration object.
-- Every result is validated before use; unavailable/secret results fail closed.
local function Public(value, kind)
	return not ns.Utils.IsValueSecret(value) and type(value) == kind
end
local function Number(value)
	return Public(value, "number") and value >= 0 and value < math.huge
end
local function Integer(value, minimum, maximum)
	return Number(value) and value >= minimum and value <= maximum and value == math.floor(value)
end
local function Call(api, method, ...)
	if not Public(api, "table") or type(api[method]) ~= "function" then return nil end
	local ok, value = pcall(api[method], ...)
	if ok and not ns.Utils.IsValueSecret(value) then return value end
end

function Items:ParseItemIDs(text)
	if not Public(text, "string") then return nil, "invalid" end
	if text:match("^%s*$") then return {} end
	if text:find("[^%d,%s]") then return nil, "invalid" end
	local ids, seen = {}, {}
	for token in text:gmatch("[^,%s]+") do
		local id = tonumber(token)
		if not Integer(id, 1, MAX_ID) then return nil, "invalid" end
		if not seen[id] then
			ids[#ids + 1], seen[id] = id, true
			if #ids > 12 then return nil, "too_many" end
		end
	end
	if #ids == 0 then return nil, "invalid" end
	return ids
end

function Items:Describe(id)
	if not Integer(id, 1, MAX_ID) then return nil end
	local name = Call(C_Item, "GetItemInfo", id)
	local icon = Call(C_Item, "GetItemIconByID", id)
	if not Public(name, "string") or name == "" then name = string.format(L["Item %d"], id) end
	if not Integer(icon, 1, MAX_ID) then icon = 134400 end
	return { id = id, name = name, icon = icon }
end

function Items:GetCount(id)
	if not Integer(id, 1, MAX_ID) then return nil end
	-- Carried uses, including charged items; excludes every bank.
	local count = Call(C_Item, "GetItemCount", id, false, true, false, false)
	if Integer(count, 0, MAX_ID) then return count end
end

function Items:GetCooldown(id)
	if not Integer(id, 1, MAX_ID) or not Public(C_Item, "table")
		or type(C_Item.GetItemCooldown) ~= "function" then return nil end
	local ok, start, duration, enabled = pcall(C_Item.GetItemCooldown, id)
	if not ok or not Number(start) or not Number(duration) or not Public(enabled, "boolean") then return nil end
	return start, duration, enabled
end

local function IsConsumable(id)
	if not Public(C_Item, "table") or type(C_Item.GetItemInfoInstant) ~= "function" then return false end
	local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, id)
	-- Consumable is ItemClass 0, including potions, food, flasks, and healthstones.
	return ok and Integer(classID, 0, MAX_ID) and classID == 0
end

function Items:Refresh()
	cachedBags = nil
end

function Items:GetBagItems()
	if cachedBags then return cachedBags end
	local entries, seen = {}, {}
	-- Explicit picker reads only, bounded carried bags (including reagent bag).
	for bag = 0, 5 do
		local count = Call(C_Container, "GetContainerNumSlots", bag)
		if Integer(count, 0, 200) then
			for slot = 1, count do
				local id = Call(C_Container, "GetContainerItemID", bag, slot)
				if Integer(id, 1, MAX_ID) and not seen[id] and IsConsumable(id) then
					seen[id] = true
					entries[#entries + 1] = self:Describe(id)
				end
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.name == b.name then return a.id < b.id end
		return a.name < b.name
	end)
	cachedBags = entries
	return entries
end
