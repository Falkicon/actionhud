local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Cooldowns = addon:NewModule("Cooldowns", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Local upvalues for performance
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local table_insert = table.insert
local CooldownFrame_Set = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear

local activeProxies = {} -- [cooldownID] = proxyFrame

-- Reusable tables to avoid garbage creation
local usedKeysCache = {}
local categoriesCache = {}
local rowProxiesCache = {}

-- Pre-allocated category info tables (reused each frame)
local essentialCatInfo = { name = "Essential", cat = nil, w = 0, h = 0 }
local utilityCatInfo = { name = "Utility", cat = nil, w = 0, h = 0 }

-- Runtime category resolution
local function GetEssentialCategory()
	return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential
end

local function GetUtilityCategory()
	return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility
end

function Cooldowns:OnInitialize()
	self.db = addon.db
end

function Cooldowns:OnEnable()
	-- Skip this legacy module if new native viewer modules are enabled
	local p = addon.db and addon.db.profile
	if p and (p.essentialCooldownsEnabled or p.utilityCooldownsEnabled) then
		addon:Log("Cooldowns: Legacy module disabled - using native viewer modules", "discovery")
		return
	end
	
	addon:Log("Cooldowns:OnEnable - custom replacement mode", "discovery")
	Manager:CreateContainer("cd", "ActionHudCooldownContainer")
	self:UpdateLayout()

	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
	self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
	self:RegisterEvent("SPELL_UPDATE_USABLE", "OnSpellUpdateCooldown")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

	-- IMPORTANT: Use C_Timer.After(0) to escape Blizzard's tainted callback context
	if EventRegistry then
		EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
			C_Timer.After(0, function()
				self:UpdateLayout()
			end)
		end, self)
	end

	-- Single delayed retry in case data provider wasn't ready at OnEnable
	C_Timer.After(0.5, function()
		self:UpdateLayout()
		-- Debug: Report status
		local p = self.db and self.db.profile
		local essentialCat = GetEssentialCategory()
		local utilityCat = GetUtilityCategory()
		local essentialCount = essentialCat and #(Manager:GetCooldownIDsForCategory(essentialCat, "Essential") or {}) or 0
		local utilityCount = utilityCat and #(Manager:GetCooldownIDsForCategory(utilityCat, "Utility") or {}) or 0
		addon:Log(string.format("Cooldowns status: enabled=%s, essential=%d, utility=%d",
			tostring(p and p.cdEnabled), essentialCount, utilityCount), "discovery")
	end)
end

function Cooldowns:OnDisable()
	local container = Manager:GetContainer("cd")
	if container then
		container:Hide()
	end
	-- Pure custom replacement: we never touch Blizzard frames
	-- Users should disable Blizzard's CooldownViewer via Edit Mode if they want ours only
end

-- Calculate the height of this module for LayoutManager
function Cooldowns:CalculateHeight()
	local p = self.db.profile
	if not p.cdEnabled then
		return 0
	end

	-- Custom replacement: we work independently of Blizzard's viewer CVar
	-- The data provider still returns configured spells even when viewer is disabled
	local essentialCat = GetEssentialCategory()
	local utilityCat = GetUtilityCategory()

	local totalHeight = 0
	local spacing = p.cdSpacing
	local rowCount = 0

	-- Count rows and their heights
	if essentialCat then
		local cooldownIDs = Manager:GetCooldownIDsForCategory(essentialCat, "Essential")
		if cooldownIDs and #cooldownIDs > 0 then
			totalHeight = totalHeight + p.cdEssentialHeight
			rowCount = rowCount + 1
		end
	end

	if utilityCat then
		local cooldownIDs = Manager:GetCooldownIDsForCategory(utilityCat, "Utility")
		if cooldownIDs and #cooldownIDs > 0 then
			totalHeight = totalHeight + p.cdUtilityHeight
			rowCount = rowCount + 1
		end
	end

	-- Add spacing between rows
	if rowCount > 1 then
		totalHeight = totalHeight + (spacing * (rowCount - 1))
	end

	return totalHeight
end

-- Get the width of this module for LayoutManager
function Cooldowns:GetLayoutWidth()
	local p = addon.db.profile
	local cols = 6
	return cols * (p.iconWidth or 20)
end

