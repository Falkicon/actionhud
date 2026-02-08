-- ActionHud.lua
-- Main addon entry point and initialization

local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local ActionHud = LibStub("AceAddon-3.0"):NewAddon("ActionHud", "AceEvent-3.0", "AceConsole-3.0")
_G.ActionHud = ActionHud
local Utils = ns.Utils

-- Development mode detection (set by DevMarker.lua which is excluded from CurseForge packages)
local IS_DEV_MODE = ns.IS_DEV_MODE or false
ns.IS_DEV_MODE = IS_DEV_MODE

-- ============================================================================
-- Profile Defaults
-- ============================================================================

local defaults = {
	profile = {
		locked = true,
		iconWidth = 20,
		iconHeight = 17,
		opacity = 0.0,
		procGlowAlpha = 0.75,
		assistGlowAlpha = 0.65,
		cooldownFontSize = 8,
		countFontSize = 8,
		actionBarsIncludeInStack = true, -- Whether Action Bars are in HUD stack
		actionBarsXOffset = 0, -- X offset for independent mode positioning
		actionBarsYOffset = 0, -- Y offset for independent mode positioning
		resEnabled = true,
		resHealthEnabled = true,
		resPowerEnabled = true,
		resClassEnabled = true,
		resShowTarget = true,
		resPosition = "TOP",
		resHealthHeight = 6,
		resPowerHeight = 3,
		resClassHeight = 3,
		resShowPredict = true,
		resShowAbsorbs = true,
		resOffset = 1,
		resSpacing = 0,
		resGap = 2,
		resBarWidth = nil, -- nil = use HUD width, number = fixed width
		xOffset = 0,
		yOffset = -220,
		cdEnabled = true,
		cdPosition = "BOTTOM",
		cdSpacing = 2,
		cdReverse = false,
		cdGap = 4,
		cdItemGap = 0,
		cdEssentialWidth = 20,
		cdEssentialHeight = 20,
		cdUtilityWidth = 20,
		cdUtilityHeight = 20,
		cdCountFontSize = 10,
		cdTimerFontSize = "medium",
		cdHideBlizzardViewer = true, -- Hide Blizzard's CooldownViewer when our module is active

		-- Essential Cooldowns (native Blizzard viewer positioning)
		essentialCooldownsEnabled = true,
		essentialCooldownsIncludeInStack = true,
		essentialCooldownsXOffset = 0,
		essentialCooldownsYOffset = -100,
		essentialCooldownsIconSize = 36,
		essentialCooldownsColumns = 8,

		-- Utility Cooldowns (native Blizzard viewer positioning)
		utilityCooldownsEnabled = true,
		utilityCooldownsIncludeInStack = true,
		utilityCooldownsXOffset = 0,
		utilityCooldownsYOffset = -140,
		utilityCooldownsIconSize = 36,
		utilityCooldownsColumns = 8,

		-- Per-module HUD alignment (LEFT, CENTER, RIGHT)
		resourcesAlignment = "CENTER",
		essentialCooldownsAlignment = "CENTER",
		utilityCooldownsAlignment = "CENTER",

		-- Tracked Buffs (container-based positioning)
		styleTrackedBuffs = true,
		buffsXOffset = 0,
		buffsYOffset = -180,
		buffsIconSize = 36,
		buffsSpacingH = 2,
		buffsSpacingV = 2,
		buffsColumns = 8,
		buffsBorderEnabled = true,
		buffsBorderColor = { 0, 0, 0, 1 },
		buffsBorderSize = 1,
		buffsBackgroundEnabled = false,
		buffsBackgroundColor = { 0, 0, 0, 0.5 },
		buffsCountFontSize = 10,
		buffsTimerFontSize = "medium",
		buffsHideBlizzardFrame = true, -- Hide Blizzard's buff viewer when our module is active
		trackedBuffsIncludeInStack = false, -- Whether TrackedBuffs module is in HUD stack

		-- Tracked Defensives (container-based positioning, 12.0+ only)
		styleExternalDefensives = true,
		defensivesXOffset = 0,
		defensivesYOffset = -260,
		defensivesIconSize = 32,
		defensivesSpacingH = 2,
		defensivesSpacingV = 2,
		defensivesColumns = 8,
		defensivesBorderEnabled = true,
		defensivesBorderColor = { 0, 0, 0, 1 },
		defensivesBorderSize = 1,
		defensivesBackgroundEnabled = false,
		defensivesBackgroundColor = { 0, 0, 0, 0.5 },
		defensivesCountFontSize = 9,
		defensivesTimerFontSize = "small",

		-- Unit Frames (Player/Target/Focus)
		ufEnabled = false,
		ufHideBlizzard = false, -- Hide Blizzard PlayerFrame/TargetFrame/FocusFrame
		ufShowAllIcons = false, -- Show all status icons for testing/placement
		ufPlayerXOffset = -189,
		ufPlayerYOffset = 13,
		ufTargetXOffset = 210,
		ufTargetYOffset = 13,
		ufFocusXOffset = -353,
		ufFocusYOffset = 19,
		ufTargettargetXOffset = 370,
		ufTargettargetYOffset = 13,
		ufHealthHeight = 30,
		ufPowerHeight = 10,
		ufWidth = 200,
		ufConfig = {
			player = {
				enabled = true,
				width = 150,
				height = 50,
				xOffset = -189,
				yOffset = 13,
				font = "Arial Narrow", -- Top-level font for all text elements
				bgColor = { r = 0, g = 0, b = 0 },
				bgOpacity = 0.4,
				borderColor = { r = 0, g = 0, b = 0 },
				borderOpacity = 0,
				borderSize = 1,
				powerBarEnabled = true,
				powerBarHeight = 6,
				classBarEnabled = true,
				classBarHeight = 6,
				textPaddingH = 4,
				textPaddingV = 2,
				iconMargin = 2,
				healthText = {
					name = {
						enabled = true,
						position = "TopLeft",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					level = {
						enabled = true,
						position = "TopRight",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					value = {
						enabled = true,
						position = "Center",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					-- Percent display removed due to Midnight secret value issues
				},
				powerText = {
					value = {
						enabled = false,
						position = "Left",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					percent = {
						enabled = false,
						position = "Right",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
				},
				iconMargin = 0,
				icons = {
					combat = { enabled = true, position = "TopLeft", size = 16, offsetX = -10, offsetY = 0 },
					resting = { enabled = true, position = "TopLeft", size = 16, offsetX = -10, offsetY = 10 },
					pvp = { enabled = true, position = "Left", size = 16, offsetX = -11, offsetY = 5 },
					leader = { enabled = true, position = "TopCenter", size = 16, offsetX = 0, offsetY = 10 },
					role = { enabled = true, position = "Right", size = 16, offsetX = 0, offsetY = 5 },
					guide = { enabled = true, position = "TopCenter", size = 16, offsetX = 0, offsetY = 13 },
					mainTank = { enabled = true, position = "BottomRight", size = 16, offsetX = 0, offsetY = 5 },
					mainAssist = { enabled = true, position = "BottomRight", size = 16, offsetX = 0, offsetY = 2 },
					vehicle = { enabled = true, position = "TopRight", size = 16, offsetX = 0, offsetY = 10 },
					phased = { enabled = false, position = "BottomCenter", size = 16, offsetX = 0, offsetY = 5 },
					summon = { enabled = true, position = "BottomCenter", size = 32, offsetX = 0, offsetY = 0 },
					readyCheck = { enabled = true, position = "Center", size = 32, offsetX = 0, offsetY = 3 },
				},
			},
			target = {
				enabled = true,
				width = 150,
				height = 50,
				xOffset = 210,
				yOffset = 13,
				font = "Arial Narrow", -- Top-level font for all text elements
				bgColor = { r = 0, g = 0, b = 0 },
				bgOpacity = 0.4,
				borderColor = { r = 0, g = 0, b = 0 },
				borderOpacity = 0,
				borderSize = 1,
				powerBarEnabled = true,
				powerBarHeight = 6,
				classBarEnabled = false,
				classBarHeight = 6,
				textPaddingH = 4,
				textPaddingV = 2,
				iconMargin = 2,
				healthText = {
					name = {
						enabled = true,
						position = "TopLeft",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					level = {
						enabled = true,
						position = "TopRight",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					value = {
						enabled = true,
						position = "Center",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					-- Percent display removed due to Midnight secret value issues
				},
				powerText = {
					value = {
						enabled = false,
						position = "Left",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					-- Percent display removed due to Midnight secret value issues
				},
				iconMargin = 0,
				icons = {
					combat = { enabled = false, position = "TopLeft", size = 16, offsetX = -10, offsetY = 0 },
					resting = { enabled = false, position = "TopLeft", size = 16, offsetX = -10, offsetY = 10 },
					pvp = { enabled = true, position = "Left", size = 16, offsetX = -11, offsetY = 5 },
					leader = { enabled = true, position = "TopCenter", size = 16, offsetX = 0, offsetY = 10 },
					role = { enabled = true, position = "Right", size = 16, offsetX = 0, offsetY = 5 },
					guide = { enabled = true, position = "TopCenter", size = 16, offsetX = 0, offsetY = 13 },
					mainTank = { enabled = true, position = "BottomRight", size = 16, offsetX = 0, offsetY = 5 },
					mainAssist = { enabled = true, position = "BottomRight", size = 16, offsetX = 0, offsetY = 2 },
					vehicle = { enabled = true, position = "TopRight", size = 16, offsetX = 0, offsetY = 10 },
					phased = { enabled = true, position = "BottomCenter", size = 16, offsetX = 0, offsetY = 5 },
					summon = { enabled = false, position = "BottomCenter", size = 32, offsetX = 0, offsetY = 0 },
					readyCheck = { enabled = false, position = "Center", size = 32, offsetX = 0, offsetY = 3 },
				},
			},
			focus = {
				enabled = false,
				width = 150,
				height = 35,
				xOffset = -353,
				yOffset = 19,
				font = "Arial Narrow", -- Top-level font for all text elements
				bgColor = { r = 0, g = 0, b = 0 },
				bgOpacity = 0.4,
				borderColor = { r = 0, g = 0, b = 0 },
				borderOpacity = 0,
				borderSize = 1,
				powerBarEnabled = true,
				powerBarHeight = 6,
				classBarEnabled = false,
				classBarHeight = 6,
				textPaddingH = 4,
				textPaddingV = 2,
				iconMargin = 2,
				healthText = {
					name = {
						enabled = true,
						position = "TopLeft",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					level = {
						enabled = true,
						position = "TopRight",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					value = {
						enabled = true,
						position = "BottomCenter",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					-- Percent display removed due to Midnight secret value issues
				},
				powerText = {
					value = {
						enabled = false,
						position = "Left",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					-- Percent display removed due to Midnight secret value issues
				},
				iconMargin = 0,
				icons = {
					combat = { enabled = false, position = "TopLeft", size = 14, offsetX = -10, offsetY = 0 },
					resting = { enabled = false, position = "TopLeft", size = 14, offsetX = -10, offsetY = 10 },
					pvp = { enabled = true, position = "Left", size = 14, offsetX = -11, offsetY = 5 },
					leader = { enabled = true, position = "TopCenter", size = 14, offsetX = 0, offsetY = 10 },
					role = { enabled = true, position = "Right", size = 14, offsetX = 0, offsetY = 5 },
					guide = { enabled = false, position = "TopCenter", size = 14, offsetX = 0, offsetY = 13 },
					mainTank = { enabled = true, position = "BottomRight", size = 14, offsetX = 0, offsetY = 5 },
					mainAssist = { enabled = false, position = "BottomRight", size = 14, offsetX = 0, offsetY = 2 },
					vehicle = { enabled = false, position = "TopRight", size = 14, offsetX = 0, offsetY = 10 },
					phased = { enabled = true, position = "BottomCenter", size = 14, offsetX = 0, offsetY = 5 },
					summon = { enabled = false, position = "BottomCenter", size = 28, offsetX = 0, offsetY = 0 },
					readyCheck = { enabled = false, position = "Center", size = 28, offsetX = 0, offsetY = 3 },
				},
			},
			targettarget = {
				enabled = false,
				width = 150,
				height = 50,
				xOffset = 370,
				yOffset = 13,
				font = "Arial Narrow",
				bgColor = { r = 0, g = 0, b = 0 },
				bgOpacity = 0.4,
				borderColor = { r = 0, g = 0, b = 0 },
				borderOpacity = 0,
				borderSize = 1,
				powerBarEnabled = true,
				powerBarHeight = 6,
				classBarEnabled = false,
				classBarHeight = 6,
				textPaddingH = 4,
				textPaddingV = 2,
				iconMargin = 2,
				healthText = {
					name = {
						enabled = true,
						position = "TopLeft",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					level = {
						enabled = true,
						position = "TopRight",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					value = {
						enabled = true,
						position = "Center",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					-- Percent display removed due to Midnight secret value issues
				},
				powerText = {
					value = {
						enabled = false,
						position = "Left",
						xOffset = 0,
						yOffset = 0,
						font = "Arial Narrow",
						size = 11,
						outline = "NONE",
						colorMode = "white",
					},
					-- Percent display removed due to Midnight secret value issues
				},
				iconMargin = 0,
				icons = {
					combat = { enabled = false, position = "TopLeft", size = 16, offsetX = -10, offsetY = 0 },
					resting = { enabled = false, position = "TopLeft", size = 16, offsetX = -10, offsetY = 10 },
					pvp = { enabled = true, position = "Left", size = 16, offsetX = -11, offsetY = 5 },
					leader = { enabled = true, position = "TopCenter", size = 16, offsetX = 0, offsetY = 10 },
					role = { enabled = true, position = "Right", size = 16, offsetX = 0, offsetY = 5 },
					guide = { enabled = true, position = "TopCenter", size = 16, offsetX = 0, offsetY = 13 },
					mainTank = { enabled = true, position = "BottomRight", size = 16, offsetX = 0, offsetY = 5 },
					mainAssist = { enabled = true, position = "BottomRight", size = 16, offsetX = 0, offsetY = 2 },
					vehicle = { enabled = true, position = "TopRight", size = 16, offsetX = 0, offsetY = 10 },
					phased = { enabled = true, position = "BottomCenter", size = 16, offsetX = 0, offsetY = 5 },
					summon = { enabled = false, position = "BottomCenter", size = 32, offsetX = 0, offsetY = 0 },
					readyCheck = { enabled = false, position = "Center", size = 32, offsetX = 0, offsetY = 3 },
				},
			},
		},

		-- Dynamic Layout Settings
		barPriority = "bar1",
		barAlignment = "CENTER",

		-- Minimap Icon (LibDBIcon)
		minimap = {
			hide = false,
		},

		-- Layout (managed by LayoutManager)
		showLayoutOutlines = false,
		layoutUnlocked = false, -- Global lock state for drag positioning

		-- Trinkets Module
		trinketsEnabled = true,
		trinketsIncludeInStack = false, -- Default: independent positioning
		trinketsIconWidth = 32,
		trinketsIconHeight = 32,
		trinketsXOffset = 80,
		trinketsYOffset = 23,
		trinketsTimerFontSize = "medium",
		trinketsGrowDirection = "RIGHT", -- LEFT or RIGHT

		-- Module Stack Inclusion (managed by LayoutManager)
		resourcesIncludeInStack = true,
		cooldownsIncludeInStack = true,

		-- Independent Position Defaults (used when out of stack)
		resourcesXOffset = 0,
		resourcesYOffset = 100,
		cooldownsXOffset = 0,
		cooldownsYOffset = -100,
		buffsXOffset = 0,
		buffsYOffset = -180,
	},
}

-- ============================================================================
-- Initialization
-- ============================================================================

function ActionHud:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("ActionHudDB", defaults, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	-- Migrate old position settings to new layout system
	local LM = self:GetModule("LayoutManager", true)
	if LM and LM.MigrateOldSettings then
		LM:MigrateOldSettings()
	end

	-- Register with Addon Compartment (Blizzard's dropdown menu)
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = "ActionHud",
			icon = "Interface\\Icons\\Ability_DualWield",
			notCheckable = true,
			func = function()
				self:SlashHandler("")
			end,
		})
	end

	self:SetupOptions()
end

function ActionHud:OnProfileChanged()
	self:UpdateLockState()

	local LM = self:GetModule("LayoutManager", true)
	if LM then
		if LM.MigrateOldSettings then
			LM:MigrateOldSettings()
		end
		LM:TriggerLayoutUpdate()
	else
		for name, module in self:IterateModules() do
			if module.UpdateLayout then
				module:UpdateLayout()
			end
			if module.RefreshAll then
				module:RefreshAll()
			end
		end
	end
end

function ActionHud:RefreshLayout()
	local layoutMode = self.db.profile.showLayoutOutlines

	for name, module in self:IterateModules() do
		if module.UpdateLayout then
			module:UpdateLayout()
		end
		if module.SetLayoutMode then
			module:SetLayoutMode(layoutMode)
		end
	end

	local LM = self:GetModule("LayoutManager", true)
	if LM then
		LM:TriggerLayoutUpdate()
	end
end

function ActionHud:OnEnable()
	self:CreateMainFrame()
	self:ApplySettings()

	self:RegisterChatCommand("actionhud", "SlashHandler")
	self:RegisterChatCommand("ah", "SlashHandler")

	if IS_DEV_MODE then
		self:Print("|cff00ff00[DEV MODE]|r " .. L["[DEV MODE] Running from git clone"])
	end
end

-- ============================================================================
-- Logging (delegates to MechanicLib)
-- ============================================================================

-- Safe tostring that handles secret values
local function SafeToString(v)
	if Utils.IsValueSecret(v) then
		return "<secret>"
	end
	return tostring(v)
end

function ActionHud:Log(msg, debugType)
	local safeMsg = SafeToString(msg)
	local MechanicLib = LibStub("MechanicLib-1.0", true)
	if MechanicLib then
		local category = debugType and string.format("[%s]", debugType) or "[General]"
		MechanicLib:Log("ActionHud", safeMsg, category)
	end
end

-- ============================================================================
-- Layout Outline (for debugging)
-- ============================================================================

function ActionHud:UpdateLayoutOutline(frame, labelText, moduleId)
	if not frame then
		return
	end

	local p = self.db.profile
	-- Show outlines when layout is unlocked for positioning
	if p.layoutUnlocked then
		-- Get module color from StackContainer registry
		local StackContainer = ns.StackContainer
		local color = { r = 0.5, g = 0.5, b = 0.5 }
		if StackContainer and StackContainer.MODULE_COLORS and moduleId then
			color = StackContainer.MODULE_COLORS[moduleId] or color
		end

		-- Check if we need to recreate (old BackdropTemplate style or missing bg texture)
		if frame.layoutOutline and not frame.layoutOutline.bg then
			frame.layoutOutline:Hide()
			frame.layoutOutline:SetParent(nil)
			frame.layoutOutline = nil
		end

		if not frame.layoutOutline then
			-- Create simple overlay (no BackdropTemplate, just texture)
			local outline = CreateFrame("Frame", nil, frame)
			outline:SetAllPoints()
			outline:SetFrameLevel(frame:GetFrameLevel() + 50)

			-- Background texture with module color (no border)
			outline.bg = outline:CreateTexture(nil, "BACKGROUND")
			outline.bg:SetAllPoints()
			outline.bg:SetColorTexture(color.r, color.g, color.b, 0.4)

			-- Label with Arial font and outline
			local label = outline:CreateFontString(nil, "OVERLAY")
			label:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
			label:SetPoint("CENTER")
			label:SetText(labelText or "")
			outline.label = label

			frame.layoutOutline = outline
		else
			-- Update existing overlay color
			if frame.layoutOutline.bg then
				frame.layoutOutline.bg:SetColorTexture(color.r, color.g, color.b, 0.4)
			end
		end

		if labelText and frame.layoutOutline.label then
			frame.layoutOutline.label:SetText(labelText)
		end

		if frame:GetWidth() <= 1 or frame:GetHeight() <= 1 then
			frame:SetSize(120, 40)
		end

		frame.layoutOutline:Show()
		frame:Show()
	elseif frame.layoutOutline then
		frame.layoutOutline:Hide()
	end
end

-- ============================================================================
-- Frame Logic (Root Container)
-- ============================================================================

function ActionHud:CreateMainFrame()
	if self.frame then
		return
	end

	local f = CreateFrame("Frame", "ActionHudFrame", UIParent)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")

	f:SetScript("OnDragStart", function(s)
		if not self.db.profile.locked then
			s:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local _, _, _, x, y = s:GetPoint()
		self.db.profile.xOffset = x
		self.db.profile.yOffset = y
	end)

	-- HUD background when layout unlocked (50% black for visibility)
	f.dragBg = f:CreateTexture(nil, "BACKGROUND")
	f.dragBg:SetAllPoints()
	f.dragBg:SetColorTexture(0, 0, 0, 0.5)
	f.dragBg:Hide()

	self.frame = f
end

function ActionHud:ApplySettings()
	local p = self.db.profile
	if p.xOffset and p.yOffset then
		self.frame:ClearAllPoints()
		self.frame:SetPoint("CENTER", p.xOffset, p.yOffset)
	else
		self.frame:SetPoint("CENTER", 0, -220)
	end
	self.frame:Show()
	self:UpdateLockState()

	local LM = self:GetModule("LayoutManager", true)
	if LM then
		C_Timer.After(0.1, function()
			LM:TriggerLayoutUpdate()
		end)
	else
		for name, module in self:IterateModules() do
			if module.UpdateLayout then
				module:UpdateLayout()
			end
		end
	end
end

function ActionHud:UpdateLockState()
	local p = self.db.profile
	local locked = p.locked
	local layoutUnlocked = p.layoutUnlocked

	-- Can't modify secure frame properties during combat
	if InCombatLockdown() then
		return
	end

	-- Enable mouse when HUD is unlocked OR layout is being edited
	self.frame:EnableMouse(not locked or layoutUnlocked)

	-- Show background when either unlocked or layout is being edited
	if locked and not layoutUnlocked then
		self.frame.dragBg:Hide()
	else
		self.frame.dragBg:Show()
	end
end

-- ============================================================================
-- Settings Helper
-- ============================================================================

function ActionHud:OpenSettings(categoryName)
	if InCombatLockdown() then
		print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Settings cannot be opened while in combat."])
		return false
	end

	if Settings and Settings.OpenToCategory then
		local targetName = categoryName or "ActionHud"
		local categoryID

		if self.optionsFrame then
			categoryID = self.optionsFrame
		end

		if not categoryID and SettingsPanel and SettingsPanel.GetAllCategories then
			local categories = SettingsPanel:GetAllCategories()
			for _, cat in ipairs(categories) do
				if cat.GetName and cat:GetName() == targetName then
					categoryID = cat:GetID()
					break
				end
			end

			if not categoryID and categoryName then
				for _, cat in ipairs(categories) do
					local name = cat.GetName and cat:GetName()
					if name and name:find(targetName) then
						categoryID = cat:GetID()
						break
					end
				end
			end
		end

		if not categoryID and targetName ~= "ActionHud" then
			if SettingsPanel and SettingsPanel.GetAllCategories then
				for _, cat in ipairs(SettingsPanel:GetAllCategories()) do
					if cat.GetName and cat:GetName() == "ActionHud" then
						categoryID = cat:GetID()
						break
					end
				end
			end
		end

		if categoryID then
			local ok = pcall(Settings.OpenToCategory, categoryID)
			return ok
		end
	end

	if InterfaceOptionsFrame_OpenToCategory then
		pcall(InterfaceOptionsFrame_OpenToCategory, self.optionsFrame or categoryName or "ActionHud")
	elseif Settings and Settings.OpenToCategory then
		pcall(Settings.OpenToCategory, self.optionsFrame or categoryName or "ActionHud")
	end
end

-- ============================================================================
-- Slash Commands
-- ============================================================================

function ActionHud:SlashHandler(msg)
	msg = msg and msg:trim():lower() or ""

	if msg == "dump" then
		local Manager = ns.CooldownManager
		if Manager and Manager.DumpTrackedBuffInfo then
			Manager:DumpTrackedBuffInfo()
		else
			print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Cooldown Manager not available."])
		end
		return
	end

	if msg == "reset" then
		self.db:ResetProfile()
		print("|cff33ff99" .. L["ActionHud:"] .. "|r Profile reset to defaults. /reload to apply.")
		return
	end

	if msg == "wipe" then
		ActionHudDB = nil
		print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["SavedVariables wiped. /reload required."])
		return
	end

	if msg == "positions" or msg == "pos" then
		print("|cff33ff99ActionHud:|r Current module/frame positions:")
		local p = self.db.profile

		-- Main HUD position
		print("-- Main HUD")
		print(string.format("hudXOffset = %d,", p.hudXOffset or 0))
		print(string.format("hudYOffset = %d,", p.hudYOffset or 0))

		-- Unit Frames
		print("-- Unit Frames")
		if p.ufConfig then
			for frameId, cfg in pairs(p.ufConfig) do
				local xKey = "uf" .. frameId:sub(1, 1):upper() .. frameId:sub(2) .. "XOffset"
				local yKey = "uf" .. frameId:sub(1, 1):upper() .. frameId:sub(2) .. "YOffset"
				print(string.format("%s = %d, %s = %d, -- %s", xKey, p[xKey] or 0, yKey, p[yKey] or 0, frameId))
			end
		end

		-- Cooldown modules
		print("-- Cooldowns")
		local cdKeys = { "essential", "utility", "buffs", "defensives" }
		for _, key in ipairs(cdKeys) do
			local xKey = key .. "XOffset"
			local yKey = key .. "YOffset"
			if p[xKey] or p[yKey] then
				print(string.format("%s = %d, %s = %d,", xKey, p[xKey] or 0, yKey, p[yKey] or 0))
			end
		end

		-- Action Bars
		print("-- Action Bars")
		local abKeys = { "actionBarsXOffset", "actionBarsYOffset" }
		if p.actionBarsXOffset or p.actionBarsYOffset then
			print(
				string.format(
					"actionBarsXOffset = %d, actionBarsYOffset = %d,",
					p.actionBarsXOffset or 0,
					p.actionBarsYOffset or 0
				)
			)
		end

		-- Trinkets
		print("-- Trinkets")
		if p.trinketsXOffset or p.trinketsYOffset then
			print(
				string.format(
					"trinketsXOffset = %d, trinketsYOffset = %d,",
					p.trinketsXOffset or 0,
					p.trinketsYOffset or 0
				)
			)
		end

		print("|cff33ff99ActionHud:|r Copy above to update defaults in ActionHud.lua")
		return
	end

	-- Default: open main settings
	self:OpenSettings()
end
