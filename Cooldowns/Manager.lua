local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Manager = addon:NewModule("CooldownManager", "AceEvent-3.0")
ns.CooldownManager = Manager

local Utils = ns.Utils

-- Local upvalues for performance
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local GetTime = GetTime
local pcall = pcall
local table_insert = table.insert
local CooldownFrame_Set = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear

-- Reusable empty table constant (never modify this!)
local EMPTY_TABLE = {}

-- Shared state
local proxyPool = {}
local containers = {}

-- Pre-seeded cache for cooldown data (avoids calling data provider during combat)
-- Pattern G from 13-midnight-secret-values.doc.md: Pre-Seeding Lookup Tables
local cooldownCache = {
	categoryIDs = {}, -- [category] = { cooldownID, cooldownID, ... }
	cooldownInfo = {}, -- [cooldownID] = cooldownInfo
	valid = false,
}

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Manager:OnEnable()
	self:RegisterEvent("CVAR_UPDATE", "OnEvent")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")

	-- NOTE: We intentionally do NOT use CVarCallbackRegistry:RegisterCallback()
	-- because it fires from Blizzard's protected context, causing taint cascade.
	-- Instead, we rely on CVAR_UPDATE event which fires in a clean context.

	-- Listen for CooldownViewer data changes (when user configures tracked spells)
	-- IMPORTANT: Use C_Timer.After(0) to escape Blizzard's tainted callback context
	-- The EventRegistry callback fires from within Blizzard's protected code,
	-- so any work done directly in the callback becomes tainted.
	if EventRegistry then
		EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
			-- Schedule on next frame to escape tainted context
			C_Timer.After(0, function()
				self:InvalidateCooldownCache()
				-- Refresh immediately if safe
				if not InCombatLockdown() then
					self:RefreshCooldownCache()
				end
			end)
		end, self)
	end

	addon:Log(L["CooldownManager Enabled"], "proxy")
	local blizzEnabled = self:IsBlizzardCooldownViewerEnabled()
	addon:Log(string.format(L["Blizzard Cooldown Manager enabled: %s"], tostring(blizzEnabled)), "proxy")

	-- Initial cache population (delayed to ensure data provider is ready)
	C_Timer.After(0.5, function()
		if not InCombatLockdown() then
			self:RefreshCooldownCache()
		end
	end)
end

function Manager:OnDisable()
	self:UnregisterEvent("CVAR_UPDATE")
	-- NOTE: No CVarCallbackRegistry to unregister - we use CVAR_UPDATE event instead
end

function Manager:OnEvent(event, ...)
	if event == "CVAR_UPDATE" then
		local cvarName, value = ...
		if cvarName == "cooldownViewerEnabled" then
			self:OnCVarChanged(cvarName, value)
		end
	end
end

function Manager:OnCVarChanged(cvarName, value)
	addon:Log(string.format(L["CVar Changed: %s = %s"], tostring(cvarName), tostring(value)), "proxy")

	-- Notify all dependent modules to refresh their layout and visibility
	local modules = { "Cooldowns", "TrackedBuffs", "TrackedDefensives" }
	for _, modName in ipairs(modules) do
		local mod = addon:GetModule(modName, true)
		if mod and mod.UpdateLayout then
			mod:UpdateLayout()
		end
	end

	-- Trigger central layout recalculation
	local LM = addon:GetModule("LayoutManager", true)
	if LM then
		LM:TriggerLayoutUpdate()
	end
end

function Manager:OnPlayerEnteringWorld()
	-- Refresh cache when entering world (always safe here)
	addon:Log("CooldownManager: OnPlayerEnteringWorld - refreshing cache", "proxy")
	C_Timer.After(0.5, function()
		if not InCombatLockdown() then
			self:RefreshCooldownCache()
		end
	end)
end

function Manager:OnPlayerRegenEnabled()
	-- Refresh cache when leaving combat (if invalidated during combat)
	if not cooldownCache.valid then
		addon:Log("CooldownManager: OnPlayerRegenEnabled - refreshing invalidated cache", "proxy")
		self:RefreshCooldownCache()
	end
end

-- ============================================================================
-- Cooldown Cache (Pre-seeding for Midnight Secret Value Safety)
-- ============================================================================

