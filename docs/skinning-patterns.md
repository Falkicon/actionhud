# Cooldown Frame Skinning Patterns

Research notes from analyzing WoW Midnight (12.0) addons that skin CooldownViewer frames.

## Reference Addons

- **Masque_CooldownStyle** - `_beta_\Interface\AddOns\Masque_CooldownStyle\`
- **TweaksUI_Cooldowns** - `_beta_\Interface\AddOns\TweaksUI_Cooldowns\`

---

## 1. Frame Discovery & Identification

### Target Frames (Blizzard CooldownViewers)

```lua
local TRACKERS = {
    { name = "EssentialCooldownViewer", key = "essential" },
    { name = "UtilityCooldownViewer",   key = "utility" },
    { name = "BuffIconCooldownViewer",  key = "buffs" },
}

-- Access via global name
local viewer = _G["BuffIconCooldownViewer"]
```

### Icon Detection Pattern

```lua
-- TweaksUI pattern: Check for icon/cooldown elements
local function IsIcon(frame)
    if not frame then return false end
    if not frame.GetWidth then return false end

    local w, h = frame:GetWidth(), frame:GetHeight()
    if not w or not h or w < 10 or h < 10 then return false end

    -- Check for Icon texture
    if frame.Icon or frame.icon then return true end

    -- Check for cooldown element
    if frame.Cooldown or frame.cooldown then return true end

    return false
end
```

### Icon Collection (Nested Children)

```lua
-- Some viewers have nested container frames
local function CollectIcons(viewer)
    local icons = {}
    local numChildren = viewer:GetNumChildren() or 0

    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        if IsIcon(child) then
            icons[#icons + 1] = child
        elseif child and child.GetNumChildren then
            -- Check nested children (container frames)
            local numNested = child:GetNumChildren() or 0
            for j = 1, numNested do
                local nested = select(j, child:GetChildren())
                if IsIcon(nested) then
                    icons[#icons + 1] = nested
                end
            end
        end
    end
    return icons
end
```

---

## 2. Reset CSS Equivalent: Clean Slate Pattern

### Approach A: Store & Hide (TweaksUI)

The key insight: **Store original alphas** so you can restore them later.

```lua
-- Hide ALL textures except the icon, storing original state
local function StripForMasque(button, iconTexture, cooldownFrame)
    button._TUI_HiddenRegions = button._TUI_HiddenRegions or {}

    -- Direct regions
    for _, region in ipairs({button:GetRegions()}) do
        if region and region:GetObjectType() == "Texture" then
            if region ~= iconTexture then
                local oldAlpha = region:GetAlpha()
                if oldAlpha > 0 then
                    button._TUI_HiddenRegions[region] = oldAlpha
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- Child frame regions (skip cooldown frame)
    for _, child in ipairs({button:GetChildren()}) do
        if child ~= cooldownFrame and child.GetRegions then
            for _, region in ipairs({child:GetRegions()}) do
                if region and region:GetObjectType() == "Texture" then
                    local oldAlpha = region:GetAlpha()
                    if oldAlpha > 0 then
                        button._TUI_HiddenRegions[region] = oldAlpha
                        region:SetAlpha(0)
                    end
                end
            end
        end
    end
end
```

### Approach B: Named Element Hiding (Simpler)

```lua
-- Hide known Blizzard decoration elements
local function StripBlizzardDecorations(itemFrame)
    if not itemFrame then return end
    if itemFrame._stripped then return end  -- Only once

    local regions = {itemFrame:GetRegions()}
    for _, region in ipairs(regions) do
        -- MaskTextures remove rounded corners
        if region:IsObjectType("MaskTexture") then
            region:Hide()
        -- Hide non-icon textures
        elseif region:IsObjectType("Texture") and region ~= itemFrame.Icon then
            region:Hide()
        end
    end

    -- Standard icon crop (remove edge pixels)
    if itemFrame.Icon then
        itemFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    itemFrame._stripped = true
end
```

### Restoration Pattern

```lua
local function RestoreBlizzardDecorations(button)
    -- Restore hidden regions
    if button._TUI_HiddenRegions then
        for region, oldAlpha in pairs(button._TUI_HiddenRegions) do
            if region and region.SetAlpha then
                region:SetAlpha(oldAlpha)
            end
        end
        button._TUI_HiddenRegions = nil
    end

    -- Restore named elements
    if button._TUI_HiddenElements then
        if button.Border then button.Border:SetAlpha(button._TUI_HiddenElements.Border or 1) end
        if button.IconBorder then button.IconBorder:SetAlpha(button._TUI_HiddenElements.IconBorder or 1) end
        button._TUI_HiddenElements = nil
    end

    button._stripped = nil
end
```

---

## 3. Hook Management: Preventing Duplicates

### Flag Pattern (Masque_CooldownStyle)

```lua
local function HideCooldownEffects(child)
    local frames = {"PandemicIcon", "ProcStartFlipbook", "Finish"}

    for _, name in ipairs(frames) do
        local f = child[name]
        if f then
            f:Hide()
            f:SetAlpha(0)

            -- CRITICAL: Only hook once
            if not f._NoHook then
                f._NoHook = true
                child:HookScript("OnShow", function(self)
                    local ff = self[name]
                    if ff then ff:Hide(); ff:SetAlpha(0) end
                end)
            end
        end
    end
end
```

### Tracking Pattern (TweaksUI)

```lua
-- Track hooked viewers
local hookedViewers = {}  -- [viewerFrame] = trackerKey

local function HookViewer(viewer, trackerKey)
    if hookedViewers[viewer] then return end  -- Already hooked

    -- Hook RefreshLayout
    if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", function()
            ApplyCustomLayout(viewer, trackerKey)
        end)
    end

    -- Hook OnAcquireItemFrame for new icons
    if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
            StyleItemFrame(itemFrame, trackerKey)
        end)
    end

    hookedViewers[viewer] = trackerKey
