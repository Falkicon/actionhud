local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
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
		self:Print("|cff00ff00[DEV MODE]|r " .. L["[DEV MODE] Running from git clone"])
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
		print(
			"|cff33ff99"
				.. L["ActionHud:"]
				.. "|r "
				.. string.format(L["Debug recording auto-stopped (buffer cap of %d reached)."], DEBUG_BUFFER_CAP)
		)
	end
end

function ActionHud:StartDebugRecording()
	debugRecording = true
	print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Debug recording started."])
end

function ActionHud:StopDebugRecording()
	debugRecording = false
	print(
		"|cff33ff99"
			.. L["ActionHud:"]
			.. "|r "
			.. string.format(L["Debug recording stopped (%d entries buffered)."], #debugBuffer)
	)
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
	print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Debug buffer cleared."])
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
		print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Settings cannot be opened while in combat."])
		return false
	end

	if Settings and Settings.OpenToCategory then
		local targetName = categoryName or "ActionHud"
		local categoryID

		-- Prefer explicit category object if we have it
		if self.optionsFrame then
			categoryID = self.optionsFrame
		end

		-- Try to find the numeric category ID explicitly if we don't have the object
		if not categoryID and SettingsPanel and SettingsPanel.GetAllCategories then
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
		pcall(InterfaceOptionsFrame_OpenToCategory, self.optionsFrame or categoryName or "ActionHud")
	elseif Settings and Settings.OpenToCategory then
		-- In 11.0+, passing a string to OpenToCategory can cause a C-level crash/error
		-- if it can't be converted to a numeric ID. Prefer the category object.
		pcall(Settings.OpenToCategory, self.optionsFrame or categoryName or "ActionHud")
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
			print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Cooldown Manager not available."])
		end
		return
	end

	if msg == "reset" then
		-- Reset profile to defaults
		self.db:ResetProfile()
		print("|cff33ff99" .. L["ActionHud:"] .. "|r Profile reset to defaults. /reload to apply.")
		return
	end

	if msg == "wipe" then
		-- Nuclear option: wipe entire database
		ActionHudDB = nil
		print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["SavedVariables wiped. /reload required."])
		return
	end

	if msg == "testapi" then
		self:RunMidnightAPITest()
		return
	end

	-- Default: open main settings
	self:OpenSettings()
end

