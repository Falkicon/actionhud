-- Consumables settings options

local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

local PAGE_SIZE = 6
local MAX_ITEMS = 12

local STATUS_TEXT = {
	disabled = L["Consumables is disabled."],
	empty = L["Add at least one item to display Consumables."],
	invalid = L["Fix the saved item ID list under Advanced: Item IDs before editing selected items."],
	pending = L["Consumables is waiting until combat ends to update its display."],
	active = L["Consumables is active."],
}

local function GetModule()
	return ActionHud:GetModule("Consumables", true)
end

local function IsInStack()
	local manager = ActionHud:GetModule("LayoutManager", true)
	if manager then
		return manager:IsModuleInStack("consumables")
	end
	return ActionHud.db.profile.consumablesIncludeInStack
end

local function ApplyItemIDs(addon, text)
	addon.db.profile.consumablesItemIDs = text
	local module = GetModule()
	if module then module:ApplyEnabledState() end
	addon:RefreshLayout()
end

local function ValidateItemIDs(text)
	local ids, reason = ns.ConsumableItems:ParseItemIDs(text)
	if ids then return true end
	if reason == "too_many" then
		return L["Enter no more than 12 unique item IDs."]
	end
	return L["Enter only positive integer item IDs separated by commas or whitespace."]
end

local function GetStatusText()
	local module = GetModule()
	local status = module and module:GetStatus() or "disabled"
	local text = STATUS_TEXT[status] or L["Consumables could not update its display."]
	if status == "active" then return "|cff00ff00" .. text .. "|r" end
	if status == "disabled" or status == "empty" then return "|cffaaaaaa" .. text .. "|r" end
	if status == "pending" then return "|cffffcc00" .. text .. "|r" end
	return "|cffff4444" .. text .. "|r"
end

