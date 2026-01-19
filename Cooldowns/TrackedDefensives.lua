local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedDefensives = addon:NewModule("TrackedDefensives", "AceEvent-3.0")

-- ============================================================================
-- TrackedDefensives: DISABLED - NO WORKING APPROACH IN WOW 12.0
-- ============================================================================
-- Exhaustive testing confirmed NO API works for secret-valued buffs in combat.
-- See docs/aura-api-testing.md for full test matrix and findings.
--
-- Hooks cause taint, and all direct API approaches fail:
--   - GetPlayerAuraBySpellID returns nil
--   - GetBuffDataByIndex blocked in combat
--   - UNIT_AURA addedAuras fields are SECRET
--
-- Blizzard's CooldownViewer is the only supported display method.
-- ============================================================================

function TrackedDefensives:OnInitialize()
	self.db = addon.db
end

function TrackedDefensives:OnEnable()
	-- DISABLED: Hooking ExternalDefensivesFrame causes taint
	addon:Log("TrackedDefensives: DISABLED (hooks cause taint)", "discovery")
end

function TrackedDefensives:OnDisable() end

function TrackedDefensives:SetLayoutMode(enabled) end

function TrackedDefensives:UpdateSettings() end