-- Apply position from LayoutManager
function Cooldowns:ApplyLayoutPosition()
	local container = Manager:GetContainer("cd")
	if not container then
		return
	end

	local p = self.db.profile
	if not p.cdEnabled then
		container:Hide()
		return
	end

	local main = _G["ActionHudFrame"]
	if not main then
		return
	end

	local LM = addon:GetModule("LayoutManager", true)
	if not LM then
		return
	end

	-- Check if we're in stack mode
	local inStack = LM:IsModuleInStack("cooldowns")

	container:ClearAllPoints()

	if inStack then
		-- Stack mode: position from LayoutManager
		local yOffset = LM:GetModulePosition("cooldowns")
		container:SetPoint("TOP", main, "TOP", 0, yOffset)
		container:EnableMouse(false)
	else
		-- Independent mode: use DraggableContainer positioning
		local DraggableContainer = ns.DraggableContainer
		if DraggableContainer then
			-- If container hasn't been set up as draggable, do it now
			if not container._db then
				container._db = self.db
				container._xKey = "cooldownsXOffset"
				container._yKey = "cooldownsYOffset"
				container._defaultX = 0
				container._defaultY = -100
				container.moduleId = "cooldowns"
				container:SetMovable(true)
				container:SetClampedToScreen(true)
				
				-- Create overlay and label if missing
				if not container.overlay then
					container.overlay = container:CreateTexture(nil, "OVERLAY")
					container.overlay:SetAllPoints()
					container.overlay:SetColorTexture(0, 0.5, 1, 0.4) -- Blue
					container.overlay:Hide()
				end
				if not container.label then
					container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
					container.label:SetPoint("CENTER")
					container.label:SetText("Cooldowns")
					container.label:Hide()
				end
				
				-- Drag handlers
				container:SetScript("OnDragStart", function(self)
					if DraggableContainer:IsUnlocked(self._db) then
						self:StartMoving()
					end
				end)
				container:SetScript("OnDragStop", function(self)
					self:StopMovingOrSizing()
					local cx, cy = self:GetCenter()
					local px, py = main:GetCenter()
					self._db.profile[self._xKey] = cx - px
					self._db.profile[self._yKey] = cy - py
					if LibStub("AceConfigRegistry-3.0", true) then
						LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud")
					end
				end)
			end
			DraggableContainer:UpdatePosition(container)
			DraggableContainer:UpdateOverlay(container)
		else
			-- Fallback positioning
			local xOffset = p.cooldownsXOffset or 0
			local yOffset = p.cooldownsYOffset or -100
			container:SetPoint("CENTER", main, "CENTER", xOffset, yOffset)
		end
	end

	container:Show()
	addon:Log(string.format("Cooldowns positioned: inStack=%s", tostring(inStack)), "layout")
end

function Cooldowns:UpdateLayout()
	local main = _G["ActionHudFrame"]
	if not main then
		return
	end
	local p = self.db.profile
	local container = Manager:GetContainer("cd")
	if not container then
		return
	end

	-- Report height to LayoutManager
	local LM = addon:GetModule("LayoutManager", true)
	local height = self:CalculateHeight()
	if LM then
		LM:SetModuleHeight("cooldowns", height)
	end

	-- Pure custom replacement architecture:
	-- - Option to hide Blizzard's CooldownViewer when ours is active
	-- - Data provider still returns configured spells (we cache outside combat)
	if p.cdEnabled then
		-- Hide Blizzard's CooldownViewer if setting is enabled
		if p.cdHideBlizzardViewer then
			self:HideBlizzardCooldownViewer()
		else
			self:ShowBlizzardCooldownViewer()
		end

		self:ApplyLayoutPosition()

		-- Set container size BEFORE creating overlay (so overlay has dimensions)
		local containerHeight = self:CalculateHeight()
		local LM = addon:GetModule("LayoutManager", true)
		local inStack = LM and LM:IsModuleInStack("cooldowns")
		local containerWidth
		if inStack and LM then
			containerWidth = LM:GetMaxWidth()
		else
			containerWidth = self:GetLayoutWidth()
		end
		if containerHeight > 0 and containerWidth > 0 then
			container:SetSize(containerWidth, containerHeight)
		end

		container:Show()
		Manager:UpdateContainerDebug("cd", { r = 0, g = 0, b = 1 }) -- Blue for CDs
		addon:UpdateLayoutOutline(container, "Cooldowns", "cooldowns")
		self:RenderCooldownProxies(container, p)

		-- DEBUG: Log container position and proxy count (throttled)
		if not self._lastDebugTime or (GetTime() - self._lastDebugTime) > 5 then
			self._lastDebugTime = GetTime()
			local point, relativeTo, relativePoint, xOfs, yOfs = container:GetPoint()
			local proxyCount = 0
			for _ in pairs(activeProxies) do proxyCount = proxyCount + 1 end
			addon:Log(string.format("Cooldowns: point=%s, yOfs=%.0f, proxies=%d, height=%d",
				tostring(point), yOfs or 0, proxyCount, height), "layout")
		end
	else
		container:Hide()
		self:ReleaseCooldownProxies()
		-- Show Blizzard's viewer if our module is disabled
		self:ShowBlizzardCooldownViewer()
	end
