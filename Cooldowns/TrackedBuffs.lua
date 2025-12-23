local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffs = addon:NewModule("TrackedBuffs", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's BuffIconCooldownViewer frame
-- and apply custom styling. Position is controlled by Blizzard's EditMode.
-- This is similar to how ClassyMap styles the minimap without moving it.

local BLIZZARD_FRAME_NAME = "BuffIconCooldownViewer"

local isStylingActive = false
local hooksInstalled = false

function TrackedBuffs:OnInitialize()
	self.db = addon.db
end

function TrackedBuffs:OnEnable()
	addon:Log("TrackedBuffs:OnEnable (style-only mode)", "discovery")

	-- Register for combat end to apply deferred styling
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

	-- Delay initial setup to ensure Blizzard frames are loaded
	C_Timer.After(0.5, function()
		self:SetupStyling()
	end)
end

function TrackedBuffs:OnDisable()
	-- Note: Can't fully undo styling due to hooksecurefunc limitations
	isStylingActive = false
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

-- When combat ends, apply styling to any frames that were acquired during combat
function TrackedBuffs:OnCombatEnd()
	if isStylingActive then
		self:ForceStyleAllItems()
	end
end

-- Get the Blizzard frame we're styling
function TrackedBuffs:GetBlizzardFrame()
	return _G[BLIZZARD_FRAME_NAME]
end

-- Install hooks on the Blizzard frame (only once, can't be removed)
function TrackedBuffs:InstallHooks()
	if hooksInstalled then
		return true
	end

	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		addon:Log("TrackedBuffs: BuffIconCooldownViewer not found for hooks", "discovery")
		return false
	end

	-- Hook RefreshLayout to re-apply our styling after Blizzard updates
	hooksecurefunc(blizzFrame, "RefreshLayout", function()
		if isStylingActive then
			self:ApplyStyling()
		end
	end)

	-- Hook OnAcquireItemFrame to style individual items as they're created
	hooksecurefunc(blizzFrame, "OnAcquireItemFrame", function(_, itemFrame)
		if isStylingActive then
			-- CRITICAL: We use C_Timer.After(0) to style the frame in a separate execution path.
			-- This prevents taint from leaking back into Blizzard's protected aura logic,
			-- which is what causes the "secret value" crashes in Midnight Beta.
			C_Timer.After(0, function()
				local success, err = pcall(function()
					self:StyleItemFrame(itemFrame)
				end)
				if not success then
					addon:Log("TrackedBuffs: Error styling item frame: " .. tostring(err), "frames")
				end
			end)
		end
	end)

	hooksInstalled = true
	addon:Log("TrackedBuffs: Hooks installed on BuffIconCooldownViewer", "discovery")
	return true
end

-- Apply styling to the frame and all existing items
function TrackedBuffs:ApplyStyling()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		return
	end

	-- Main frame properties are safe to set in hooks
	-- Re-apply styling to all active items (Blizzard may have reset them)
	self:ForceStyleAllItems()
end

-- Force style all active items (unsafe in Blizzard hooks, call only from settings/enable)
function TrackedBuffs:ForceStyleAllItems()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame or not blizzFrame.itemFramePool then
		return
	end

	-- We try to enumerate. If it crashes, the pcall will catch it.
	local count = 0
	local success, err = pcall(function()
		for itemFrame in blizzFrame.itemFramePool:EnumerateActive() do
			self:StyleItemFrame(itemFrame)
			count = count + 1
		end
	end)

	if not success then
		addon:Log("TrackedBuffs: ForceStyleAllItems failed: " .. tostring(err), "frames")
	elseif count > 0 then
		addon:Log(string.format("TrackedBuffs: Styled %d items", count), "frames")
	end
end

-- Style an individual item frame
function TrackedBuffs:StyleItemFrame(itemFrame)
	if not itemFrame or Utils.Cap.IsRoyal then
		return
	end

	local p = self.db.profile

	-- Always strip decorations (Utils helper handles combat safety with SetAlpha)
	self:StripBlizzardDecorations(itemFrame)

	-- Apply custom timer font size (SAFE in combat)
	local timerSize = p.buffsTimerFontSize or "medium"
	if timerSize and itemFrame.Cooldown then
		local fontName = Utils.GetTimerFont(timerSize)
		if fontName then
			itemFrame.Cooldown:SetCountdownFont(fontName)
		end
	end

	-- Apply custom count font size (SAFE in combat)
	local countSize = p.buffsCountFontSize or 10
	if countSize and type(countSize) == "number" then
		local applicationsFrame = itemFrame.Applications
		if applicationsFrame and applicationsFrame.Applications then
			applicationsFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", countSize, "OUTLINE")
		end
	end
end

-- Remove Blizzard's decorative textures (mask, overlay, shadow)
-- Called every time to ensure decorations stay hidden
function TrackedBuffs:StripBlizzardDecorations(itemFrame)
	if not itemFrame then
		return
	end

	-- Use unified helper for stripping (handles combat safety)
	Utils.StripBlizzardDecorations(itemFrame)

	-- Apply standard icon crop (always safe)
	if itemFrame.Icon then
		Utils.ApplyIconCrop(itemFrame.Icon, 1, 1)
	end
end

-- Main setup function
function TrackedBuffs:SetupStyling()
	-- Capability Check: If we are on a "Royal" client (Beta 5+), enter standby
	-- These features are currently broken due to API transition (Duration objects/SecondsFormatter)
	if Utils.Cap.IsRoyal then
		if not self.notifiedStandby then
			addon:Log("TrackedBuffs: Entering STANDBY mode for 12.0 'Royal' transition.", "discovery")
			self.notifiedStandby = true
		end
		isStylingActive = false
		return
	end

	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		addon:Log("TrackedBuffs: BuffIconCooldownViewer not available, retrying...", "discovery")
		C_Timer.After(1.0, function()
			self:SetupStyling()
		end)
		return
	end

	local p = self.db.profile
	local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()

	addon:Log(string.format("TrackedBuffs: styleTrackedBuffs=%s, blizzEnabled=%s", 
		tostring(p.styleTrackedBuffs), tostring(blizzEnabled)), "discovery")

	if not p.styleTrackedBuffs or not blizzEnabled then
		isStylingActive = false
		addon:Log("TrackedBuffs: Styling DISABLED by settings", "discovery")
		return
	end

	-- Install hooks (only once)
	if not self:InstallHooks() then
		addon:Log("TrackedBuffs: InstallHooks() FAILED", "discovery")
		return
	end

	isStylingActive = true

	-- Apply initial styling to existing items
	-- This is safe here because it's called from OnEnable/C_Timer, not a Blizzard hook
	self:ForceStyleAllItems()

	addon:Log("TrackedBuffs: Styling active", "discovery")
end

-- Update styling (called when settings change)
function TrackedBuffs:UpdateLayout()
	addon:Log("TrackedBuffs: UpdateLayout() called", "frames")
	self:SetupStyling()

	-- Debug Container Visual
	local blizzFrame = self:GetBlizzardFrame()
	if blizzFrame then
		Manager:UpdateFrameDebug(blizzFrame, { r = 1, g = 0.5, b = 0 }) -- Orange for Buffs
		addon:UpdateLayoutOutline(blizzFrame, "Tracked Buffs")
	end

	-- Force re-apply styling to all existing frames if active
	if isStylingActive then
		self:ForceStyleAllItems()
	end
end