-- Refresh the cooldown cache from the data provider
-- IMPORTANT: Only call this outside combat when values are readable
function Manager:RefreshCooldownCache()
	if InCombatLockdown() then
		addon:Log("CooldownManager: Skipping cache refresh (in combat)", "proxy")
		return
	end

	wipe(cooldownCache.categoryIDs)
	wipe(cooldownCache.cooldownInfo)

	local categories = {
		{ name = "Essential", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential },
		{ name = "Utility", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility },
		{ name = "TrackedBuff", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff },
		{ name = "TrackedBar", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar },
	}

	if not CooldownViewerSettings or not CooldownViewerSettings.GetDataProvider then
		cooldownCache.valid = false
		return
	end

	local provider = CooldownViewerSettings:GetDataProvider()
	if not provider then
		cooldownCache.valid = false
		return
	end

	local totalCached = 0
	for _, catInfo in ipairs(categories) do
		if catInfo.cat and provider.GetOrderedCooldownIDsForCategory then
			local ok, ids = pcall(provider.GetOrderedCooldownIDsForCategory, provider, catInfo.cat)
			if ok and ids then
				-- Deep copy the IDs to avoid holding references to provider internals
				local cachedIDs = {}
				for _, id in ipairs(ids) do
					table_insert(cachedIDs, id)

					-- Also cache the info for each ID
					if provider.GetCooldownInfoForID then
						local infoOk, info = pcall(provider.GetCooldownInfoForID, provider, id)
						if infoOk and info then
							-- Deep copy relevant fields to avoid secret value contamination
							cooldownCache.cooldownInfo[id] = {
								spellID = info.spellID,
								overrideSpellID = info.overrideSpellID,
								overrideTooltipSpellID = info.overrideTooltipSpellID,
								linkedSpellIDs = info.linkedSpellIDs,
								category = info.category,
							}
							totalCached = totalCached + 1
						end
					end
				end
				cooldownCache.categoryIDs[catInfo.cat] = cachedIDs
			end
		end
	end

	cooldownCache.valid = true
	addon:Log(string.format("CooldownManager: Cached %d cooldowns", totalCached), "proxy")
end

-- Invalidate the cache (forces refresh on next safe opportunity)
function Manager:InvalidateCooldownCache()
	cooldownCache.valid = false
	addon:Log("CooldownManager: Cache invalidated", "proxy")
end

-- ============================================================================
-- Infrastructure
-- ============================================================================

function Manager:IsBlizzardCooldownViewerEnabled()
	if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
		local val = CVarCallbackRegistry:GetCVarValueBool("cooldownViewerEnabled")
		if val ~= nil then
			return val
		end
	end
	local val = GetCVar("cooldownViewerEnabled")
	return Utils.SafeCompare(val, "1", "==")
end

function Manager:GetCooldownIDsForCategory(category, categoryName)
	-- In combat or M+: Use cached data to avoid triggering Blizzard's secret value crashes
	-- The data provider internally compares secret spellIDs which causes cascade errors
	if InCombatLockdown() or Utils.MayHaveSecretValues() then
		if cooldownCache.valid and cooldownCache.categoryIDs[category] then
			return cooldownCache.categoryIDs[category]
		end
		-- Cache not valid during combat - return empty (graceful degradation)
		return EMPTY_TABLE
	end

	-- Outside combat: Refresh cache if invalid, then return cached data
	if not cooldownCache.valid then
		self:RefreshCooldownCache()
	end

	if cooldownCache.categoryIDs[category] then
		return cooldownCache.categoryIDs[category]
	end

	return EMPTY_TABLE
end

function Manager:GetCooldownInfoForID(cooldownID)
	if not cooldownID then
		return nil
	end

	-- In combat or M+: Use cached data to avoid triggering Blizzard's secret value crashes
	if InCombatLockdown() or Utils.MayHaveSecretValues() then
		if cooldownCache.valid and cooldownCache.cooldownInfo[cooldownID] then
			return cooldownCache.cooldownInfo[cooldownID]
		end
		-- Cache not valid during combat - return nil (graceful degradation)
		return nil
	end

	-- Outside combat: Refresh cache if invalid, then return cached data
	if not cooldownCache.valid then
		self:RefreshCooldownCache()
	end

	return cooldownCache.cooldownInfo[cooldownID]
end

-- ============================================================================
-- Blizzard Frame Management (REMOVED)
-- ============================================================================
-- NOTE: We no longer hide/show Blizzard frames to avoid taint.
-- Users should disable Blizzard's CooldownViewer via Edit Mode if desired.
-- This is a pure custom replacement architecture.

-- ============================================================================
-- Proxy Management
-- ============================================================================

