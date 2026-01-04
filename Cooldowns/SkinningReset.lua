-- ============================================================================
-- ActionHud: Skinning Reset
-- ============================================================================
-- A centralized "CSS Reset" for CooldownViewer skinning.
--
-- This module provides consistent baseline functions that strip Blizzard's
-- default decorations (masks, borders, overlays) from CooldownViewer frames,
-- giving skinning modules a clean slate to apply custom styles.
--
-- Usage:
--   local Reset = ns.SkinningReset
--   Reset.StripIconFrame(itemFrame)      -- For icon-style viewers
--   Reset.StripBarFrame(itemFrame)       -- For bar-style viewers
--   Reset.RestoreFrame(itemFrame)        -- Restore original state
-- ============================================================================

local addonName, ns = ...

local SkinningReset = {}
ns.SkinningReset = SkinningReset

-- ============================================================================
-- Configuration: What to strip and what to preserve
-- ============================================================================

-- Standard icon crop (removes edge pixels for cleaner look)
SkinningReset.ICON_TEXCOORDS = {0.08, 0.92, 0.08, 0.92}

-- Original texcoords (full icon)
SkinningReset.ICON_TEXCOORDS_ORIGINAL = {0, 1, 0, 1}

-- Known Blizzard effect frames to suppress (flash, glow, pandemic indicators)
SkinningReset.EFFECT_FRAMES = {
    "PandemicIcon",       -- Red warning icon for expiring buffs
    "ProcStartFlipbook",  -- Flash effect on proc
    "Finish",             -- Completion effect
    "FX",                 -- Effect container (pandemic glow, etc.)
    "Border",             -- Decorative border frame
    "DebuffBorder",       -- Debuff-specific border
}


-- ============================================================================
-- Core Reset Functions
-- ============================================================================

-- Strip an icon-style CooldownViewer item frame (BuffIconCooldownViewer)
-- Removes: MaskTextures, overlay borders, decorative textures
-- Preserves: Icon texture, Cooldown frame, Applications/Count text
function SkinningReset.StripIconFrame(itemFrame)
    if not itemFrame then return end
    if itemFrame._ahReset then return end -- Already reset

    -- Store original state for potential restoration
    itemFrame._ahOriginal = {
        regions = {},
        texCoords = nil,
        effects = {},
    }

    -- Save original icon texcoords
    if itemFrame.Icon and itemFrame.Icon.GetTexCoord then
        local ok, l, r, t, b = pcall(itemFrame.Icon.GetTexCoord, itemFrame.Icon)
        if ok then
            itemFrame._ahOriginal.texCoords = {l, r, t, b}
        end
    end

    -- Process direct regions
    for _, region in ipairs({itemFrame:GetRegions()}) do
        SkinningReset._ProcessRegion(itemFrame, region, itemFrame.Icon)
    end

    -- Process child frame regions (skip Cooldown)
    for _, child in ipairs({itemFrame:GetChildren()}) do
        if child ~= itemFrame.Cooldown then
            if child.GetRegions then
                for _, region in ipairs({child:GetRegions()}) do
                    SkinningReset._ProcessRegion(itemFrame, region, nil)
                end
            end
        end
    end

    -- Suppress effect frames
    SkinningReset._SuppressEffects(itemFrame)

    -- Apply standard icon crop
    if itemFrame.Icon then
        itemFrame.Icon:SetTexCoord(unpack(SkinningReset.ICON_TEXCOORDS))
    end

    itemFrame._ahReset = true
end

