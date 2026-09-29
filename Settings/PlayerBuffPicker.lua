local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

function ns.Settings.BuildPlayerBuffPickerOptions(addon)
	local recent = ns.RecentPlayerBuffs
	local catalog = ns.BlizzardBuffCatalog
	local evidence, sounds = ns.BuffEvidence, ns.AuraSounds
	local SOUND_STATUS = {
		muted = L["Sound muted for this buff."],
		off = L["Sound is chosen but the master sound switch is off."],
		unavailable = L["This client does not offer native aura sounds."],
		ambiguous = L["No sound rule: Blizzard lists several related IDs for this buff. Add its own aura ID under Advanced: Spell IDs to use a sound."],
		pending = L["Sound rule will be registered once combat ends and Player Buffs is active."],
		active = L["Sound rule registered. Blizzard plays it when the buff is applied."],
		failed = L["Blizzard refused this sound rule. Try another sound or a different aura ID."],
	}
	local function soundValues()
		local values = sounds:GetChoices()
		values.none = L["No sound"]
		return values
	end
	local function soundOrder()
		local _, order = sounds:GetChoices()
		local list = { "none" }
		for _, key in ipairs(order) do list[#list + 1] = key end
		return list
	end
	local playerBuffs = addon:GetModule("PlayerBuffs")
	local source, query, page = "recent", "", 1
	local resultEntries, resultSource, resultQuery, resultCache
	local PAGE_SIZE = 8

	local function ids()
		return playerBuffs:ParseSpellIDs(addon.db.profile.playerBuffsSpellIDs or "")
	end

	local function resolve(id)
		if not id then return nil end
		return playerBuffs:ResolveAuraSpellID(id)
	end

	local function describe(id, entry)
		local metadata = catalog:Describe(id) or entry or {}
		return {
			id = metadata.id or id,
			name = metadata.name or (entry and entry.name) or string.format(L["Spell %d"], id),
			icon = metadata.icon or (entry and entry.icon) or 134400,
			description = metadata.description or (entry and entry.description),
			candidateSpellIDs = metadata.candidateSpellIDs or (entry and entry.candidateSpellIDs),
		}
	end

	local function save(list)
		local values = {}
		for i, id in ipairs(list) do values[i] = tostring(id) end
		addon.db.profile.playerBuffsSpellIDs = table.concat(values, ", ")
		playerBuffs:ApplyEnabledState()
		addon:RefreshLayout()
	end

	local function backend()
		return source == "catalog" and catalog or recent
	end

	local function invalidate()
		resultEntries, resultSource, resultQuery, resultCache = nil, nil, nil, nil
	end

	local function containsID(candidateSpellIDs, needle)
		if not candidateSpellIDs then return false end
		for key, value in pairs(candidateSpellIDs) do
			local candidate = value
			if value == true then candidate = key end
			if (type(candidate) == "number" or type(candidate) == "string")
				and tostring(candidate):find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	local function matches(entry, needle)
		if needle == "" then return true end
		local metadata = describe(entry.id, entry)
		return tostring(metadata.id):find(needle, 1, true)
			or tostring(entry.id):find(needle, 1, true)
			or metadata.name:lower():find(needle, 1, true)
			or containsID(metadata.candidateSpellIDs, needle)
	end

	local function results()
		local entries = backend():GetEntries()
		local normalizedQuery = query:lower():match("^%s*(.-)%s*$")
		if entries ~= resultEntries or source ~= resultSource or normalizedQuery ~= resultQuery then
			resultCache = {}
			for _, entry in ipairs(entries) do
				if entry.id and matches(entry, normalizedQuery) then
					resultCache[#resultCache + 1] = describe(entry.id, entry)
				end
			end
			resultEntries, resultSource, resultQuery = entries, source, normalizedQuery
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

	local function equivalent(left, right)
		left, right = resolve(left), resolve(right)
		if not left or not right then return false end
		if left == right then return true end
		local leftCandidates = catalog:GetCandidateSpellIDs(left)
		if leftCandidates and leftCandidates[right] then return true end
		local rightCandidates = catalog:GetCandidateSpellIDs(right)
		return rightCandidates and rightCandidates[left] or false
	end

	local function canAdd(id)
		local list = ids()
		if not resolve(id) or not list or #list >= 12 then return false end
		for _, selected in ipairs(list) do if equivalent(selected, id) then return false end end
		return true
	end

	local function isSelected(id)
		local list = ids()
		if not resolve(id) or not list then return false end
		for _, selectedID in ipairs(list) do
			if equivalent(selectedID, id) then return true end
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
		type = "group", name = L["Find Buffs"], inline = true, order = 10,
		args = {
			note = { type = "description", order = 0,
				name = L["Choose a buff to track. Known spell-to-buff mappings are applied automatically; use Advanced: Spell IDs if one does not appear."] },
			source = { type = "select", name = L["Source"], order = 1,
				values = { recent = L["Recent Buffs"], catalog = L["Blizzard Catalog"] },
				get = function() return source end,
				set = function(_, value) source = value; page = 1; invalidate() end },
			sourceNote = { type = "description", order = 2, name = function()
				if source == "recent" then
					return L["Recent Buffs records readable helpful buffs on you. It can miss buffs while combat restrictions hide aura data."]
				end
				return L["Blizzard Catalog lists known self buffs from Blizzard data. It is not a complete list."]
			end },
			search = { type = "input", name = L["Search buffs"], order = 3, width = "full",
				desc = L["Search by buff name or spell ID, then press Enter."],
				get = function() return query end,
				set = function(_, value) query = value:sub(1, 100); page = 1 end },
			refresh = { type = "execute", name = L["Refresh"], order = 4,
				desc = L["Refresh the selected buff source."],
				func = function()
					backend():Refresh(); page = 1; invalidate()
					if source == "catalog" then addon:RefreshLayout() end
				end },
			clearHistory = { type = "execute", name = L["Clear History"], order = 5,
				desc = L["Forget all recorded Recent Buffs. This does not change your selected buffs."],
				hidden = function() return source ~= "recent" end,
				func = function() recent:Clear(); page = 1; invalidate() end },
			status = { type = "description", order = 6, name = function()
				if source == "recent" then
					local status = recent:GetStatus()
					if status == "restricted" then
						return L["Recent Buffs may be incomplete because aura data is restricted during combat."]
					end
					if status == "unavailable" then
						return L["Recent Buffs are unavailable. You can still add spell IDs under Advanced: Spell IDs."]
					end
				elseif not catalog:IsAvailable() then
					return L["Blizzard Catalog is unavailable. You can still add spell IDs under Advanced: Spell IDs."]
				end
				if #results() == 0 then return L["No matching buffs. Try another search or refresh the selected source."] .. " " .. evidence:DiscoveryNote() end
				local list = ids()
				if not list then return L["Fix the saved spell ID list under Advanced: Spell IDs before editing selected buffs."] end
				return string.format(L["%d matching buffs. %d of 12 buffs selected."], #results(), #list)
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
			name = function() local entry = result(index); return entry and entry.name or "" end,
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
		empty = { type = "description", order = 0, name = L["No buffs selected. Add a buff above or enter a spell ID under Advanced: Spell IDs."],
			hidden = function() return selected(1) ~= nil end },
	} }
	for index = 1, 12 do
		selection.args["slot" .. index] = {
			type = "group", name = "", inline = true, order = index,
			hidden = function() return not selected(index) end,
			args = {
				label = { type = "description", dialogControl = "InteractiveLabel", order = 0,
					width = "relative", relWidth = 0.6,
					name = function() local id = selected(index); return id and string.format("%d. %s", index, describe(id).name) or "" end,
					image = function() local id = selected(index); return id and describe(id).icon end,
					imageWidth = 24, imageHeight = 24,
					tooltipHyperlink = function() local id = selected(index); return id and "spell:" .. id end },
				up = { type = "execute", name = L["Up"], order = 1, width = "relative", relWidth = 0.1,
					desc = L["Move Up"], disabled = function() return index == 1 end, func = function() move(index, -1) end },
				down = { type = "execute", name = L["Down"], order = 2, width = "relative", relWidth = 0.12,
					desc = L["Move Down"], disabled = function() return not selected(index + 1) end, func = function() move(index, 1) end },
				remove = { type = "execute", name = L["Remove"], order = 3, width = "relative", relWidth = 0.18,
					func = function() local list = ids(); if list and list[index] then table.remove(list, index); save(list) end end },
				evidence = { type = "description", order = 4, width = "full", fontSize = "medium",
					name = function()
						local id = selected(index)
						if not id then return "" end
						return string.format(L["Evidence: %s"], evidence:Describe(id)) .. "\n" .. evidence:Explain(id)
					end },
				sound = { type = "select", name = L["Sound"], order = 5, width = "relative", relWidth = 0.45,
					desc = L["Play a sound when this buff is applied. Blizzard decides when the sound plays."],
					values = function() return soundValues() end,
					sorting = function() return soundOrder() end,
					get = function()
						local id = selected(index)
						local rule = id and sounds:GetRule(id)
						return rule and rule.sound or "none"
					end,
					set = function(_, value)
						local id = selected(index)
						if id then sounds:SetRule(id, { sound = value ~= "none" and value or false }) end
					end },
				soundPreview = { type = "execute", name = L["Preview Sound"], order = 6, width = "relative", relWidth = 0.28,
					desc = L["Play the chosen sound once. This only auditions the file; it does not test the live trigger."],
					disabled = function()
						local id = selected(index)
						local rule = id and sounds:GetRule(id)
						return not (rule and rule.sound)
					end,
					func = function()
						local id = selected(index)
						local rule = id and sounds:GetRule(id)
						if rule and rule.sound then sounds:Preview(rule.sound) end
					end },
				soundMute = { type = "toggle", name = L["Mute"], order = 7, width = "relative", relWidth = 0.2,
					desc = L["Silence this buff's sound without forgetting the choice."],
					get = function()
						local id = selected(index)
						local rule = id and sounds:GetRule(id)
						return rule and rule.mute == true or false
					end,
					set = function(_, value)
						local id = selected(index)
						if id then sounds:SetRule(id, { mute = value == true }) end
					end },
				soundStatus = { type = "description", order = 8, width = "full",
					hidden = function()
						local id = selected(index)
						return not id or sounds:GetStatus(id) == "none"
					end,
					name = function()
						local id = selected(index)
						return id and (SOUND_STATUS[sounds:GetStatus(id)] or "") or ""
					end },
			},
		}
	end

	local preview = { type = "group", name = L["Preview"], inline = true, order = 12, args = {
		note = { type = "description", order = 0, name = L["Preview shows configured order and columns at a fixed icon size, even when buffs are inactive."] },
		icons = { type = "description", order = 1, name = function()
			local list, lines, row = ids() or {}, {}, {}
			local columns = math.max(1, math.min(12, tonumber(addon.db.profile.playerBuffsColumns) or 4))
			for index, id in ipairs(list) do
				row[#row + 1] = string.format("|T%d:24:24|t", describe(id).icon)
				if index % columns == 0 or index == #list then lines[#lines + 1] = table.concat(row, " "); row = {} end
			end
			return table.concat(lines, "\n")
		end },
	} }
	return browser, selection, preview
end
