-- ActionHud Mechanic Integration
-- Tools panel, in-game tests, performance profiling

local addonName, ns = ...
local MechanicLib = LibStub("MechanicLib-1.0", true)
if not MechanicLib then
	return
end
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")

---@class ActionHudMechanic
ActionHudMechanic = {}

-- =============================================================================
-- Tools Panel (Button-based)
-- =============================================================================

local function GetProfile()
	local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
	return addon and addon.db and addon.db.profile
end

local function CreateToolButton(parent, x, y, width, text, onClick)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	btn:SetSize(width, 24)
	btn:SetText(text)
	btn:SetScript("OnClick", onClick)
	return btn
end

local function ToggleModule(moduleName, profileKey, label)
	local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
	local profile = GetProfile()
	local module = addon and addon:GetModule(moduleName, true)
	if not profile or not module or not module.ApplyEnabledState then
		return
	end
	profile[profileKey] = not profile[profileKey]
	module:ApplyEnabledState()
	local layout = addon:GetModule("LayoutManager", true)
	if layout then
		layout:TriggerLayoutUpdate()
	end
	print("|cff00ff00ActionHud:|r " .. label .. " " .. (profile[profileKey] and L["ON"] or L["OFF"]))
end

function ActionHudMechanic:CreateToolsPanel(container)
	local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText(L["ActionHud Tools"])

	local desc = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	desc:SetPoint("TOPLEFT", 10, -35)
	desc:SetText(L["Quick actions for HUD management."])

	-- Row 1: Lock/Unlock & Settings
	local row1Label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row1Label:SetPoint("TOPLEFT", 10, -65)
	row1Label:SetText(L["HUD:"])

	CreateToolButton(container, 80, -60, 80, L["Toggle Lock"], function()
		local profile = GetProfile()
		local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
		if profile then
			profile.locked = not profile.locked
			if addon and addon.UpdateLockState then
				addon:UpdateLockState()
			end
			print("|cff00ff00ActionHud:|r " .. (profile.locked and L["Locked"] or L["Unlocked"]))
		end
	end)

	CreateToolButton(container, 165, -60, 80, L["Settings"], function()
		local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
		if addon then
			addon:OpenSettings()
		end
	end)

	-- Row 2: Module Toggles
	local row2Label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row2Label:SetPoint("TOPLEFT", 10, -100)
	row2Label:SetText(L["Modules:"])

	CreateToolButton(container, 80, -95, 70, L["Resources"], function()
		ToggleModule("Resources", "resEnabled", L["Resources"])
	end)

	CreateToolButton(container, 155, -95, 70, L["Trinkets"], function()
		ToggleModule("Trinkets", "trinketsEnabled", L["Trinkets"])
	end)

	-- Row 3: Debug
	local row3Label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row3Label:SetPoint("TOPLEFT", 10, -135)
	row3Label:SetText(L["Debug:"])

	CreateToolButton(container, 80, -130, 80, L["Record"], function()
		local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
		if addon then
			if addon.IsDebugRecording and addon:IsDebugRecording() then
				addon:StopDebugRecording()
			elseif addon.StartDebugRecording then
				addon:StartDebugRecording()
			end
		end
	end)

	CreateToolButton(container, 165, -130, 80, L["Clear"], function()
		local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
		if addon and addon.ClearDebugBuffer then
			addon:ClearDebugBuffer()
		end
	end)

	-- Footer
	local footer = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("BOTTOM", 0, 10)
	footer:SetText(L["Use /ah or /actionhud for more options."])
end

-- =============================================================================
-- In-Game Tests
-- =============================================================================

ActionHudMechanic.tests = {
	{
		id = "layout_manager",
		name = "Layout Manager Active",
		category = "Core",
		type = "auto",
		description = "Verifies LayoutManager module is loaded and functional.",
	},
	{
		id = "resources_module",
		name = "Resources Module",
		category = "Modules",
		type = "auto",
		description = "Checks Resources bars are initialized.",
	},
	{
		id = "action_bars",
		name = "Action Bars Module",
		category = "Modules",
		type = "auto",
		description = "Checks ActionBars frames are created.",
	},
	{
		id = "midnight_safe",
		name = "Midnight Safety",
		category = "API",
		type = "auto",
		description = "Verifies safe API wrappers are functional.",
	},
}

function ActionHudMechanic:GetTests()
	return self.tests
end

function ActionHudMechanic:RunTest(id)
	local start = debugprofilestop()
	local result = self:GetTestResult(id)
	result.duration = (debugprofilestop() - start) / 1000
	result.id = id
	return result
end