end
```

---

## 4. Border & Opacity Control

### Border Alpha Pattern

```lua
local function ApplyBorderAlpha(icon, alpha)
    if not icon then return end
    alpha = alpha or 1.0

    pcall(function()
        -- Try all common border texture names
        if icon.Border then icon.Border:SetAlpha(alpha) end
        if icon.border then icon.border:SetAlpha(alpha) end
        if icon.IconBorder then icon.IconBorder:SetAlpha(alpha) end
        if icon.iconBorder then icon.iconBorder:SetAlpha(alpha) end

        -- Check NormalTexture (button background)
        if icon.GetNormalTexture then
            local normal = icon:GetNormalTexture()
            if normal then normal:SetAlpha(alpha) end
        end

        -- Search all regions for border-like textures
        for _, region in ipairs({icon:GetRegions()}) do
            if region:GetObjectType() == "Texture" then
                local texturePath = region:GetTexture() or ""
                if type(texturePath) == "string" then
                    if texturePath:find("Border") or texturePath:find("Highlight") then
                        region:SetAlpha(alpha)
                    end
                end
            end
        end
    end)
end
```

---

## 5. Masque Integration

### Group Creation

```lua
local Masque = LibStub("Masque", true)
local MasqueGroups = {}

local function InitializeMasque()
    if not Masque then return false end

    local trackerNames = {
        essential = "Essential Cooldowns",
        utility = "Utility Cooldowns",
        buffs = "Buff Tracker",
    }

    for key, displayName in pairs(trackerNames) do
        MasqueGroups[key] = Masque:Group("MyAddon", displayName)
    end

    -- Register for skin changes
    Masque:RegisterCallback("MyAddon", function(_, group, skinID)
        C_Timer.After(0.1, function()
            RefreshAllLayouts()
        end)
    end)
end
```

### Adding Buttons to Masque

```lua
local function AddToMasque(trackerKey, button)
    local group = MasqueGroups[trackerKey]
    if not group then return end
    if button._MasqueAdded then return end

    -- Build button data for Masque
    local data = {
        Icon = button.Icon or button.icon,
        Cooldown = button.Cooldown or button.cooldown,
        Count = button.Count or button.count,
        Border = button.Border or button.border or button.IconBorder,
        Normal = button:GetNormalTexture(),
        Pushed = button:GetPushedTexture(),
        Highlight = button:GetHighlightTexture(),
    }

    -- Hide Blizzard visuals before adding to Masque
    StripForMasque(button, data.Icon, data.Cooldown)

    -- Add to Masque group
    group:AddButton(button, data)
    button._MasqueAdded = true
    button._MasqueGroup = trackerKey
