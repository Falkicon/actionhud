-- Settings/PlayerBuffs.lua
-- Player Buffs settings options

local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

local STATUS_TEXT = {
	disabled = L["Player Buffs is disabled."],
	unavailable = L["Player Buffs requires WoW 12.1's native aura container API, which is unavailable on this client."],
	empty = L["Add at least one spell to display Player Buffs."],
	invalid = L["Fix the saved spell ID list under Advanced: Spell IDs before editing selected buffs."],
	pending = L["Player Buffs is waiting until combat ends to create its display."],
	active = L["Player Buffs is active."],
	error = L["Player Buffs could not create its native aura display."],
}

local function GetModule()
	return ActionHud:GetModule("PlayerBuffs", true)
end

local function IsAvailable()
	local module = GetModule()
	return module and module:IsAvailable()
end

local function IsInStack()
	local manager = ActionHud:GetModule("LayoutManager", true)
	if manager then
		return manager:IsModuleInStack("playerBuffs")
	end
	return ActionHud.db.profile.playerBuffsIncludeInStack
end

local function ApplySpellIDs(self, text)
	self.db.profile.playerBuffsSpellIDs = text
	local module = GetModule()
	if module then
		module:ApplyEnabledState()
	end
	self:RefreshLayout()
end

local function UpdateLayout(self)
	local module = GetModule()
	if module then
		module:UpdateLayout()
	else
		self:RefreshLayout()
	end
end

local function ValidateSpellIDs(text)
	local module = GetModule()
	if not module then
		return L["Enter only positive integer spell IDs separated by commas or whitespace."]
	end

	local ids, errorCode = module:ParseSpellIDs(text)
	if ids then
		return true
	end
	if errorCode == "too_many" then
		return L["Enter no more than 12 unique spell IDs."]
	end
	return L["Enter only positive integer spell IDs separated by commas or whitespace."]
end

local function GetStatusText()
	local module = GetModule()
	local status = module and module:GetStatus() or "unavailable"
	if not IsAvailable() then
		status = "unavailable"
	end
	local text = STATUS_TEXT[status] or STATUS_TEXT.error
	if status == "active" then
		return "|cff00ff00" .. text .. "|r"
	end
	if status == "disabled" or status == "empty" then
		return "|cffaaaaaa" .. text .. "|r"
	end
	if status == "pending" then
		return "|cffffcc00" .. text .. "|r"
	end
	return "|cffff4444" .. text .. "|r"
end

function ns.Settings.BuildPlayerBuffsOptions(self)
	local advanced = false
	local browser, selected, preview = ns.Settings.BuildPlayerBuffPickerOptions(self)
	return {
		name = L["Player Buffs"],
		handler = ActionHud,
		type = "group",
		args = {
			browser = browser,
			selected = selected,
			preview = preview,
			advanced = {
				type = "toggle", name = L["Advanced: Spell IDs"], order = 30, width = "full",
				get = function() return advanced end,
				set = function(_, value) advanced = value end,
			},
			intro = {
				name = L["Track selected helpful player buffs and defensives in fixed positions. Configured slots stay reserved while inactive, so icons do not shift."],
				type = "description",
				order = 0,
			},
			status = {
				name = GetStatusText,
				type = "description",
				order = 1,
			},
			enable = {
				name = L["Enable Player Buffs"],
				desc = function()
					if not IsAvailable() then
						return L["Player Buffs requires WoW 12.1's native aura container API, which is unavailable on this client."]
					end
					return L["Show the configured helpful auras on the player."]
				end,
				type = "toggle",
				order = 2,
				disabled = function()
					return not IsAvailable()
				end,
				get = function(info)
					return self.db.profile.playerBuffsEnabled
				end,
				set = function(info, value)
					self.db.profile.playerBuffsEnabled = value
					local module = GetModule()
					if module then
						module:ApplyEnabledState()
					end
					self:RefreshLayout()
				end,
			},
			includeInStack = {
				name = L["Include in HUD Stack"],
				desc = L["When enabled, this module is positioned as part of the vertical ActionHud stack. When disabled, it can be positioned independently."],
				type = "toggle",
				order = 3,
				width = "full",
				get = function(info)
					return IsInStack()
				end,
				set = function(info, value)
					self.db.profile.playerBuffsIncludeInStack = value
					local manager = ActionHud:GetModule("LayoutManager", true)
					if manager then
						manager:SetModuleInStack("playerBuffs", value)
					end
					self:RefreshLayout()
				end,
			},
			positionNote = {
				name = L["Position is controlled by Layout tab when in HUD Stack."],
				type = "description",
				order = 4,
				hidden = function()
					return not IsInStack()
				end,
			},
			dragNote = {
				name = L["Use the 'Unlock Module Positions' toggle in the Layout tab to drag this module to a new position."],
				type = "description",
				order = 5,
				hidden = function()
					return IsInStack()
				end,
			},
			resetPosition = {
				name = L["Reset Position"],
				desc = L["Reset this module to its default position."],
				type = "execute",
				order = 6,
				hidden = function()
					return IsInStack()
				end,
				func = function()
					local defaults = self.db.defaults.profile
					self.db.profile.playerBuffsXOffset = defaults.playerBuffsXOffset
					self.db.profile.playerBuffsYOffset = defaults.playerBuffsYOffset
					UpdateLayout(self)
				end,
			},
			spellIDsGroup = {
				name = L["Advanced: Spell IDs"],
				type = "group",
				inline = true,
				order = 31,
				hidden = function() return not advanced end,
				args = {
					spellIDs = {
						name = L["Aura Spell IDs"],
						desc = L["Enter up to 12 helpful aura spell IDs separated by commas or whitespace. Aura spell IDs can differ from the spells you cast."],
						type = "input",
						order = 1,
						width = "full",
						multiline = 4,
						get = function(info)
							return self.db.profile.playerBuffsSpellIDs
						end,
						set = function(info, value)
							ApplySpellIDs(self, value)
						end,
						validate = function(info, value)
							return ValidateSpellIDs(value)
						end,
					},
					clearSpellIDs = {
						name = L["Clear Spell IDs"],
						desc = L["Clear the aura spell ID list without changing any other Player Buffs settings."],
						type = "execute",
						order = 3,
						func = function()
							ApplySpellIDs(self, "")
						end,
					},
				},
			},
			sizingGroup = {
				name = L["Sizing"],
				type = "group",
				inline = true,
				order = 20,
				args = {
					iconSize = {
						name = L["Icon Size"],
						desc = L["Size of Player Buffs icons."],
						type = "range",
						order = 1,
						min = 16,
						max = 64,
						step = 1,
						get = function(info)
							return self.db.profile.playerBuffsIconSize
						end,
						set = function(info, value)
							self.db.profile.playerBuffsIconSize = value
							UpdateLayout(self)
						end,
					},
					columns = {
						name = L["Columns"],
						desc = L["Maximum number of Player Buffs icons per row."],
						type = "range",
						order = 2,
						min = 1,
						max = 12,
						step = 1,
						get = function(info)
							return self.db.profile.playerBuffsColumns
						end,
						set = function(info, value)
							self.db.profile.playerBuffsColumns = value
							UpdateLayout(self)
						end,
					},
					spacing = {
						name = L["Spacing"],
						desc = L["Space between Player Buffs icons."],
						type = "range",
						order = 3,
						min = 0,
						max = 20,
						step = 1,
						get = function(info)
							return self.db.profile.playerBuffsSpacing
						end,
						set = function(info, value)
							self.db.profile.playerBuffsSpacing = value
							UpdateLayout(self)
						end,
					},
				},
			},
		},
	}
end
