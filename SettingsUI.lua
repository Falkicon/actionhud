-- SettingsUI.lua
-- Defines the configuration options using AceConfig-3.0

local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")

-- Constants
local CVAR_COOLDOWN_VIEWER_ENABLED = "cooldownViewerEnabled"

-- Helper to check if Blizzard's Cooldown Manager is enabled
local function IsBlizzardCooldownViewerEnabled()
	if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
		return CVarCallbackRegistry:GetCVarValueBool(CVAR_COOLDOWN_VIEWER_ENABLED)
	end
	-- Fallback for older clients
	local val = GetCVar(CVAR_COOLDOWN_VIEWER_ENABLED)
	return val == "1"
end

-- Helper to open the Gameplay Enhancements (Advanced Options) settings panel
-- Uses Blizzard's defined constant which is more robust than hardcoded IDs
local function OpenGameplayEnhancements()
	if Settings and Settings.OpenToCategory then
		-- Blizzard defines this constant in AdvancedOptions.lua
		if Settings.ADVANCED_OPTIONS_CATEGORY_ID then
			Settings.OpenToCategory(Settings.ADVANCED_OPTIONS_CATEGORY_ID)
			return true
		end
	end

	-- Fallback: Show settings panel and click Game tab
	if SettingsPanel then
		SettingsPanel:Show()
		if SettingsPanel.GameTab then
			SettingsPanel.GameTab:Click()
		end
		print("|cff33ff99ActionHud:|r Navigate to |cffffcc00Gameplay Enhancements|r.")
		return true
	end
	return false
end

