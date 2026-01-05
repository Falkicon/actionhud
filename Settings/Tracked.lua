-- Settings/Tracked.lua
-- Tracked Abilities settings (Buffs, Bars, External Defensives)

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

function ns.Settings.BuildTrackedOptions(self)
	local IsBlizzardCooldownViewerEnabled = ns.Settings.IsBlizzardCooldownViewerEnabled

	return {
		name = L["Tracked Abilities"],
		handler = ActionHud,
		type = "group",
		args = {
			reqNote = {
				name = function()
					if IsBlizzardCooldownViewerEnabled() then
						return "|cff00ff00" .. L["Blizzard Cooldown Manager is enabled."] .. "|r"
					else
						return "|cffff4444" .. L["Blizzard Cooldown Manager is disabled."] .. "|r\n\n" .. L["Enable it in Gameplay Enhancements to use these features."]
					end
				end,
				type = "description",
				order = 0,
			},
			infoNote = {
				type = "description",
				order = 1,
				name = L["Custom frames for tracked abilities with independent positioning."] .. "\n",
			},

			-- Tracked Buffs Section
			buffsHeader = { name = L["Tracked Buffs"], type = "header", order = 10 },
			styleTrackedBuffs = {
				name = L["Enable Styling"],
				desc = L["Apply ActionHud styling to the Tracked Buffs frame (removes rounded corners, custom fonts)."],
				type = "toggle",
				order = 11,
				width = 1.0,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.styleTrackedBuffs
				end,
				set = function(info, val)
					self.db.profile.styleTrackedBuffs = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			trackedBuffsIncludeInStack = {
				name = L["Include in HUD Stack"],
				desc = L["When enabled, this module is positioned as part of the vertical ActionHud stack. When disabled, it can be positioned independently."],
				type = "toggle",
				order = 11.3,
				width = 1.0,
				disabled = function()
					return not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.trackedBuffsIncludeInStack
				end,
				set = function(info, val)
					self.db.profile.trackedBuffsIncludeInStack = val
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:TriggerLayoutUpdate()
					end
				end,
			},
			showBlizzardBuffs = {
				name = L["Show Blizzard Buffs (Debug)"],
				desc = L["Show Blizzard's buff viewer alongside ours for testing/validation."],
				type = "toggle",
				order = 11.5,
				width = "full",
				disabled = function()
					return not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return not self.db.profile.buffsHideBlizzardFrame
				end,
				set = function(info, val)
					self.db.profile.buffsHideBlizzardFrame = not val
					-- Trigger TrackedBuffsLayout to update visibility
					local layout = ActionHud:GetModule("TrackedBuffsLayout", true)
					if layout and layout.UpdateLayout then
						layout:UpdateLayout()
					end
				end,
			},
			buffsIconSize = {
				name = L["Icon Size"],
				desc = L["Size of buff icons."],
				type = "range",
				order = 12,
				width = 1.0,
				min = 16,
				max = 64,
				step = 1,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsIconSize or 36
				end,
				set = function(info, val)
					self.db.profile.buffsIconSize = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsColumns = {
				name = L["Columns"],
				desc = L["Maximum number of icons per row."],
				type = "range",
				order = 13,
				width = 1.0,
				min = 1,
				max = 16,
				step = 1,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsColumns or 8
				end,
				set = function(info, val)
					self.db.profile.buffsColumns = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsSpacingH = {
				name = L["Horizontal Spacing"],
				desc = L["Space between icons horizontally."],
				type = "range",
				order = 14,
				width = 1.0,
				min = 0,
				max = 20,
				step = 1,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsSpacingH or 2
				end,
				set = function(info, val)
					self.db.profile.buffsSpacingH = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsSpacingV = {
				name = L["Vertical Spacing"],
				desc = L["Space between icons vertically."],
				type = "range",
				order = 15,
				width = 1.0,
				min = 0,
				max = 20,
				step = 1,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsSpacingV or 2
				end,
				set = function(info, val)
					self.db.profile.buffsSpacingV = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsBorderEnabled = {
				name = L["Border"],
				desc = L["Show a border around each icon."],
				type = "toggle",
				order = 16,
				width = 1.0,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsBorderEnabled
				end,
				set = function(info, val)
					self.db.profile.buffsBorderEnabled = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsBorderSize = {
				name = L["Border Size"],
				desc = L["Thickness of the border."],
				type = "range",
				order = 17,
				width = 1.0,
				min = 1,
				max = 4,
				step = 1,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs or not self.db.profile.buffsBorderEnabled
				end,
				get = function(info)
					return self.db.profile.buffsBorderSize or 1
				end,
				set = function(info, val)
					self.db.profile.buffsBorderSize = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsCountFontSize = {
				name = L["Stack Count Font"],
				desc = L["Font size for stack counts."],
				type = "range",
				min = 6,
				max = 18,
				step = 1,
				order = 18,
				width = 1.0,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsCountFontSize or 10
				end,
				set = function(info, val)
					self.db.profile.buffsCountFontSize = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsTimerFontSize = {
				name = L["Timer Font"],
				desc = L["Font size for cooldown timers."],
				type = "select",
				order = 19,
				width = 1.0,
				values = { small = L["Small"], medium = L["Medium"], large = L["Large"], huge = L["Huge"] },
				sorting = { "small", "medium", "large", "huge" },
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsTimerFontSize or "medium"
				end,
				set = function(info, val)
					self.db.profile.buffsTimerFontSize = val
					ActionHud:GetModule("TrackedBuffs"):UpdateSettings()
				end,
			},
			buffsPositionHeader = { name = L["Position"], type = "header", order = 20 },
			buffsUnlock = {
				name = function()
					local layout = ActionHud:GetModule("TrackedBuffsLayout", true)
					return (layout and layout:IsLocked()) and L["Unlock Frame"] or L["Lock Frame"]
				end,
				desc = L["Unlock the frame to drag it to a new position."],
				type = "execute",
				order = 21,
				width = "full",
				func = function()
					local layout = ActionHud:GetModule("TrackedBuffsLayout", true)
					if layout then
						layout:ToggleLock()
					end
				end,
			},
			buffsXOffset = {
				name = L["X Offset"],
				desc = L["Horizontal offset from center."],
				type = "range",
				order = 22,
				width = 1.0,
				min = -500,
				max = 500,
				step = 1,
				get = function(info)
					return self.db.profile.buffsXOffset or 0
				end,
				set = function(info, val)
					self.db.profile.buffsXOffset = val
					local layout = ActionHud:GetModule("TrackedBuffsLayout", true)
					if layout then
						layout:UpdateLayout()
					end
				end,
			},
			buffsYOffset = {
				name = L["Y Offset"],
				desc = L["Vertical offset from center."],
				type = "range",
				order = 23,
				width = 1.0,
				min = -500,
				max = 500,
				step = 1,
				get = function(info)
					return self.db.profile.buffsYOffset or -180
				end,
				set = function(info, val)
					self.db.profile.buffsYOffset = val
					local layout = ActionHud:GetModule("TrackedBuffsLayout", true)
					if layout then
						layout:UpdateLayout()
					end
				end,
			},
			buffsResetPosition = {
				name = L["Reset Position"],
				type = "execute",
				order = 24,
				width = "full",
				func = function()
					self.db.profile.buffsXOffset = 0
					self.db.profile.buffsYOffset = -180
					local layout = ActionHud:GetModule("TrackedBuffsLayout", true)
					if layout then
						layout:UpdateLayout()
					end
				end,
			},

			-- External Defensives Section (12.0+ only)
			defensivesHeader = { name = L["External Defensives"], type = "header", order = 30 },
			defensivesNote = {
				type = "description",
				order = 31,
				name = function()
					if not ExternalDefensivesFrame then
						return "|cffaaaaaa" .. L["(Requires WoW 12.0 Midnight or later)"] .. "|r"
					end
					return ""
				end,
				hidden = function()
					return ExternalDefensivesFrame ~= nil
				end,
			},
			styleExternalDefensives = {
				name = L["Enable Styling"],
				desc = L["Apply ActionHud styling to the External Defensives frame."],
				type = "toggle",
				order = 32,
				width = 1.0,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				get = function(info)
					return self.db.profile.styleExternalDefensives
				end,
				set = function(info, val)
					self.db.profile.styleExternalDefensives = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesIconSize = {
				name = L["Icon Size"],
				desc = L["Size of defensive icons."],
				type = "range",
				order = 33,
				width = 1.0,
				min = 16,
				max = 64,
				step = 1,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives
				end,
				get = function(info)
					return self.db.profile.defensivesIconSize or 36
				end,
				set = function(info, val)
					self.db.profile.defensivesIconSize = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesColumns = {
				name = L["Columns"],
				desc = L["Maximum number of icons per row."],
				type = "range",
				order = 34,
				width = 1.0,
				min = 1,
				max = 16,
				step = 1,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives
				end,
				get = function(info)
					return self.db.profile.defensivesColumns or 8
				end,
				set = function(info, val)
					self.db.profile.defensivesColumns = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesSpacingH = {
				name = L["Horizontal Spacing"],
				desc = L["Space between icons horizontally."],
				type = "range",
				order = 35,
				width = 1.0,
				min = 0,
				max = 20,
				step = 1,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives
				end,
				get = function(info)
					return self.db.profile.defensivesSpacingH or 2
				end,
				set = function(info, val)
					self.db.profile.defensivesSpacingH = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesSpacingV = {
				name = L["Vertical Spacing"],
				desc = L["Space between icons vertically."],
				type = "range",
				order = 36,
				width = 1.0,
				min = 0,
				max = 20,
				step = 1,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives
				end,
				get = function(info)
					return self.db.profile.defensivesSpacingV or 2
				end,
				set = function(info, val)
					self.db.profile.defensivesSpacingV = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesBorderEnabled = {
				name = L["Border"],
				desc = L["Show a border around each icon."],
				type = "toggle",
				order = 37,
				width = 1.0,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives
				end,
				get = function(info)
					return self.db.profile.defensivesBorderEnabled
				end,
				set = function(info, val)
					self.db.profile.defensivesBorderEnabled = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesBorderSize = {
				name = L["Border Size"],
				desc = L["Thickness of the border."],
				type = "range",
				order = 38,
				width = 1.0,
				min = 1,
				max = 4,
				step = 1,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives or not self.db.profile.defensivesBorderEnabled
				end,
				get = function(info)
					return self.db.profile.defensivesBorderSize or 1
				end,
				set = function(info, val)
					self.db.profile.defensivesBorderSize = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesCountFontSize = {
				name = L["Stack Count Font"],
				desc = L["Font size for stack counts."],
				type = "range",
				min = 6,
				max = 18,
				step = 1,
				order = 39,
				width = 1.0,
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives
				end,
				get = function(info)
					return self.db.profile.defensivesCountFontSize or 10
				end,
				set = function(info, val)
					self.db.profile.defensivesCountFontSize = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
			defensivesTimerFontSize = {
				name = L["Timer Font"],
				desc = L["Font size for cooldown timers."],
				type = "select",
				order = 40,
				width = 1.0,
				values = { small = L["Small"], medium = L["Medium"], large = L["Large"], huge = L["Huge"] },
				sorting = { "small", "medium", "large", "huge" },
				hidden = function()
					return not ExternalDefensivesFrame
				end,
				disabled = function()
					return not self.db.profile.styleExternalDefensives
				end,
				get = function(info)
					return self.db.profile.defensivesTimerFontSize or "medium"
				end,
				set = function(info, val)
					self.db.profile.defensivesTimerFontSize = val
					local mod = ActionHud:GetModule("TrackedDefensives", true)
					if mod then
						mod:UpdateSettings()
					end
				end,
			},
		},
	}
end