function ns.Settings.BuildConsumablesOptions(addon)
	local query, page, advanced = "", 1, false
	local bagEntries, filteredEntries, filteredQuery

	local function selectedIDs()
		return ns.ConsumableItems:ParseItemIDs(addon.db.profile.consumablesItemIDs or "")
	end

	local function describe(id, entry)
		local metadata = ns.ConsumableItems:Describe(id) or entry or {}
		return {
			id = metadata.id or id,
			name = metadata.name or (entry and entry.name) or string.format(L["Item %d"], id),
			icon = metadata.icon or (entry and entry.icon) or 134400,
		}
	end

	local function quantity(id)
		local count = ns.ConsumableItems:GetCount(id)
		return count == nil and L["?"] or tostring(count)
	end

	local function save(list)
		local values = {}
		for index, id in ipairs(list) do values[index] = tostring(id) end
		ApplyItemIDs(addon, table.concat(values, ", "))
	end

	local function invalidate()
		bagEntries, filteredEntries, filteredQuery = nil, nil, nil
	end

	-- SetupOptions hooks this on the panel's OnShow. The explicit Refresh button
	-- uses the same path, so bag contents are never rescanned by every getter.
	function ns.Settings.RefreshConsumablesPicker()
		ns.ConsumableItems:Refresh()
		invalidate()
		page = 1
		LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Consumables")
	end

	local function results()
		if not bagEntries then bagEntries = ns.ConsumableItems:GetBagItems() or {} end
		local needle = query:lower():match("^%s*(.-)%s*$")
		if needle ~= filteredQuery or not filteredEntries then
			filteredEntries = {}
			for _, entry in ipairs(bagEntries) do
				local id = entry.id
				local metadata = id and describe(id, entry)
				if metadata and (needle == ""
					or tostring(metadata.id):find(needle, 1, true)
					or metadata.name:lower():find(needle, 1, true)) then
					filteredEntries[#filteredEntries + 1] = metadata
				end
			end
			filteredQuery = needle
		end
		return filteredEntries
	end

	local function pageCount()
		return math.max(1, math.ceil(#results() / PAGE_SIZE))
	end

	local function result(index)
		page = math.min(page, pageCount())
		return results()[(page - 1) * PAGE_SIZE + index]
	end

	local function contains(id)
		local list = selectedIDs()
		if not list then return false end
		for _, selectedID in ipairs(list) do
			if selectedID == id then return true end
		end
		return false
	end

	local function canAdd(id)
		local list = selectedIDs()
		return id and list and #list < MAX_ITEMS and not contains(id)
	end

	local function add(id)
		if not canAdd(id) then return end
		local list = selectedIDs()
		list[#list + 1] = id
		save(list)
	end

	local function selected(index)
		local list = selectedIDs()
		return list and list[index]
	end

	local function move(index, delta)
		local list = selectedIDs()
		if not list or not list[index] or not list[index + delta] then return end
		list[index], list[index + delta] = list[index + delta], list[index]
		save(list)
	end

	local browser = {
		type = "group", name = L["Choose from Bags"], inline = true, order = 10,
		args = {
			note = { type = "description", order = 0,
				name = L["Choose an item currently in your bags, or use Advanced: Item IDs for any exact item ID."] },
			search = { type = "input", name = L["Search items"], order = 1, width = "full",
				desc = L["Search by item name or item ID, then press Enter."],
				get = function() return query end,
				set = function(_, value) query = value:sub(1, 100); page = 1; filteredQuery = nil end },
			refresh = { type = "execute", name = L["Refresh"], order = 2,
				desc = L["Refresh items from your bags."],
				func = ns.Settings.RefreshConsumablesPicker },
			status = { type = "description", order = 3, name = function()
				local list = selectedIDs()
				if not list then
					return L["Fix the saved item ID list under Advanced: Item IDs before editing selected items."]
				end
				if #results() == 0 then return L["No matching items. Try another search or refresh your bags."] end
				return string.format(L["%d matching items. %d of 12 items selected."], #results(), #list)
			end },
			previous = { type = "execute", name = L["Previous"], order = 30,
				desc = L["Previous page"], width = "relative", relWidth = 0.2,
				disabled = function() return page <= 1 end,
				func = function() page = math.max(1, page - 1) end },
			page = { type = "description", order = 31, width = "relative", relWidth = 0.6,
				name = function() return string.format(L["Page %d of %d"], math.min(page, pageCount()), pageCount()) end },
			next = { type = "execute", name = L["Next"], order = 32,
				desc = L["Next page"], width = "relative", relWidth = 0.2,
				disabled = function() return page >= pageCount() end,
				func = function() page = math.min(pageCount(), page + 1) end },
		},
	}

	for index = 1, PAGE_SIZE do
		browser.args["itemLabel" .. index] = {
			type = "description", dialogControl = "InteractiveLabel",
			order = 4 + index * 2, width = "relative", relWidth = 0.82,
			hidden = function() return not result(index) end,
			name = function()
				local entry = result(index)
				return entry and string.format(L["%s  ×%s"], entry.name, quantity(entry.id)) or ""
			end,
			image = function() local entry = result(index); return entry and entry.icon end,
			imageWidth = 24, imageHeight = 24,
			tooltipHyperlink = function() local entry = result(index); return entry and "item:" .. entry.id end,
		}
		browser.args["item" .. index] = {
			type = "execute", order = 5 + index * 2, width = "relative", relWidth = 0.18,
			hidden = function() return not result(index) end,
			name = function()
				local entry = result(index)
				if not entry then return "" end
				return contains(entry.id) and L["Added"] or L["Add"]
			end,
			disabled = function() local entry = result(index); return not canAdd(entry and entry.id) end,
			func = function() local entry = result(index); if entry then add(entry.id) end end,
		}
	end

	local selection = {
		type = "group", name = L["Selected Items"], inline = true, order = 11,
		args = {
			empty = { type = "description", order = 0,
				name = L["No items selected. Add an item above or enter an item ID under Advanced: Item IDs."],
				hidden = function() return selected(1) ~= nil end },
		},
	}

	for index = 1, MAX_ITEMS do
		selection.args["slot" .. index] = {
			type = "group", name = "", inline = true, order = index,
			hidden = function() return not selected(index) end,
			args = {
				label = { type = "description", dialogControl = "InteractiveLabel", order = 0,
					width = "relative", relWidth = 0.6,
					name = function()
						local id = selected(index)
						if not id then return "" end
						return string.format(L["%d. %s  ×%s"], index, describe(id).name, quantity(id))
					end,
					image = function() local id = selected(index); return id and describe(id).icon end,
					imageWidth = 24, imageHeight = 24,
					tooltipHyperlink = function() local id = selected(index); return id and "item:" .. id end },
				up = { type = "execute", name = L["Up"], order = 1, width = "relative", relWidth = 0.1,
					desc = L["Move Up"], disabled = function() return index == 1 end,
					func = function() move(index, -1) end },
				down = { type = "execute", name = L["Down"], order = 2, width = "relative", relWidth = 0.12,
					desc = L["Move Down"], disabled = function() return not selected(index + 1) end,
					func = function() move(index, 1) end },
				remove = { type = "execute", name = L["Remove"], order = 3, width = "relative", relWidth = 0.18,
					func = function()
						local list = selectedIDs()
						if list and list[index] then table.remove(list, index); save(list) end
					end },
			},
		}
	end

	return {
		name = L["Consumables"], handler = ActionHud, type = "group",
		args = {
			intro = { type = "description", order = 0,
				name = L["Show carried counts and cooldowns for selected consumables. Icons are display-only and do not use items. Depleted items stay in place, dimmed; exact item IDs are never swapped for quality variants."] },
			status = { type = "description", order = 1, name = GetStatusText },
			enable = { type = "toggle", name = L["Enable Consumables"], order = 2,
				desc = L["Show the selected consumables."],
				get = function() return addon.db.profile.consumablesEnabled end,
				set = function(_, value)
					addon.db.profile.consumablesEnabled = value
					local module = GetModule()
					if module then module:ApplyEnabledState() end
					addon:RefreshLayout()
				end },
			includeInStack = { type = "toggle", name = L["Include in HUD Stack"], order = 3, width = "full",
				desc = L["When enabled, this module is positioned as part of the vertical ActionHud stack. When disabled, it can be positioned independently."],
				get = IsInStack,
				set = function(_, value)
					addon.db.profile.consumablesIncludeInStack = value
					local manager = ActionHud:GetModule("LayoutManager", true)
					if manager then manager:SetModuleInStack("consumables", value) end
					addon:RefreshLayout()
				end },
			positionNote = { type = "description", order = 4,
				name = L["Position is controlled by Layout tab when in HUD Stack."],
				hidden = function() return not IsInStack() end },
			dragNote = { type = "description", order = 5,
				name = L["Use the 'Unlock Module Positions' toggle in the Layout tab to drag this module to a new position."],
				hidden = IsInStack },
			resetPosition = { type = "execute", name = L["Reset Position"], order = 6,
				desc = L["Reset this module to its default position."],
				hidden = IsInStack,
				func = function()
					local defaults = addon.db.defaults.profile
					addon.db.profile.consumablesXOffset = defaults.consumablesXOffset
					addon.db.profile.consumablesYOffset = defaults.consumablesYOffset
					addon:RefreshLayout()
				end },
			browser = browser,
			selected = selection,
			sizing = { type = "group", name = L["Sizing"], inline = true, order = 20, args = {
				iconSize = { type = "range", name = L["Icon Size"], order = 1, min = 16, max = 64, step = 1,
					desc = L["Size of Consumables icons."],
					get = function() return addon.db.profile.consumablesIconSize end,
					set = function(_, value) addon.db.profile.consumablesIconSize = value; addon:RefreshLayout() end },
				columns = { type = "range", name = L["Columns"], order = 2, min = 1, max = 12, step = 1,
					desc = L["Maximum number of Consumables icons per row."],
					get = function() return addon.db.profile.consumablesColumns end,
					set = function(_, value) addon.db.profile.consumablesColumns = value; addon:RefreshLayout() end },
				spacing = { type = "range", name = L["Spacing"], order = 3, min = 0, max = 20, step = 1,
					desc = L["Space between Consumables icons."],
					get = function() return addon.db.profile.consumablesSpacing end,
					set = function(_, value) addon.db.profile.consumablesSpacing = value; addon:RefreshLayout() end },
			} },
			advanced = { type = "toggle", name = L["Advanced: Item IDs"], order = 30, width = "full",
				get = function() return advanced end,
				set = function(_, value) advanced = value end },
			itemIDs = { type = "group", name = L["Advanced: Item IDs"], inline = true, order = 31,
				hidden = function() return not advanced end,
				args = {
					input = { type = "input", name = L["Item IDs"], order = 1, width = "full", multiline = 4,
						desc = L["Enter up to 12 exact item IDs separated by commas or whitespace. Quality variants use separate item IDs."],
						get = function() return addon.db.profile.consumablesItemIDs end,
						set = function(_, value) ApplyItemIDs(addon, value) end,
						validate = function(_, value) return ValidateItemIDs(value) end },
					clear = { type = "execute", name = L["Clear Item IDs"], order = 2,
						desc = L["Clear the item ID list without changing any other Consumables settings."],
						func = function() ApplyItemIDs(addon, "") end },
				},
			},
		},
	}
end