function ActionHud:SetupOptions()
	-- ROOT: General
	local generalOptions = {
		name = "ActionHud",
		handler = ActionHud,
		type = "group",
		args = {
			locked = {
				name = "Lock Frame",
				desc = "Lock the HUD in place. Uncheck to drag.",
				type = "toggle",
				order = 1,
				get = function(info)
					return self.db.profile.locked
				end,
				set = function(info, val)
					self.db.profile.locked = val
					self:UpdateLockState()
				end,
			},
			minimapIcon = {
				name = "Show Minimap Icon",
				desc = "Toggle the minimap icon.",
				type = "toggle",
				order = 2,
				hidden = function()
					return not self.icon
				end, -- Hide if LibDBIcon not available
				get = function(info)
					if not self.db.profile.minimap then
						return true
					end
					return not self.db.profile.minimap.hide
				end,
				set = function(info, val)
					if not self.db.profile.minimap then
						self.db.profile.minimap = { hide = false }
					end
					self.db.profile.minimap.hide = not val
					if self.icon then
						if val then
							self.icon:Show("ActionHud")
						else
							self.icon:Hide("ActionHud")
						end
					end
				end,
			},
			divider = { type = "header", name = "Info & Prerequisites", order = 10 },
			readme = {
				type = "description",
				name = [[|cff33ff99ActionHud 2.6.2|r

A minimalist HUD mirroring Action Bars 1 & 2 in a 6x4 grid.

|cffffcc00Required Setup:|r
Click the button below to open WoW's Gameplay Enhancements settings.

Enable these options:
  - |cffffffffAssisted Highlight|r (rotation glows)
  - |cffffffffEnable Cooldown Manager|r (tracked cooldowns)
  
Use |cffffffffAdvanced Cooldown Settings|r to configure which spells are tracked.
]],
				fontSize = "medium",
				order = 11,
			},
			btnPreReq1 = {
				name = "Open Gameplay Enhancements",
				desc = "Opens WoW Settings directly to Gameplay Enhancements.",
				type = "execute",
				width = "double",
				func = function()
					OpenGameplayEnhancements()
				end,
				order = 12,
			},
			helpHeader = { type = "header", name = "Help & Slash Commands", order = 20 },
			helpCommands = {
				type = "description",
				name = [[|cffffcc00Slash Commands:|r
  - |cffffffff/ah|r: Open settings.
  - |cffffffff/ah debug|r: Toggle debug recording.
  - |cffffffff/ah clear|r: Clear debug buffer.
  - |cffffffff/ah dump|r: Dump tracked spell info to chat.

|cffffcc00Debugging & Layout:|r
Use the |cffffffffLayout|r tab to enable |cffffffffShow Layout Outlines|r. This helps position frames when they are empty or out of combat.
]],
				fontSize = "medium",
				order = 21,
			},
		},
	}

	-- SUB: Action Bars
	local abOptions = {
		name = "Action Bars",
		handler = ActionHud,
		type = "group",
		args = {
			enable = {
				name = "Enable",
				type = "toggle",
				order = 1,
				desc = "Enable the main Action Bar Grid.",
				get = function(info)
					return ActionHud:GetModule("ActionBars"):IsEnabled()
				end,
				set = function(info, val)
					if val then
						ActionHud:GetModule("ActionBars"):Enable()
					else
						ActionHud:GetModule("ActionBars"):Disable()
					end
					self:RefreshLayout()
				end,
			},
			iconDimensions = { name = "Dimensions", type = "header", order = 10 },
			iconWidth = {
				name = "Icon Width",
				desc = "Width of the action icons.",
				type = "range",
				min = 10,
				max = 50,
				step = 1,
				order = 11,
				get = function(info)
					return self.db.profile.iconWidth
				end,
				set = function(info, val)
					self.db.profile.iconWidth = val
					self:RefreshLayout()
				end,
			},
			iconHeight = {
				name = "Icon Height",
				desc = "Height of the action icons.",
				type = "range",
				min = 10,
				max = 50,
				step = 1,
				order = 12,
				get = function(info)
					return self.db.profile.iconHeight
				end,
				set = function(info, val)
					self.db.profile.iconHeight = val
					self:RefreshLayout()
				end,
			},
			visuals = { name = "Visuals & Opacity", type = "header", order = 20 },
			opacity = {
				name = "Background Opacity",
				desc = "Opacity of empty slots.",
				type = "range",
				min = 0,
				max = 1,
				step = 0.05,
				isPercent = true,
				order = 21,
				get = function(info)
					return self.db.profile.opacity
				end,
				set = function(info, val)
					self.db.profile.opacity = val
					ActionHud:GetModule("ActionBars"):UpdateOpacity()
				end,
			},
			procGlowAlpha = {
				name = "Proc Glow Opacity (Yellow)",
				type = "range",
				min = 0,
				max = 1,
				step = 0.05,
				isPercent = true,
				order = 22,
				get = function(info)
					return self.db.profile.procGlowAlpha
				end,
				set = function(info, val)
					self.db.profile.procGlowAlpha = val
					ActionHud:GetModule("ActionBars"):UpdateLayout()
				end,
			},
			assistGlowAlpha = {
				name = "Assist Glow Opacity (Blue)",
				type = "range",
				min = 0,
				max = 1,
				step = 0.05,
				isPercent = true,
				order = 23,
				get = function(info)
					return self.db.profile.assistGlowAlpha
				end,
				set = function(info, val)
					self.db.profile.assistGlowAlpha = val
					ActionHud:GetModule("ActionBars"):UpdateLayout()
				end,
			},
			fonts = { name = "Fonts", type = "header", order = 30 },
			cooldownFontSize = {
				name = "Cooldown Font Size",
				type = "range",
				min = 6,
				max = 24,
				step = 1,
				order = 31,
				get = function(info)
					return self.db.profile.cooldownFontSize
				end,
				set = function(info, val)
					self.db.profile.cooldownFontSize = val
					ActionHud:GetModule("ActionBars"):UpdateLayout()
				end,
			},
			countFontSize = {
				name = "Stack Count Font Size",
				type = "range",
				min = 6,
				max = 24,
				step = 1,
				order = 32,
				get = function(info)
					return self.db.profile.countFontSize
				end,
				set = function(info, val)
					self.db.profile.countFontSize = val
					ActionHud:GetModule("ActionBars"):UpdateLayout()
				end,
			},
			mirrorHeader = { name = "Layout Mirroring", type = "header", order = 40 },
			barPriority = {
				name = "Top Bar Priority",
				desc = "Choose which bar appears at the top of the HUD stack.",
				type = "select",
				order = 42,
				width = 1.2,
				values = { bar1 = "Main Bar (Bar 1)", bar6 = "Bottom Left Bar (Bar 2)" },
				get = function(info)
					return self.db.profile.barPriority
				end,
				set = function(info, val)
					self.db.profile.barPriority = val
					ActionHud:GetModule("ActionBars"):UpdateLayout()
				end,
			},
			barAlignment = {
				name = "Row Alignment",
				desc = "Horizontal alignment of the bars within the HUD container.",
				type = "select",
				order = 43,
				width = 0.8,
				values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
				get = function(info)
					return self.db.profile.barAlignment
				end,
				set = function(info, val)
					self.db.profile.barAlignment = val
					ActionHud:GetModule("ActionBars"):UpdateLayout()
				end,
			},
		},
	}

	-- SUB: Resources
	local resOptions = {
		name = "Resource Bars",
		handler = ActionHud,
		type = "group",
		args = {
			enable = {
				name = "Enable",
				type = "toggle",
				order = 1,
				get = function(info)
					return self.db.profile.resEnabled
				end,
				set = function(info, val)
					self.db.profile.resEnabled = val
					self:RefreshLayout()
				end,
			},
			showTarget = {
				name = "Show Target Stats",
				desc = "Split bars to show target health/power.",
				type = "toggle",
				order = 2,
				get = function(info)
					return self.db.profile.resShowTarget
				end,
				set = function(info, val)
					self.db.profile.resShowTarget = val
					self:RefreshLayout()
				end,
			},
			widthNote = {
				type = "description",
				order = 3,
				name = "|cffaaaaaaNote: The width of these bars is automatically matched to the Action Bar grid (Action Bars > Icon Width).|r",
			},
			commonHeader = { name = "Common Settings", type = "header", order = 10 },
			commonGroup = {
				type = "group",
				inline = true,
				name = "",
				order = 11,
				args = {
					gap = {
						name = "Player-Target Gap",
						desc = "Space between player and target bars.",
						type = "range",
						min = 0,
						max = 50,
						step = 1,
						order = 1,
						get = function(info)
							return self.db.profile.resGap
						end,
						set = function(info, val)
							self.db.profile.resGap = val
							self:RefreshLayout()
						end,
					},
					spacing = {
						name = "Bar Spacing",
						type = "range",
						min = 0,
						max = 10,
						step = 1,
						order = 2,
						get = function(info)
							return self.db.profile.resSpacing
						end,
						set = function(info, val)
							self.db.profile.resSpacing = val
							self:RefreshLayout()
						end,
					},
				},
			},
			healthGroup = {
				name = "Health Bar",
				type = "group",
				inline = true,
				order = 20,
				args = {
					enable = {
						name = "Enable",
						type = "toggle",
						order = 1,
						get = function(info)
							return self.db.profile.resHealthEnabled ~= false
						end,
						set = function(info, val)
							self.db.profile.resHealthEnabled = val
							self:RefreshLayout()
						end,
					},
					height = {
						name = "Height",
						type = "range",
						min = 1,
						max = 30,
						step = 1,
						order = 2,
						get = function(info)
							return self.db.profile.resHealthHeight
						end,
						set = function(info, val)
							self.db.profile.resHealthHeight = val
							self:RefreshLayout()
						end,
					},
				},
			},
			powerGroup = {
				name = "Power Bar",
				type = "group",
				inline = true,
				order = 30,
				args = {
					enable = {
						name = "Enable",
						type = "toggle",
						order = 1,
						get = function(info)
							return self.db.profile.resPowerEnabled ~= false
						end,
						set = function(info, val)
							self.db.profile.resPowerEnabled = val
							self:RefreshLayout()
						end,
					},
					height = {
						name = "Height",
						type = "range",
						min = 1,
						max = 30,
						step = 1,
						order = 2,
						get = function(info)
							return self.db.profile.resPowerHeight
						end,
						set = function(info, val)
							self.db.profile.resPowerHeight = val
							self:RefreshLayout()
						end,
					},
				},
			},
			classGroup = {
				name = "Class Resource",
				type = "group",
				inline = true,
				order = 40,
				args = {
					enable = {
						name = "Enable",
						type = "toggle",
						order = 1,
						get = function(info)
							return self.db.profile.resClassEnabled ~= false
						end,
						set = function(info, val)
							self.db.profile.resClassEnabled = val
							self:RefreshLayout()
						end,
					},
					height = {
						name = "Height",
						type = "range",
						min = 1,
						max = 20,
						step = 1,
						order = 2,
						get = function(info)
							return self.db.profile.resClassHeight
						end,
						set = function(info, val)
							self.db.profile.resClassHeight = val
							self:RefreshLayout()
						end,
					},
				},
			},
		},
	}

	-- SUB: Cooldowns
	local cdOptions = {
		name = "Cooldown Manager",
		handler = ActionHud,
		type = "group",
		args = {
			reqNote = {
				name = function()
					if IsBlizzardCooldownViewerEnabled() then
						return [[|cff00ff00Blizzard Cooldown Manager is enabled.|r

ActionHud will hide the native UI and display custom-styled proxies.
Use |cffffffffAdvanced Cooldown Settings|r in Gameplay Enhancements to configure tracked spells.]]
					else
						return [[|cffff4444Blizzard Cooldown Manager is disabled.|r

You must enable it first in WoW's Gameplay Enhancements settings.
All ActionHud cooldown features are unavailable until enabled.]]
					end
				end,
				type = "description",
				order = 0,
			},
			btnOpen = {
				name = "Open Gameplay Enhancements",
				desc = "Opens WoW Settings directly to Gameplay Enhancements.",
				type = "execute",
				width = "double",
				func = function()
					OpenGameplayEnhancements()
				end,
				order = 0.5,
			},
			divider = { type = "header", name = "", order = 0.6 },
			enable = {
				name = "Enable",
				desc = "Enable management of the native Cooldown Manager frame.",
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
			spacing = {
				name = "Bar Spacing",
				desc = "Space between Essential and Utility bars.",
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
				name = "Reverse Order",
				desc = "Swap the Essential and Utility bars.",
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
				name = "Icon Spacing",
				desc = "Space between cooldown icons.",
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
			headerEssential = { type = "header", name = "Essential Bar", order = 10 },
			essWidth = {
				name = "Width",
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
				name = "Height",
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
			headerUtility = { type = "header", name = "Utility Bar", order = 20 },
			utilWidth = {
				name = "Width",
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
				name = "Height",
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
			headerFont = { type = "header", name = "Typography", order = 25 },
			fontSize = {
				name = "Stack Font Size",
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
				name = "Timer Font Size",
				type = "select",
				order = 27,
				values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
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

	-- SUB: Tracked Abilities (Tracked Buffs, Tracked Bars, External Defensives)
	-- Style-only overlays on Blizzard's native frames. Position via EditMode.
	local trackedOptions = {
		name = "Tracked Abilities",
		handler = ActionHud,
		type = "group",
		args = {
			reqNote = {
				name = function()
					if IsBlizzardCooldownViewerEnabled() then
						return "|cff00ff00Blizzard Cooldown Manager is enabled.|r"
					else
						return [[|cffff4444Blizzard Cooldown Manager is disabled.|r

Enable it in Gameplay Enhancements to use these features.]]
					end
				end,
				type = "description",
				order = 0,
			},
			infoNote = {
				type = "description",
				order = 1,
				name = [[ActionHud applies custom styling to Blizzard's Tracked Abilities frames, removing rounded corners and adjusting fonts.

|cffffcc00Positioning:|r Use Blizzard's |cff00ff00EditMode|r to move and resize these frames.
]],
			},
			openEditMode = {
				name = "Open EditMode",
				desc = "Open Blizzard's EditMode to position and resize Tracked Abilities frames.",
				type = "execute",
				order = 2,
				width = "normal",
				func = function()
					if EditModeManagerFrame then
						EditModeManagerFrame:Show()
					end
				end,
			},

			-- Tracked Buffs Section
			buffsHeader = { name = "Tracked Buffs", type = "header", order = 10 },
			styleTrackedBuffs = {
				name = "Enable Styling",
				desc = "Apply ActionHud styling to the Tracked Buffs frame (removes rounded corners, custom fonts).",
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
					ActionHud:GetModule("TrackedBuffs"):UpdateLayout()
				end,
			},
			buffsCountFontSize = {
				name = "Stack Count Font",
				desc = "Font size for stack counts.",
				type = "range",
				min = 6,
				max = 18,
				step = 1,
				order = 12,
				width = 1.0,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsCountFontSize or 10
				end,
				set = function(info, val)
					self.db.profile.buffsCountFontSize = val
					ActionHud:GetModule("TrackedBuffs"):UpdateLayout()
				end,
			},
			buffsTimerFontSize = {
				name = "Timer Font",
				desc = "Font size for cooldown timers.",
				type = "select",
				order = 13,
				width = 1.0,
				values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
				sorting = { "small", "medium", "large", "huge" },
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs
				end,
				get = function(info)
					return self.db.profile.buffsTimerFontSize or "medium"
				end,
				set = function(info, val)
					self.db.profile.buffsTimerFontSize = val
					ActionHud:GetModule("TrackedBuffs"):UpdateLayout()
				end,
			},

			-- Tracked Bars Section
			barsHeader = { name = "Tracked Bars", type = "header", order = 20 },
			styleTrackedBars = {
				name = "Enable Styling",
				desc = "Apply ActionHud styling to the Tracked Bars frame (removes rounded corners, custom fonts).",
				type = "toggle",
				order = 21,
				width = 1.0,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled()
				end,
				get = function(info)
					return self.db.profile.styleTrackedBars
				end,
				set = function(info, val)
					self.db.profile.styleTrackedBars = val
					ActionHud:GetModule("TrackedBars"):UpdateLayout()
				end,
			},
			barsCountFontSize = {
				name = "Stack Count Font",
				desc = "Font size for stack counts.",
				type = "range",
				min = 6,
				max = 18,
				step = 1,
				order = 22,
				width = 1.0,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBars
				end,
				get = function(info)
					return self.db.profile.barsCountFontSize or 10
				end,
				set = function(info, val)
					self.db.profile.barsCountFontSize = val
					ActionHud:GetModule("TrackedBars"):UpdateLayout()
				end,
			},
			barsTimerFontSize = {
				name = "Timer Font",
				desc = "Font size for cooldown timers.",
				type = "select",
				order = 23,
				width = 1.0,
				values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
				sorting = { "small", "medium", "large", "huge" },
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBars
				end,
				get = function(info)
					return self.db.profile.barsTimerFontSize or "medium"
				end,
				set = function(info, val)
					self.db.profile.barsTimerFontSize = val
					ActionHud:GetModule("TrackedBars"):UpdateLayout()
				end,
			},
			barsCompactMode = {
				name = "Compact Mode (Icons Only)",
				desc = "Hide the cooldown bars, showing only icons. Useful for a more compact display.",
				type = "toggle",
				order = 24,
				width = 1.5,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBars
				end,
				get = function(info)
					return self.db.profile.barsCompactMode
				end,
				set = function(info, val)
					self.db.profile.barsCompactMode = val
					ActionHud:GetModule("TrackedBars"):UpdateLayout()
				end,
			},
			barsTimerOnIcon = {
				name = "Timer on Icon",
				desc = "Display the countdown timer centered on the icon instead of on the bar.",
				type = "toggle",
				order = 25,
				width = 1.0,
				disabled = function()
					return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBars
				end,
				get = function(info)
					return self.db.profile.barsTimerOnIcon
				end,
				set = function(info, val)
					self.db.profile.barsTimerOnIcon = val
					ActionHud:GetModule("TrackedBars"):UpdateLayout()
				end,
			},

			-- External Defensives Section (12.0+ only)
			defensivesHeader = { name = "External Defensives", type = "header", order = 30 },
			defensivesNote = {
				type = "description",
				order = 31,
				name = function()
					if not ExternalDefensivesFrame then
						return "|cffaaaaaa(Requires WoW 12.0 Midnight or later)|r"
					end
					return ""
				end,
				hidden = function()
					return ExternalDefensivesFrame ~= nil
				end,
			},
			styleExternalDefensives = {
				name = "Enable Styling",
				desc = "Apply ActionHud styling to the External Defensives frame.",
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
						mod:UpdateLayout()
					end
				end,
			},
			defensivesCountFontSize = {
				name = "Stack Count Font",
				desc = "Font size for stack counts.",
				type = "range",
				min = 6,
				max = 18,
				step = 1,
				order = 33,
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
						mod:UpdateLayout()
					end
				end,
			},
			defensivesTimerFontSize = {
				name = "Timer Font",
				desc = "Font size for cooldown timers.",
				type = "select",
				order = 34,
				width = 1.0,
				values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
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
						mod:UpdateLayout()
					end
				end,
			},
		},
	}

	-- SUB: Unit Frames (Player/Target/Focus)
	local unitFrameOptions = {
		name = "Unit Frames",
		handler = ActionHud,
		type = "group",
		args = {
			experimentalNote = {
				type = "description",
				order = 0.1,
				name = [[|cffffcc00Experimental Feature:|r
Due to Blizzard's API changes in Midnight (12.0), traditional unit frame customization is significantly restricted. ActionHud's styling approach balances these technical limitations with a modern, minimalist aesthetic. This feature will continue to evolve as new APIs become available.

|cffffcc00Note:|r High-impact changes (like bar heights or width) require |cff00ff00/reload|r to properly synchronize anchors and prevent combat taint.
]],
			},
			enable = {
				name = "Enable Unit Frame Styling",
				desc = "Apply ActionHud styling to unit frames.",
				type = "toggle",
				order = 1,
				width = "full",
				get = function(info)
					return self.db.profile.ufEnabled
				end,
				set = function(info, val)
					self.db.profile.ufEnabled = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},

			-- Appearance Section
			appearanceHeader = { name = "Appearance", type = "header", order = 10 },
			hidePortraits = {
				name = "Hide Portraits",
				desc = "Hide the circular portrait image plus portrait-area elements (rest indicator, corner embellishment, combat icon).",
				type = "toggle",
				order = 11,
				width = 1.0,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufHidePortraits
				end,
				set = function(info, val)
					self.db.profile.ufHidePortraits = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			hideBorders = {
				name = "Hide Borders",
				desc = "Remove the frame border/decoration texture. Note: This also hides the gold ring around the portrait (they're one texture).",
				type = "toggle",
				order = 12,
				width = 1.0,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufHideBorders
				end,
				set = function(info, val)
					self.db.profile.ufHideBorders = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			flatBars = {
				name = "Flat Bar Texture",
				desc = "Use a solid flat texture instead of gradient bars.",
				type = "toggle",
				order = 13,
				width = 1.0,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufFlatBars
				end,
				set = function(info, val)
					self.db.profile.ufFlatBars = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			showBackground = {
				name = "Show Background",
				desc = "Add a dark semi-transparent background behind the bars.",
				type = "toggle",
				order = 14,
				width = 1.0,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufShowBackground
				end,
				set = function(info, val)
					self.db.profile.ufShowBackground = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},

			-- Typography Section
			typographyHeader = { name = "Typography", type = "header", order = 15 },
			statusTextTip = {
				type = "description",
				order = 15.1,
				name = [[|cffffcc00Pro Tip:|r To show health and resource numbers on your frames, use the built-in Blizzard setting: |cff00ff00Options|r > |cff00ff00Gameplay|r > |cff00ff00Interface|r > |cff00ff00Status Text|r and select |cff00ff00Numeric Value|r.
]],
			},
			fontName = {
				name = "Font",
				desc = "Font for health and power bar text.",
				type = "select",
				order = 16,
				width = 1.5,
				dialogControl = "LSM30_Font",
				values = function()
					return LSM:HashTable("font")
				end,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufFontName
				end,
				set = function(info, val)
					self.db.profile.ufFontName = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			fontSize = {
				name = "Font Size",
				desc = "Size of the health and power bar text.",
				type = "range",
				min = 6,
				max = 18,
				step = 1,
				order = 17,
				width = 1.0,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufFontSize
				end,
				set = function(info, val)
					self.db.profile.ufFontSize = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},

			-- Sizing Section
			sizingHeader = { name = "Bar Sizing", type = "header", order = 20 },
			healthHeight = {
				name = "Health Bar Height",
				desc = "Height of the health bar in pixels.",
				type = "range",
				min = 5,
				max = 40,
				step = 1,
				order = 21,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufHealthHeight
				end,
				set = function(info, val)
					self.db.profile.ufHealthHeight = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			manaHeight = {
				name = "Mana/Power Bar Height",
				desc = "Height of the mana/power bar in pixels.",
				type = "range",
				min = 2,
				max = 30,
				step = 1,
				order = 22,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufManaHeight
				end,
				set = function(info, val)
					self.db.profile.ufManaHeight = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			barScale = {
				name = "Bar Width Scale",
				desc = "Scale the width of health/mana bars (1.0 = default).",
				type = "range",
				min = 0.5,
				max = 1.5,
				step = 0.05,
				order = 23,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufBarScale
				end,
				set = function(info, val)
					self.db.profile.ufBarScale = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},

			-- Class Resources Section
			classHeader = { name = "Class Resources", type = "header", order = 30 },
			classBarHeight = {
				name = "Class Bar Height",
				desc = "Height of the class resource bar (combo points, holy power, etc.).",
				type = "range",
				min = 5,
				max = 30,
				step = 1,
				order = 31,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufClassBarHeight
				end,
				set = function(info, val)
					self.db.profile.ufClassBarHeight = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},

			-- Scope Section
			scopeHeader = { name = "Frame Selection", type = "header", order = 40 },
			scopeNote = {
				type = "description",
				order = 41,
				name = "Choose which frames to style:",
			},
			stylePlayer = {
				name = "Player Frame",
				desc = "Apply styling to your Player Frame.",
				type = "toggle",
				order = 42,
				width = 0.8,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufStylePlayer
				end,
				set = function(info, val)
					self.db.profile.ufStylePlayer = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			styleTarget = {
				name = "Target Frame",
				desc = "Apply styling to the Target Frame.",
				type = "toggle",
				order = 43,
				width = 0.8,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufStyleTarget
				end,
				set = function(info, val)
					self.db.profile.ufStyleTarget = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
			styleFocus = {
				name = "Focus Frame",
				desc = "Apply styling to the Focus Frame.",
				type = "toggle",
				order = 44,
				width = 0.8,
				disabled = function()
					return not self.db.profile.ufEnabled
				end,
				get = function(info)
					return self.db.profile.ufStyleFocus
				end,
				set = function(info, val)
					self.db.profile.ufStyleFocus = val
					ActionHud:GetModule("UnitFrames"):UpdateLayout()
				end,
			},
		},
	}

	-- SUB: Trinkets
	local trinketOptions = {
		name = "Trinkets",
		handler = ActionHud,
		type = "group",
		args = {
			enable = {
				name = "Enable",
				desc = "Enable the sidecar Trinket module.",
				type = "toggle",
				order = 1,
				get = function(info)
					return self.db.profile.trinketsEnabled
				end,
				set = function(info, val)
					self.db.profile.trinketsEnabled = val
					ActionHud:GetModule("Trinkets"):UpdateLayout()
				end,
			},
			sizingHeader = { name = "Sizing & Positioning", type = "header", order = 10 },
			iconWidth = {
				name = "Icon Width",
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 11,
				get = function(info)
					return self.db.profile.trinketsIconWidth
				end,
				set = function(info, val)
					self.db.profile.trinketsIconWidth = val
					ActionHud:GetModule("Trinkets"):UpdateLayout()
				end,
			},
			iconHeight = {
				name = "Icon Height",
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 12,
				get = function(info)
					return self.db.profile.trinketsIconHeight
				end,
				set = function(info, val)
					self.db.profile.trinketsIconHeight = val
					ActionHud:GetModule("Trinkets"):UpdateLayout()
				end,
			},
			fontHeader = { name = "Typography", type = "header", order = 20 },
			timerFontSize = {
				name = "Timer Font Size",
				type = "select",
				order = 21,
				values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
				sorting = { "small", "medium", "large", "huge" },
				get = function(info)
					return self.db.profile.trinketsTimerFontSize or "medium"
				end,
				set = function(info, val)
					self.db.profile.trinketsTimerFontSize = val
					ActionHud:GetModule("Trinkets"):UpdateLayout()
				end,
			},
		},
	}

	-- SUB: Layout
	-- Helper to get LayoutManager
	local function GetLayoutManager()
		return ActionHud:GetModule("LayoutManager", true)
	end

	-- Helper to trigger layout update
	local function TriggerLayoutUpdate()
		local LM = GetLayoutManager()
		if LM then
			LM:TriggerLayoutUpdate()
		end
	end

	-- Build dynamic layout options based on current stack order
	local function BuildLayoutArgs()
		local args = {}
		local LM = GetLayoutManager()
		if not LM then
			return args
		end

		-- HUD Stack Section (first)
		args.stackHeader = { type = "header", name = "HUD Stack Order", order = 1 }
		args.showOutlines = {
			name = "Show Layout Outlines",
			desc = "Show semi-transparent boxes and labels for all HUD modules to help with positioning.",
			type = "toggle",
			order = 1.5,
			width = "full",
			get = function()
				return ActionHud.db.profile.showLayoutOutlines
			end,
			set = function(_, val)
				ActionHud.db.profile.showLayoutOutlines = val
				ActionHud:RefreshLayout()
			end,
		}
		args.stackDesc = {
			type = "description",
			order = 2,
			name = "Arrange modules from top to bottom. Use arrows to reorder. Gap defines spacing after each module.\n ",
		}

		local stack = LM:GetStack()
		local gaps = LM:GetGaps()
		local baseOrder = 10

		-- Filter enabled modules for the UI list
		local activeModules = {}
		for i, moduleId in ipairs(stack) do
			local moduleName = moduleId
			if moduleId == "actionBars" then
				moduleName = "ActionBars"
			elseif moduleId == "resources" then
				moduleName = "Resources"
			elseif moduleId == "cooldowns" then
				moduleName = "Cooldowns"
			end

			local m = ActionHud:GetModule(moduleName, true)
			local isEnabled = false
			if moduleId == "resources" then
				isEnabled = ActionHud.db.profile.resEnabled
			elseif moduleId == "cooldowns" then
				isEnabled = ActionHud.db.profile.cdEnabled
					and LibStub("AceAddon-3.0"):GetAddon("ActionHud"):GetModule("Cooldowns"):IsEnabled()
			elseif m and m.IsEnabled then
				isEnabled = m:IsEnabled()
			end

			if isEnabled then
				table.insert(activeModules, { id = moduleId, stackIdx = i })
			end
		end

		for i, modInfo in ipairs(activeModules) do
			local moduleId = modInfo.id
			local stackIdx = modInfo.stackIdx
			local moduleName = LM:GetModuleName(moduleId)
			local orderBase = baseOrder + (i * 10)

			-- Module row header with position number
			args["mod_" .. i .. "_header"] = {
				type = "description",
				order = orderBase,
				name = string.format("|cffffcc00%d.|r |cffffffff%s|r", i, moduleName),
				fontSize = "medium",
				width = "full",
			}

			-- Move Up button
			args["mod_" .. i .. "_up"] = {
				name = "Up",
				desc = "Move " .. moduleName .. " up in the stack",
				type = "execute",
				order = orderBase + 1,
				width = 0.4,
				disabled = function()
					return i == 1
				end,
				func = function()
					LM:MoveModule(moduleId, "up")
					-- Force AceConfig to rebuild the options
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Layout")
				end,
			}

			-- Move Down button
			args["mod_" .. i .. "_down"] = {
				name = "Down",
				desc = "Move " .. moduleName .. " down in the stack",
				type = "execute",
				order = orderBase + 2,
				width = 0.4,
				disabled = function()
					return i == #activeModules
				end,
				func = function()
					LM:MoveModule(moduleId, "down")
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Layout")
				end,
			}

			-- Gap slider (not shown for last ACTIVE module)
			if i < #activeModules then
				args["mod_" .. i .. "_gap"] = {
					name = "Gap After",
					desc = string.format("Space between %s and the next module.", moduleName),
					type = "range",
					min = 0,
					max = 50,
					step = 1,
					order = orderBase + 3,
					width = 1.0,
					get = function()
						local g = LM:GetGaps()
						return g[stackIdx] or 0
					end,
					set = function(_, val)
						LM:SetGap(stackIdx, val)
					end,
				}
			end

			-- Spacer line
			args["mod_" .. i .. "_spacer"] = {
				type = "description",
				order = orderBase + 5,
				name = " ",
				width = "full",
			}
		end

		-- Reset button (inside HUD Stack section)
		args.resetBtn = {
			name = "Reset to Default Order",
			desc = "Restore the default module order and gap values.",
			type = "execute",
			order = 99,
			width = "double",
			func = function()
				LM:ResetToDefault()
				LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Layout")
			end,
		}

		-- Trinkets Positioning Section
		args.trinketsHeader = { type = "header", name = "Trinkets Positioning", order = 100 }
		args.trinketsXOffset = {
			name = "X Offset",
			desc = "Horizontal position relative to HUD center.",
			type = "range",
			min = -400,
			max = 400,
			step = 1,
			order = 101,
			get = function()
				return ActionHud.db.profile.trinketsXOffset
			end,
			set = function(_, val)
				ActionHud.db.profile.trinketsXOffset = val
				ActionHud:GetModule("Trinkets"):UpdateLayout()
			end,
		}
		args.trinketsYOffset = {
			name = "Y Offset",
			desc = "Vertical position relative to HUD center.",
			type = "range",
			min = -400,
			max = 400,
			step = 1,
			order = 102,
			get = function()
				return ActionHud.db.profile.trinketsYOffset
			end,
			set = function(_, val)
				ActionHud.db.profile.trinketsYOffset = val
				ActionHud:GetModule("Trinkets"):UpdateLayout()
			end,
		}

		-- Tracked Abilities Section
		args.trackedHeader = { type = "header", name = "Tracked Abilities", order = 120 }
		args.trackedDesc = {
			type = "description",
			order = 121,
			name = [[These frames are styled by ActionHud but positioned via Blizzard's EditMode:
• Tracked Buffs
• Tracked Bars
• External Defensives
]],
		}
		args.openEditMode = {
			name = "Open EditMode",
			desc = "Open Blizzard's EditMode to position and resize Tracked Abilities frames.",
			type = "execute",
			order = 122,
			width = "normal",
			func = function()
				if EditModeManagerFrame then
					EditModeManagerFrame:Show()
				end
			end,
		}

		return args
	end

	-- Use a function for layoutOptions so AceConfig rebuilds it each time
	-- This makes the UI rows visually reorder when modules are moved
	local function GetLayoutOptions()
		return {
			name = "Layout",
			handler = ActionHud,
			type = "group",
			args = BuildLayoutArgs(),
		}
	end

	local debugOptions = {
		name = "Debugging",
		handler = ActionHud,
		type = "group",
		args = {
			toolsHeader = { type = "header", name = "Tools", order = 1 },
			refresh = {
				name = "Force Layout Update",
				type = "execute",
				order = 2,
				func = function()
					for _, mName in ipairs({
						"ActionBars",
						"Resources",
						"Cooldowns",
						"TrackedBars",
						"TrackedBuffs",
						"Trinkets",
					}) do
						local m = ActionHud:GetModule(mName, true)
						if m and m.UpdateLayout then
							m:UpdateLayout()
						end
					end
					print("ActionHud: Layout Refreshed.")
				end,
			},
			scan = {
				name = "Scan for New Frames",
				desc = "Scans all global frames for 'Viewer' or 'Tracked' names and logs them.",
				type = "execute",
				order = 3,
				func = function()
					local Manager = ns.CooldownManager
					if Manager and Manager.FindPotentialTargets then
						Manager:FindPotentialTargets()
					end
				end,
			},
			dumpBuffInfo = {
				name = "Dump Buff/Bar Info",
				desc = "Prints all tracked buff/bar spell IDs and linkedSpellIDs to chat. Use /ah dump as shortcut.",
				type = "execute",
				order = 4,
				func = function()
					local Manager = ns.CooldownManager
					if Manager and Manager.DumpTrackedBuffInfo then
						Manager:DumpTrackedBuffInfo()
					end
				end,
			},
			showBlizzardFrames = {
				name = "Show Native Blizzard Frames (Cooldown Manager)",
				desc = "Show both Blizzard's cooldown frames and ActionHud proxies side-by-side for comparison.",
				type = "toggle",
				order = 5,
				width = "full",
				get = function(info)
					return self.db.profile.debugShowBlizzardFrames
				end,
				set = function(info, val)
					self.db.profile.debugShowBlizzardFrames = val
					ActionHud:GetModule("Cooldowns"):UpdateLayout()
				end,
			},

			filtersHeader = { type = "header", name = "Troubleshooting & Discovery Filters", order = 10 },
			discovery = {
				name = "Debug Discovery",
				desc = "Logs when new Blizzard widgets are found and hijacked.",
				type = "toggle",
				order = 11,
				get = function(info)
					return self.db.profile.debugDiscovery
				end,
				set = function(info, val)
					self.db.profile.debugDiscovery = val
				end,
			},
			frames = {
				name = "Debug Frames",
				desc = "Logs detailed information about frame hierarchies and children.",
				type = "toggle",
				order = 12,
				get = function(info)
					return self.db.profile.debugFrames
				end,
				set = function(info, val)
					self.db.profile.debugFrames = val
				end,
			},
			events = {
				name = "Debug Events",
				desc = "Logs key HUD events to the chat window.",
				type = "toggle",
				order = 13,
				get = function(info)
					return self.db.profile.debugEvents
				end,
				set = function(info, val)
					self.db.profile.debugEvents = val
				end,
			},
			proxy = {
				name = "Debug Proxies",
				desc = "Logs detailed information about tracked buff/bar population and aura changes.",
				type = "toggle",
				order = 14,
				get = function(info)
					return self.db.profile.debugProxy
				end,
				set = function(info, val)
					self.db.profile.debugProxy = val
				end,
			},
			layout = {
				name = "Debug Layout",
				desc = "Logs layout positioning calculations including stack order, heights, gaps, and Y offsets.",
				type = "toggle",
				order = 15,
				get = function(info)
					return self.db.profile.debugLayout
				end,
				set = function(info, val)
					self.db.profile.debugLayout = val
				end,
			},
			containers = {
				name = "Debug Containers",
				desc = "Shows colored backgrounds behind the Hud containers to verify their positions.",
				type = "toggle",
				order = 16,
				get = function(info)
					return self.db.profile.debugContainers
				end,
				set = function(info, val)
					self.db.profile.debugContainers = val
					local modules =
						{ "ActionBars", "Resources", "Cooldowns", "TrackedBars", "TrackedBuffs", "TrackedDefensives" }
					for _, mName in ipairs(modules) do
						local m = ActionHud:GetModule(mName, true)
						if m and m.UpdateLayout then
							m:UpdateLayout()
						end
					end
				end,
			},

			recordingHeader = { type = "header", name = "Debug Recording", order = 30 },
			recordingStatus = {
				type = "description",
				order = 31,
				name = function()
					local count = ActionHud:GetDebugBufferCount()
					local status = ActionHud:IsDebugRecording() and "|cff00ff00Recording...|r" or "|cffaaaaaaStopped|r"

					local activeTypes = {}
					local p = ActionHud.db.profile
					if p.debugDiscovery then
						table.insert(activeTypes, "Discovery")
					end
					if p.debugFrames then
						table.insert(activeTypes, "Frames")
					end
					if p.debugEvents then
						table.insert(activeTypes, "Events")
					end
					if p.debugProxy then
						table.insert(activeTypes, "Proxies")
					end
					if p.debugLayout then
						table.insert(activeTypes, "Layout")
					end

					local activeStr = #activeTypes > 0 and table.concat(activeTypes, ", ") or "|cffff4444None|r"

					return string.format(
						"%s (%d entries buffered)\n|cffaaaaaaActive filters:|r %s",
						status,
						count,
						activeStr
					)
				end,
			},
			recordButton = {
				name = "Record",
				desc = "Start recording debug messages to the buffer.",
				type = "execute",
				order = 32,
				width = "half",
				hidden = function()
					return ActionHud:IsDebugRecording()
				end,
				func = function()
					ActionHud:StartDebugRecording()
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Debug")
				end,
			},
			stopButton = {
				name = "Stop",
				desc = "Stop recording debug messages.",
				type = "execute",
				order = 33,
				width = "half",
				hidden = function()
					return not ActionHud:IsDebugRecording()
				end,
				func = function()
					ActionHud:StopDebugRecording()
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Debug")
				end,
			},
			clearDebug = {
				name = "Clear",
				desc = "Clears the debug buffer without copying.",
				type = "execute",
				order = 34,
				width = "half",
				func = function()
					ActionHud:ClearDebugBuffer()
					LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Debug")
				end,
			},
			logField = {
				name = "Debug Log",
				desc = "Recorded debug messages. Select all and copy to export.",
				type = "input",
				multiline = 15,
				width = "full",
				order = 40,
				get = function()
					return ActionHud:GetDebugText()
				end,
				set = function() end, -- Read-only
			},
		},
	}

	-- Register settings panels in logical order
	-- 1. General settings
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud", generalOptions)
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud", "ActionHud")

	-- 2. Layout (overall HUD structure) - early so users see it
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Layout", GetLayoutOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Layout", "Layout", "ActionHud")

	-- 3-4. Core HUD components (inline stacked)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_AB", abOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_AB", "Action Bars", "ActionHud")

	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Res", resOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Res", "Resource Bars", "ActionHud")

	-- 5-7. Cooldown Manager components (grouped together)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_CD", cdOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_CD", "Cooldown Manager", "ActionHud")

	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Tracked", trackedOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Tracked", "Tracked Abilities", "ActionHud")

	-- 7. Unit Frames (Player/Target/Focus)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_UnitFrames", unitFrameOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_UnitFrames", "Unit Frames", "ActionHud")

	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Trinkets", trinketOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Trinkets", "Trinkets", "ActionHud")

	-- 9-10. Meta settings
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Profiles", profiles)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Profiles", "Profiles", "ActionHud")

	-- Only show Debugging panel in dev mode (DevMarker.lua excluded from CurseForge packages)
	if ns.IS_DEV_MODE then
		LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Debug", debugOptions)
		LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Debug", "Debugging", "ActionHud")
	end
end
