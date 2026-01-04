local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBars = addon:NewModule("TrackedBars", "AceEvent-3.0")
local Utils = ns.Utils
local Reset = ns.SkinningReset  -- Centralized skinning reset

-- Style-only approach: We hook into Blizzard's BuffBarCooldownViewer frame
-- and apply custom styling WITHOUT reparenting. Position is controlled by
-- Blizzard's EditMode. Reparenting causes issues when Blizzard's code errors.

local BLIZZARD_FRAME_NAME = "BuffBarCooldownViewer"

-- State for styling management
local isStylingActive = false
local hooksInstalled = false

function TrackedBars:OnInitialize()
    self.db = addon.db
end

function TrackedBars:OnEnable()
    addon:Log("TrackedBars:OnEnable (style-only mode)", "discovery")

    -- Delay initial setup to ensure Blizzard frames are loaded
    C_Timer.After(0.5, function()
        self:SetupStyling()
    end)
end

function TrackedBars:OnDisable()
    isStylingActive = false
end

-- Get the Blizzard frame we're styling
function TrackedBars:GetBlizzardFrame()
    return _G[BLIZZARD_FRAME_NAME]
end

-- Install hooks on the Blizzard frame (only once, can't be removed)
function TrackedBars:InstallHooks()
    if hooksInstalled then return true end

    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBars: BuffBarCooldownViewer not found for hooks", "discovery")
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
    addon:Log("TrackedBars: Hooks installed on BuffBarCooldownViewer", "discovery")
    return true
end

-- Apply styling to all existing items
function TrackedBars:ApplyStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then return end

    -- Style existing items (wrap in pcall for safety)
    pcall(function()
        if blizzFrame.itemFramePool then
            for itemFrame in blizzFrame.itemFramePool:EnumerateActive() do
                self:StyleItemFrame(itemFrame)
            end
        end
    end)
end

-- Style an individual bar item frame
-- Only applies cosmetic changes - no reparenting, no forcing layouts
function TrackedBars:StyleItemFrame(itemFrame)
    if not itemFrame then return end

    local p = self.db.profile

    -- Strip Blizzard decorations using centralized reset
    Reset.StripBarFrame(itemFrame)

    -- Apply custom timer font size if specified
    if p.barsTimerFontSize then
        local fontObject = Utils.GetTimerFont(p.barsTimerFontSize)
        if fontObject then
            pcall(function()
                local durationFontString = itemFrame.Bar and itemFrame.Bar.Duration
                if durationFontString then
                    durationFontString:SetFontObject(fontObject)
                end

                local nameFontString = itemFrame.Bar and itemFrame.Bar.Name
                if nameFontString then
                    nameFontString:SetFontObject(fontObject)
                end
            end)
        end
    end

    -- Apply custom count font size if specified (numeric)
    if p.barsCountFontSize and type(p.barsCountFontSize) == "number" then
        pcall(function()
            local iconFrame = itemFrame.Icon
            if iconFrame and iconFrame.Applications then
                iconFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", p.barsCountFontSize, "OUTLINE")
            end
        end)
    end
end

-- Main setup function
function TrackedBars:SetupStyling()
    local blizzFrame = self:GetBlizzardFrame()
    if not blizzFrame then
        addon:Log("TrackedBars: BuffBarCooldownViewer not available yet", "discovery")
        -- Retry after a delay
        C_Timer.After(1.0, function() self:SetupStyling() end)
        return
    end

    local p = self.db.profile

    if not p.styleTrackedBars then
        isStylingActive = false
        addon:Log("TrackedBars: Styling disabled", "discovery")
        return
    end

    -- Install hooks (only once)
    if not self:InstallHooks() then
        return
    end

    -- Apply initial styling to existing items
    self:ApplyStyling()

    isStylingActive = true
    addon:Log("TrackedBars: Styling active", "discovery")
end

-- Update styling (called when settings change)
function TrackedBars:UpdateLayout()
    self:SetupStyling()
end