end
```

---

## 6. Combat-Safe Styling

### pcall Wrapper for Secret Values

```lua
-- Texture fileID can be "secret" during combat
local function GetIconTextureID(icon)
    if not icon then return 0 end
    local textureObj = icon.Icon or icon.icon
    if textureObj and textureObj.GetTextureFileID then
        local ok, fileID = pcall(function()
            local id = textureObj:GetTextureFileID()
            return (id and id > 0) and id or nil
        end)
        if ok and fileID then return fileID end
    end
    return 0
end
```

### Deferred Updates

```lua
-- Flag-based update system
local needsLayoutUpdate = {}  -- [trackerKey] = true

-- Set flag (safe to call anytime)
local function RequestLayoutUpdate(trackerKey)
    needsLayoutUpdate[trackerKey] = true
end

-- Process flags (call on OnUpdate or timer)
local function ProcessLayoutUpdates()
    for trackerKey, needed in pairs(needsLayoutUpdate) do
        if needed then
            local viewer = _G[GetViewerName(trackerKey)]
            if viewer and viewer:IsShown() then
                ApplyCustomLayout(viewer, trackerKey)
            end
            needsLayoutUpdate[trackerKey] = nil
        end
    end
end
```

### Combat Lockdown Check

```lua
local function SafelyModifyFrame(frame, callback)
    if InCombatLockdown() then
        -- Defer to after combat
        local ticker
        ticker = C_Timer.NewTicker(0.5, function()
            if not InCombatLockdown() then
                callback(frame)
                ticker:Cancel()
            end
        end)
    else
        callback(frame)
    end
end
```

---

## 7. Element Hierarchy

Standard CooldownViewer icon structure:

```
ItemFrame (Button)
├── Icon (Texture)           -- Main spell icon - PRESERVE
├── Cooldown (CooldownFrame) -- Swipe animation - PRESERVE
├── Border/IconBorder        -- Decorative border - HIDE or STYLE
├── MaskTexture              -- Rounded corner mask - HIDE
├── Applications/Count       -- Stack count text - STYLE
├── PandemicIcon            -- Red warning icon - HIDE
├── ProcStartFlipbook       -- Flash effect - HIDE
└── Finish                   -- Completion effect - HIDE
```

---

## 8. Recommended Architecture for ActionHud

### Skinning Manager Module

```lua
local SkinningManager = {}

-- State
SkinningManager.hookedViewers = {}
SkinningManager.strippedIcons = {}  -- [icon] = {originalState}

-- Public API
function SkinningManager:Enable(viewerName, trackerKey)
    local viewer = _G[viewerName]
    if not viewer then return false end

    self:HookViewer(viewer, trackerKey)
    self:ApplyToAllIcons(viewer, trackerKey)
    return true
end

function SkinningManager:Disable(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    -- Restore all icons
    for icon, state in pairs(self.strippedIcons) do
        if icon:GetParent() == viewer then
            self:RestoreIcon(icon, state)
        end
    end
end

-- Internal
function SkinningManager:StripIcon(icon)
    if self.strippedIcons[icon] then return end

    local state = {
        regions = {},
        texCoords = icon.Icon and {icon.Icon:GetTexCoord()} or nil,
    }

    -- Store and hide regions
    for _, region in ipairs({icon:GetRegions()}) do
        if region:GetObjectType() == "Texture" and region ~= icon.Icon then
            state.regions[region] = region:GetAlpha()
            region:SetAlpha(0)
        elseif region:IsObjectType("MaskTexture") then
            state.regions[region] = true
            region:Hide()
        end
    end

    -- Apply custom texcoords
    if icon.Icon then
        icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    self.strippedIcons[icon] = state
end

function SkinningManager:RestoreIcon(icon, state)
    if not state then return end

    for region, value in pairs(state.regions) do
        if type(value) == "number" then
            region:SetAlpha(value)
        else
            region:Show()
        end
    end

    if state.texCoords and icon.Icon then
        icon.Icon:SetTexCoord(unpack(state.texCoords))
    end

    self.strippedIcons[icon] = nil
end
```

---

## Key Takeaways

1. **Store before hiding** - Always save original alpha/visibility before modifying
2. **Flag-based deduplication** - Use `_hooked`, `_stripped` flags on frames
3. **Iterate both regions AND children** - Icons have nested structure
4. **pcall for secret values** - Combat protection for texture IDs
5. **Defer layout updates** - Use flag + timer pattern for combat safety
6. **Separate concerns** - Hook management vs. styling vs. restoration
