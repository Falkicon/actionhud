-- Settings/init.lua
-- Core settings initialization and shared helpers

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")

-- Initialize Settings namespace
ns.Settings = {}

-- Constants
local CVAR_COOLDOWN_VIEWER_ENABLED = "cooldownViewerEnabled"

-- ============================================================================
-- Shared Helper Functions
-- ============================================================================

-- Helper to check if Blizzard's Cooldown Manager is enabled
function ns.Settings.IsBlizzardCooldownViewerEnabled()
	if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
		return CVarCallbackRegistry:GetCVarValueBool(CVAR_COOLDOWN_VIEWER_ENABLED)
	end
	-- Fallback for older clients
	local val = GetCVar(CVAR_COOLDOWN_VIEWER_ENABLED)
	return val == "1"
end

-- Helper to open the Gameplay Enhancements (Advanced Options) settings panel
function ns.Settings.OpenGameplayEnhancements()
	if Settings and Settings.OpenToCategory then
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
		print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["ActionHud: Navigate to Gameplay Enhancements."])
		return true
	end
	return false
end

-- ============================================================================
-- General Options (Root Panel)
-- ============================================================================

function ns.Settings.BuildGeneralOptions(self)
	return {
		name = "ActionHud",
		handler = ActionHud,
		type = "group",
		args = {
			minimapIcon = {
				name = L["Show Minimap Icon"],
				desc = L["Toggle the minimap icon."],
				type = "toggle",
				order = 2,
				hidden = function()
					return not self.icon
				end,
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
			divider = { type = "header", name = L["Info & Prerequisites"], order = 10 },
			readme = {
				type = "description",
				name = string.format(
					"|cff33ff99%s|r\n\n%s\n\n|cffffcc00%s|r\n%s\n\n%s\n  - |cffffffff%s|r %s\n  - |cffffffff%s|r %s\n  \n%s",
					L["ActionHud 2.6.2"],
					L["A minimalist HUD mirroring Action Bars 1 & 2 in a 6x4 grid."],
					L["Required Setup:"],
					L["Click the button below to open WoW's Gameplay Enhancements settings."],
					L["Enable these options:"],
					L["Assisted Highlight"],
					L["(rotation glows)"],
					L["Enable Cooldown Manager"],
					L["(tracked cooldowns)"],
					L["Use Advanced Cooldown Settings to configure which spells are tracked."]
				),
				fontSize = "medium",
				order = 11,
			},
			btnPreReq1 = {
				name = L["Open Gameplay Enhancements"],
				desc = L["Opens WoW Settings directly to Gameplay Enhancements."],
				type = "execute",
				width = "double",
				func = function()
					ns.Settings.OpenGameplayEnhancements()
				end,
				order = 12,
			},
			helpHeader = { type = "header", name = L["Help & Slash Commands"], order = 20 },
			helpCommands = {
				type = "description",
				name = string.format(
					"|cffffcc00%s|r\n  - |cffffffff%s|r\n  - |cffffffff%s|r\n  - |cffffffff%s|r\n  - |cffffffff%s|r\n\n|cffffcc00%s|r\n%s",
					L["Slash Commands:"],
					L["/ah: Open settings."],
					L["/ah debug: Toggle debug recording."],
					L["/ah clear: Clear debug buffer."],
					L["/ah dump: Dump tracked spell info to chat."],
					L["Debugging & Layout:"],
					L["Use the Layout tab to enable Show Layout Outlines. This helps position frames when they are empty or out of combat."]
				),
				fontSize = "medium",
				order = 21,
			},
		},
	}
end

-- ============================================================================
-- SetupOptions - Main entry point
-- ============================================================================

function ActionHud:SetupOptions()
	-- Build all options tables
	local generalOptions = ns.Settings.BuildGeneralOptions(self)
	local abOptions = ns.Settings.BuildActionBarsOptions(self)
	local resOptions = ns.Settings.BuildResourcesOptions(self)
	local cdOptions = ns.Settings.BuildCooldownsOptions(self)
	local trackedOptions = ns.Settings.BuildTrackedOptions(self)
	local customUfOptions = ns.Settings.BuildUnitFramesOptions(self)
	local trinketOptions = ns.Settings.BuildTrinketsOptions(self)
	local GetLayoutOptions = ns.Settings.BuildLayoutOptions(self)

	-- Register all options with AceConfig
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud", generalOptions)
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud", "ActionHud")

	-- 2. Layout (Stack Order)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Layout", GetLayoutOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Layout", L["Layout"], "ActionHud")

	-- 3. Action Bars
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_AB", abOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_AB", L["Action Bars"], "ActionHud")

	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Res", resOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Res", L["Resource Bars"], "ActionHud")

	-- 5. Cooldown Manager
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_CD", cdOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_CD", L["Cooldown Manager"], "ActionHud")

	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Tracked", trackedOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Tracked", L["Tracked Abilities"], "ActionHud")

	-- 7. Unit Frames (Player/Target/Focus)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_UnitFrames", customUfOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_UnitFrames", L["Unit Frames"], "ActionHud")

	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Trinkets", trinketOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Trinkets", L["Trinkets"], "ActionHud")

	-- 9-10. Meta settings
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Profiles", profiles)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Profiles", L["Profiles"], "ActionHud")
end
