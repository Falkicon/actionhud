-- Settings/Resources.lua
-- Resource Bars settings options

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

-- Helper to check if module is in stack
local function IsInStack()
	local LM = ActionHud:GetModule("LayoutManager", true)
	return LM and LM:IsModuleInStack("resources")
end

function ns.Settings.BuildResourcesOptions(self)
	return {
		name = L["Resource Bars"],
		handler = ActionHud,
		type = "group",
		args = {
			enable = {
				name = L["Enable"],
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
			hideOutOfCombat = {
				name = L["Hide Out of Combat"],
				type = "toggle",
				order = 1.1,
				desc = L["Hide the resource bars when not in combat."],
				get = function(info)
					return self.db.profile.resHideOutOfCombat
				end,
				set = function(info, val)
					self.db.profile.resHideOutOfCombat = val
					local Res = ActionHud:GetModule("Resources", true)
					if Res then
						Res:UpdateCombatVisibility()
					end
				end,
			},
			includeInStack = {
				name = L["Include in HUD Stack"],
				desc = L["When enabled, this module will be positioned in the vertical HUD stack. Otherwise, use independent X/Y positioning."],
				type = "toggle",
				order = 1.5,
				width = "full",
				get = function(info)
					return IsInStack()
				end,
				set = function(info, val)
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:SetModuleInStack("resources", val)
					end
				end,
			},
			positionNote = {
				name = L["Position is controlled by Layout tab when in HUD Stack."],
				type = "description",
				order = 1.6,
				hidden = function()
					return not IsInStack()
				end,
			},
			dragNote = {
				name = L["Use the 'Unlock Module Positions' toggle in the Layout tab to drag this module to a new position."],
				type = "description",
				order = 1.7,
				hidden = function()
					return IsInStack()
				end,
			},
			resetPosition = {
				name = L["Reset Position"],
				desc = L["Reset this module to its default position."],
				type = "execute",
				order = 1.8,
				hidden = function()
					return IsInStack()
				end,
				func = function()
					self.db.profile.resourcesXOffset = 0
					self.db.profile.resourcesYOffset = 100
					local DraggableContainer = ns.DraggableContainer
					if DraggableContainer then
						local container = DraggableContainer:GetContainer("resources")
						if container then
							DraggableContainer:UpdatePosition(container)
						end
					end
					local Resources = ActionHud:GetModule("Resources", true)
					if Resources then
						Resources:ApplyLayoutPosition()
					end
				end,
			},
			showTarget = {
				name = L["Show Target Stats"],
				desc = L["Split bars to show target health/power."],
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
				name = "|cffaaaaaa"
					.. L["Note: The width of these bars is automatically matched to the Action Bar grid (Action Bars > Icon Width)."]
					.. "|r",
			},
			commonHeader = { name = L["Common Settings"], type = "header", order = 10 },
			commonGroup = {
				type = "group",
				inline = true,
				name = "",
				order = 11,
				args = {
					gap = {
						name = L["Player-Target Gap"],
						desc = L["Space between player and target bars."],
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
						name = L["Bar Spacing"],
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
					useFixedWidth = {
						name = L["Use Fixed Width"],
						desc = L["When enabled, use a fixed width instead of matching the HUD width."],
						type = "toggle",
						order = 3,
						get = function(info)
							return self.db.profile.resBarWidth and self.db.profile.resBarWidth > 0
						end,
						set = function(info, val)
							if val then
								self.db.profile.resBarWidth = 200 -- Default fixed width
							else
								self.db.profile.resBarWidth = nil
							end
							self:RefreshLayout()
						end,
					},
					barWidth = {
						name = L["Bar Width"],
						desc = L["Fixed width for resource bars."],
						type = "range",
						min = 50,
						max = 600,
						step = 5,
						order = 4,
						hidden = function()
							return not (self.db.profile.resBarWidth and self.db.profile.resBarWidth > 0)
						end,
						get = function(info)
							return self.db.profile.resBarWidth or 200
						end,
						set = function(info, val)
							self.db.profile.resBarWidth = val
							self:RefreshLayout()
						end,
					},
				},
			},
			healthGroup = {
				name = L["Health Bar"],
				type = "group",
				inline = true,
				order = 20,
				args = {
					enable = {
						name = L["Enable"],
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
						name = L["Bar Height"],
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
					showPredict = {
						name = L["Show Heal Prediction"],
						desc = L["Show incoming heals as an overlay on the health bar."],
						type = "toggle",
						order = 3,
						get = function(info)
							return self.db.profile.resShowPredict ~= false
						end,
						set = function(info, val)
							self.db.profile.resShowPredict = val
							self:RefreshLayout()
						end,
					},
					showAbsorbs = {
						name = L["Show Absorbs"],
						desc = L["Show damage absorption shields as an overlay on the health bar."],
						type = "toggle",
						order = 4,
						get = function(info)
							return self.db.profile.resShowAbsorbs ~= false
						end,
						set = function(info, val)
							self.db.profile.resShowAbsorbs = val
							self:RefreshLayout()
						end,
					},
				},
			},
			powerGroup = {
				name = L["Power Bar"],
				type = "group",
				inline = true,
				order = 30,
				args = {
					enable = {
						name = L["Enable"],
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
						name = L["Bar Height"],
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
				name = L["Class Resource"],
				type = "group",
				inline = true,
				order = 40,
				args = {
					enable = {
						name = L["Enable"],
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
						name = L["Bar Height"],
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
end
