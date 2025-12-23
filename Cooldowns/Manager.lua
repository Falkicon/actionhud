local addonName, ns = ...
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
local hiddenFrames = {}
local containers = {}

-- Target Blizzard Frames (only cd frames are hidden/shown by Manager)
-- TrackedBuffs/TrackedBars/TrackedDefensives use style-only approach via EditMode
local blizzardFrames = {
	cd = { "EssentialCooldownViewer", "UtilityCooldownViewer" },
}

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Manager:OnEnable()
	self:RegisterEvent("CVAR_UPDATE", "OnEvent")

	-- Watch for Blizzard Cooldown Manager setting changes
	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		CVarCallbackRegistry:RegisterCallback("cooldownViewerEnabled", self.OnCVarChanged, self)
	end

	addon:Log("CooldownManager Enabled", "proxy")
	local blizzEnabled = self:IsBlizzardCooldownViewerEnabled()
	addon:Log("Blizzard Cooldown Manager enabled: " .. tostring(blizzEnabled), "proxy")
end

function Manager:OnDisable()
	self:UnregisterEvent("CVAR_UPDATE")

	if CVarCallbackRegistry and CVarCallbackRegistry.UnregisterCallback then
		CVarCallbackRegistry:UnregisterCallback("cooldownViewerEnabled", self)
	end
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
	addon:Log("CVar Changed: " .. tostring(cvarName) .. " = " .. tostring(value), "proxy")

	-- Notify all dependent modules to refresh their layout and visibility
	local modules = { "Cooldowns", "TrackedBars", "TrackedBuffs", "TrackedDefensives" }
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
	local ids = EMPTY_TABLE
	if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
		local provider = CooldownViewerSettings:GetDataProvider()
		if provider and provider.GetOrderedCooldownIDsForCategory then
			local ok, result = pcall(provider.GetOrderedCooldownIDsForCategory, provider, category)
			if ok and result then
				ids = result
			end
		end
	end
	return ids
end

function Manager:GetCooldownInfoForID(cooldownID)
	if not cooldownID then
		return nil
	end
	if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
		local provider = CooldownViewerSettings:GetDataProvider()
		if provider and provider.GetCooldownInfoForID then
			local ok, info = pcall(provider.GetCooldownInfoForID, provider, cooldownID)
			if ok and info then
				return info
			end
		end
	end
	return nil
end

-- ============================================================================
-- Blizzard Frame Management
-- ============================================================================

function Manager:HideBlizzardFrame(frameName)
	local frame = _G[frameName]
	if not frame then
		return
	end

	if not hiddenFrames[frameName] then
		hiddenFrames[frameName] = true
		-- Use Alpha/Mouse instead of function override to avoid taint in 12.0
		frame:SetAlpha(0)
		frame:SetPropagateMouseClicks(true) -- Let clicks pass through to our proxies
		addon:Log("Visual-hidden Blizzard frame: " .. frameName, "frames")
	end
end

function Manager:ShowBlizzardFrame(frameName)
	local frame = _G[frameName]
	if not frame then
		return
	end

	if hiddenFrames[frameName] then
		hiddenFrames[frameName] = nil
		frame:SetAlpha(1)
		frame:SetPropagateMouseClicks(false)
		addon:Log("Restored Blizzard frame: " .. frameName, "frames")
	end
end

function Manager:RestoreAllBlizzardFrames()
	for _, group in pairs(blizzardFrames) do
		for _, frameName in ipairs(group) do
			self:ShowBlizzardFrame(frameName)
		end
	end
	wipe(hiddenFrames)
end

function Manager:GetBlizzardFrames()
	return blizzardFrames
end

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
	addon:UpdateFrameDebug(container, color)
end

function Manager:UpdateFrameDebug(frame, color)
	addon:UpdateFrameDebug(frame, color)
end

-- ============================================================================
-- Debug / Discovery
-- ============================================================================

function Manager:FindPotentialTargets()
	addon:Log("Scanning for Blizzard CooldownViewer frames...", "discovery")
	for k, v in pairs(_G) do
		if type(k) == "string" and (k:match("Viewer$") or k:match("Tracked")) then
			if type(v) == "table" and v.GetObjectType then
				local ok, objType = pcall(v.GetObjectType, v)
				if ok and (objType == "Frame" or objType == "Button") then
					addon:Log("Found: " .. k .. " (Type: " .. objType .. ")", "discovery")
				end
			end
		end
	end
end

function Manager:DumpTrackedBuffInfo()
	print("|cff33ff99ActionHud:|r Dumping Cooldown Manager Info...")

	local categories = {
		{ name = "Essential", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential },
		{ name = "Utility", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility },
		{ name = "TrackedBuff", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff },
		{ name = "TrackedBar", cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar },
	}

	for _, catInfo in ipairs(categories) do
		if catInfo.cat then
			local ids = self:GetCooldownIDsForCategory(catInfo.cat, catInfo.name)
			print(string.format("|cff00ff00%s:|r %d items", catInfo.name, #ids))
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
	print("|cff33ff99ActionHud:|r Dump complete.")
end