function Manager:GetProxy(parent, proxyType)
	local proxy
	for _, p in ipairs(proxyPool) do
		-- Only reuse if hidden AND not leased to anyone
		if not p:IsShown() and p.proxyType == proxyType and not p.leasedTo then
			proxy = p
			break
		end
	end

	if not proxy then
		proxy = CreateFrame("Button", nil, parent)
		proxy:SetSize(40, 40)
		proxy:EnableMouse(true)
		proxy.proxyType = proxyType

		proxy.icon = proxy:CreateTexture(nil, "ARTWORK")
		proxy.icon:SetAllPoints()
		proxy.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		proxy.cooldown = CreateFrame("Cooldown", nil, proxy, "CooldownFrameTemplate")
		proxy.cooldown:SetAllPoints()
		proxy.cooldown:SetDrawEdge(false)

		proxy.count = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		proxy.count:SetPoint("BOTTOMRIGHT", proxy, "BOTTOMRIGHT", 2, -2)

		proxy.timer = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		proxy.timer:SetPoint("CENTER", proxy, "CENTER", 0, 0)
		proxy.timer:SetTextColor(1, 0.8, 0)

		proxy:SetScript("OnEnter", function(self)
			if self.spellID then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(self.spellID)
				GameTooltip:Show()
			elseif self.auraInstanceID then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetUnitBuffByAuraInstanceID("player", self.auraInstanceID)
				GameTooltip:Show()
			end
		end)
		proxy:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)

		table.insert(proxyPool, proxy)
	end

	proxy:SetParent(parent)
	proxy:SetFrameStrata("MEDIUM")
	return proxy
end

function Manager:ReleaseProxy(proxy)
	proxy:Hide()
	proxy:ClearAllPoints()
	proxy.spellID = nil
	proxy.cooldownID = nil
	proxy.auraInstanceID = nil
	proxy.cooldownInfo = nil
	proxy.leasedTo = nil -- Clear lease so pool can reuse
	proxy.spellName = nil
end

-- ============================================================================
-- Container Management
-- ============================================================================

function Manager:GetContainer(containerType)
	return containers[containerType]
end

function Manager:CreateContainer(containerType, name)
	if containers[containerType] then
		return containers[containerType]
	end
	local main = _G["ActionHudFrame"]
	if not main then
		return nil
	end

	local container = CreateFrame("Frame", name, main)
	container:SetSize(1, 1)
	container:SetPoint("CENTER", main, "CENTER", 0, 0)
	containers[containerType] = container
	return container
end

function Manager:UpdateContainerDebug(containerType, color)
	local container = containers[containerType]
	if not container then
		return
	end
	-- Obsolete: use ActionHud:UpdateLayoutOutline directly if needed
end

function Manager:UpdateFrameDebug(frame, color)
	-- Obsolete
end

-- ============================================================================
-- Debug / Discovery
-- ============================================================================

function Manager:FindPotentialTargets()
	addon:Log(L["Scanning for Blizzard CooldownViewer frames..."], "discovery")
	for k, v in pairs(_G) do
		if type(k) == "string" and (k:match("Viewer$") or k:match("Tracked")) then
			if type(v) == "table" and v.GetObjectType then
				local ok, objType = pcall(v.GetObjectType, v)
				if ok and (objType == "Frame" or objType == "Button") then
					addon:Log(string.format(L["Found: %s (Type: %s)"], k, objType), "discovery")
				end
			end
		end
	end
end

function Manager:DumpTrackedBuffInfo()
	print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Dumping Cooldown Manager Info..."])

	local categories = {
		{ name = L["Essential"], cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential },
		{ name = L["Utility"], cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility },
		{ name = L["TrackedBuff"], cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff },
		{ name = L["TrackedBar"], cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar },
	}

	for _, catInfo in ipairs(categories) do
		if catInfo.cat then
			local ids = self:GetCooldownIDsForCategory(catInfo.cat, catInfo.name)
			print(string.format("|cff00ff00" .. L["%s: %d items"], catInfo.name, #ids))
			for _, cooldownID in ipairs(ids) do
				local info = self:GetCooldownInfoForID(cooldownID)
				if info then
					local name = C_Spell.GetSpellName(info.spellID) or "?"
					local linkedStr = (info.linkedSpellIDs and #info.linkedSpellIDs > 0)
							and table.concat(info.linkedSpellIDs, ", ")
						or "none"
					print(
						string.format(
							"  [%d] %s: spellID=%s, linked=[%s], override=%s, tooltipOverride=%s",
							cooldownID,
							name,
							tostring(info.spellID),
							linkedStr,
							tostring(info.overrideSpellID),
							tostring(info.overrideTooltipSpellID)
						)
					)
				end
			end
		end
	end
	print("|cff33ff99" .. L["ActionHud:"] .. "|r " .. L["Dump complete."])
end
