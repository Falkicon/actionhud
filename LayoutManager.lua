-- LayoutManager.lua
-- Central layout system for ActionHud vertical stack positioning

local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LayoutManager = addon:NewModule("LayoutManager")
ns.LayoutManager = LayoutManager

-- Module display names for UI
local MODULE_NAMES = {
    trackedBuffs = "Tracked Buffs",
    resources = "Resource Bars",
    actionBars = "Action Bars",
    cooldowns = "Cooldowns",
}

-- Default stack order and gaps
local DEFAULT_STACK = { "trackedBuffs", "resources", "actionBars", "cooldowns" }
local DEFAULT_GAPS = { 4, 4, 4, 0 }

-- Cache of module heights (updated by modules when they render)
local moduleHeights = {}

function LayoutManager:OnInitialize()
    -- Nothing needed here - we use addon.db directly
end

function LayoutManager:OnEnable()
    -- Ensure layout data exists
    self:EnsureLayoutData()
end

-- Get profile safely (addon.db may not be set during very early calls)
local function GetProfile()
    if addon.db and addon.db.profile then
        return addon.db.profile
    end
    return nil
end

-- Ensure layout table exists with valid data
function LayoutManager:EnsureLayoutData()
    local p = GetProfile()
    if not p then return end  -- DB not ready yet
    if not p.layout then
        p.layout = {
            stack = CopyTable(DEFAULT_STACK),
            gaps = CopyTable(DEFAULT_GAPS),
        }
    end
    
    -- Validate stack has all modules
    local hasModule = {}
    for _, id in ipairs(p.layout.stack) do
        hasModule[id] = true
    end
    
    -- Add any missing modules
    for _, id in ipairs(DEFAULT_STACK) do
        if not hasModule[id] then
            table.insert(p.layout.stack, id)
            table.insert(p.layout.gaps, 0)
        end
    end
    
    -- Ensure gaps array matches stack length
    while #p.layout.gaps < #p.layout.stack do
        table.insert(p.layout.gaps, 0)
    end
end

-- Get the ordered stack
function LayoutManager:GetStack()
    self:EnsureLayoutData()
    local p = GetProfile()
    if p and p.layout then
        return p.layout.stack
    end
    return CopyTable(DEFAULT_STACK)  -- Return default if not ready
end

-- Get gaps array
function LayoutManager:GetGaps()
    self:EnsureLayoutData()
    local p = GetProfile()
    if p and p.layout then
        return p.layout.gaps
    end
    return CopyTable(DEFAULT_GAPS)  -- Return default if not ready
end

-- Get display name for a module
function LayoutManager:GetModuleName(moduleId)
    return MODULE_NAMES[moduleId] or moduleId
end

-- Get all available module IDs
function LayoutManager:GetAllModuleIds()
    return { "trackedBuffs", "resources", "actionBars", "cooldowns" }
end

-- Set height for a module (called by modules during their UpdateLayout)
function LayoutManager:SetModuleHeight(moduleId, height)
    moduleHeights[moduleId] = height or 0
end

-- Get height for a module
function LayoutManager:GetModuleHeight(moduleId)
    return moduleHeights[moduleId] or 0
end

-- Calculate the Y position for a module (offset from container TOP)
-- Returns: yOffset (negative value, since we anchor from TOP going down)
function LayoutManager:GetModulePosition(moduleId)
    local stack = self:GetStack()
    local gaps = self:GetGaps()
    
    local yOffset = 0
    for i, id in ipairs(stack) do
        if id == moduleId then
            return -yOffset  -- Return negative for TOPLEFT anchoring
        end
        -- Add this module's height + the gap after it
        yOffset = yOffset + self:GetModuleHeight(id) + (gaps[i] or 0)
    end
    
    -- Module not found, return 0
    return 0
end

-- Calculate total stack height
function LayoutManager:GetStackHeight()
    local stack = self:GetStack()
    local gaps = self:GetGaps()
    
    local totalHeight = 0
    for i, id in ipairs(stack) do
        totalHeight = totalHeight + self:GetModuleHeight(id)
        if i < #stack then
            totalHeight = totalHeight + (gaps[i] or 0)
        end
    end
    
    return totalHeight
