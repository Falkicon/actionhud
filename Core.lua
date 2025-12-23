local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):NewAddon("ActionHud", "AceEvent-3.0", "AceConsole-3.0")
_G.ActionHud = ActionHud -- Global for debugging
local Utils = ns.Utils

-- Development mode detection (set by DevMarker.lua which is excluded from CurseForge packages)
local IS_DEV_MODE = ns.IS_DEV_MODE or false
ns.IS_DEV_MODE = IS_DEV_MODE -- Ensure it's available to other modules

local defaults = {
	profile = {
		locked = false,
		iconWidth = 20,
		iconHeight = 17,
		opacity = 0.0,
		procGlowAlpha = 0.75,
		assistGlowAlpha = 0.65,
		cooldownFontSize = 8,
		countFontSize = 8,
		resEnabled = true,
		resHealthEnabled = true,
		resPowerEnabled = true,
		resClassEnabled = true,
		resShowTarget = true,
		resPosition = "TOP",
		resHealthHeight = 6,
		resPowerHeight = 3,
		resClassHeight = 3,
		resOffset = 1,
		resSpacing = 0,
		resGap = 2,
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

		-- Tracked Abilities (style-only, position via EditMode)
		styleTrackedBuffs = true,
		buffsCountFontSize = 10,
		buffsTimerFontSize = "medium",

		styleTrackedBars = true,
		barsCountFontSize = 8,
		barsTimerFontSize = "small",
		barsCompactMode = true, -- Hide bars, show icons only
		barsTimerOnIcon = true, -- Move timer text on top of icon

		styleExternalDefensives = true, -- 12.0+ (Midnight)
		defensivesCountFontSize = 9,
		defensivesTimerFontSize = "small",

		-- Unit Frames Reskin (Player/Target/Focus)
		ufEnabled = false, -- Master toggle for unit frame styling
		ufHidePortraits = true, -- Hide circular portrait images
		ufHideBorders = true, -- Hide frame borders/decorations
		ufFlatBars = true, -- Use flat solid bar texture
		ufHealthHeight = 30, -- Health bar height in pixels
		ufManaHeight = 10, -- Mana/power bar height in pixels
		ufBarScale = 1.0, -- Width scale multiplier
		ufClassBarHeight = 20, -- Class resource bar height
		ufStylePlayer = true, -- Style the Player Frame
		ufStyleTarget = true, -- Style the Target Frame
		ufStyleFocus = true, -- Style the Focus Frame
		ufShowBackground = true, -- Show dark background behind bars
		ufFontName = "Arial Narrow", -- Font for bar text (LibSharedMedia name)
		ufFontSize = 11, -- Font size for bar text

		-- Dynamic Layout Settings
		barPriority = "bar1",
		barAlignment = "CENTER",

		-- Minimap Icon (LibDBIcon)
		minimap = {
			hide = false,
		},

		-- Debugging (Consolidated)
		debugDiscovery = false,
		debugFrames = false,
		debugEvents = false,
		debugShowBlizzardFrames = false,
		debugProxy = false,
		debugLayout = false,
		debugContainers = false,

		-- Layout (managed by LayoutManager)
		-- layout = { stack = {...}, gaps = {...} }
		-- Initialized by LayoutManager:EnsureLayoutData() or migration
		showLayoutOutlines = false,

		-- Trinkets Module
		trinketsEnabled = true,
		trinketsIconWidth = 32,
		trinketsIconHeight = 32,
		trinketsXOffset = 150,
		trinketsYOffset = 0,
		trinketsTimerFontSize = "medium",
	},
}

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

	self:SetupOptions() -- In SettingsUI.lua
end

function ActionHud:OnProfileChanged()
	self:UpdateLockState()

	-- Migrate layout if needed for new profile
	local LM = self:GetModule("LayoutManager", true)
	if LM then
		if LM.MigrateOldSettings then
			LM:MigrateOldSettings()
		end
		LM:TriggerLayoutUpdate()
	else
		-- Fallback: notify modules directly
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

-- Refresh all modules and update the layout
function ActionHud:RefreshLayout()
	for name, module in self:IterateModules() do
		if module.UpdateLayout then
			module:UpdateLayout()
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
		self:Print("|cff00ff00[DEV MODE]|r Running from git clone")
	end
