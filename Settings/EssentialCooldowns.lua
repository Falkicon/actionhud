-- Settings/EssentialCooldowns.lua
-- Essential Cooldowns settings options

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

-- Helper to check if module is in stack
local function IsInStack()
	local LM = ActionHud:GetModule("LayoutManager", true)
	return LM and LM:IsModuleInStack("essentialCooldowns")
end

function ns.Settings.BuildEssentialCooldownsOptions(self)
	local IsBlizzardCooldownViewerEnabled = ns.Settings.IsBlizzardCooldownViewerEnabled

	return {
		name = L["Essential Cooldowns"],
		handler = ActionHud,
		type = "group",
		args = {
			reqNote = {
				name = function()
					if IsBlizzardCooldownViewerEnabled() then
						return "|cff00ff00" .. L["Blizzard Cooldown Manager is enabled."] .. "|r"
					else
						return "|cffff4444"
							.. L["Blizzard Cooldown Manager is disabled."]
							.. "|r\n\n"
							.. L["Enable it in Gameplay Enhancements to use these features."]
					end
				end,
				type = "description",
				order = 0,
			},
			enable = {
				name = L["Enable"],
				desc = L["Enable management of Essential Cooldowns frame."],
				type = "toggle",
				order = 1,
				width = 1.0,
				get = function(info)
					return self.db.profile.essentialCooldownsEnabled
				end,
				set = function(info, val)
					self.db.profile.essentialCooldownsEnabled = val
					local mod = ActionHud:GetModule("EssentialCooldownsLayout", true)
					if mod then
						mod:UpdateLayout()
					end
				end,
			},
			includeInStack = {
				name = L["Include in HUD Stack"],
				desc = L["When enabled, this module is positioned as part of the vertical ActionHud stack. When disabled, it can be positioned independently."],
				type = "toggle",
				order = 2,
				width = 1.5,
				disabled = function()
					return not self.db.profile.essentialCooldownsEnabled
				end,
				get = function(info)
					local LM = ActionHud:GetModule("LayoutManager", true)
					return LM and LM:IsModuleInStack("essentialCooldowns")
				end,
				set = function(info, val)
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:SetModuleInStack("essentialCooldowns", val)
						LM:TriggerLayoutUpdate()
					end
				end,
			},

			-- Sizing group
			sizingGroup = {
				name = L["Sizing"],
				type = "group",
				inline = true,
				order = 10,
				args = {
					iconSize = {
						name = L["Icon Size"],
						desc = L["Size of cooldown icons."],
						type = "range",
						order = 1,
						width = 1.0,
						min = 16,
						max = 64,
						step = 1,
						disabled = function()
							return not IsBlizzardCooldownViewerEnabled()
								or not self.db.profile.essentialCooldownsEnabled
						end,
						get = function(info)
							return self.db.profile.essentialCooldownsIconSize or 36
						end,
						set = function(info, val)
							self.db.profile.essentialCooldownsIconSize = val
							local mod = ActionHud:GetModule("EssentialCooldownsLayout", true)
							if mod then
								mod:UpdateLayout()
							end
						end,
					},
					columns = {
						name = L["Columns"],
						desc = L["Maximum number of icons per row."],
						type = "range",
						order = 2,
						width = 1.0,
						min = 1,
						max = 16,
						step = 1,
						disabled = function()
							return not IsBlizzardCooldownViewerEnabled()
								or not self.db.profile.essentialCooldownsEnabled
						end,
						get = function(info)
							return self.db.profile.essentialCooldownsColumns or 8
						end,
						set = function(info, val)
							self.db.profile.essentialCooldownsColumns = val
							local mod = ActionHud:GetModule("EssentialCooldownsLayout", true)
							if mod then
								mod:UpdateLayout()
							end
						end,
					},
				},
			},

			-- Position group (only shown when not in stack)
			positionGroup = {
				name = L["Position"],
				type = "group",
				inline = true,
				order = 20,
				hidden = function()
					return IsInStack()
				end,
				args = {
					dragNote = {
						name = L["Use the 'Unlock Module Positions' toggle in the Layout tab to drag this module to a new position."],
						type = "description",
						order = 1,
					},
					resetPosition = {
						name = L["Reset Position"],
						desc = L["Reset this module to its default position."],
						type = "execute",
						order = 2,
						func = function()
							self.db.profile.essentialCooldownsXOffset = 0
							self.db.profile.essentialCooldownsYOffset = -100
							local mod = ActionHud:GetModule("EssentialCooldownsLayout", true)
							if mod then
								mod:UpdateLayout()
							end
						end,
					},
				},
			},
		},
	}
end