-- Diagnostic test for Midnight APIs and whitelists
function ActionHud:RunMidnightAPITest()
	local build, buildNum, buildDate, uiVersion = GetBuildInfo()
	print(string.format("|cff33ff99ActionHud:|r %s (%s, Build %s, UI %s)", L["Testing Midnight APIs..."], build, buildNum, uiVersion))

	-- 1. Capability Status
	print("|cff33ff99" .. L["Detected Capabilities:"] .. "|r")
	local caps = {
		{ name = L["IS_MIDNIGHT (Internal)"], val = Utils.IS_MIDNIGHT },
		{ name = L["IsRoyal"], val = Utils.Cap.IsRoyal },
		{ name = L["HasSecondsFormatter"], val = Utils.Cap.HasSecondsFormatter },
		{ name = L["HasHealCalculator"], val = Utils.Cap.HasHealCalculator },
		{ name = L["IsAuraLegacy"], val = Utils.Cap.IsAuraLegacy },
		{ name = L["HasBooleanColor"], val = Utils.Cap.HasBooleanColor },
		{ name = L["HasDurationUtil"], val = _G.C_DurationUtil ~= nil },
		{ name = L["HasSecrecyQueries"], val = (_G.C_Secrets ~= nil or _G.GetSpellAuraSecrecy ~= nil) },
	}
	for _, cap in ipairs(caps) do
		local color = cap.val and "|cff00ff00" or "|cffffcc00"
		print(string.format("%s- %s:|r %s", color, cap.name, cap.val and L["Yes"] or L["No"]))
	end

	-- 2. Readiness Score (Simple heuristic)
	-- 2. Readiness Score (Comprehensive 12.0 scoring)
	local readiness = 0
	if Utils.IS_MIDNIGHT then
		-- Capability Checks (60 pts)
		if Utils.Cap.HasSecondsFormatter then readiness = readiness + 10 end
		if Utils.Cap.HasHealCalculator then readiness = readiness + 10 end
		if not Utils.Cap.IsAuraLegacy then readiness = readiness + 10 end
		if Utils.Cap.HasBooleanColor then readiness = readiness + 10 end
		if Utils.Cap.HasDurationUtil then readiness = readiness + 10 end
		if Utils.Cap.HasSecrecyQueries then readiness = readiness + 10 end

		-- Basic Secrecy Tests (20 pts)
		local cp = GetComboPoints("player", "target")
		if not Utils.IsValueSecret(cp) then readiness = readiness + 10 end
		
		local ss = UnitPower("player", Enum.PowerType.SoulShards)
		if not Utils.IsValueSecret(ss) then readiness = readiness + 10 end

		-- Whitelist & Duration Object Tests (20 pts)
		local cd = C_Spell.GetSpellCooldown(61304)
		if cd and cd.duration and not Utils.IsValueSecret(cd.duration) then readiness = readiness + 10 end

		if C_DurationUtil and C_DurationUtil.CreateDuration then
			local dur = C_DurationUtil.CreateDuration()
			if dur and (dur.GetRemainingDuration or dur.EvaluateRemainingDuration) then
				readiness = readiness + 10
			end
		end
	else
		readiness = 100 -- Fully ready on legacy clients
	end

	local readinessColor = "|cff00ff00"
	if readiness < 50 then
		readinessColor = "|cffff0000"
	elseif readiness < 100 then
		readinessColor = "|cffffcc00"
	end

	print(string.format("|cff33ff99" .. L["Royal Readiness Score:"] .. "|r %s%d%%|r", readinessColor, readiness))

	if Utils.Cap.IsRoyal then
		print("|cff00ff00- " .. L["Styling Status:"] .. "|r " .. L["Active (Phase 7 Restoration)"])
	else
		print("|cff00ff00- " .. L["Styling Status:"] .. "|r " .. L["Active"])
	end

	-- 3. Detailed Secrecy Tests
	print("|cff33ff99" .. L["Security System Tests:"] .. "|r")

	-- Test GCD Whitelist (Spell 61304)
	if _G.issecretvalue then
		local cd = C_Spell.GetSpellCooldown(61304)
		if cd and cd.duration and _G.issecretvalue(cd.duration) then
			print("|cffff0000- " .. L["GCD Whitelist:"] .. "|r " .. L["FAILED (GCD is still secret)"])
		else
			print("|cff00ff00- " .. L["GCD Whitelist:"] .. "|r " .. L["OK (GCD is readable)"])
		end
	end

	-- Test Combo Points Secrecy
	local cp = GetComboPoints("player", "target")
	if _G.issecretvalue and _G.issecretvalue(cp) then
		print("|cffff0000- " .. L["Combo Points:"] .. "|r " .. L["PROTECTED (Secret)"])
	else
		print("|cff00ff00- " .. L["Combo Points:"] .. "|r " .. L["OK (Readable)"])
	end

	-- Test Soul Shards Secrecy
	local ss = UnitPower("player", Enum.PowerType.SoulShards)
	local ss_max = UnitPowerMax("player", Enum.PowerType.SoulShards)
	if _G.issecretvalue and _G.issecretvalue(ss) then
		print("|cffff0000- " .. L["Soul Shards:"] .. "|r " .. L["PROTECTED (Secret)"])
	else
		local raw = UnitPower("player", Enum.PowerType.SoulShards, true)
		local mod = (UnitPowerDisplayMod and UnitPowerDisplayMod(Enum.PowerType.SoulShards)) or 100
		local val = (mod ~= 0) and (raw / mod) or ss
		local mval = tonumber(ss_max) or "???"
		print(string.format("|cff00ff00- %s|r %s (%.2f/%s)", L["Soul Shards:"], L["OK (Readable)"], val, mval))
	end

	-- Test New Duration Objects
	if C_DurationUtil and C_DurationUtil.CreateDuration then
		local dur = C_DurationUtil.CreateDuration()
		if dur and (dur.GetRemainingDuration or dur.EvaluateRemainingDuration) then
			print("|cff00ff00- " .. L["Duration Objects:"] .. "|r " .. L["OK"])
		else
			print("|cffffcc00- " .. L["Duration Objects:"] .. "|r " .. L["Missing Methods"])
		end
	else
		print("|cffffcc00- " .. L["Duration Objects:"] .. "|r " .. L["Not found"])
	end

	print("|cff33ff99ActionHud:|r " .. L["API test complete."])
end