-- Strip a bar-style CooldownViewer item frame (BuffBarCooldownViewer)
-- Removes: MaskTextures, icon overlays, bar backgrounds, pip indicators
-- Preserves: Icon texture, bar fill, name/duration text
function SkinningReset.StripBarFrame(itemFrame)
    if not itemFrame then return end
    if itemFrame._ahReset then return end

    itemFrame._ahOriginal = {
        regions = {},
        texCoords = nil,
        effects = {},
        pip = nil,
    }

    -- Strip the Icon sub-frame
    if itemFrame.Icon then
        local iconFrame = itemFrame.Icon

        -- Save icon texcoords
        if iconFrame.Icon and iconFrame.Icon.GetTexCoord then
            local ok, l, r, t, b = pcall(iconFrame.Icon.GetTexCoord, iconFrame.Icon)
            if ok then
                itemFrame._ahOriginal.texCoords = {l, r, t, b}
            end
        end

        -- Process icon regions
        for _, region in ipairs({iconFrame:GetRegions()}) do
            SkinningReset._ProcessRegion(itemFrame, region, iconFrame.Icon)
        end

        -- Apply icon crop
        if iconFrame.Icon then
            iconFrame.Icon:SetTexCoord(unpack(SkinningReset.ICON_TEXCOORDS))
        end
    end

    -- Strip the Bar sub-frame
    if itemFrame.Bar then
        local barFrame = itemFrame.Bar
        local barTexture = barFrame:GetStatusBarTexture()

        -- Hide background/decorative textures (keep bar fill)
        for _, region in ipairs({barFrame:GetRegions()}) do
            if region:IsObjectType("Texture") and region ~= barTexture then
                local alpha = region:GetAlpha()
                itemFrame._ahOriginal.regions[region] = {
                    type = "texture",
                    alpha = alpha
                }
                region:SetAlpha(0)
            end
        end

        -- Hide the pip (end cap indicator)
        if barFrame.Pip then
            itemFrame._ahOriginal.pip = barFrame.Pip:IsShown()
            barFrame.Pip:Hide()
        end
    end

    -- Suppress effect frames
    SkinningReset._SuppressEffects(itemFrame)

    itemFrame._ahReset = true
end

-- Restore a frame to its original Blizzard state
function SkinningReset.RestoreFrame(itemFrame)
    if not itemFrame then return end
    if not itemFrame._ahOriginal then return end

    local orig = itemFrame._ahOriginal

    -- Restore regions
    for region, info in pairs(orig.regions) do
        if region then
            if info.type == "mask" and info.shown then
                region:Show()
            elseif info.type == "texture" then
                region:SetAlpha(info.alpha or 1)
            end
        end
    end

    -- Restore icon texcoords
    if orig.texCoords then
        local icon = itemFrame.Icon
        if icon then
            -- For bar frames, Icon is a frame containing Icon texture
            if icon.Icon then
                icon.Icon:SetTexCoord(unpack(orig.texCoords))
            elseif icon.SetTexCoord then
                icon:SetTexCoord(unpack(orig.texCoords))
            end
        end
    end

    -- Restore pip
    if orig.pip and itemFrame.Bar and itemFrame.Bar.Pip then
        itemFrame.Bar.Pip:Show()
    end

    -- Re-enable effects
    for name, wasShown in pairs(orig.effects) do
        local effectFrame = itemFrame[name]
        if effectFrame and wasShown then
            effectFrame:Show()
            effectFrame:SetAlpha(1)
        end
    end

    itemFrame._ahOriginal = nil
    itemFrame._ahReset = nil
end

-- ============================================================================
-- Internal Helpers
-- ============================================================================

-- Process a single region (texture or mask)
function SkinningReset._ProcessRegion(itemFrame, region, preserveTexture)
    if not region then return end

    if region:IsObjectType("MaskTexture") then
        -- Hide mask textures (removes rounded corners)
        itemFrame._ahOriginal.regions[region] = {
            type = "mask",
            shown = region:IsShown()
        }
        region:Hide()

    elseif region:IsObjectType("Texture") then
        -- Hide non-icon textures
        if region ~= preserveTexture then
            local alpha = region:GetAlpha()
            if alpha > 0 then
                itemFrame._ahOriginal.regions[region] = {
                    type = "texture",
                    alpha = alpha
                }
                region:SetAlpha(0)
            end
        end
    end
end

-- Forward declaration for recursive calls
local SuppressEffectFrame

-- Track containers that need child monitoring
local monitoredContainers = {}

