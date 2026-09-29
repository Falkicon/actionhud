local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

-- Player Buffs presentation, sound, and guided-check controls. Appearance values
-- are plain profile settings; sounds and checks go through their Core modules.
function ns.Settings.BuildPlayerBuffSetupOptions(addon)
	local playerBuffs = addon:GetModule("PlayerBuffs")
	local evidence, sounds, presentation = ns.BuffEvidence, ns.AuraSounds, ns.Presentation
	local checkIndex = 1

	local function profile() return addon.db.profile end
	local function apply(key, value)
		profile()[key] = value
		playerBuffs:ApplyStyle()
		playerBuffs:UpdateLayout()
		presentation:RefreshSample()
	end
	local function selectedList() return playerBuffs:ParseSpellIDs(profile().playerBuffsSpellIDs or "") or {} end
	local function checkedID()
		local list = selectedList()
		checkIndex = math.min(checkIndex, math.max(1, #list))
		return list[checkIndex]
	end

	local function range(name, desc, order, key, min, max, step)
		return { type = "range", name = name, desc = desc, order = order, min = min, max = max, step = step or 1,
			get = function() return profile()[key] end,
			set = function(_, value) apply(key, value) end }
	end

	local appearance = { type = "group", name = L["Appearance"], inline = true, order = 21, args = {
		note = { type = "description", order = 0,
			name = L["Text and slot styling for Player Buffs. Backgrounds and borders belong to the slot, so inactive slots stay visible. Presets are under the Accessibility tab."] },
		timerSize = range(L["Countdown text size"],
			L["Size of the countdown text. 0 keeps Blizzard's default small timer font."], 1, "playerBuffsTimerFontSize", 0, 32),
		countSize = range(L["Stack text size"], L["Size of the stack count text."], 2, "playerBuffsCountFontSize", 8, 32),
		outline = { type = "toggle", name = L["Outline text"], order = 3,
			desc = L["Draw a dark outline around countdown and stack text."],
			get = function() return profile().playerBuffsTextOutline ~= false end,
			set = function(_, value) apply("playerBuffsTextOutline", value) end },
		background = range(L["Slot background"], L["Opacity of a dark background behind every slot, active or not."],
			4, "playerBuffsBackgroundOpacity", 0, 1, 0.05),
		border = range(L["Slot border"], L["Thickness of a white border on every slot. 0 hides it."],
			5, "playerBuffsBorderSize", 0, 6),
		preview = { type = "execute", name = L["Show Sample"], order = 6,
			desc = L["Show a movable sample with invented timers and stacks. It does not check live buffs."],
			func = function() presentation:ShowSample() end },
		hidePreview = { type = "execute", name = L["Hide Sample"], order = 7,
			hidden = function() return not presentation:IsSampleShown() end,
			func = function() presentation:HideSample() end },
	} }

	local audio = { type = "group", name = L["Sounds"], inline = true, order = 22, args = {
		note = { type = "description", order = 0,
			name = L["Optional sounds play when a selected buff is applied. Sounds are off until you turn them on, and applying a style preset never changes them. Choose a sound for each selected buff above."] },
		enable = { type = "toggle", name = L["Enable buff sounds"], order = 1, width = "full",
			desc = L["Master switch for all Player Buff sounds."],
			disabled = function() return not sounds:IsAvailable() end,
			get = function() return profile().playerBuffsSoundEnabled == true end,
			set = function(_, value) profile().playerBuffsSoundEnabled = value; sounds:Sync() end },
		unavailable = { type = "description", order = 2,
			hidden = function() return sounds:IsAvailable() end,
			name = L["This client does not offer native aura sounds, so buff sounds are unavailable."] },
	} }

	local check = { type = "group", name = L["Setup Check"], inline = true, order = 13, args = {
		intro = { type = "description", order = 0,
			name = L["Check a selected buff: preview how it looks, make sure changes are applied outside combat, gain the buff, then tell ActionHud what you saw. Your answers are recorded as your own report, not as verified facts."] },
		buff = { type = "select", name = L["Buff to check"], order = 1,
			values = function()
				local values = {}
				for index, id in ipairs(selectedList()) do
					values[index] = string.format("%d. %s", index, ns.BlizzardBuffCatalog:Describe(id).name)
				end
				return values
			end,
			get = function() return checkIndex end,
			set = function(_, value) checkIndex = value end },
		previewLook = { type = "execute", name = L["Preview Look"], order = 2,
			desc = L["Show the sample display. It does not test a live buff."],
			func = function() presentation:ShowSample() end },
		previewSound = { type = "execute", name = L["Preview Sound"], order = 3,
			hidden = function() local id = checkedID(); local rule = id and sounds:GetRule(id); return not (rule and rule.sound) end,
			func = function()
				local id = checkedID(); local rule = id and sounds:GetRule(id)
				if rule and rule.sound then sounds:Preview(rule.sound) end
			end },
		steps = { type = "description", order = 4,
			name = L["1. Leave combat. 2. Make sure Player Buffs is enabled. 3. Gain the buff. 4. Answer below."] },
		appeared = { type = "execute", name = L["It appeared"], order = 5,
			hidden = function() return checkedID() == nil end,
			func = function() local id = checkedID(); if id then evidence:Record(id, "appearance", true) end end },
		missing = { type = "execute", name = L["It did not appear"], order = 6,
			hidden = function() return checkedID() == nil end,
			func = function() local id = checkedID(); if id then evidence:Record(id, "appearance", false) end end },
		sounded = { type = "execute", name = L["It sounded"], order = 7,
			hidden = function() local id = checkedID(); local rule = id and sounds:GetRule(id); return not (rule and rule.sound) end,
			func = function() local id = checkedID(); if id then evidence:Record(id, "sound", true) end end },
		silent = { type = "execute", name = L["It did not sound"], order = 8,
			hidden = function() local id = checkedID(); local rule = id and sounds:GetRule(id); return not (rule and rule.sound) end,
			func = function() local id = checkedID(); if id then evidence:Record(id, "sound", false) end end },
		result = { type = "description", order = 9, width = "full",
			hidden = function() return checkedID() == nil end,
			name = function() local id = checkedID(); return id and evidence:DescribeResult(id) or "" end },
		diagnostics = { type = "description", order = 10, width = "full",
			hidden = function()
				local id = checkedID()
				local result = id and evidence:GetResult(id)
				return not (result and (result.appearance == "missing" or result.sound == "silent"))
			end,
			name = function()
				local id = checkedID()
				if not id then return "" end
				local result = evidence:GetResult(id) or {}
				local lines = evidence:Diagnose(id)
				if result.appearance == "missing" then lines[#lines + 1] = evidence:NextSteps("appearance") end
				if result.sound == "silent" then lines[#lines + 1] = evidence:NextSteps("sound") end
				return L["Public checks (these do not show whether the buff is active):"] .. "\n" .. table.concat(lines, "\n")
			end },
		forget = { type = "execute", name = L["Clear Check"], order = 11,
			hidden = function() local id = checkedID(); return not (id and evidence:GetResult(id)) end,
			func = function() local id = checkedID(); if id then evidence:Forget(id) end end },
	} }
	return check, appearance, audio
end