end

-- Helper to hide Blizzard's CooldownViewer frame
function Cooldowns:HideBlizzardCooldownViewer()
	-- Try multiple possible Blizzard frame names
	local frameNames = {
		"EssentialCooldownViewer",
		"UtilityCooldownViewer",
		"CooldownViewerFrame",
	}
	
	for _, frameName in ipairs(frameNames) do
		local blizzViewer = _G[frameName]
		if blizzViewer and blizzViewer:IsShown() then
			blizzViewer:Hide()
			addon:Log("Hidden Blizzard " .. frameName, "layout")
		end
	end
end

-- Helper to show Blizzard's CooldownViewer frame (restore default)
function Cooldowns:ShowBlizzardCooldownViewer()
	-- Only restore if user enables the debug option
	local frameNames = {
		"EssentialCooldownViewer",
		"UtilityCooldownViewer",
		"CooldownViewerFrame",
	}
	
	-- Only show if Blizzard's CVar is enabled
	local cvarEnabled = GetCVar("cooldownViewerEnabled") == "1"
	if not cvarEnabled then return end
	
	for _, frameName in ipairs(frameNames) do
		local blizzViewer = _G[frameName]
		if blizzViewer then
			blizzViewer:Show()
			addon:Log("Restored Blizzard " .. frameName, "layout")
		end
	end
end

function Cooldowns:RenderCooldownProxies(container, p)
	-- Reuse cached tables to avoid garbage creation
	wipe(usedKeysCache)
	wipe(categoriesCache)

	local essentialCat = GetEssentialCategory()
	local utilityCat = GetUtilityCategory()

	-- Update pre-allocated category info tables
	if p.cdReverse then
		if utilityCat then
			utilityCatInfo.cat = utilityCat
			utilityCatInfo.w = p.cdUtilityWidth
			utilityCatInfo.h = p.cdUtilityHeight
			table_insert(categoriesCache, utilityCatInfo)
		end
		if essentialCat then
			essentialCatInfo.cat = essentialCat
			essentialCatInfo.w = p.cdEssentialWidth
			essentialCatInfo.h = p.cdEssentialHeight
			table_insert(categoriesCache, essentialCatInfo)
		end
	else
		if essentialCat then
			essentialCatInfo.cat = essentialCat
			essentialCatInfo.w = p.cdEssentialWidth
			essentialCatInfo.h = p.cdEssentialHeight
			table_insert(categoriesCache, essentialCatInfo)
		end
		if utilityCat then
			utilityCatInfo.cat = utilityCat
			utilityCatInfo.w = p.cdUtilityWidth
			utilityCatInfo.h = p.cdUtilityHeight
			table_insert(categoriesCache, utilityCatInfo)
		end
	end

	local yOffset = 0
	local spacing = p.cdSpacing
	local itemGap = p.cdItemGap

	for _, catInfo in ipairs(categoriesCache) do
		local cooldownIDs = Manager:GetCooldownIDsForCategory(catInfo.cat, catInfo.name)
		if #cooldownIDs > 0 then
			local rowWidth = 0
			local xOffset = 0
			wipe(rowProxiesCache)

			for i, cooldownID in ipairs(cooldownIDs) do
				local info = Manager:GetCooldownInfoForID(cooldownID)
				if info and info.spellID then
					-- Use cooldownID directly as key to avoid string concatenation
					usedKeysCache[cooldownID] = true

					local proxy = activeProxies[cooldownID]
					if not proxy then
						proxy = Manager:GetProxy(container, "cooldown")
						activeProxies[cooldownID] = proxy
						proxy.proxyKey = cooldownID
					end

					-- Mark this proxy as leased to this key
					proxy.leasedTo = cooldownID

					proxy:SetSize(catInfo.w, catInfo.h)
					proxy.count:SetFont("Fonts\\FRIZQT__.TTF", p.cdCountFontSize or 10, "OUTLINE")
					proxy.cooldown:SetCountdownFont(Utils.GetTimerFont(p.cdTimerFontSize))

					self:PopulateProxy(proxy, cooldownID, info)

					proxy:ClearAllPoints()
					proxy.pendingX = xOffset
					proxy.pendingY = yOffset
					table_insert(rowProxiesCache, proxy)

					xOffset = xOffset + catInfo.w + itemGap
					rowWidth = xOffset - itemGap
				end
			end

			local centerOffset = -rowWidth / 2
			for _, proxy in ipairs(rowProxiesCache) do
				-- Position from top of container (LayoutManager handles overall positioning)
				proxy:SetPoint("TOPLEFT", container, "TOP", centerOffset + proxy.pendingX, -proxy.pendingY)
				proxy.pendingX = nil
				proxy.pendingY = nil
			end
			yOffset = yOffset + catInfo.h + spacing
		end
	end

	-- Cleanup any proxies that are no longer in the configured list
	for key, proxy in pairs(activeProxies) do
		if not usedKeysCache[key] then
			Manager:ReleaseProxy(proxy)
			activeProxies[key] = nil
		end
	end
