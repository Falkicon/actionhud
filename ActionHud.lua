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

local defaults = ns.defaults

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
	self:ApplyRootPosition()
	self:UpdateLockState()

	for _, module in self:IterateModules() do
		if module.ApplyEnabledState then
			module:ApplyEnabledState()
		end
	end

	local LM = self:GetModule("LayoutManager", true)
	if LM then
		if LM.MigrateOldSettings then
			LM:MigrateOldSettings()
		end
		LM:TriggerLayoutUpdate()
	end
end

function ActionHud:RefreshLayout()
	local layoutMode = self.db.profile.showLayoutOutlines

	for _, module in self:IterateModules() do
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

function ActionHud:IsLoggingEnabled()
	local mechanic = LibStub("MechanicLib-1.0", true)
	return self.db and self.db.profile.debugDiscovery == true
		and mechanic and mechanic:IsEnabled() or false
end

function ActionHud:Logf(debugType, pattern, ...)
	if self:IsLoggingEnabled() then
		self:Log(string.format(pattern, ...), debugType)
	end
end

function ActionHud:Log(msg, debugType)
	if not self:IsLoggingEnabled() then return end
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
		-- Use the shared draggable-container metadata for layout outlines.
		local DraggableContainer = ns.DraggableContainer
		local color = { r = 0.5, g = 0.5, b = 0.5 }
		if DraggableContainer and DraggableContainer.MODULE_COLORS and moduleId then
			color = DraggableContainer.MODULE_COLORS[moduleId] or color
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
		if not InCombatLockdown() and not self.db.profile.locked then
			s:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function()
		self._pendingDragStop = true
		self:ApplyRootPosition()
	end)

	-- HUD background when layout unlocked (50% black for visibility)
	f.dragBg = f:CreateTexture(nil, "BACKGROUND")
	f.dragBg:SetAllPoints()
	f.dragBg:SetColorTexture(0, 0, 0, 0.5)
	f.dragBg:Hide()

	self.frame = f
end

function ActionHud:ApplyRootPosition()
	if not self.frame then
		return
	end
	if InCombatLockdown() then
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "ApplyRootPosition")
		return
	end
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local p = self.db.profile
	if self._pendingDragStop then
		self._pendingDragStop = nil
		self.frame:StopMovingOrSizing()
		local x, y = self.frame:GetCenter()
		local px, py = UIParent:GetCenter()
		local scale = UIParent:GetEffectiveScale() / self.frame:GetEffectiveScale()
		p.xOffset = x - px * scale
		p.yOffset = y - py * scale
	end
	self.frame:ClearAllPoints()
	self.frame:SetPoint("CENTER", UIParent, "CENTER", p.xOffset or 0, p.yOffset or -220)
	self:UpdateLockState()
end

function ActionHud:ApplySettings()
	self:ApplyRootPosition()
	self.frame:Show()
	self:UpdateLockState()

	local LM = self:GetModule("LayoutManager", true)
	if LM then
		LM:RequestLayout("settings")
	end
end

function ActionHud:UpdateLockState()
	local p = self.db.profile
	local locked = p.locked
	local layoutUnlocked = p.layoutUnlocked

	-- Can't modify secure frame properties during combat
	if InCombatLockdown() then
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "ApplyRootPosition")
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
	if msg == "perf" or msg:match("^perf%s") then
		local performance = ns.Performance
		local command = msg:match("^perf%s+(%S+)$") or "report"
		if command == "on" then
			performance:Reset()
			performance:SetEnabled(true)
			self:Print(L["Performance recording started."])
		elseif command == "off" then
			performance:SetEnabled(false)
			self:Print(L["Performance recording stopped. Results retained."])
		elseif command == "reset" then
			performance:Reset()
			self:Print(L["Performance counters reset."])
		elseif command == "report" then
			local metrics = performance:GetMetrics()
			if #metrics == 0 then self:Print(L["No performance samples. Use /ah perf on to start."]) end
			for _, metric in ipairs(metrics) do
				self:Print(string.format(L["%s: %d calls, %.3f ms total, %.3f ms average, %.3f ms peak"],
					metric.name, metric.calls, metric.totalMs, metric.averageMs, metric.peakMs))
			end
		else
			self:Print(L["Usage: /ah perf on, off, reset, or report"])
		end
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
			for frameId in pairs(p.ufConfig) do
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