end

-- Debug message buffer for clipboard export
local debugBuffer = {}
local debugRecording = false
local DEBUG_BUFFER_CAP = 1000

function ActionHud:Log(msg, debugType)
	-- Only record if recording is active
	if not debugRecording then
		return
	end

	local p = self.db.profile

	-- Check if this specific debug type is enabled
	local enabled = false
	local shouldPrint = false

	if debugType == "discovery" then
		enabled = p.debugDiscovery
		shouldPrint = enabled
	elseif debugType == "frames" then
		enabled = p.debugFrames
		shouldPrint = enabled
	elseif debugType == "events" then
		enabled = p.debugEvents
		shouldPrint = enabled
	elseif debugType == "proxy" then
		enabled = p.debugProxy
		shouldPrint = enabled
	elseif debugType == "layout" then
		enabled = p.debugLayout
		shouldPrint = enabled
	elseif debugType == "debug" then
		enabled = p.debugDiscovery
		shouldPrint = enabled
	elseif not debugType then
		enabled = true -- General logs
		shouldPrint = p.debugDiscovery -- Only print general to chat if discovery is on
	end

	if not enabled then
		return
	end

	-- Safe tostring that handles secret values (they error on tostring/format)
	local function SafeToString(v)
		if Utils.IsValueSecret(v) then
			return "<secret>"
		end
		return tostring(v)
	end

	local timestamp = date("%H:%M:%S")
	local safeMsg = SafeToString(msg)

	-- Print to chat if enabled for this type
	if shouldPrint then
		print(string.format("|cff33ff99AH[%s]|r %s", debugType or "Debug", safeMsg))
	end

	-- Add to debug buffer (no chat output - buffer only)
	table.insert(debugBuffer, string.format("[%s][%s] %s", timestamp, debugType or "General", safeMsg))

	-- Check buffer cap and auto-stop if reached
	if #debugBuffer >= DEBUG_BUFFER_CAP then
		debugRecording = false
		print("|cff33ff99ActionHud:|r Debug recording auto-stopped (buffer cap of " .. DEBUG_BUFFER_CAP .. " reached).")
	end
end

function ActionHud:StartDebugRecording()
	debugRecording = true
	print("|cff33ff99ActionHud:|r Debug recording started.")
end

function ActionHud:StopDebugRecording()
	debugRecording = false
	print("|cff33ff99ActionHud:|r Debug recording stopped (" .. #debugBuffer .. " entries buffered).")
end

function ActionHud:IsDebugRecording()
	return debugRecording
end

function ActionHud:GetDebugText()
	return table.concat(debugBuffer, "\n")
end

function ActionHud:GetDebugBufferCount()
	return #debugBuffer
end

function ActionHud:ClearDebugBuffer()
	wipe(debugBuffer)
	print("|cff33ff99ActionHud:|r Debug buffer cleared.")
end

function ActionHud:UpdateFrameDebug(frame, color)
	if not frame then
		return
	end

	local p = self.db.profile
	if p.debugContainers then
		if not frame.debugBg then
			frame.debugBg = frame:CreateTexture(nil, "BACKGROUND")
			frame.debugBg:SetAllPoints()
		end
		frame.debugBg:SetColorTexture(color.r, color.g, color.b, 0.5)
		frame.debugBg:Show()
		-- Ensure size is visible for empty containers
		if frame:GetWidth() <= 1 then
			frame:SetSize(100, 100)
		end
	elseif frame.debugBg then
		frame.debugBg:Hide()
	end
end

function ActionHud:UpdateLayoutOutline(frame, labelText)
	if not frame then
		return
	end

	local p = self.db.profile
	if p.showLayoutOutlines then
		if not frame.layoutOutline then
			local outline = CreateFrame("Frame", nil, frame, "BackdropTemplate")
			outline:SetAllPoints()
			outline:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8x8",
				edgeFile = "Interface\\Buttons\\WHITE8x8",
				edgeSize = 1,
			})
			outline:SetBackdropColor(0, 0, 0, 0.4)
			outline:SetBackdropBorderColor(1, 1, 1, 0.6)
			outline:SetFrameLevel(frame:GetFrameLevel() + 50)

			local label = outline:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetPoint("CENTER")
			label:SetText(labelText or "")
			outline.label = label

			frame.layoutOutline = outline
		end

		-- Update label if changed
		if labelText and frame.layoutOutline.label then
			frame.layoutOutline.label:SetText(labelText)
		end

		-- Force visibility and sizing for configuration
		if frame:GetWidth() <= 1 or frame:GetHeight() <= 1 then
			frame:SetSize(120, 40) -- Minimum visible size
		end

		frame.layoutOutline:Show()
		frame:Show() -- Ensure the parent is shown so the outline is visible
	elseif frame.layoutOutline then
		frame.layoutOutline:Hide()
	end
