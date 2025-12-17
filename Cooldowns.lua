local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Cooldowns = addon:NewModule("Cooldowns", "AceEvent-3.0", "AceHook-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName, true)

-- Defaults (Moved to Core.lua)

-- Widget Handling
local cdContainer
local hijackedFrames = {}

-- Target Frames
local targets = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    -- "BuffIconCooldownViewer" -- Optional for later
}

function Cooldowns:OnInitialize()
    self.db = addon.db
    
    StaticPopupDialogs["ACTIONHUD_COOLDOWN_RELOAD"] = {
        text = "ActionHud: Disabling the Cooldown Manager requires a UI Reload to fully restore native Blizzard frames.",
        button1 = "Reload Now",
        button2 = "Later",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

function Cooldowns:OnEnable()
    if self.db.profile.debugDiscovery then print("ActionHud Debug: Cooldown Module Enabled") end
    if not self.db.profile.cdEnabled then return end
    
    -- Create our container anchored to the main HUD
    if not cdContainer then
        local main = _G["ActionHudFrame"]
        if main then
            cdContainer = CreateFrame("Frame", "ActionHudCooldownContainer", main)
            cdContainer:SetSize(1, 1) -- Anchor point
            cdContainer:SetPoint("CENTER", main, "CENTER", 0, 0)
        end
    end
    
    -- Scan immediately
    self:ScanForWidgets()
    
    -- Register events that might re-create widgets
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ScanForWidgets")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "ScanForWidgets")
end

function Cooldowns:OnDisable()
    if cdContainer then cdContainer:Hide() end
    
    -- Check if we hijacked anything
    local hasHijack = false
    for _ in pairs(hijackedFrames) do hasHijack = true break end
    
    if hasHijack then
        StaticPopup_Show("ACTIONHUD_COOLDOWN_RELOAD")
    end
end

function Cooldowns:ScanForWidgets()
    for _, name in ipairs(targets) do
        local frame = _G[name]
        if frame and not hijackedFrames[frame] then
            if self.db.profile.debugDiscovery then
                 print("ActionHud: Found Global Frame -> " .. name)
            end
            self:HijackFrame(frame)
        end
    end
    self:UpdateLayout()
end

function Cooldowns:HijackFrame(frame)
    if hijackedFrames[frame] then return end 
    hijackedFrames[frame] = true
    
    frame:SetParent(cdContainer)
    frame:ClearAllPoints()
    
    if frame.Layout then
        hooksecurefunc(frame, "Layout", function() self:ApplyStyle(frame) end)
    end
    
    -- Prevent native anchors
    hooksecurefunc(frame, "SetPoint", function(f)
        if f:GetParent() ~= cdContainer and self.db.profile.cdEnabled then
             -- Logic handled by UpdateLayout
        end
    end)
    
    self:ApplyStyle(frame)
end

function Cooldowns:ApplyStyle(frame)
    if not self.db.profile.cdEnabled then return end
    local p = self.db.profile
    local name = frame:GetName()
    
    local w, h = 40, 40
    -- Removed implicit scale multiplier; user controls raw size
    if name == "EssentialCooldownViewer" then
        w, h = p.cdEssentialWidth, p.cdEssentialHeight
    elseif name == "UtilityCooldownViewer" then
        w, h = p.cdUtilityWidth, p.cdUtilityHeight
    end
    
    local children = { frame:GetChildren() }
    if #children == 0 then 
        frame:SetSize(1, 1)
        return 
    end

    local sorted = {}
    for _, child in ipairs(children) do
        if child:IsShown() then
            table.insert(sorted, {
                frame = child,
                x = child:GetLeft() or 0
            })
        else
            -- Ensure hidden children don't block
            if child:IsVisible() then child:Hide() end
        end
    end
    table.sort(sorted, function(a,b) return a.x < b.x end)
    
    local count = #sorted
    local margin = 2
    local totalWidth = (count * w) + ((count - 1) * margin)
    if totalWidth < 1 then totalWidth = 1 end
    
    frame:SetSize(totalWidth, h)
    
    local rx = 0
    for _, item in ipairs(sorted) do
        local child = item.frame
        child:ClearAllPoints()
        child:SetScale(1)
        child:SetSize(w, h)
        child:SetPoint("LEFT", frame, "LEFT", rx, 0)
        
        rx = rx + w + margin
        
        -- Skinning (Aspect Ratio Crop)
        local aspect = w / h
        local L, R, T, B = 0.08, 0.92, 0.08, 0.92 -- Default square crop (0.84 span)
        
        if aspect > 1 then
            -- Wide: Crop Top/Bottom to fit width
            local spanH = 0.84 / aspect
            T = 0.5 - (spanH / 2)
            B = 0.5 + (spanH / 2)
        elseif aspect < 1 then
            -- Tall: Crop Left/Right to fit height
            local spanW = 0.84 * aspect
            L = 0.5 - (spanW / 2)
            R = 0.5 + (spanW / 2)
        end
        
        if child.Icon then
            child.Icon:SetTexCoord(L, R, T, B)
            child.Icon:SetDrawLayer("ARTWORK")
        elseif child.icon then
            child.icon:SetTexCoord(L, R, T, B)
            child.icon:SetDrawLayer("ARTWORK")
        end
        
        if child.Cooldown then child.Cooldown:SetAllPoints(child) end
        if child.cooldown then child.cooldown:SetAllPoints(child) end
        
        -- Font Styling (Charges)
        local fSize = p.cdCountFontSize or 12
        
        local function StyleFS(fs)
             fs:SetFont("Fonts\\FRIZQT__.TTF", fSize, "OUTLINE")
             fs:ClearAllPoints()
             fs:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", 2, 0)
             fs:SetDrawLayer("OVERLAY", 7)
        end
        
        local function IsCount(fs)
             if fs:GetObjectType() ~= "FontString" then return false end
             local text = fs:GetText()
             if not text or not text:match("^%d+$") then return false end
             if not fs:IsShown() then return false end
             -- Heuristic: Position
             local p1, _, _, _, _ = fs:GetPoint()
             if p1 and (p1:find("BOTTOM") or p1:find("RIGHT")) then return true end
             return true
        end
        
        local function ScanFrame(f)
             if f.Count and f.Count.SetFont then StyleFS(f.Count) end
             if f.count and f.count.SetFont then StyleFS(f.count) end
             
             for _, r in ipairs({f:GetRegions()}) do
                 if IsCount(r) then StyleFS(r) end
             end
        end
        
        -- 1. Scan the Icon Button itself
        ScanFrame(child)
        
        -- 2. Scan Children (CMT Method 3)
        for _, gc in ipairs({child:GetChildren()}) do
             -- Avoid re-styling cooldown numbers if they slip through (unlikely if IsCount checks digits)
             if gc ~= child.Cooldown and gc ~= child.cooldown then
                  ScanFrame(gc)
             end
        end
        
        -- Aggressive clean up of native decorations
        if child.SetNormalTexture then child:SetNormalTexture("") end
        if child.SetHighlightTexture then child:SetHighlightTexture("") end
        if child.SetPushedTexture then child:SetPushedTexture("") end
        if child.SetDisabledTexture then child:SetDisabledTexture("") end
        
        if child.Border then child.Border:SetAlpha(0) end
        if child.CircleMask then child.CircleMask:Hide() end
        
        for _, r in ipairs({child:GetRegions()}) do
            if r:GetObjectType() == "MaskTexture" then
                 r:Hide()
            elseif r:GetObjectType() == "Texture" then
               -- Hide EVERYTHING that isn't the icon
               if r ~= child.Icon and r ~= child.icon then
                   r:SetAlpha(0)
               end
            end
        end

    end
end

function Cooldowns:UpdateLayout()
    if not cdContainer then return end
    local main = _G["ActionHudFrame"]
    if not main then return end
    local p = self.db.profile
    
    -- 1. Determine Anchor (HUD or Resources)
    local anchorFrame = main
    
    if ns.Resources and ns.Resources.GetContainer then
        local resContainer = ns.Resources:GetContainer()
        if resContainer and resContainer:IsShown() then
            local resPos = addon.db.profile.resPosition
            if resPos == p.cdPosition then
                anchorFrame = resContainer
            end
        end
    end
    
    -- 2. Position Container
    cdContainer:ClearAllPoints()
    cdContainer:SetScale(1.0)
    
    local gap = p.cdGap
    if p.cdPosition == "TOP" then
        cdContainer:SetPoint("BOTTOM", anchorFrame, "TOP", 0, gap)
    else 
        cdContainer:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -gap)
    end
    cdContainer:Show()
    
    -- 3. Determine Bar Order
    local orderedFrames = {}
    local essential = _G["EssentialCooldownViewer"]
    local utility = _G["UtilityCooldownViewer"]
    
    if p.cdReverse then
        if utility then table.insert(orderedFrames, utility) end
        if essential then table.insert(orderedFrames, essential) end
    else
        if essential then table.insert(orderedFrames, essential) end
        if utility then table.insert(orderedFrames, utility) end
    end
    
    -- 4. Stack Bars
    local spacing = p.cdSpacing
    for i, frame in ipairs(orderedFrames) do
        frame:ClearAllPoints()
        frame:SetParent(cdContainer)
        self:ApplyStyle(frame) -- Will resize frame to fit content
        
        if i == 1 then
            if p.cdPosition == "TOP" then
                frame:SetPoint("BOTTOM", cdContainer, "BOTTOM", 0, 0)
            else
                frame:SetPoint("TOP", cdContainer, "TOP", 0, 0)
            end
        else
            local prev = orderedFrames[i-1]
            if p.cdPosition == "TOP" then
                frame:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
            else
                frame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
            end
        end
    end
end
