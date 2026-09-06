-- Settings/ActionBars.lua
-- Action Bars settings options

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

function ns.Settings.BuildActionBarsOptions(self)
	return {
		name = L["Action Bars"],
		handler = ActionHud,
		type = "group",
		args = {
			enable = {
				name = L["Enable"],
				type = "toggle",
				order = 1,
				desc = L["Enable the main Action Bar Grid."],
				get = function(info)
					return self.db.profile.actionBarsEnabled ~= false
				end,
				set = function(info, val)
					self.db.profile.actionBarsEnabled = val
					ActionHud:GetModule("ActionBars"):ApplyEnabledState()
					self:RefreshLayout()
				end,
			},
			hideOutOfCombat = {
				name = L["Hide Out of Combat"],
				type = "toggle",
				order = 1.1,
				desc = L["Hide the action bars when not in combat."],
				get = function(info)
					return self.db.profile.hideOutOfCombat
				end,
				set = function(info, val)
					self.db.profile.hideOutOfCombat = val
					local AB = ActionHud:GetModule("ActionBars", true)
					if AB then
						AB:UpdateCombatVisibility()
					end
				end,
			},
			actionBarsIncludeInStack = {
				name = L["Include in HUD Stack"],
				desc = L["When enabled, this module is positioned as part of the vertical ActionHud stack. When disabled, it can be positioned independently."],
				type = "toggle",
				order = 1.5,
				width = "full",
				get = function(info)
					return self.db.profile.actionBarsIncludeInStack
				end,
				set = function(info, val)
					self.db.profile.actionBarsIncludeInStack = val
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:TriggerLayoutUpdate()
					end
				end,
			},
			positionNote = {
				name = L["Position is controlled by Layout tab when in HUD Stack."],
				type = "description",
				order = 1.6,
				hidden = function()
					return not self.db.profile.actionBarsIncludeInStack
				end,
			},
			dragNote = {
				name = L["Use the 'Unlock Module Positions' toggle in the Layout tab to drag this module to a new position."],
				type = "description",
				order = 1.7,
				hidden = function()
					return self.db.profile.actionBarsIncludeInStack
				end,
			},
			resetPosition = {
				name = L["Reset Position"],
				desc = L["Reset this module to its default position."],
				type = "execute",
				order = 1.8,
				hidden = function()
					return self.db.profile.actionBarsIncludeInStack
				end,
				func = function()
					local defaults = self.db.defaults.profile
					self.db.profile.actionBarsXOffset = defaults.actionBarsXOffset
					self.db.profile.actionBarsYOffset = defaults.actionBarsYOffset
					local DraggableContainer = ns.DraggableContainer
					if DraggableContainer then
						local container = DraggableContainer:GetContainer("actionBars")
						if container then
							DraggableContainer:UpdatePosition(container)
						end
					end
					ActionHud:GetModule("ActionBars"):UpdateLayout()
				end,
			},
			dimensionsGroup = {
				name = L["Dimensions"],
				type = "group",
				inline = true,
				order = 10,
				args = {
					iconWidth = {
						name = L["Icon Width"],
						desc = L["Width of the action icons."],
						type = "range",
						min = 10,
						max = 50,
						step = 1,
						order = 1,
						get = function(info)
							return self.db.profile.iconWidth
						end,
						set = function(info, val)
							self.db.profile.iconWidth = val
							self:RefreshLayout()
						end,
					},
					iconHeight = {
						name = L["Icon Height"],
						desc = L["Height of the action icons."],
						type = "range",
						min = 10,
						max = 50,
						step = 1,
						order = 2,
						get = function(info)
							return self.db.profile.iconHeight
						end,
						set = function(info, val)
							self.db.profile.iconHeight = val
							self:RefreshLayout()
						end,
					},
				},
			},
			visualsGroup = {
				name = L["Visuals & Opacity"],
				type = "group",
				inline = true,
				order = 20,
				args = {
					opacity = {
						name = L["Background Opacity"],
						desc = L["Opacity of empty slots."],
						type = "range",
						min = 0,
						max = 1,
						step = 0.05,
						isPercent = true,
						order = 1,
						get = function(info)
							return self.db.profile.opacity
						end,
						set = function(info, val)
							self.db.profile.opacity = val
							ActionHud:GetModule("ActionBars"):UpdateOpacity()
						end,
					},
					procGlowAlpha = {
						name = L["Proc Glow Opacity (Yellow)"],
						type = "range",
						min = 0,
						max = 1,
						step = 0.05,
						isPercent = true,
						order = 2,
						get = function(info)
							return self.db.profile.procGlowAlpha
						end,
						set = function(info, val)
							self.db.profile.procGlowAlpha = val
							ActionHud:GetModule("ActionBars"):UpdateLayout()
						end,
					},
					assistGlowAlpha = {
						name = L["Assist Glow Opacity (Blue)"],
						type = "range",
						min = 0,
						max = 1,
						step = 0.05,
						isPercent = true,
						order = 3,
						get = function(info)
							return self.db.profile.assistGlowAlpha
						end,
						set = function(info, val)
							self.db.profile.assistGlowAlpha = val
							ActionHud:GetModule("ActionBars"):UpdateLayout()
						end,
					},
				},
			},
			cooldownsGroup = {
				name = L["Cooldowns"],
				type = "group",
				inline = true,
				order = 25,
				args = {
					showGlobalCooldown = {
						name = L["Show Global Cooldown"],
						desc = L["Show the global cooldown sweep on action icons. Spell cooldowns and charge recovery remain visible when disabled."],
						type = "toggle",
						order = 1,
						get = function()
							return self.db.profile.showGlobalCooldown ~= false
						end,
						set = function(_, val)
							self.db.profile.showGlobalCooldown = val
							self:RefreshLayout()
						end,
					},
					decimalThreshold = {
						name = L["Countdown Decimal Threshold"],
						desc = L["Show tenths of a second below this duration on action and trinket cooldowns. Set to 0 for whole seconds."],
						type = "range",
						min = 0,
						max = 10,
						step = 1,
						order = 2,
						get = function()
							return self.db.profile.cooldownDecimalThreshold or 3
						end,
						set = function(_, val)
							self.db.profile.cooldownDecimalThreshold = val
							self:RefreshLayout()
						end,
					},
				},
			},
			fontsGroup = {
				name = L["Fonts"],
				type = "group",
				inline = true,
				order = 30,
				args = {
					cooldownFontSize = {
						name = L["Cooldown Font Size"],
						type = "range",
						min = 6,
						max = 24,
						step = 1,
						order = 1,
						get = function(info)
							return self.db.profile.cooldownFontSize
						end,
						set = function(info, val)
							self.db.profile.cooldownFontSize = val
							ActionHud:GetModule("ActionBars"):UpdateLayout()
						end,
					},
					countFontSize = {
						name = L["Stack Count Font Size"],
						type = "range",
						min = 6,
						max = 24,
						step = 1,
						order = 2,
						get = function(info)
							return self.db.profile.countFontSize
						end,
						set = function(info, val)
							self.db.profile.countFontSize = val
							ActionHud:GetModule("ActionBars"):UpdateLayout()
						end,
					},
				},
			},
			layoutGroup = {
				name = L["Layout Mirroring"],
				type = "group",
				inline = true,
				order = 40,
				args = {
					barPriority = {
						name = L["Top Bar Priority"],
						desc = L["Choose which bar appears at the top of the HUD stack."],
						type = "select",
						order = 1,
						width = 1.2,
						values = { bar1 = L["Main Bar (Bar 1)"], bar6 = L["Bottom Left Bar (Bar 2)"] },
						get = function(info)
							return self.db.profile.barPriority
						end,
						set = function(info, val)
							self.db.profile.barPriority = val
							ActionHud:GetModule("ActionBars"):UpdateLayout()
						end,
					},
					barAlignment = {
						name = L["Row Alignment"],
						desc = L["Horizontal alignment of the bars within the HUD container."],
						type = "select",
						order = 2,
						width = 0.8,
						values = { LEFT = L["Left"], CENTER = L["Center"], RIGHT = L["Right"] },
						get = function(info)
							return self.db.profile.barAlignment
						end,
						set = function(info, val)
							self.db.profile.barAlignment = val
							ActionHud:GetModule("ActionBars"):UpdateLayout()
						end,
					},
				},
			},
		},
	}
end
