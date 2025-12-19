-- SettingsUI.lua
-- Defines the configuration options using AceConfig-3.0

local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")

-- Constants
local CVAR_COOLDOWN_VIEWER_ENABLED = "cooldownViewerEnabled"

-- Helper to check if Blizzard's Cooldown Manager is enabled
local function IsBlizzardCooldownViewerEnabled()
    if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
        return CVarCallbackRegistry:GetCVarValueBool(CVAR_COOLDOWN_VIEWER_ENABLED)
    end
    -- Fallback for older clients
    local val = GetCVar(CVAR_COOLDOWN_VIEWER_ENABLED)
    return val == "1"
end

-- Helper to open the Gameplay Enhancements settings panel
-- Category ID 42 = "Gameplay Enhancements" (discovered via testing)
local function OpenGameplayEnhancements()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(42)  -- Gameplay Enhancements
        return true
    end
    
    -- Fallback: Show settings panel and click Game tab
    if SettingsPanel then
        SettingsPanel:Show()
        if SettingsPanel.GameTab then
            SettingsPanel.GameTab:Click()
        end
        print("|cff33ff99ActionHud:|r Navigate to |cffffcc00Gameplay Enhancements|r.")
        return true
    end
    return false
end

function ActionHud:SetupOptions()
    -- ROOT: General
    local generalOptions = {
        name = "ActionHud",
        handler = ActionHud,
        type = 'group',
        args = {
            locked = {
                name = "Lock Frame",
                desc = "Lock the HUD in place. Uncheck to drag.",
                type = "toggle",
                order = 1,
                get = function(info) return self.db.profile.locked end,
                set = function(info, val) 
                    self.db.profile.locked = val
                    self:UpdateLockState()
                end,
            },
            minimapIcon = {
                name = "Show Minimap Icon",
                desc = "Toggle the minimap icon.",
                type = "toggle",
                order = 2,
                hidden = function() return not self.icon end, -- Hide if LibDBIcon not available
                get = function(info) 
                    if not self.db.profile.minimap then return true end
                    return not self.db.profile.minimap.hide 
                end,
                set = function(info, val)
                    if not self.db.profile.minimap then
                        self.db.profile.minimap = { hide = false }
                    end
                    self.db.profile.minimap.hide = not val
                    if self.icon then
                        if val then
                            self.icon:Show("ActionHud")
                        else
                            self.icon:Hide("ActionHud")
                        end
                    end
                end,
            },
            divider = { type = "header", name = "Info & Prerequisites", order = 10 },
            readme = {
                type = "description",
                name = [[|cff33ff99ActionHud 2.3.1|r

A minimalist HUD mirroring Action Bars 1 & 2 in a 6x4 grid.

|cffffcc00Required Setup:|r
Click the button below to open WoW's Gameplay Enhancements settings.

Enable these options:
  - |cffffffffAssisted Highlight|r (rotation glows)
  - |cffffffffEnable Cooldown Manager|r (tracked cooldowns)
  
Use |cffffffffAdvanced Cooldown Settings|r to configure which spells are tracked.
]],
                fontSize = "medium",
                order = 11,
            },
            btnPreReq1 = {
                name = "Open Gameplay Enhancements",
                desc = "Opens WoW Settings directly to Gameplay Enhancements.",
                type = "execute",
                width = "double",
                func = function() OpenGameplayEnhancements() end,
                order = 12,
            },
        },
    }
    
    -- SUB: Action Bars
    local abOptions = {
        name = "Action Bars",
        handler = ActionHud,
        type = "group",
        args = {
            enable = {
                name = "Enable",
                type = "toggle",
                order = 1,
                desc = "Enable the main Action Bar Grid.",
                get = function(info) return ActionHud:GetModule("ActionBars"):IsEnabled() end,
                set = function(info, val) 
                    if val then ActionHud:GetModule("ActionBars"):Enable() 
                    else ActionHud:GetModule("ActionBars"):Disable() end 
                end,
            },
            iconDimensions = { name = "Dimensions", type = "header", order = 10 },
            iconWidth = {
                name = "Icon Width", desc = "Width of the action icons.", type = "range", min = 10, max = 50, step = 1, order = 11,
                get = function(info) return self.db.profile.iconWidth end,
                set = function(info, val) self.db.profile.iconWidth = val; ActionHud:GetModule("ActionBars"):UpdateLayout() end,
            },
            iconHeight = {
                name = "Icon Height", desc = "Height of the action icons.", type = "range", min = 10, max = 50, step = 1, order = 12,
                get = function(info) return self.db.profile.iconHeight end,
                set = function(info, val) self.db.profile.iconHeight = val; ActionHud:GetModule("ActionBars"):UpdateLayout() end,
            },
            visuals = { name = "Visuals & Opacity", type = "header", order = 20 },
            opacity = {
                name = "Background Opacity", desc = "Opacity of empty slots.", type = "range", min = 0, max = 1, step = 0.05, isPercent = true, order = 21,
                get = function(info) return self.db.profile.opacity end,
                set = function(info, val) self.db.profile.opacity = val; ActionHud:GetModule("ActionBars"):UpdateOpacity() end,
            },
            procGlowAlpha = {
                name = "Proc Glow Opacity (Yellow)", type = "range", min = 0, max = 1, step = 0.05, isPercent = true, order = 22,
                get = function(info) return self.db.profile.procGlowAlpha end,
                set = function(info, val) self.db.profile.procGlowAlpha = val; ActionHud:GetModule("ActionBars"):UpdateLayout() end,
            },
            assistGlowAlpha = {
                name = "Assist Glow Opacity (Blue)", type = "range", min = 0, max = 1, step = 0.05, isPercent = true, order = 23,
                get = function(info) return self.db.profile.assistGlowAlpha end,
                set = function(info, val) self.db.profile.assistGlowAlpha = val; ActionHud:GetModule("ActionBars"):UpdateLayout() end,
            },
            fonts = { name = "Fonts", type = "header", order = 30 },
            cooldownFontSize = {
                name = "Cooldown Font Size", type = "range", min = 6, max = 24, step = 1, order = 31,
                get = function(info) return self.db.profile.cooldownFontSize end,
                set = function(info, val) self.db.profile.cooldownFontSize = val; ActionHud:GetModule("ActionBars"):UpdateLayout() end,
            },
            countFontSize = {
                name = "Stack Count Font Size", type = "range", min = 6, max = 24, step = 1, order = 32,
                get = function(info) return self.db.profile.countFontSize end,
                set = function(info, val) self.db.profile.countFontSize = val; ActionHud:GetModule("ActionBars"):UpdateLayout() end,
            },
        },
    }
    
    -- SUB: Resources
    local resOptions = {
        name = "Resource Bars",
        handler = ActionHud,
        type = "group",
        args = {
            enable = {
                name = "Enable", type = "toggle", order = 1,
                get = function(info) return self.db.profile.resEnabled end,
                set = function(info, val) self.db.profile.resEnabled = val; self:UpdateLayout() end,
            },
            showTarget = {
                name = "Show Target Stats", desc = "Split bars to show target health/power.", type = "toggle", order = 2,
                get = function(info) return self.db.profile.resShowTarget end,
                set = function(info, val) self.db.profile.resShowTarget = val; self:UpdateLayout() end,
            },
            position = {
                name = "Position", type = "select", values = { ["TOP"] = "Top", ["BOTTOM"] = "Bottom" }, sorting = { "TOP", "BOTTOM" }, order = 3,
                get = function(info) return self.db.profile.resPosition end,
                set = function(info, val) self.db.profile.resPosition = val; self:UpdateLayout() end,
            },
            layout = { name = "Layout Dimensions", type = "header", order = 10 },
            healthHeight = {
                name = "Health Bar Height", type = "range", min = 1, max = 30, step = 1, order = 11,
                get = function(info) return self.db.profile.resHealthHeight end,
                set = function(info, val) self.db.profile.resHealthHeight = val; self:UpdateLayout() end,
            },
            powerHeight = {
                name = "Power Bar Height", type = "range", min = 1, max = 30, step = 1, order = 12,
                get = function(info) return self.db.profile.resPowerHeight end,
                set = function(info, val) self.db.profile.resPowerHeight = val; self:UpdateLayout() end,
            },
            classHeight = {
                name = "Class Resource Height", desc = "Height of Combo Points, Holy Power, etc.", type = "range", min = 1, max = 20, step = 1, order = 12.5,
                get = function(info) return self.db.profile.resClassHeight end,
                set = function(info, val) self.db.profile.resClassHeight = val; self:UpdateLayout() end,
            },
            offset = {
                name = "Gap from HUD", type = "range", min = 0, max = 50, step = 1, order = 13,
                get = function(info) return self.db.profile.resOffset end,
                set = function(info, val) self.db.profile.resOffset = val; self:UpdateLayout() end,
            },
            spacing = {
                name = "Bar Spacing", type = "range", min = 0, max = 10, step = 1, order = 14,
                get = function(info) return self.db.profile.resSpacing end,
                set = function(info, val) self.db.profile.resSpacing = val; self:UpdateLayout() end,
            },
            gap = {
                name = "Player-Target Gap", desc = "Space between player and target bars.", type = "range", min = 0, max = 50, step = 1, order = 15,
                get = function(info) return self.db.profile.resGap end,
                set = function(info, val) self.db.profile.resGap = val; self:UpdateLayout() end,
            },
        },
    }
    
    -- SUB: Cooldowns
    local cdOptions = {
        name = "Cooldown Manager",
        handler = ActionHud,
        type = "group",
        args = {
            reqNote = {
                name = function()
                    if IsBlizzardCooldownViewerEnabled() then
                        return [[|cff00ff00Blizzard Cooldown Manager is enabled.|r

ActionHud will hide the native UI and display custom-styled proxies.
Use |cffffffffAdvanced Cooldown Settings|r in Gameplay Enhancements to configure tracked spells.]]
                    else
                        return [[|cffff4444Blizzard Cooldown Manager is disabled.|r

You must enable it first in WoW's Gameplay Enhancements settings.
All ActionHud cooldown features are unavailable until enabled.]]
                    end
                end,
                type = "description", order = 0,
            },
            btnOpen = {
                 name = "Open Gameplay Enhancements",
                 desc = "Opens WoW Settings directly to Gameplay Enhancements.",
                 type = "execute",
                 width = "double",
                 func = function() OpenGameplayEnhancements() end,
                 order = 0.5,
            },
            divider = { type = "header", name = "", order = 0.6 },
            enable = {
                name = "Enable", desc = "Enable management of the native Cooldown Manager frame.", type = "toggle", order = 1,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdEnabled end,
                set = function(info, val)
                    self.db.profile.cdEnabled = val
                    ActionHud:GetModule("Cooldowns"):UpdateLayout()
                end,
            },
            position = {
                name = "Position", desc = "Attach to Top or Bottom of the HUD.", type = "select", values = {"Top", "Bottom"}, order = 2,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdPosition == "BOTTOM" and 2 or 1 end,
                set = function(info, val) self.db.profile.cdPosition = (val == 2) and "BOTTOM" or "TOP"; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            gap = {
                name = "Gap from HUD", desc = "Distance from the HUD (or Resource Bars).", type = "range", min = 0, max = 50, step = 1, order = 3,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdGap end,
                set = function(info, val) self.db.profile.cdGap = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            spacing = {
                name = "Bar Spacing", desc = "Space between Essential and Utility bars.", type = "range", min = 0, max = 50, step = 1, order = 4,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdSpacing end,
                set = function(info, val) self.db.profile.cdSpacing = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            reverse = {
                name = "Reverse Order", desc = "Swap the Essential and Utility bars.", type = "toggle", order = 5,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdReverse end,
                set = function(info, val) self.db.profile.cdReverse = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            itemGap = {
                name = "Icon Spacing", desc = "Space between cooldown icons.", type = "range", min = 0, max = 20, step = 1, order = 6,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdItemGap end,
                set = function(info, val) self.db.profile.cdItemGap = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            headerEssential = { type="header", name="Essential Bar", order=10 },
            essWidth = {
                name = "Width", type = "range", min = 10, max = 100, step = 1, order = 11,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdEssentialWidth end,
                set = function(info, val) self.db.profile.cdEssentialWidth = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            essHeight = {
                name = "Height", type = "range", min = 10, max = 100, step = 1, order = 12,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdEssentialHeight end,
                set = function(info, val) self.db.profile.cdEssentialHeight = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            headerUtility = { type="header", name="Utility Bar", order=20 },
            utilWidth = {
                name = "Width", type = "range", min = 10, max = 100, step = 1, order = 21,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdUtilityWidth end,
                set = function(info, val) self.db.profile.cdUtilityWidth = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            utilHeight = {
                name = "Height", type = "range", min = 10, max = 100, step = 1, order = 22,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdUtilityHeight end,
                set = function(info, val) self.db.profile.cdUtilityHeight = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            headerFont = { type="header", name="Typography", order=25 },
            fontSize = {
                name = "Stack Font Size", type = "range", min=6, max=18, step=1, order=26,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdCountFontSize end,
                set = function(info, val) self.db.profile.cdCountFontSize = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            timerFontSize = {
                name = "Timer Font Size", type = "select", order = 27,
                values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
                sorting = { "small", "medium", "large", "huge" },
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.cdTimerFontSize end,
                set = function(info, val) self.db.profile.cdTimerFontSize = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
        },
    }
    
    -- SUB: Tracked Bars
    local tbOptions = {
        name = "Tracked Bars",
        handler = ActionHud,
        type = "group",
        args = {
            reqNote = {
                name = function()
                    if IsBlizzardCooldownViewerEnabled() then
                        return "|cff00ff00Blizzard Cooldown Manager is enabled.|r"
                    else
                        return [[|cffff4444Blizzard Cooldown Manager is disabled.|r

Enable it in Gameplay Enhancements to use Tracked Bars.]]
                    end
                end,
                type = "description", order = 0,
            },
            enable = {
                name = "Enable Tracked Bars", desc = "Enable and style the Tracked Bars (Active Effects) viewer.", type = "toggle", order = 1, width = "full",
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbEnabled end,
                set = function(info, val) self.db.profile.tbEnabled = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            offsets = { name = "Positioning", type = "header", order = 10 },
            tbXOffset = {
                name = "X Offset (Sidecar)", desc = "Horizontal offset from center of HUD.", type = "range", min = -500, max = 500, step = 1, order = 11,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbXOffset end,
                set = function(info, val) self.db.profile.tbXOffset = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            tbYOffset = {
                name = "Y Offset", desc = "Vertical offset from center of HUD.", type = "range", min = -500, max = 500, step = 1, order = 12,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbYOffset end,
                set = function(info, val) self.db.profile.tbYOffset = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            visuals = { name = "Dimensions & Spacing", type = "header", order = 20 },
            tbWidth = {
                name = "Icon Width", type = "range", min = 10, max = 100, step = 1, order = 21,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbWidth end,
                set = function(info, val) self.db.profile.tbWidth = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            tbHeight = {
                name = "Icon Height", type = "range", min = 10, max = 100, step = 1, order = 22,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbHeight end,
                set = function(info, val) self.db.profile.tbHeight = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            tbGap = {
                name = "Icon Spacing", desc = "Distance between items in the stack.", type = "range", min = 0, max = 20, step = 1, order = 23,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbGap end,
                set = function(info, val) self.db.profile.tbGap = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            displayOptions = { name = "Display Options", type = "header", order = 25 },
            tbHideInactive = {
                name = "Hide Inactive Bars", desc = "Only show bars when they are active.", type = "toggle", order = 26,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbHideInactive end,
                set = function(info, val) self.db.profile.tbHideInactive = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            tbInactiveOpacity = {
                name = "Inactive Bar Opacity", desc = "Opacity for inactive (greyed out) bars when not hidden.", type = "range", min = 0.1, max = 1.0, step = 0.1, isPercent = true, order = 27,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() or self.db.profile.tbHideInactive end,
                get = function(info) return self.db.profile.tbInactiveOpacity end,
                set = function(info, val) self.db.profile.tbInactiveOpacity = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            fonts = { name = "Fonts", type = "header", order = 30 },
            tbCountFontSize = {
                name = "Stack Count Font Size", type = "range", min = 6, max = 18, step = 1, order = 31,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbCountFontSize end,
                set = function(info, val) self.db.profile.tbCountFontSize = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            tbTimerFontSize = {
                name = "Timer Font Size", type = "select", order = 32,
                values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
                sorting = { "small", "medium", "large", "huge" },
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.tbTimerFontSize end,
                set = function(info, val) self.db.profile.tbTimerFontSize = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
        },
    }
    
    -- SUB: Tracked Buffs
    local buffOptions = {
        name = "Tracked Buffs",
        handler = ActionHud,
        type = "group",
        args = {
            reqNote = {
                name = function()
                    if IsBlizzardCooldownViewerEnabled() then
                        return "|cff00ff00Blizzard Cooldown Manager is enabled.|r"
                    else
                        return [[|cffff4444Blizzard Cooldown Manager is disabled.|r

Enable it in Gameplay Enhancements to use Tracked Buffs.]]
                    end
                end,
                type = "description", order = 0,
            },
            enable = {
                name = "Enable Tracked Buffs", desc = "Enable and style the long-duration buffs center-top.", type = "toggle", order = 1, width = "full",
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsEnabled end,
                set = function(info, val) self.db.profile.buffsEnabled = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            offsets = { name = "Positioning", type = "header", order = 10 },
            buffsGap = {
                name = "Gap from HUD", desc = "Distance above the personal health/power bars.", type = "range", min = 0, max = 200, step = 1, order = 11,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsGap end,
                set = function(info, val) self.db.profile.buffsGap = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            visuals = { name = "Dimensions & Spacing", type = "header", order = 20 },
            buffsWidth = {
                name = "Icon Width", type = "range", min = 10, max = 100, step = 1, order = 21,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsWidth end,
                set = function(info, val) self.db.profile.buffsWidth = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            buffsHeight = {
                name = "Icon Height", type = "range", min = 10, max = 100, step = 1, order = 22,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsHeight end,
                set = function(info, val) self.db.profile.buffsHeight = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            buffsSpacing = {
                name = "Icon Spacing", type = "range", min = 0, max = 20, step = 1, order = 23,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsSpacing end,
                set = function(info, val) self.db.profile.buffsSpacing = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            displayOptions = { name = "Display Options", type = "header", order = 25 },
            buffsHideInactive = {
                name = "Hide Inactive Buffs", desc = "Only show buffs when they are active.", type = "toggle", order = 26,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsHideInactive end,
                set = function(info, val) self.db.profile.buffsHideInactive = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            buffsInactiveOpacity = {
                name = "Inactive Buff Opacity", desc = "Opacity for inactive (greyed out) buffs when not hidden.", type = "range", min = 0.1, max = 1.0, step = 0.1, isPercent = true, order = 27,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() or self.db.profile.buffsHideInactive end,
                get = function(info) return self.db.profile.buffsInactiveOpacity end,
                set = function(info, val) self.db.profile.buffsInactiveOpacity = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            fonts = { name = "Fonts", type = "header", order = 30 },
            buffsCountFontSize = {
                name = "Stack Count Font Size", type = "range", min = 6, max = 18, step = 1, order = 31,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsCountFontSize end,
                set = function(info, val) self.db.profile.buffsCountFontSize = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
            buffsTimerFontSize = {
                name = "Timer Font Size", type = "select", order = 32,
                values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
                sorting = { "small", "medium", "large", "huge" },
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.buffsTimerFontSize end,
                set = function(info, val) self.db.profile.buffsTimerFontSize = val; ActionHud:GetModule("Cooldowns"):UpdateLayout() end,
            },
        },
    }

    local debugOptions = {
        name = "Debugging",
        handler = ActionHud,
        type = "group",
        args = {
            desc = {
                type = "description",
                name = "Tools for troubleshooting and frame discovery.",
                order = 1,
            },
            discovery = {
                name = "Debug Discovery", desc = "Logs when new Blizzard widgets are found and hijacked.", type = "toggle", order = 10,
                get = function(info) return self.db.profile.debugDiscovery end,
                set = function(info, val) self.db.profile.debugDiscovery = val end,
            },
            frames = {
                name = "Debug Frames", desc = "Logs detailed information about frame hierarchies and children.", type = "toggle", order = 11,
                get = function(info) return self.db.profile.debugFrames end,
                set = function(info, val) self.db.profile.debugFrames = val end,
            },
            events = {
                name = "Debug Events", desc = "Logs key HUD events to the chat window.", type = "toggle", order = 12,
                get = function(info) return self.db.profile.debugEvents end,
                set = function(info, val) self.db.profile.debugEvents = val end,
            },
            showBlizzardFrames = {
                name = "Show Native Blizzard Frames", desc = "Show both Blizzard's cooldown frames and ActionHud proxies side-by-side for comparison.", type = "toggle", order = 13,
                get = function(info) return self.db.profile.debugShowBlizzardFrames end,
                set = function(info, val) 
                    self.db.profile.debugShowBlizzardFrames = val
                    ActionHud:GetModule("Cooldowns"):UpdateLayout()
                end,
            },
            recordingHeader = { type = "header", name = "Debug Recording", order = 14 },
            recordingStatus = {
                type = "description", order = 15,
                name = function()
                    local count = ActionHud:GetDebugBufferCount()
                    if ActionHud:IsDebugRecording() then
                        return "|cff00ff00Recording...|r (count updates on Stop/Export)"
                    else
                        return "|cffaaaaaa Stopped|r (" .. count .. " entries buffered)"
                    end
                end,
            },
            recordButton = {
                name = "Record",
                desc = "Start recording debug messages to the buffer.",
                type = "execute", order = 16, width = "half",
                hidden = function() return ActionHud:IsDebugRecording() end,
                func = function() ActionHud:StartDebugRecording() end,
            },
            stopButton = {
                name = "Stop",
                desc = "Stop recording debug messages.",
                type = "execute", order = 17, width = "half",
                hidden = function() return not ActionHud:IsDebugRecording() end,
                func = function() ActionHud:StopDebugRecording() end,
            },
            clearDebug = {
                name = "Clear",
                desc = "Clears the debug buffer without copying.",
                type = "execute", order = 18, width = "half",
                func = function() ActionHud:ClearDebugBuffer() end,
            },
            copyDebug = {
                name = function() 
                    local count = ActionHud:GetDebugBufferCount()
                    return "Export (" .. count .. ")"
                end,
                desc = "Opens a popup with debug messages for copying (Ctrl+A, Ctrl+C).",
                type = "execute", order = 19, width = "half",
                disabled = function() return ActionHud:GetDebugBufferCount() == 0 end,
                func = function() ActionHud:ShowDebugExport() end,
            },
            toolsHeader = { type = "header", name = "Tools", order = 25 },
            refresh = {
                name = "Force Layout Update", type = "execute", order = 26,
                func = function() 
                    local CD = ActionHud:GetModule("Cooldowns")
                    if CD then 
                        CD:ScanForWidgets()
                        CD:UpdateLayout() 
                    end
                    print("ActionHud: Layout Refreshed.")
                end,
            },
            scan = {
                name = "Scan for New Frames", desc = "Scans all global frames for 'Viewer' or 'Tracked' names and logs them.", type = "execute", order = 27,
                func = function()
                    local CD = ActionHud:GetModule("Cooldowns")
                    if CD then CD:FindPotentialTargets() end
                end,
            },
            dumpBuffInfo = {
                name = "Dump Buff/Bar Info",
                desc = "Prints all tracked buff/bar spell IDs and linkedSpellIDs to chat. Use /ah dump as shortcut.",
                type = "execute", order = 28,
                func = function()
                    local CD = ActionHud:GetModule("Cooldowns")
                    if CD and CD.DumpTrackedBuffInfo then CD:DumpTrackedBuffInfo() end
                end,
            },
        },
    }
    
    -- Register
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud", generalOptions)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud", "ActionHud")
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_AB", abOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_AB", "Action Bars", "ActionHud")
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Res", resOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Res", "Resource Bars", "ActionHud")
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_CD", cdOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_CD", "Cooldown Manager", "ActionHud")
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_TB", tbOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_TB", "Tracked Bars", "ActionHud")
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Buffs", buffOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Buffs", "Tracked Buffs", "ActionHud")
    
    -- Profiles
    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Profiles", profiles)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Profiles", "Profiles", "ActionHud")

    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Debug", debugOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Debug", "Debugging", "ActionHud")
end
