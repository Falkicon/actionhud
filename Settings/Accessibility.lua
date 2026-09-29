local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

-- Cross-module readability presets. Nothing here runs automatically; the player
-- previews a preset, sees the exact changes, applies it, and can undo it.
function ns.Settings.BuildAccessibilityOptions(addon)
	local presentation = ns.Presentation
	local selectedPreset = "large"
	local presets = presentation:GetPresets()

	local function values()
		local result = {}
		for _, preset in ipairs(presets) do result[preset.id] = preset.name end
		return result
	end
	local function sorting()
		local order = {}
		for index, preset in ipairs(presets) do order[index] = preset.id end
		return order
	end

	return {
		name = L["Accessibility"], type = "group", handler = addon,
		args = {
			intro = { type = "description", order = 0,
				name = L["Style presets are starting points for readability. Applying one changes only text, size, spacing, and slot styling. Your buff and item choices, enabled features, sounds, and positions stay as they are. Presets are not a substitute for testing with the people who will use them."] },
			preset = { type = "select", name = L["Style preset"], order = 1, values = values, sorting = sorting,
				get = function() return selectedPreset end,
				set = function(_, value) selectedPreset = value end },
			description = { type = "description", order = 2,
				name = function() local preset = presentation:GetPreset(selectedPreset); return preset and preset.description or "" end },
			changes = { type = "description", order = 3, fontSize = "medium",
				name = function()
					return L["This preset would change:"] .. "\n" .. presentation:DescribeChanges(selectedPreset)
				end },
			preview = { type = "execute", name = L["Preview Preset"], order = 4,
				desc = L["Show a sample with this preset's values without applying it."],
				func = function() presentation:ShowSample(selectedPreset) end },
			apply = { type = "execute", name = L["Apply Preset"], order = 5,
				desc = L["Apply this preset to the current profile. You can undo the most recent application."],
				func = function() presentation:ApplyPreset(selectedPreset) end },
			undo = { type = "execute", name = L["Undo Last Preset"], order = 6,
				desc = L["Restore the values that were in place before the last preset was applied."],
				disabled = function() return not presentation:CanUndo() end,
				func = function() presentation:Undo() end },
			undoNote = { type = "description", order = 7,
				hidden = function() return not presentation:CanUndo() end,
				name = function()
					return string.format(L["Undo will restore the settings replaced by %s."], presentation:GetUndoName() or "")
				end },
			sample = { type = "execute", name = L["Show Current Sample"], order = 8,
				func = function() presentation:ShowSample() end },
			hideSample = { type = "execute", name = L["Hide Sample"], order = 9,
				hidden = function() return not presentation:IsSampleShown() end,
				func = function() presentation:HideSample() end },
		},
	}
end
