-- Settings/UnitFrames.lua
-- Unit Frames settings options

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")

function ns.Settings.BuildUnitFramesOptions(self)
	-- Helper to copy frame config
	local function CopyFrameConfig(fromId, toId)
		if not fromId or not toId or fromId == toId then
			return
		end
		local source = ActionHud.db.profile.ufConfig[fromId]
		if source then
			-- Deep copy the configuration
			ActionHud.db.profile.ufConfig[toId] = ns.Utils.DeepCopy(source)
			local mod = ActionHud:GetModule("UnitFrames", true)
			if mod and mod:IsEnabled() then
				mod:UpdateLayout()
			end
			LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_UnitFrames")
		end
	end

	-- Helper to generate options for a single icon
	local function GetIconGroup(frameId, iconType, iconName, iconOrder)
		return {
			name = iconName,
			type = "group",
			order = iconOrder,
			inline = true,
			args = {
				enabled = {
					name = L["Enable"],
					type = "toggle",
					order = 1,
					get = function()
						local db = self.db.profile.ufConfig[frameId]
						return db and db.icons and db.icons[iconType] and db.icons[iconType].enabled
					end,
					set = function(_, val)
						local db = self.db.profile.ufConfig[frameId]
						if db and db.icons and db.icons[iconType] then
							db.icons[iconType].enabled = val
							ActionHud:GetModule("UnitFrames"):UpdateLayout()
						end
					end,
				},
				position = {
					name = L["Position"],
					type = "select",
					order = 2,
					values = {
						TopLeft = L["Top Left"],
						TopCenter = L["Top Center"],
						TopRight = L["Top Right"],
						Left = L["Left"],
						Center = L["Center"],
						Right = L["Right"],
						BottomLeft = L["Bottom Left"],
						BottomCenter = L["Bottom Center"],
						BottomRight = L["Bottom Right"],
					},
					get = function()
						local db = self.db.profile.ufConfig[frameId]
						return db and db.icons and db.icons[iconType] and db.icons[iconType].position
					end,
					set = function(_, val)
						local db = self.db.profile.ufConfig[frameId]
						if db and db.icons and db.icons[iconType] then
							db.icons[iconType].position = val
							ActionHud:GetModule("UnitFrames"):UpdateLayout()
						end
					end,
				},
				size = {
					name = L["Size"],
					type = "range",
					min = 4,
					max = 64,
					step = 1,
					order = 3,
					get = function()
						local db = self.db.profile.ufConfig[frameId]
						return db and db.icons and db.icons[iconType] and db.icons[iconType].size
					end,
					set = function(_, val)
						local db = self.db.profile.ufConfig[frameId]
						if db and db.icons and db.icons[iconType] then
							db.icons[iconType].size = val
							ActionHud:GetModule("UnitFrames"):UpdateLayout()
						end
					end,
				},
				offsetX = {
					name = L["X Offset"],
					type = "range",
					min = -50,
					max = 50,
					step = 1,
					order = 4,
					get = function()
						local db = self.db.profile.ufConfig[frameId]
						return db and db.icons and db.icons[iconType] and db.icons[iconType].offsetX
					end,
					set = function(_, val)
						local db = self.db.profile.ufConfig[frameId]
						if db and db.icons and db.icons[iconType] then
							db.icons[iconType].offsetX = val
							ActionHud:GetModule("UnitFrames"):UpdateLayout()
						end
					end,
				},
				offsetY = {
					name = L["Y Offset"],
					type = "range",
					min = -50,
					max = 50,
					step = 1,
					order = 5,
					get = function()
						local db = self.db.profile.ufConfig[frameId]
						return db and db.icons and db.icons[iconType] and db.icons[iconType].offsetY
					end,
					set = function(_, val)
						local db = self.db.profile.ufConfig[frameId]
						if db and db.icons and db.icons[iconType] then
							db.icons[iconType].offsetY = val
							ActionHud:GetModule("UnitFrames"):UpdateLayout()
						end
					end,
				},
			},
		}
	end

	-- Helper to generate options for a single frame
	local function GetFrameOptions(frameId, frameName, order)
		local function GetTextGroup(category, textType, textName, textOrder)
			return {
				name = textName,
				type = "group",
				inline = true,
				order = textOrder,
				args = {
					enabled = {
						name = L["Enable"],
						type = "toggle",
						order = 1,
						get = function()
							local db = self.db.profile.ufConfig[frameId]
							return db and db[category] and db[category][textType] and db[category][textType].enabled
						end,
						set = function(_, val)
							local db = self.db.profile.ufConfig[frameId]
							if db and db[category] and db[category][textType] then
								db[category][textType].enabled = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end
						end,
					},
					position = {
						name = L["Position"],
						type = "select",
						order = 2,
						values = {
							TopLeft = L["Top Left"],
							TopCenter = L["Top Center"],
							TopRight = L["Top Right"],
							Left = L["Left"],
							Center = L["Center"],
							Right = L["Right"],
							BottomLeft = L["Bottom Left"],
							BottomCenter = L["Bottom Center"],
							BottomRight = L["Bottom Right"],
						},
						get = function()
							local db = self.db.profile.ufConfig[frameId]
							return db and db[category] and db[category][textType] and db[category][textType].position
						end,
						set = function(_, val)
							local db = self.db.profile.ufConfig[frameId]
							if db and db[category] and db[category][textType] then
								db[category][textType].position = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end
						end,
					},
					font = {
						name = L["Font"],
						type = "select",
						order = 3,
						dialogControl = "LSM30_Font",
						values = LSM:HashTable("font"),
						get = function()
							local db = self.db.profile.ufConfig[frameId]
							return db and db[category] and db[category][textType] and db[category][textType].font
						end,
						set = function(_, val)
							local db = self.db.profile.ufConfig[frameId]
							if db and db[category] and db[category][textType] then
								db[category][textType].font = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end
						end,
					},
					size = {
						name = L["Font Size"],
						type = "range",
						min = 6,
						max = 32,
						step = 1,
						order = 4,
						get = function()
							local db = self.db.profile.ufConfig[frameId]
							return db and db[category] and db[category][textType] and db[category][textType].size
						end,
						set = function(_, val)
							local db = self.db.profile.ufConfig[frameId]
							if db and db[category] and db[category][textType] then
								db[category][textType].size = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end
						end,
					},
					outline = {
						name = L["Font Outline"],
						type = "select",
						order = 5,
						values = {
							NONE = L["None"],
							OUTLINE = L["Outline"],
							THICKOUTLINE = L["Thick Outline"],
							MONOCHROME = L["Monochrome"],
						},
						get = function()
							local db = self.db.profile.ufConfig[frameId]
							return db and db[category] and db[category][textType] and db[category][textType].outline
						end,
						set = function(_, val)
							local db = self.db.profile.ufConfig[frameId]
							if db and db[category] and db[category][textType] then
								db[category][textType].outline = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end
						end,
					},
					colorMode = {
						name = L["Color Mode"],
						type = "select",
						order = 6,
						values = { custom = L["Custom"], class = L["Class"], reaction = L["Reaction"] },
						get = function()
							local db = self.db.profile.ufConfig[frameId]
							return db and db[category] and db[category][textType] and db[category][textType].colorMode
						end,
						set = function(_, val)
							local db = self.db.profile.ufConfig[frameId]
							if db and db[category] and db[category][textType] then
								db[category][textType].colorMode = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end
						end,
					},
					color = {
						name = L["Color"],
						type = "color",
						order = 7,
						hasAlpha = false,
						hidden = function()
							local db = self.db.profile.ufConfig[frameId]
							return not (db and db[category] and db[category][textType] and db[category][textType].colorMode == "custom")
						end,
						get = function()
							local db = self.db.profile.ufConfig[frameId]
							local c = db and db[category] and db[category][textType] and db[category][textType].color
							return c and c.r or 1, c and c.g or 1, c and c.b or 1
						end,
						set = function(_, r, g, b)
							local db = self.db.profile.ufConfig[frameId]
							if db and db[category] and db[category][textType] then
								db[category][textType].color = { r = r, g = g, b = b }
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end
						end,
					},
				},
			}
		end

		return {
			name = frameName,
			type = "group",
			order = order,
			childGroups = "tab",
			args = {
				enableGroup = {
					name = L["Enable"],
					type = "group",
					inline = true,
					order = 1,
					args = {
						enabled = {
							name = L["Enable"],
							type = "toggle",
							order = 1,
							get = function()
								return self.db.profile.ufConfig[frameId].enabled
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].enabled = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						copyFrom = {
							name = L["Copy Settings From"],
							type = "select",
							order = 2,
							values = function()
								local vals = { [""] = L["-- Select --"] }
								if frameId ~= "player" then
									vals.player = L["Player Frame"]
								end
								if frameId ~= "target" then
									vals.target = L["Target Frame"]
								end
								if frameId ~= "focus" then
									vals.focus = L["Focus Frame"]
								end
								return vals
							end,
							get = function()
								return ""
							end,
							set = function(_, val)
								if val ~= "" then
									CopyFrameConfig(val, frameId)
								end
							end,
						},
					},
				},
				dimensions = {
					name = L["Dimensions"],
					type = "group",
					order = 10,
					args = {
						width = {
							name = L["Bar Width"],
							type = "range",
							min = 50,
							max = 500,
							step = 1,
							order = 1,
							get = function()
								return self.db.profile.ufConfig[frameId].width
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].width = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						height = {
							name = L["Height"],
							type = "range",
							min = 10,
							max = 100,
							step = 1,
							order = 2,
							get = function()
								return self.db.profile.ufConfig[frameId].height
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].height = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						xOffset = {
							name = L["X Offset"],
							type = "range",
							min = -800,
							max = 800,
							step = 1,
							order = 3,
							get = function()
								return self.db.profile.ufConfig[frameId].xOffset
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].xOffset = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						yOffset = {
							name = L["Y Offset"],
							type = "range",
							min = -600,
							max = 600,
							step = 1,
							order = 4,
							get = function()
								return self.db.profile.ufConfig[frameId].yOffset
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].yOffset = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
					},
				},
				visuals = {
					name = L["Background & Border"],
					type = "group",
					order = 20,
					args = {
						bgColor = {
							name = L["Background Color"],
							type = "color",
							order = 1,
							get = function()
								local c = self.db.profile.ufConfig[frameId].bgColor
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								self.db.profile.ufConfig[frameId].bgColor = { r = r, g = g, b = b }
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						bgOpacity = {
							name = L["Background Opacity"],
							type = "range",
							min = 0,
							max = 1,
							step = 0.05,
							isPercent = true,
							order = 2,
							get = function()
								return self.db.profile.ufConfig[frameId].bgOpacity
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].bgOpacity = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						borderColor = {
							name = L["Border Color"],
							type = "color",
							order = 3,
							get = function()
								local c = self.db.profile.ufConfig[frameId].borderColor
								return c.r, c.g, c.b
							end,
							set = function(_, r, g, b)
								self.db.profile.ufConfig[frameId].borderColor = { r = r, g = g, b = b }
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						borderOpacity = {
							name = L["Border Opacity"],
							type = "range",
							min = 0,
							max = 1,
							step = 0.05,
							isPercent = true,
							order = 4,
							get = function()
								return self.db.profile.ufConfig[frameId].borderOpacity
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].borderOpacity = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						borderSize = {
							name = L["Border Size"],
							type = "range",
							min = 0,
							max = 10,
							step = 1,
							order = 5,
							get = function()
								return self.db.profile.ufConfig[frameId].borderSize
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].borderSize = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
					},
				},
				bars = {
					name = L["Bars"],
					type = "group",
					order = 30,
					args = {
						powerBarEnabled = {
							name = L["Enable Power Bar"],
							type = "toggle",
							order = 1,
							get = function()
								return self.db.profile.ufConfig[frameId].powerBarEnabled
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].powerBarEnabled = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						powerBarHeight = {
							name = L["Power Bar Height"],
							type = "range",
							min = 0,
							max = 50,
							step = 1,
							order = 2,
							get = function()
								return self.db.profile.ufConfig[frameId].powerBarHeight
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].powerBarHeight = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						classBarEnabled = {
							name = L["Enable Class Bar"],
							type = "toggle",
							order = 3,
							hidden = (frameId ~= "player"),
							get = function()
								return self.db.profile.ufConfig[frameId].classBarEnabled
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].classBarEnabled = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						classBarHeight = {
							name = L["Class Bar Height"],
							type = "range",
							min = 0,
							max = 50,
							step = 1,
							order = 4,
							hidden = (frameId ~= "player"),
							get = function()
								return self.db.profile.ufConfig[frameId].classBarHeight
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].classBarHeight = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
					},
				},
				text = {
					name = L["Typography & Text"],
					type = "group",
					order = 40,
					args = {
						paddingH = {
							name = L["Horizontal Padding"],
							type = "range",
							min = 0,
							max = 20,
							step = 1,
							order = 1,
							get = function()
								return self.db.profile.ufConfig[frameId].textPaddingH
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].textPaddingH = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						paddingV = {
							name = L["Vertical Padding"],
							type = "range",
							min = 0,
							max = 20,
							step = 1,
							order = 2,
							get = function()
								return self.db.profile.ufConfig[frameId].textPaddingV
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].textPaddingV = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						healthHeader = { name = L["Health Text"], type = "header", order = 10 },
						level = GetTextGroup("healthText", "level", L["Level"], 11),
						name = GetTextGroup("healthText", "name", L["Name"], 12),
						value = GetTextGroup("healthText", "value", L["Health Value"], 13),
						percent = GetTextGroup("healthText", "percent", L["Health Percent"], 14),

						powerHeader = { name = L["Power Text"], type = "header", order = 20 },
						powerValue = GetTextGroup("powerText", "value", L["Power Value"], 21),
						powerPercent = GetTextGroup("powerText", "percent", L["Power Percent"], 22),
					},
				},
				icons = {
					name = L["Status Icons"],
					type = "group",
					order = 50,
					args = {
						margin = {
							name = L["Icon Margin"],
							type = "range",
							min = 0,
							max = 20,
							step = 1,
							order = 1,
							get = function()
								return self.db.profile.ufConfig[frameId].iconMargin
							end,
							set = function(_, val)
								self.db.profile.ufConfig[frameId].iconMargin = val
								ActionHud:GetModule("UnitFrames"):UpdateLayout()
							end,
						},
						combat = GetIconGroup(frameId, "combat", L["Combat"], 10),
						resting = GetIconGroup(frameId, "resting", L["Resting"], 11),
						pvp = GetIconGroup(frameId, "pvp", L["PVP"], 12),
						leader = GetIconGroup(frameId, "leader", L["Group Leader"], 13),
						role = GetIconGroup(frameId, "role", L["Role: Tank"] .. "/" .. L["Role: Healer"] .. "/" .. L["Role: DPS"], 14),
						guide = GetIconGroup(frameId, "guide", L["Dungeon Guide"], 15),
						leaderGroup = {
							name = L["Group Management"],
							type = "group",
							inline = true,
							order = 20,
							args = {
								mainTank = GetIconGroup(frameId, "mainTank", L["Main Tank"], 1),
								mainAssist = GetIconGroup(frameId, "mainAssist", L["Main Assist"], 2),
							},
						},
						statusGroup = {
							name = L["Status Indicators"],
							type = "group",
							inline = true,
							order = 30,
							args = {
								vehicle = GetIconGroup(frameId, "vehicle", L["Vehicle"], 1),
								phased = GetIconGroup(frameId, "phased", L["Phased"], 2),
								summon = GetIconGroup(frameId, "summon", L["Summon"], 3),
								readyCheck = GetIconGroup(frameId, "readyCheck", L["Ready Check"], 4),
							},
						},
					},
				},
			},
		}
	end

	-- Build the main options table
	return {
		name = L["Unit Frames"],
		handler = ActionHud,
		type = "group",
		args = {
			note = {
				type = "description",
				order = 0.1,
				name = "|cffffcc00" .. L["Custom Unit Frames"] .. "|r\n" .. L["Custom frames for Player and Target with advanced support for Midnight's 'Secret Values'."] .. "\n",
			},
			enable = {
				name = L["Enable Custom Unit Frames"],
				desc = L["Enable ActionHud custom player and target unit frames. Compatible with Midnight 12.0 secret values."],
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
			player = GetFrameOptions("player", L["Player Frame"], 10),
			target = GetFrameOptions("target", L["Target Frame"], 20),
			focus = GetFrameOptions("focus", L["Focus Frame"], 30),
		},
	}
end
