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
                name = [[|cff33ff99ActionHud 2.5.0|r

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
                set = function(info, val) self.db.profile.resEnabled = val; ActionHud:GetModule("Resources"):UpdateLayout() end,
            },
            showTarget = {
                name = "Show Target Stats", desc = "Split bars to show target health/power.", type = "toggle", order = 2,
                get = function(info) return self.db.profile.resShowTarget end,
                set = function(info, val) self.db.profile.resShowTarget = val; ActionHud:GetModule("Resources"):UpdateLayout() end,
            },
            layout = { name = "Layout Dimensions", type = "header", order = 10 },
            healthHeight = {
                name = "Health Bar Height", type = "range", min = 1, max = 30, step = 1, order = 11,
                get = function(info) return self.db.profile.resHealthHeight end,
                set = function(info, val) self.db.profile.resHealthHeight = val; ActionHud:GetModule("Resources"):UpdateLayout() end,
            },
            powerHeight = {
                name = "Power Bar Height", type = "range", min = 1, max = 30, step = 1, order = 12,
                get = function(info) return self.db.profile.resPowerHeight end,
                set = function(info, val) self.db.profile.resPowerHeight = val; ActionHud:GetModule("Resources"):UpdateLayout() end,
            },
            classHeight = {
                name = "Class Resource Height", desc = "Height of Combo Points, Holy Power, etc.", type = "range", min = 1, max = 20, step = 1, order = 12.5,
                get = function(info) return self.db.profile.resClassHeight end,
                set = function(info, val) self.db.profile.resClassHeight = val; ActionHud:GetModule("Resources"):UpdateLayout() end,
            },
            spacing = {
                name = "Bar Spacing", type = "range", min = 0, max = 10, step = 1, order = 14,
                get = function(info) return self.db.profile.resSpacing end,
                set = function(info, val) self.db.profile.resSpacing = val; ActionHud:GetModule("Resources"):UpdateLayout() end,
            },
            gap = {
                name = "Player-Target Gap", desc = "Space between player and target bars.", type = "range", min = 0, max = 50, step = 1, order = 15,
                get = function(info) return self.db.profile.resGap end,
                set = function(info, val) self.db.profile.resGap = val; ActionHud:GetModule("Resources"):UpdateLayout() end,
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
    
    -- SUB: Tracked Abilities (Tracked Buffs, Tracked Bars, External Defensives)
    -- Style-only overlays on Blizzard's native frames. Position via EditMode.
    local trackedOptions = {
        name = "Tracked Abilities",
        handler = ActionHud,
        type = "group",
        args = {
            reqNote = {
                name = function()
                    if IsBlizzardCooldownViewerEnabled() then
                        return "|cff00ff00Blizzard Cooldown Manager is enabled.|r"
                    else
                        return [[|cffff4444Blizzard Cooldown Manager is disabled.|r

Enable it in Gameplay Enhancements to use these features.]]
                    end
                end,
                type = "description", order = 0,
            },
            infoNote = {
                type = "description", order = 1,
                name = [[ActionHud applies custom styling to Blizzard's Tracked Abilities frames, removing rounded corners and adjusting fonts.

|cffffcc00Positioning:|r Use Blizzard's |cff00ff00EditMode|r to move and resize these frames.
]],
            },
            openEditMode = {
                name = "Open EditMode",
                desc = "Open Blizzard's EditMode to position and resize Tracked Abilities frames.",
                type = "execute", order = 2, width = "normal",
                func = function()
                    if EditModeManagerFrame then
                        EditModeManagerFrame:Show()
                    end
                end,
            },
            
            -- Tracked Buffs Section
            buffsHeader = { name = "Tracked Buffs", type = "header", order = 10 },
            styleTrackedBuffs = {
                name = "Enable Styling", 
                desc = "Apply ActionHud styling to the Tracked Buffs frame (removes rounded corners, custom fonts).", 
                type = "toggle", order = 11, width = 1.0,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.styleTrackedBuffs end,
                set = function(info, val) 
                    self.db.profile.styleTrackedBuffs = val
                    ActionHud:GetModule("TrackedBuffs"):UpdateLayout() 
                end,
            },
            buffsCountFontSize = {
                name = "Stack Count Font", 
                desc = "Font size for stack counts.",
                type = "range", min = 6, max = 18, step = 1, order = 12, width = 1.0,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs end,
                get = function(info) return self.db.profile.buffsCountFontSize or 10 end,
                set = function(info, val) 
                    self.db.profile.buffsCountFontSize = val
                    ActionHud:GetModule("TrackedBuffs"):UpdateLayout()
                end,
            },
            buffsTimerFontSize = {
                name = "Timer Font", 
                desc = "Font size for cooldown timers.",
                type = "select", order = 13, width = 1.0,
                values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
                sorting = { "small", "medium", "large", "huge" },
                disabled = function() return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBuffs end,
                get = function(info) return self.db.profile.buffsTimerFontSize or "medium" end,
                set = function(info, val) 
                    self.db.profile.buffsTimerFontSize = val
                    ActionHud:GetModule("TrackedBuffs"):UpdateLayout()
                end,
            },
            
            -- Tracked Bars Section
            barsHeader = { name = "Tracked Bars", type = "header", order = 20 },
            styleTrackedBars = {
                name = "Enable Styling", 
                desc = "Apply ActionHud styling to the Tracked Bars frame (removes rounded corners, custom fonts).", 
                type = "toggle", order = 21, width = 1.0,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() end,
                get = function(info) return self.db.profile.styleTrackedBars end,
                set = function(info, val) 
                    self.db.profile.styleTrackedBars = val
                    ActionHud:GetModule("TrackedBars"):UpdateLayout() 
                end,
            },
            barsCountFontSize = {
                name = "Stack Count Font", 
                desc = "Font size for stack counts.",
                type = "range", min = 6, max = 18, step = 1, order = 22, width = 1.0,
                disabled = function() return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBars end,
                get = function(info) return self.db.profile.barsCountFontSize or 10 end,
                set = function(info, val) 
                    self.db.profile.barsCountFontSize = val
                    ActionHud:GetModule("TrackedBars"):UpdateLayout()
                end,
            },
            barsTimerFontSize = {
                name = "Timer Font", 
                desc = "Font size for cooldown timers.",
                type = "select", order = 23, width = 1.0,
                values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
                sorting = { "small", "medium", "large", "huge" },
                disabled = function() return not IsBlizzardCooldownViewerEnabled() or not self.db.profile.styleTrackedBars end,
                get = function(info) return self.db.profile.barsTimerFontSize or "medium" end,
                set = function(info, val) 
                    self.db.profile.barsTimerFontSize = val
                    ActionHud:GetModule("TrackedBars"):UpdateLayout()
                end,
            },
            
            -- External Defensives Section (12.0+ only)
            defensivesHeader = { name = "External Defensives", type = "header", order = 30 },
            defensivesNote = {
                type = "description", order = 31,
                name = function()
                    if not ExternalDefensivesFrame then
                        return "|cffaaaaaa(Requires WoW 12.0 Midnight or later)|r"
                    end
                    return ""
                end,
                hidden = function() return ExternalDefensivesFrame ~= nil end,
            },
            styleExternalDefensives = {
                name = "Enable Styling", 
                desc = "Apply ActionHud styling to the External Defensives frame.", 
                type = "toggle", order = 32, width = 1.0,
                hidden = function() return not ExternalDefensivesFrame end,
                get = function(info) return self.db.profile.styleExternalDefensives end,
                set = function(info, val) 
                    self.db.profile.styleExternalDefensives = val
                    local mod = ActionHud:GetModule("TrackedDefensives", true)
                    if mod then mod:UpdateLayout() end
                end,
            },
            defensivesCountFontSize = {
                name = "Stack Count Font", 
                desc = "Font size for stack counts.",
                type = "range", min = 6, max = 18, step = 1, order = 33, width = 1.0,
                hidden = function() return not ExternalDefensivesFrame end,
                disabled = function() return not self.db.profile.styleExternalDefensives end,
                get = function(info) return self.db.profile.defensivesCountFontSize or 10 end,
                set = function(info, val) 
                    self.db.profile.defensivesCountFontSize = val
                    local mod = ActionHud:GetModule("TrackedDefensives", true)
                    if mod then mod:UpdateLayout() end
                end,
            },
            defensivesTimerFontSize = {
                name = "Timer Font", 
                desc = "Font size for cooldown timers.",
                type = "select", order = 34, width = 1.0,
                values = { small = "Small", medium = "Medium", large = "Large", huge = "Huge" },
                sorting = { "small", "medium", "large", "huge" },
                hidden = function() return not ExternalDefensivesFrame end,
                disabled = function() return not self.db.profile.styleExternalDefensives end,
                get = function(info) return self.db.profile.defensivesTimerFontSize or "medium" end,
                set = function(info, val) 
                    self.db.profile.defensivesTimerFontSize = val
                    local mod = ActionHud:GetModule("TrackedDefensives", true)
                    if mod then mod:UpdateLayout() end
                end,
            },
        },
    }

    -- SUB: Layout
    -- Helper to get LayoutManager
    local function GetLayoutManager()
        return ActionHud:GetModule("LayoutManager", true)
    end
    
    -- Helper to trigger layout update
    local function TriggerLayoutUpdate()
        local LM = GetLayoutManager()
        if LM then LM:TriggerLayoutUpdate() end
    end
    
    -- Build dynamic layout options based on current stack order
    local function BuildLayoutArgs()
        local args = {}
        local LM = GetLayoutManager()
        if not LM then return args end
        
        -- HUD Stack Section (first)
        args.stackHeader = { type = "header", name = "HUD Stack Order", order = 1 }
        args.stackDesc = {
            type = "description", order = 2,
            name = "Arrange modules from top to bottom. Use arrows to reorder. Gap defines spacing after each module.\n ",
        }
        
        local stack = LM:GetStack()
        local gaps = LM:GetGaps()
        local baseOrder = 10
        
        for i, moduleId in ipairs(stack) do
            local moduleName = LM:GetModuleName(moduleId)
            local orderBase = baseOrder + (i * 10)
            
            -- Module row header with position number
            args["mod_" .. i .. "_header"] = {
                type = "description", order = orderBase,
                name = string.format("|cffffcc00%d.|r |cffffffff%s|r", i, moduleName),
                fontSize = "medium",
                width = "full",
            }
            
            -- Move Up button
            args["mod_" .. i .. "_up"] = {
                name = "Up",
                desc = "Move " .. moduleName .. " up in the stack",
                type = "execute", order = orderBase + 1, width = 0.4,
                disabled = function() return i == 1 end,
                func = function()
                    LM:MoveModule(moduleId, "up")
                    -- Force AceConfig to rebuild the options
                    LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Layout")
                end,
            }
            
            -- Move Down button
            args["mod_" .. i .. "_down"] = {
                name = "Down",
                desc = "Move " .. moduleName .. " down in the stack",
                type = "execute", order = orderBase + 2, width = 0.4,
                disabled = function() return i == #stack end,
                func = function()
                    LM:MoveModule(moduleId, "down")
                    LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Layout")
                end,
            }
            
            -- Gap slider (not shown for last module)
            if i < #stack then
                args["mod_" .. i .. "_gap"] = {
                    name = "Gap After",
                    desc = string.format("Space between %s and the next module.", moduleName),
                    type = "range", min = 0, max = 50, step = 1, order = orderBase + 3,
                    width = 1.0,
                    get = function() 
                        local g = LM:GetGaps()
                        return g[i] or 0 
                    end,
                    set = function(_, val)
                        LM:SetGap(i, val)
                    end,
                }
            end
            
            -- Spacer line
            args["mod_" .. i .. "_spacer"] = {
                type = "description", order = orderBase + 5,
                name = " ",
                width = "full",
            }
        end
        
        -- Reset button (inside HUD Stack section)
        args.resetBtn = {
            name = "Reset to Default Order",
            desc = "Restore the default module order and gap values.",
            type = "execute", order = 99, width = "double",
            func = function()
                LM:ResetToDefault()
                LibStub("AceConfigRegistry-3.0"):NotifyChange("ActionHud_Layout")
            end,
        }
        
        -- Tracked Abilities Section
        args.trackedHeader = { type = "header", name = "Tracked Abilities", order = 100 }
        args.trackedDesc = {
            type = "description", order = 101,
            name = [[These frames are styled by ActionHud but positioned via Blizzard's EditMode:
• Tracked Buffs
• Tracked Bars
• External Defensives
]],
        }
        args.openEditMode = {
            name = "Open EditMode",
            desc = "Open Blizzard's EditMode to position and resize Tracked Abilities frames.",
            type = "execute", order = 102, width = "normal",
            func = function()
                if EditModeManagerFrame then
                    EditModeManagerFrame:Show()
                end
            end,
        }
        
        return args
    end
    
    -- Use a function for layoutOptions so AceConfig rebuilds it each time
    -- This makes the UI rows visually reorder when modules are moved
    local function GetLayoutOptions()
        return {
            name = "Layout",
            handler = ActionHud,
            type = "group",
            args = BuildLayoutArgs(),
        }
    end

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
            proxy = {
                name = "Debug Proxies", desc = "Logs detailed information about tracked buff/bar population and aura changes.", type = "toggle", order = 12.5,
                get = function(info) return self.db.profile.debugProxy end,
                set = function(info, val) self.db.profile.debugProxy = val end,
            },
            layout = {
                name = "Debug Layout", desc = "Logs layout positioning calculations including stack order, heights, gaps, and Y offsets.", type = "toggle", order = 12.55,
                get = function(info) return self.db.profile.debugLayout end,
                set = function(info, val) self.db.profile.debugLayout = val end,
            },
            containers = {
                name = "Debug Containers", desc = "Shows colored backgrounds behind the Hud containers to verify their positions.", type = "toggle", order = 12.6,
                get = function(info) return self.db.profile.debugContainers end,
                set = function(info, val) 
                    self.db.profile.debugContainers = val
                    for _, mName in ipairs({"Cooldowns", "TrackedBars", "TrackedBuffs"}) do
                        local m = ActionHud:GetModule(mName, true)
                        if m and m.UpdateLayout then m:UpdateLayout() end
                    end
                end,
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
                    for _, mName in ipairs({"ActionBars", "Resources", "Cooldowns", "TrackedBars", "TrackedBuffs"}) do
                        local m = ActionHud:GetModule(mName, true)
                        if m and m.UpdateLayout then m:UpdateLayout() end
                    end
                    print("ActionHud: Layout Refreshed.")
                end,
            },
            scan = {
                name = "Scan for New Frames", desc = "Scans all global frames for 'Viewer' or 'Tracked' names and logs them.", type = "execute", order = 27,
                func = function()
                    local Manager = ns.CooldownManager
                    if Manager and Manager.FindPotentialTargets then Manager:FindPotentialTargets() end
                end,
            },
            dumpBuffInfo = {
                name = "Dump Buff/Bar Info",
                desc = "Prints all tracked buff/bar spell IDs and linkedSpellIDs to chat. Use /ah dump as shortcut.",
                type = "execute", order = 28,
                func = function()
                    local Manager = ns.CooldownManager
                    if Manager and Manager.DumpTrackedBuffInfo then Manager:DumpTrackedBuffInfo() end
                end,
            },
        },
    }
    
    -- Register settings panels in logical order
    -- 1. General settings
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud", generalOptions)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud", "ActionHud")
    
    -- 2. Layout (overall HUD structure) - early so users see it
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Layout", GetLayoutOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Layout", "Layout", "ActionHud")
    
    -- 3-4. Core HUD components (inline stacked)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_AB", abOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_AB", "Action Bars", "ActionHud")
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Res", resOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Res", "Resource Bars", "ActionHud")
    
    -- 5-7. Cooldown Manager components (grouped together)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_CD", cdOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_CD", "Cooldown Manager", "ActionHud")
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Tracked", trackedOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Tracked", "Tracked Abilities", "ActionHud")
    
    -- 8-9. Meta settings
    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Profiles", profiles)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Profiles", "Profiles", "ActionHud")

    -- Only show Debugging panel in dev mode (DevMarker.lua excluded from CurseForge packages)
    if ns.IS_DEV_MODE then
        LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Debug", debugOptions)
        LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Debug", "Debugging", "ActionHud")
    end
end