end

-- Get the index of a module in the stack
function LayoutManager:GetModuleIndex(moduleId)
    local stack = self:GetStack()
    for i, id in ipairs(stack) do
        if id == moduleId then
            return i
        end
    end
    return nil
end

-- Move a module up or down in the stack
-- direction: "up" (toward index 1) or "down" (toward end)
function LayoutManager:MoveModule(moduleId, direction)
    local stack = self:GetStack()
    local gaps = self:GetGaps()
    local idx = self:GetModuleIndex(moduleId)
    
    if not idx then return false end
    
    local newIdx
    if direction == "up" and idx > 1 then
        newIdx = idx - 1
    elseif direction == "down" and idx < #stack then
        newIdx = idx + 1
    else
        return false  -- Can't move
    end
    
    -- Swap in stack
    stack[idx], stack[newIdx] = stack[newIdx], stack[idx]
    
    -- Swap gaps (gaps follow their modules)
    gaps[idx], gaps[newIdx] = gaps[newIdx], gaps[idx]
    
    -- Trigger full layout update
    self:TriggerLayoutUpdate()
    
    return true
end

-- Set gap after a module (by index)
function LayoutManager:SetGap(index, value)
    local gaps = self:GetGaps()
    if index >= 1 and index <= #gaps then
        gaps[index] = value
        self:TriggerLayoutUpdate()
    end
end

-- Get gap after a module (by index)
function LayoutManager:GetGap(index)
    local gaps = self:GetGaps()
    return gaps[index] or 0
end

-- Reset to default order
function LayoutManager:ResetToDefault()
    local p = GetProfile()
    if not p then return end
    p.layout = {
        stack = CopyTable(DEFAULT_STACK),
        gaps = CopyTable(DEFAULT_GAPS),
    }
    self:TriggerLayoutUpdate()
end

-- Trigger layout update for all modules
function LayoutManager:TriggerLayoutUpdate()
    local stack = self:GetStack()
    local gaps = self:GetGaps()
    
    addon:Log("=== Layout Update Triggered ===", "layout")
    addon:Log(string.format("Stack order: %s", table.concat(stack, " -> ")), "layout")
    addon:Log(string.format("Gaps: %s", table.concat(gaps, ", ")), "layout")
    
    -- First pass: let modules calculate their heights
    for i, moduleId in ipairs(stack) do
        local moduleName = moduleId
        -- Map our IDs to actual module names
        if moduleId == "actionBars" then moduleName = "ActionBars"
        elseif moduleId == "resources" then moduleName = "Resources"
        elseif moduleId == "cooldowns" then moduleName = "Cooldowns"
        elseif moduleId == "trackedBuffs" then moduleName = "TrackedBuffs"
        end
        
        local m = addon:GetModule(moduleName, true)
        if m and m.CalculateHeight then
            local height = m:CalculateHeight()
            self:SetModuleHeight(moduleId, height)
            addon:Log(string.format("[%d] %s: height=%d, gap_after=%d", i, moduleId, height, gaps[i] or 0), "layout")
        else
            addon:Log(string.format("[%d] %s: NO CalculateHeight function or module not found", i, moduleId), "layout")
        end
    end
    
    -- Update main container size
    self:UpdateContainerSize()
    
    local main = _G["ActionHudFrame"]
    if main then
        addon:Log(string.format("Container size: %dx%d", main:GetWidth(), main:GetHeight()), "layout")
    end
    
    -- Second pass: position all modules
    addon:Log("--- Positioning modules ---", "layout")
    for i, moduleId in ipairs(stack) do
        local moduleName = moduleId
        if moduleId == "actionBars" then moduleName = "ActionBars"
        elseif moduleId == "resources" then moduleName = "Resources"
        elseif moduleId == "cooldowns" then moduleName = "Cooldowns"
        elseif moduleId == "trackedBuffs" then moduleName = "TrackedBuffs"
        end
        
        local yOffset = self:GetModulePosition(moduleId)
        addon:Log(string.format("[%d] %s: calculated yOffset=%d", i, moduleId, yOffset), "layout")
        
        local m = addon:GetModule(moduleName, true)
        if m and m.ApplyLayoutPosition then
            m:ApplyLayoutPosition()
        end
    end
    
    -- Also update TrackedBars (sidecar) since it may reference HUD position
    local tb = addon:GetModule("TrackedBars", true)
    if tb and tb.UpdateLayout then
        tb:UpdateLayout()
    end
    
    addon:Log("=== Layout Update Complete ===", "layout")