end

function Cooldowns:PopulateProxy(proxy, cooldownID, cooldownInfo)
	if not cooldownInfo then
		return
	end
	local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
	proxy.spellID = spellID
	proxy.cooldownID = cooldownID
	proxy.cooldownInfo = cooldownInfo

	local texture = Utils.GetSpellTextureSafe(spellID)
	if texture then
		proxy.icon:SetTexture(texture)
	end

	local cdInfo = Utils.GetSpellCooldownSafe(spellID)
	local hasCD = false

	-- DEBUG: Log cooldown info for first few calls (routes to Mechanic console)
	if not self._debugCount then self._debugCount = 0 end
	if self._debugCount < 10 then
		self._debugCount = self._debugCount + 1
		local spellName = C_Spell.GetSpellName(spellID) or "?"
		if cdInfo then
			addon:Log(string.format("CD: %s (id=%d): start=%.1f, dur=%.1f",
				spellName, spellID, cdInfo.startTime or 0, cdInfo.duration or 0), "proxy")
		else
			addon:Log(string.format("CD: %s (id=%d): cdInfo is NIL", spellName, spellID), "proxy")
		end
	end

	if cdInfo then
		local duration = cdInfo.duration
		local startTime = cdInfo.startTime

		-- desaturation logic
		local isUsable = true
		local ok, result = pcall(C_Spell.IsSpellUsable, spellID)
		if ok then
			if Utils.IsValueSecret(result) then
				isUsable = true
			else
				isUsable = result
			end
		end
		proxy.icon:SetDesaturated(not isUsable)

		-- Simplified passthrough for cooldowns
		if duration and (Utils.IsValueSecret(duration) or Utils.SafeCompare(duration, 0, ">")) then
			hasCD = true
			-- Simplified GCD check
			if not Utils.IsValueSecret(duration) and Utils.SafeCompare(duration, 1.5, "<=") then
				CooldownFrame_Clear(proxy.cooldown)
				proxy.icon:SetDesaturated(false)
			else
				-- Passthrough SetCooldown handles secrets
				proxy.cooldown:SetCooldown(startTime or GetTime(), duration)
			end
		end
	end

	if not hasCD then
		CooldownFrame_Clear(proxy.cooldown)
		proxy.icon:SetDesaturated(false)
	end

	-- Charges / Counts
	local chargeInfo = Utils.GetSpellChargesSafe(spellID)
	if chargeInfo and chargeInfo.maxCharges and Utils.SafeCompare(chargeInfo.maxCharges, 1, ">") then
		local currentCharges = chargeInfo.currentCharges
		proxy.count:SetText(currentCharges)
		proxy.count:Show()

		local chargeStart = chargeInfo.cooldownStartTime
		local chargeDuration = chargeInfo.cooldownDuration

		if
			chargeStart
			and chargeDuration
			and (Utils.IsValueSecret(chargeDuration) or Utils.SafeCompare(chargeDuration, 0, ">"))
		then
			proxy.cooldown:SetCooldown(chargeStart, chargeDuration)
			proxy.icon:SetDesaturated(false)
		end
	else
		local castCount = spellID and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(spellID)
		if castCount and (Utils.IsValueSecret(castCount) or Utils.SafeCompare(castCount, 0, ">")) then
			proxy.count:SetText(castCount)
			proxy.count:Show()
		else
			proxy.count:Hide()
		end
	end
	proxy.timer:Hide()
	proxy:Show()
end

function Cooldowns:ReleaseCooldownProxies()
	for key, proxy in pairs(activeProxies) do
		Manager:ReleaseProxy(proxy)
		activeProxies[key] = nil
	end
end

function Cooldowns:OnSpellUpdateCooldown()
	addon:Log("Cooldowns: OnSpellUpdateCooldown", "events")
	local container = Manager:GetContainer("cd")
	if container and container:IsShown() then
		for key, proxy in pairs(activeProxies) do
			if proxy.cooldownInfo then
				self:PopulateProxy(proxy, proxy.cooldownID, proxy.cooldownInfo)
			end
		end
	end
end

function Cooldowns:OnPlayerEnteringWorld()
	addon:Log("Cooldowns: OnPlayerEnteringWorld", "events")
	-- Direct call - data provider should be ready for zone transitions
	self:UpdateLayout()
end