end

-- =========================================================================
-- Frame Logic (Root Container)
-- =========================================================================

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

	-- Drag Bg
	f.dragBg = f:CreateTexture(nil, "BACKGROUND")
	f.dragBg:SetAllPoints()
	f.dragBg:SetColorTexture(0, 1, 0, 0.3)
	f.dragBg:Hide()

	self.frame = f
end

function ActionHud:ApplySettings()
	-- Apply Saved Position
	local p = self.db.profile
	if p.xOffset and p.yOffset then
		self.frame:ClearAllPoints()
		self.frame:SetPoint("CENTER", p.xOffset, p.yOffset)
	else
		self.frame:SetPoint("CENTER", 0, -220)
	end
	self.frame:Show()
	self:UpdateLockState()

	-- Use LayoutManager to coordinate module positioning
	local LM = self:GetModule("LayoutManager", true)
	if LM then
		-- Delay slightly to ensure all modules are initialized
		C_Timer.After(0.1, function()
			LM:TriggerLayoutUpdate()
		end)
	else
		-- Fallback: trigger modules directly
		for name, module in self:IterateModules() do
			if module.UpdateLayout then
				module:UpdateLayout()
			end
		end
	end
end

function ActionHud:UpdateLockState()
	local locked = self.db.profile.locked
	self.frame:EnableMouse(not locked)
	if locked then
		self.frame.dragBg:Hide()
	else
		self.frame.dragBg:Show()
	end
end

-- Helper to open specific settings categories
function ActionHud:OpenSettings(categoryName)
	if InCombatLockdown() then
		print("|cff33ff99ActionHud:|r Settings cannot be opened while in combat.")
		return false
	end

	if Settings and Settings.OpenToCategory then
		local targetName = categoryName or "ActionHud"
		local categoryID

		-- Try to find the numeric category ID explicitly
		if SettingsPanel and SettingsPanel.GetAllCategories then
			local categories = SettingsPanel:GetAllCategories()

			-- First pass: exact match on name
			for _, cat in ipairs(categories) do
				if cat.GetName and cat:GetName() == targetName then
					categoryID = cat:GetID()
					break
				end
			end

			-- Second pass: fuzzy match if sub-category
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

		-- Fallback to root ActionHud if sub-category not found
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

	-- Fallback for older clients or if numeric ID lookup failed
	if InterfaceOptionsFrame_OpenToCategory then
		pcall(InterfaceOptionsFrame_OpenToCategory, categoryName or "ActionHud")
	elseif Settings and Settings.OpenToCategory then
		pcall(Settings.OpenToCategory, categoryName or "ActionHud")
	end
end

function ActionHud:SlashHandler(msg)
	msg = msg and msg:trim():lower() or ""

	-- /ah debug or /ah record now both toggle debug recording
	if msg == "debug" or msg == "record" then
		if debugRecording then
			self:StopDebugRecording()
		else
			self:StartDebugRecording()
		end
		return
	end

	if msg == "clear" then
		self:ClearDebugBuffer()
		return
	end

	if msg == "dump" then
		local Manager = ns.CooldownManager
		if Manager and Manager.DumpTrackedBuffInfo then
			Manager:DumpTrackedBuffInfo()
		else
			print("|cff33ff99ActionHud:|r Cooldown Manager not available.")
		end
		return
	end

	-- Default: open main settings
	self:OpenSettings()
end
