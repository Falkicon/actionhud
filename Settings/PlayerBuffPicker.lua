local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

function ns.Settings.BuildPlayerBuffPickerOptions(addon)
	local book = ns.PlayerBuffSpellbook
	local playerBuffs = addon:GetModule("PlayerBuffs")
	local query, includePassive, page = "", false, 1
	local resultEntries, resultQuery, resultPassives, resultCache
	local PAGE_SIZE = 8
	local function ids()
		return playerBuffs:ParseSpellIDs(addon.db.profile.playerBuffsSpellIDs or "")
	end
	local function resolve(id)
		if not id then return nil end
		return playerBuffs:ResolveAuraSpellID(id)
	end
	local function save(list)
		local values = {}
		for i, id in ipairs(list) do values[i] = tostring(id) end
		addon.db.profile.playerBuffsSpellIDs = table.concat(values, ", ")
		addon:GetModule("PlayerBuffs"):ApplyEnabledState()
		addon:RefreshLayout()
	end
	local function results()
		local entries = book:GetEntries()
		if entries ~= resultEntries or query ~= resultQuery or includePassive ~= resultPassives then
			resultCache = book:Search(query, includePassive)
			resultEntries, resultQuery, resultPassives = entries, query, includePassive
		end
		return resultCache
	end
	local function pageCount()
		return math.max(1, math.ceil(#results() / PAGE_SIZE))
	end
	local function result(index)
		page = math.min(page, pageCount())
		return results()[(page - 1) * PAGE_SIZE + index]
	end
	local function canAdd(id)
		id = resolve(id)
		local list = ids()
		if not id or not list or #list >= 12 then return false end
		for _, selected in ipairs(list) do if selected == id then return false end end
		return true
	end
	local function isSelected(id)
		id = resolve(id)
		local list = ids()
		if not id or not list then return false end
		for _, selectedID in ipairs(list) do
			if selectedID == id then return true end
		end
		return false
	end
	local function add(id)
		local auraID = resolve(id)
		if not auraID or not canAdd(id) then return end
		local list = ids()
		list[#list + 1] = auraID
		save(list)
	end
	local function selected(index)
		local list = ids()
		return list and list[index]
	end
	local function move(index, delta)
		local list = ids()
		if not list or not list[index] or not list[index + delta] then return end
		list[index], list[index + delta] = list[index + delta], list[index]
		save(list)
	end
	local browser = {
		type = "group", name = L["Spellbook"], inline = true, order = 10,
		args = {
			note = { type = "description", order = 0,
				name = L["Choose a spell to track its buff. Known spell-to-buff mappings are applied automatically; use Advanced: Spell IDs if one does not appear."] },
			search = { type = "input", name = L["Search spells"], order = 1, width = "full",
				desc = L["Search by spell name or ID, then press Enter."],
				get = function() return query end,
				set = function(_, value) query = value:sub(1, 100); page = 1 end },
			passives = { type = "toggle", name = L["Include passive spells"], order = 2,
				width = "relative", relWidth = 0.75,
				get = function() return includePassive end,
				set = function(_, value) includePassive = value; page = 1 end },
			refresh = { type = "execute", name = L["Refresh"], order = 3,
				desc = L["Refresh spellbook"], width = "relative", relWidth = 0.25,
				disabled = function() return InCombatLockdown() end,
				func = function() book:Refresh(); page = 1 end },
			status = { type = "description", order = 4, name = function()
				if InCombatLockdown() then return L["Spellbook browsing refreshes outside combat."] end
				if not book:IsAvailable() then return L["Spellbook access is unavailable. You can still add spell IDs under Advanced: Spell IDs."] end
				if #results() == 0 then return L["No matching spells. Try another search, include passive spells, or refresh the spellbook."] end
				local list = ids()
				if not list then return L["Fix the saved spell ID list under Advanced: Spell IDs before editing selected buffs."] end
				return string.format(L["%d matching spells. %d of 12 buffs selected."], #results(), #list)
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
		browser.args["spellLabel" .. index] = {
			type = "description", dialogControl = "InteractiveLabel",
			order = 9 + index * 2, width = "relative", relWidth = 0.82,
			hidden = function() return not result(index) end,
			name = function()
				local entry = result(index)
				return entry and entry.name or ""
			end,
			image = function() local entry = result(index); return entry and entry.icon end,
			imageWidth = 24, imageHeight = 24,
			tooltipHyperlink = function() local entry = result(index); return entry and "spell:" .. entry.id end,
		}
		browser.args["spell" .. index] = {
			type = "execute", order = 10 + index * 2, width = "relative", relWidth = 0.18,
			hidden = function() return not result(index) end,
			name = function()
				local entry = result(index)
				if not entry then return "" end
				return isSelected(entry.id) and L["Added"] or L["Add"]
			end,
			tooltipHyperlink = function() local entry = result(index); return entry and "spell:" .. entry.id end,
			disabled = function() local entry = result(index); return not canAdd(entry and entry.id) end,
			func = function() local entry = result(index); if entry then add(entry.id) end end,
		}
	end
	local selection = { type = "group", name = L["Selected Buffs"], inline = true, order = 11, args = {
		empty = { type = "description", order = 0, name = L["No buffs selected. Add a spell above or enter a spell ID under Advanced: Spell IDs."],
			hidden = function() return selected(1) ~= nil end },
	} }
	for index = 1, 12 do
		selection.args["slot" .. index] = {
			type = "group", name = "", inline = true, order = index,
			hidden = function() return not selected(index) end,
			args = {
				label = { type = "description", dialogControl = "InteractiveLabel", order = 0,
					width = "relative", relWidth = 0.6,
					name = function() local id = selected(index); return id and string.format("%d. %s", index, book:Describe(id).name) or "" end,
					image = function() local id = selected(index); return id and book:Describe(id).icon end,
					imageWidth = 24, imageHeight = 24,
					tooltipHyperlink = function() local id = selected(index); return id and "spell:" .. id end },
				up = { type = "execute", name = L["Up"], order = 1, width = "relative", relWidth = 0.1,
					desc = L["Move Up"],
					disabled = function() return index == 1 end, func = function() move(index, -1) end },
				down = { type = "execute", name = L["Down"], order = 2, width = "relative", relWidth = 0.12,
					desc = L["Move Down"],
					disabled = function() return not selected(index + 1) end, func = function() move(index, 1) end },
				remove = { type = "execute", name = L["Remove"], order = 3, width = "relative", relWidth = 0.18,
					func = function() local list = ids(); if list and list[index] then table.remove(list, index); save(list) end end },
			},
		}
	end
	local preview = { type = "group", name = L["Preview"], inline = true, order = 12, args = {
		note = { type = "description", order = 0, name = L["Preview shows configured order and columns at a fixed icon size, even when buffs are inactive."] },
		icons = { type = "description", order = 1, name = function()
			local list, lines, row = ids() or {}, {}, {}
			local columns = math.max(1, math.min(12, tonumber(addon.db.profile.playerBuffsColumns) or 4))
			for index, id in ipairs(list) do
				row[#row + 1] = string.format("|T%d:24:24|t", book:Describe(id).icon)
				if index % columns == 0 or index == #list then lines[#lines + 1] = table.concat(row, " "); row = {} end
			end
			return table.concat(lines, "\n")
		end },
	} }
	return browser, selection, preview
end
