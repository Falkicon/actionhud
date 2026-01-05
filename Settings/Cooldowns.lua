-- Settings/Cooldowns.lua
-- Cooldown Manager settings options

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

-- Helper to check if module is in stack
local function IsInStack()
	local LM = ActionHud:GetModule("LayoutManager", true)
	return LM and LM:IsModuleInStack("cooldowns")
end

function ns.Settings.BuildCooldownsOptions(self)
	local IsBlizzardCooldownViewerEnabled = ns.Settings.IsBlizzardCooldownViewerEnabled
	local OpenGameplayEnhancements = ns.Settings.OpenGameplayEnhancements

	return {
		name = L["Cooldown Manager"],
		handler = ActionHud,
		type = "group",
		args = {
			reqNote = {
				name = function()
					if IsBlizzardCooldownViewerEnabled() then
						return string.format(
							"|cff00ff00%s|r\n\n%s\n%s",
							L["Blizzard Cooldown Manager is enabled."],
							L["ActionHud will hide the native UI and display custom-styled proxies."],
							L["Use Advanced Cooldown Settings in Gameplay Enhancements to configure tracked spells."]
						)
					else
						return string.format(
							"|cffff4444%s|r\n\n%s\n%s",
							L["Blizzard Cooldown Manager is disabled."],
							L["You must enable it first in WoW's Gameplay Enhancements settings."],
							L["All ActionHud cooldown features are unavailable until enabled."]
						)
					end
				end,
				type = "description",
				order = 0,
			},
			btnOpen = {
				name = L["Open Gameplay Enhancements"],
				desc = L["Opens WoW Settings directly to Gameplay Enhancements."],
				type = "execute",
				width = "double",
				func = function()
					OpenGameplayEnhancements()
				end,
				order = 0.5,
			},
			divider = { type = "header", name = "", order = 0.6 },
			enable = {
				name = L["Enable"],
				desc = L["Enable management of the native Cooldown Manager frame."],
				type = "toggle",
				order = 1,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdEnabled
				end,
				set = function(info, val)
					self.db.profile.cdEnabled = val
					self:RefreshLayout()
				end,
			},
			showBlizzardViewer = {
				name = L["Show Blizzard Cooldowns (Debug)"],
				desc = L["Show Blizzard's Cooldown Viewer alongside ours for testing/validation."],
				type = "toggle",
				order = 1.2,
				width = "full",
				disabled = function()
					return not self.db.profile.cdEnabled
				end,
				get = function(info)
					return not self.db.profile.cdHideBlizzardViewer
				end,
				set = function(info, val)
					self.db.profile.cdHideBlizzardViewer = not val
					self:RefreshLayout()
				end,
			},
			includeInStack = {
				name = L["Include in HUD Stack"],
				desc = L["When enabled, this module will be positioned in the vertical HUD stack. Otherwise, use independent X/Y positioning."],
				type = "toggle",
				order = 1.5,
				width = "full",
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return IsInStack()
				end,
				set = function(info, val)
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:SetModuleInStack("cooldowns", val)
					end
				end,
			},
			positionNote = {
				name = L["Position is controlled by Layout tab when in HUD Stack."],
				type = "description",
				order = 1.6,
				hidden = function() return not IsInStack() end,
			},
			dragNote = {
				name = L["Use the 'Unlock Module Positions' toggle in the Layout tab to drag this module to a new position."],
				type = "description",
				order = 1.7,
				hidden = function() return IsInStack() end,
			},
			resetPosition = {
				name = L["Reset Position"],
				desc = L["Reset this module to its default position."],
				type = "execute",
				order = 1.8,
				hidden = function() return IsInStack() end,
				func = function()
					self.db.profile.cooldownsXOffset = 0
					self.db.profile.cooldownsYOffset = -100
					local Cooldowns = ActionHud:GetModule("Cooldowns", true)
					if Cooldowns then Cooldowns:ApplyLayoutPosition() end
				end,
			},
			spacing = {
				name = L["Bar Spacing"],
				desc = L["Space between Essential and Utility bars."],
				type = "range",
				min = 0,
				max = 50,
				step = 1,
				order = 4,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdSpacing
				end,
				set = function(info, val)
					self.db.profile.cdSpacing = val
					self:RefreshLayout()
				end,
			},
			reverse = {
				name = L["Reverse Order"],
				desc = L["Swap the Essential and Utility bars."],
				type = "toggle",
				order = 5,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdReverse
				end,
				set = function(info, val)
					self.db.profile.cdReverse = val
					self:RefreshLayout()
				end,
			},
			itemGap = {
				name = L["Icon Spacing"],
				desc = L["Space between cooldown icons."],
				type = "range",
				min = 0,
				max = 20,
				step = 1,
				order = 6,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdItemGap
				end,
				set = function(info, val)
					self.db.profile.cdItemGap = val
					self:RefreshLayout()
				end,
			},
			headerEssential = { type = "header", name = L["Essential Bar"], order = 10 },
			essWidth = {
				name = L["Width"],
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 11,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdEssentialWidth
				end,
				set = function(info, val)
					self.db.profile.cdEssentialWidth = val
					self:RefreshLayout()
				end,
			},
			essHeight = {
				name = L["Height"],
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 12,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdEssentialHeight
				end,
				set = function(info, val)
					self.db.profile.cdEssentialHeight = val
					self:RefreshLayout()
				end,
			},
			headerUtility = { type = "header", name = L["Utility Bar"], order = 20 },
			utilWidth = {
				name = L["Width"],
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 21,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdUtilityWidth
				end,
				set = function(info, val)
					self.db.profile.cdUtilityWidth = val
					self:RefreshLayout()
				end,
			},
			utilHeight = {
				name = L["Height"],
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 22,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdUtilityHeight
				end,
				set = function(info, val)
					self.db.profile.cdUtilityHeight = val
					self:RefreshLayout()
				end,
			},
			headerFont = { type = "header", name = L["Typography"], order = 25 },
			fontSize = {
				name = L["Stack Font Size"],
				type = "range",
				min = 6,
				max = 18,
				step = 1,
				order = 26,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdCountFontSize
				end,
				set = function(info, val)
					self.db.profile.cdCountFontSize = val
					self:RefreshLayout()
				end,
			},
			timerFontSize = {
				name = L["Timer Font Size"],
				type = "select",
				order = 27,
				values = { small = L["Small"], medium = L["Medium"], large = L["Large"], huge = L["Huge"] },
				sorting = { "small", "medium", "large", "huge" },
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.cdTimerFontSize
				end,
				set = function(info, val)
					self.db.profile.cdTimerFontSize = val
					self:RefreshLayout()
				end,
			},
		},
	}
end
