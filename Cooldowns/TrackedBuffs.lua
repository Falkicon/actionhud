local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBuffs = addon:NewModule("TrackedBuffs", "AceEvent-3.0")
local Utils = ns.Utils
local Reset = ns.SkinningReset  -- Centralized skinning reset

-- Style-only approach: We hook into Blizzard's BuffIconCooldownViewer frame
-- and apply custom styling WITHOUT reparenting. Position is controlled by
-- Blizzard's EditMode. Reparenting causes issues when Blizzard's code errors.

local BLIZZARD_FRAME_NAME = "BuffIconCooldownViewer"

-- State for styling management
local isStylingActive = false
local hooksInstalled = false

function TrackedBuffs:OnInitialize()
    self.db = addon.db
end

function TrackedBuffs:OnEnable()
    addon:Log("TrackedBuffs:OnEnable (style-only mode)", "discovery")

    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function()
        self:SetupStyling()
    end)
end

function TrackedBuffs:OnDisable()
    isStylingActive = false
end

-- Get the Blizzard frame we're styling
function TrackedBuffs:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

-- Install hooks on the Blizzard frame (only once, can't be removed)
function TrackedBuffs:InstallHooks()
    if hooksInstalled then return true end

    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBuffs: BuffIconCooldownViewer not found for hooks", "discovery")
        return false
    end

    -- Hook OnAcquireItemFrame to style individual items as they appear
    -- This is the safest hook - only fires when new items are created
    hooksecurefunc(blizzFrame, "OnAcquireItemFrame", function(_, itemFrame)
        if isStylingActive then
            self:StyleItemFrame(itemFrame)
        end
    end)

    hooksInstalled = true
    addon:Log("TrackedBuffs: Hooks installed on BuffIconCooldownViewer", "discovery")
    return true
end

-- Apply styling to all existing items
function TrackedBuffs:ApplyStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end

    local p = self.db.profile

    -- Style existing items (wrap in pcall for safety)
    pcall(function()
        if blizzFrame.itemFramePool then
            for itemFrame in blizzFrame.itemFramePool:EnumerateActive() do
                self:StyleItemFrame(itemFrame)
            end
        end
    end)
end

-- Style an individual item frame
-- Only applies cosmetic changes - no reparenting, no forcing layouts
function TrackedBuffs:StyleItemFrame(itemFrame)
    if not itemFrame then return end

    local p = self.db.profile

    -- Strip Blizzard decorations using centralized reset
    Reset.StripIconFrame(itemFrame)

    -- Apply custom timer font size if specified
    if p.buffsTimerFontSize and itemFrame.Cooldown then
        local fontObject = Utils.GetTimerFont(p.buffsTimerFontSize)
        if fontObject then
            pcall(function()
                itemFrame.Cooldown:SetCountdownFont(fontObject)
            end)
        end
    end

    -- Apply custom count font size if specified (numeric)
    if p.buffsCountFontSize and type(p.buffsCountFontSize) == "number" then
        local applicationsFrame = itemFrame.Applications
        if applicationsFrame and applicationsFrame.Applications then
            pcall(function()
                applicationsFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", p.buffsCountFontSize, "OUTLINE")
            end)
        end
    end
end

-- Main setup function
function TrackedBuffs:SetupStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBuffs: BuffIconCooldownViewer not available yet", "discovery")
        -- Retry after a delay
        C_Timer.After(1.0, function() self:SetupStyling() end)
        return
    end

    local p = self.db.profile

    if not p.styleTrackedBuffs then
        isStylingActive = false
        addon:Log("TrackedBuffs: Styling disabled", "discovery")
        return
    end

    -- Install hooks (only once)
    if not self:InstallHooks() then
        return
    end

    -- Apply initial styling to existing items
    self:ApplyStyling()

    isStylingActive = true
    addon:Log("TrackedBuffs: Styling active", "discovery")
end

-- Update styling (called when settings change)
function TrackedBuffs:UpdateLayout()
    self:SetupStyling()
end

function TrackedBuffs:SetLayoutMode(enabled)
    -- No layout mode handling needed for style-only approach
end

function TrackedBuffs:UpdateSettings()
    self:SetupStyling()
end