-- Suppress a single effect frame with hooks (and optionally its children)
SuppressEffectFrame = function(itemFrame, effectFrame, name, suppressChildren)
    if not effectFrame or effectFrame._ahHooked then return end

    effectFrame._ahHooked = true
    itemFrame._ahOriginal.effects[name] = effectFrame:IsShown()

    -- Immediately suppress - use multiple techniques
    effectFrame:Hide()
    effectFrame:SetAlpha(0)
    -- Also move off-screen in case Blizzard re-shows it
    effectFrame:ClearAllPoints()
    effectFrame:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)

    -- Hook Show
    hooksecurefunc(effectFrame, "Show", function(self)
        if itemFrame._ahReset then
            self:Hide()
            self:SetAlpha(0)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)
        end
    end)

    -- Hook SetShown
    hooksecurefunc(effectFrame, "SetShown", function(self, shown)
        if shown and itemFrame._ahReset then
            self:Hide()
            self:SetAlpha(0)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)
        end
    end)

    -- Hook SetAlpha
    hooksecurefunc(effectFrame, "SetAlpha", function(self, alpha)
        if alpha > 0 and itemFrame._ahReset then
            self:SetAlpha(0)
        end
    end)

    -- Recursively suppress existing children and register for monitoring
    if suppressChildren and effectFrame.GetChildren then
        for _, child in ipairs({effectFrame:GetChildren()}) do
            SuppressEffectFrame(itemFrame, child, name .. "_child", true)
        end

        -- Register this container for periodic child monitoring
        -- This catches dynamically created frames like PandemicIcon
        if not effectFrame._ahMonitored then
            effectFrame._ahMonitored = true
            monitoredContainers[effectFrame] = {
                itemFrame = itemFrame,
                name = name
            }
        end
    end
end

-- Track frames that need continuous suppression (Blizzard re-shows them every frame)
local continuousSuppressFrames = {}

-- Periodic scanner for dynamically created children in effect containers
-- Runs every frame (OnUpdate) to catch PandemicIcon the moment it appears
-- AND continuously suppresses frames that Blizzard keeps trying to show
local scannerFrame = CreateFrame("Frame")

scannerFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Scan for new children in monitored containers
    for container, info in pairs(monitoredContainers) do
        if container and info.itemFrame._ahReset then
            -- Check for new unhooked children every frame
            local children = {container:GetChildren()}
            for _, child in ipairs(children) do
                if not child._ahHooked then
                    SuppressEffectFrame(info.itemFrame, child, info.name .. "_dyn", true)
                    -- Also add to continuous suppression list
                    continuousSuppressFrames[child] = info.itemFrame
                end
            end
        elseif not info.itemFrame._ahReset then
            -- Item frame no longer reset, remove from monitoring
            monitoredContainers[container] = nil
        end
    end

    -- Continuously force suppression on frames Blizzard keeps re-showing
    for frame, itemFrame in pairs(continuousSuppressFrames) do
        if frame and itemFrame._ahReset then
            -- Nuclear option: move it off-screen where it can never be seen
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)
            frame:SetAlpha(0)
        else
            -- No longer needed
            continuousSuppressFrames[frame] = nil
        end
    end
end)

-- Suppress known effect frames with hook prevention
function SkinningReset._SuppressEffects(itemFrame)
    -- Suppress any named effect frames (with recursive children)
    for _, name in ipairs(SkinningReset.EFFECT_FRAMES) do
        local effectFrame = itemFrame[name]
        if effectFrame then
            SuppressEffectFrame(itemFrame, effectFrame, name, true)
        end
    end

    -- Also suppress unnamed child frames that aren't essential
    -- Structure: ItemFrame > UnnamedContainer > PandemicIcon > Border/FX
    -- We need to recursively suppress all nested effect frames
    local preserved = {
        itemFrame.Cooldown,
        itemFrame.Icon,
        itemFrame.Applications,
        itemFrame.DebuffBorder,  -- Keep debuff border (we handle it separately)
    }

    for _, child in ipairs({itemFrame:GetChildren()}) do
        -- Skip known essential frames
        local isPreserved = false
        for _, p in ipairs(preserved) do
            if child == p then
                isPreserved = true
                break
            end
        end

        -- Suppress any other child frames recursively (catches nested pandemic containers)
        if not isPreserved and not child._ahHooked then
            SuppressEffectFrame(itemFrame, child, "EffectContainer", true)
        end
    end
end

-- ============================================================================
-- Utility: Apply reset to all active frames in a pool
-- ============================================================================

function SkinningReset.ResetAllInPool(framePool, resetFunc)
    if not framePool then return end

    pcall(function()
        for itemFrame in framePool:EnumerateActive() do
            resetFunc(itemFrame)
        end
    end)
end

function SkinningReset.RestoreAllInPool(framePool)
    if not framePool then return end

    pcall(function()
        for itemFrame in framePool:EnumerateActive() do
            SkinningReset.RestoreFrame(itemFrame)
        end
    end)
end