end

-- Update the main HUD container size
function LayoutManager:UpdateContainerSize()
    local main = _G["ActionHudFrame"]
    if not main then return end
    
    local stack = self:GetStack()
    local totalHeight = self:GetStackHeight()
    
    -- Width is determined by the widest module (typically ActionBars)
    local maxWidth = 0
    for _, id in ipairs(stack) do
        local moduleName = id
        if id == "actionBars" then moduleName = "ActionBars"
        elseif id == "resources" then moduleName = "Resources"
        elseif id == "cooldowns" then moduleName = "Cooldowns"
        elseif id == "trackedBuffs" then moduleName = "TrackedBuffs"
        end
        
        local m = addon:GetModule(moduleName, true)
        if m and m.GetLayoutWidth then
            local w = m:GetLayoutWidth()
            if w > maxWidth then maxWidth = w end
        end
    end
    
    -- Fallback to ActionBars width if nothing reported
    if maxWidth == 0 then
        local p = addon.db.profile
        maxWidth = 6 * (p.iconWidth or 20)
    end
    
    main:SetSize(maxWidth, math.max(totalHeight, 1))
end

-- Get the main container frame
function LayoutManager:GetContainer()
    return _G["ActionHudFrame"]
end

-- Migration: Convert old position settings to new layout structure
function LayoutManager:MigrateOldSettings()
    local p = GetProfile()
    if not p then return end
    
    -- Check if migration is needed (old settings exist, new don't)
    if p.layout then return end  -- Already migrated
    
    -- Build new stack based on old position settings
    local topModules = {}
    local bottomModules = {}
    
    -- TrackedBuffs was always on top in old system
    table.insert(topModules, { id = "trackedBuffs", gap = p.buffsGap or 25 })
    
    -- Resources
    if p.resPosition == "TOP" or p.resPosition == nil then
        table.insert(topModules, { id = "resources", gap = p.resOffset or 1 })
    else
        table.insert(bottomModules, { id = "resources", gap = p.resOffset or 1 })
    end
    
    -- ActionBars is the center anchor point
    -- Modules above actionBars go in topModules, below go in bottomModules
    
    -- Cooldowns
    if p.cdPosition == "TOP" then
        table.insert(topModules, { id = "cooldowns", gap = p.cdGap or 4 })
    else
        table.insert(bottomModules, { id = "cooldowns", gap = p.cdGap or 4 })
    end
    
    -- Build final stack: top modules (reversed), actionBars, bottom modules
    local stack = {}
    local gaps = {}
    
    -- Top modules go first (furthest from actionBars to closest)
    for i = #topModules, 1, -1 do
        table.insert(stack, topModules[i].id)
        table.insert(gaps, topModules[i].gap)
    end
    
    -- ActionBars in the middle
    table.insert(stack, "actionBars")
    table.insert(gaps, 0)  -- Gap after actionBars
    
    -- Bottom modules (closest to actionBars to furthest)
    for _, mod in ipairs(bottomModules) do
        table.insert(stack, mod.id)
        table.insert(gaps, mod.gap)
    end
    
    -- Store the new layout
    p.layout = {
        stack = stack,
        gaps = gaps,
    }
    
    addon:Log("Layout migration complete: " .. table.concat(stack, " -> "), "debug")
end