function ActionHudMechanic:GetTestResult(id)
	-- Get addon via AceAddon (not global - it's local in Core.lua)
	local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)

	if id == "layout_manager" then
		local lm = addon and addon:GetModule("LayoutManager", true)
		-- Check for EnsureLayoutData method (stack is in profile, not module)
		local isActive = lm and type(lm.EnsureLayoutData) == "function"
		return {
			passed = isActive,
			message = isActive and "LayoutManager active" or "LayoutManager not found",
			details = {
				{ label = "Module Loaded", value = lm and "Yes" or "No", status = lm and "pass" or "fail" },
				{ label = "Has Methods", value = isActive and "OK" or "nil", status = isActive and "pass" or "fail" },
			},
		}
	elseif id == "resources_module" then
		local res = addon and addon:GetModule("Resources", true)
		local profile = GetProfile()
		local enabled = profile and profile.resEnabled
		-- Check if module is enabled (frames are local variables, not on self)
		local isEnabled = res and res:IsEnabled()
		return {
			passed = res ~= nil,
			message = res and "Resources module loaded" or "Resources not found",
			details = {
				{ label = "Module", value = res and "Loaded" or "nil", status = res and "pass" or "fail" },
				{ label = "Is Enabled", value = isEnabled and "Yes" or "No", status = isEnabled and "pass" or "warn" },
				{ label = "Config Enabled", value = enabled and "Yes" or "No", status = "pass" },
			},
		}
	elseif id == "action_bars" then
		local ab = addon and addon:GetModule("ActionBars", true)
		-- Check if module is enabled
		local isEnabled = ab and ab:IsEnabled()
		return {
			passed = ab ~= nil,
			message = ab and "ActionBars module loaded" or "ActionBars not found",
			details = {
				{ label = "Module", value = ab and "Loaded" or "nil", status = ab and "pass" or "fail" },
				{ label = "Is Enabled", value = isEnabled and "Yes" or "No", status = isEnabled and "pass" or "warn" },
			},
		}
	elseif id == "midnight_safe" then
		local Utils = ns.Utils
		local hasSafeCompare = Utils and Utils.SafeCompare ~= nil
		local testResult = false
		if hasSafeCompare then
			local ok, result = pcall(function()
				return Utils.SafeCompare(5, 3, ">")
			end)
			testResult = ok and result == true
		end
		return {
			passed = testResult,
			message = testResult and "Midnight-safe APIs working" or "Safe APIs not available",
			details = {
				{ label = "Utils Module", value = Utils and "OK" or "nil", status = Utils and "pass" or "fail" },
				{
					label = "SafeCompare",
					value = hasSafeCompare and "OK" or "nil",
					status = hasSafeCompare and "pass" or "fail",
				},
				{
					label = "Test 5>3",
					value = testResult and "Pass" or "Fail",
					status = testResult and "pass" or "fail",
				},
			},
		}
	end

	return { passed = false, message = "Unknown test ID: " .. tostring(id) }
end

-- =============================================================================
-- Performance Profiling
-- =============================================================================

function ActionHudMechanic:RecordPerfMetric(name, duration)
	ns.Performance:Record(name, duration)
end

function ActionHudMechanic:GetPerformanceSubMetrics()
	local rows = {}
	for _, metric in ipairs(ns.Performance:GetMetrics()) do
		rows[#rows + 1] = {
			name = metric.name, ms = metric.averageMs,
			description = string.format(L["%d calls; %.3f ms total; %.3f ms peak"],
				metric.calls, metric.totalMs, metric.peakMs),
		}
	end
	return rows
end

-- =============================================================================
-- MechanicLib Registration
-- =============================================================================

local function RegisterWithMechanic()
	MechanicLib:Register(addonName, {
		version = C_AddOns.GetAddOnMetadata(addonName, "Version"),

		-- Console Integration (use ActionHud's existing debug methods)
		getDebugBuffer = function()
			-- Access the debug buffer via ActionHud's exposed property
			local a = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
			return a and a.debugBuffer or {}
		end,
		clearDebugBuffer = function()
			local a = LibStub("AceAddon-3.0"):GetAddon("ActionHud", true)
			if a and a.debugBuffer then
				wipe(a.debugBuffer)
			end
		end,

		-- Testing Integration
		tests = {
			getAll = function()
				return ActionHudMechanic:GetTests()
			end,
			getCategories = function()
				return { "Core", "Modules", "API" }
			end,
			run = function(id)
				return ActionHudMechanic:RunTest(id)
			end,
			getResult = function(id)
				return ActionHudMechanic:GetTestResult(id)
			end,
		},

		-- Tools Integration
		tools = {
			createPanel = function(container)
				ActionHudMechanic:CreateToolsPanel(container)
			end,
		},

		-- Performance Profiling
		performance = {
			getSubMetrics = function()
				return ActionHudMechanic:GetPerformanceSubMetrics()
			end,
		},

		-- Settings Integration
		settings = {
			debugMode = {
				type = "toggle",
				name = L["Debug Mode"],
				desc = L["Enable verbose debug logging"],
				get = function()
					local profile = GetProfile()
					return profile and profile.debugDiscovery
				end,
				set = function(v)
					local profile = GetProfile()
					if profile then
						profile.debugDiscovery = v
					end
				end,
			},
		},
	})
end

-- Hook into addon load
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, loadedAddon)
	if loadedAddon == addonName then
		-- Delay registration slightly to ensure ActionHud is fully initialized
		C_Timer.After(0, RegisterWithMechanic)
		loader:UnregisterEvent("ADDON_LOADED")
	end
end)
