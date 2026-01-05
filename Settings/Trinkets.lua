-- Settings/Trinkets.lua
-- Trinkets settings options

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

-- Helper to check if module is in stack
local function IsInStack()
	local LM = ActionHud:GetModule("LayoutManager", true)
	return LM and LM:IsModuleInStack("trinkets")
end

function ns.Settings.BuildTrinketsOptions(self)
	return {
		name = L["Trinkets"],
		handler = ActionHud,
		type = "group",
		args = {
			enable = {
				name = L["Enable"],
				desc = L["Enable the sidecar Trinket module."],
				type = "toggle",
				order = 1,
				get = function(info)
					return self.db.profile.trinketsEnabled
				end,
				set = function(info, val)
					self.db.profile.trinketsEnabled = val
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:TriggerLayoutUpdate()
					else
						ActionHud:GetModule("Trinkets"):UpdateLayout()
					end
				end,
			},
			includeInStack = {
				name = L["Include in HUD Stack"],
				desc = L["When enabled, Trinkets will be positioned in the vertical HUD stack. Otherwise, use independent X/Y positioning."],
				type = "toggle",
				order = 2,
				width = "full",
				get = function(info)
					return IsInStack()
				end,
				set = function(info, val)
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:SetModuleInStack("trinkets", val)
					end
				end,
			},
			positionHeader = {
				name = L["Position"],
				type = "header",
				order = 10,
				hidden = function() return IsInStack() end,
			},
			positionNote = {
				name = L["Position is controlled by Layout tab when in HUD Stack."],
				type = "description",
				order = 10,
				hidden = function() return not IsInStack() end,
			},
			dragNote = {
				name = L["Use the 'Unlock Module Positions' toggle in the Layout tab to drag this module to a new position."],
				type = "description",
				order = 11,
				hidden = function() return IsInStack() end,
			},
			resetPosition = {
				name = L["Reset Position"],
				desc = L["Reset this module to its default position."],
				type = "execute",
				order = 12,
				hidden = function() return IsInStack() end,
				func = function()
					self.db.profile.trinketsXOffset = 150
					self.db.profile.trinketsYOffset = 0
					local DraggableContainer = ns.DraggableContainer
					if DraggableContainer then
						local container = DraggableContainer:GetContainer("trinkets")
						if container then
							DraggableContainer:UpdatePosition(container)
						end
					end
					ActionHud:GetModule("Trinkets"):UpdateLayout()
				end,
			},
			growDirection = {
				name = L["Grow Direction"],
				desc = L["Direction to add additional trinkets when more than one is equipped."],
				type = "select",
				order = 13,
				hidden = function() return IsInStack() end,
				values = {
					["LEFT"] = L["Left"],
					["RIGHT"] = L["Right"],
				},
				get = function(info)
					return self.db.profile.trinketsGrowDirection or "RIGHT"
				end,
				set = function(info, val)
					self.db.profile.trinketsGrowDirection = val
					ActionHud:GetModule("Trinkets"):UpdateLayout()
				end,
			},
			sizingHeader = { name = L["Sizing"], type = "header", order = 20 },
			iconWidth = {
				name = L["Icon Width"],
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 21,
				get = function(info)
					return self.db.profile.trinketsIconWidth
				end,
				set = function(info, val)
					self.db.profile.trinketsIconWidth = val
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:TriggerLayoutUpdate()
					else
						ActionHud:GetModule("Trinkets"):UpdateLayout()
					end
				end,
			},
			iconHeight = {
				name = L["Icon Height"],
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				order = 22,
				get = function(info)
					return self.db.profile.trinketsIconHeight
				end,
				set = function(info, val)
					self.db.profile.trinketsIconHeight = val
					local LM = ActionHud:GetModule("LayoutManager", true)
					if LM then
						LM:TriggerLayoutUpdate()
					else
						ActionHud:GetModule("Trinkets"):UpdateLayout()
					end
				end,
			},
			fontHeader = { name = L["Typography"], type = "header", order = 30 },
			timerFontSize = {
				name = L["Timer Font Size"],
				type = "select",
				order = 31,
				values = { small = L["Small"], medium = L["Medium"], large = L["Large"], huge = L["Huge"] },
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
end
