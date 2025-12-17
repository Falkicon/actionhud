-- SettingsUI.lua
-- Defines the configuration options using AceConfig-3.0

local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")

function ActionHud:SetupOptions()
    local options = {
        name = "ActionHud",
        handler = ActionHud,
        type = 'group',
        args = {

            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    locked = {
                        name = "Lock Frame",
                        desc = "Lock the HUD in place.",
                        type = "toggle",
                        order = 1,
                        get = function(info) return self.db.profile.locked end,
                        set = function(info, val) 
                            self.db.profile.locked = val
                            self:UpdateLockState()
                        end,
                    },
                },
            },
            actionbars = {
                name = "Action Bars",
                type = "group",
                order = 2,
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
                    iconDimensions = {
                        name = "Dimensions",
                        type = "header",
                        order = 10,
                    },
                    iconWidth = {
                        name = "Icon Width",
                        desc = "Width of the action icons.",
                        type = "range",
                        min = 10, max = 50, step = 1,
                        order = 11,
                        get = function(info) return self.db.profile.iconWidth end,
                        set = function(info, val)
                            self.db.profile.iconWidth = val
                            ActionHud:GetModule("ActionBars"):UpdateLayout()
                        end,
                    },
                    iconHeight = {
                        name = "Icon Height",
                        desc = "Height of the action icons.",
                        type = "range",
                        min = 10, max = 50, step = 1,
                        order = 12,
                        get = function(info) return self.db.profile.iconHeight end,
                        set = function(info, val)
                            self.db.profile.iconHeight = val
                            ActionHud:GetModule("ActionBars"):UpdateLayout()
                        end,
                    },
                    visuals = {
                        name = "Visuals & Opacity",
                        type = "header",
                        order = 20,
                    },
                    opacity = {
                        name = "Background Opacity",
                        desc = "Opacity of empty slots.",
                        type = "range",
                        min = 0, max = 1, step = 0.05,
                        isPercent = true,
                        order = 21,
                        get = function(info) return self.db.profile.opacity end,
                        set = function(info, val)
                            self.db.profile.opacity = val
                            ActionHud:GetModule("ActionBars"):UpdateOpacity()
                        end,
                    },
                    procGlowAlpha = {
                        name = "Proc Glow Opacity (Yellow)",
                        type = "range",
                        min = 0, max = 1, step = 0.05,
                        isPercent = true,
                        order = 22,
                        get = function(info) return self.db.profile.procGlowAlpha end,
                        set = function(info, val)
                            self.db.profile.procGlowAlpha = val
                            ActionHud:GetModule("ActionBars"):UpdateLayout()
                        end,
                    },
                    assistGlowAlpha = {
                        name = "Assist Glow Opacity (Blue)",
                        type = "range",
                        min = 0, max = 1, step = 0.05,
                        isPercent = true,
                        order = 23,
                        get = function(info) return self.db.profile.assistGlowAlpha end,
                        set = function(info, val)
                            self.db.profile.assistGlowAlpha = val
                            ActionHud:GetModule("ActionBars"):UpdateLayout()
                        end,
                    },
                    fonts = {
                        name = "Fonts",
                        type = "header",
                        order = 30,
                    },
                    cooldownFontSize = {
                        name = "Cooldown Font Size",
                        type = "range",
                        min = 6, max = 24, step = 1,
                        order = 31,
                        get = function(info) return self.db.profile.cooldownFontSize end,
                        set = function(info, val)
                            self.db.profile.cooldownFontSize = val
                            ActionHud:GetModule("ActionBars"):UpdateLayout()
                        end,
                    },
                    countFontSize = {
                        name = "Stack Count Font Size",
                        type = "range",
                        min = 6, max = 24, step = 1,
                        order = 32,
                        get = function(info) return self.db.profile.countFontSize end,
                        set = function(info, val)
                            self.db.profile.countFontSize = val
                            ActionHud:GetModule("ActionBars"):UpdateLayout()
                        end,
                    },
                },
            },
            resources = {
                name = "Resource Bars",
                type = "group",
                order = 2,
                args = {
                    enable = {
                        name = "Enable",
                        type = "toggle",
                        order = 1,
                        get = function(info) return self.db.profile.resEnabled end,
                        set = function(info, val)
                            self.db.profile.resEnabled = val
                            self:UpdateLayout()
                        end,
                    },
                    showTarget = {
                        name = "Show Target Stats",
                        desc = "Split bars to show target health/power.",
                        type = "toggle",
                        order = 2,
                        get = function(info) return self.db.profile.resShowTarget end,
                        set = function(info, val)
                            self.db.profile.resShowTarget = val
                            self:UpdateLayout()
                        end,
                    },
                    position = {
                        name = "Position",
                        type = "select",
                        values = { ["TOP"] = "Top", ["BOTTOM"] = "Bottom" },
                        sorting = { "TOP", "BOTTOM" }, -- Try AceConfig sorting hint if supported, else just define Order
                        order = 3,
                        get = function(info) return self.db.profile.resPosition end,
                        set = function(info, val)
                            self.db.profile.resPosition = val
                            self:UpdateLayout()
                        end,
                    },
                    layout = {
                        name = "Layout Dimensions",
                        type = "header",
                        order = 10,
                    },
                    healthHeight = {
                        name = "Health Bar Height",
                        type = "range",
                        min = 1, max = 30, step = 1,
                        order = 11,
                        get = function(info) return self.db.profile.resHealthHeight end,
                        set = function(info, val)
                            self.db.profile.resHealthHeight = val
                            self:UpdateLayout()
                        end,
                    },
                    powerHeight = {
                        name = "Power Bar Height",
                        type = "range",
                        min = 1, max = 30, step = 1,
                        order = 12,
                        get = function(info) return self.db.profile.resPowerHeight end,
                        set = function(info, val)
                            self.db.profile.resPowerHeight = val
                            self:UpdateLayout()
                        end,
                    },
                    classHeight = {
                        name = "Class Resource Height",
                        desc = "Height of Combo Points, Holy Power, etc.",
                        type = "range",
                        min = 1, max = 20, step = 1,
                        order = 12.5,
                        get = function(info) return self.db.profile.resClassHeight end,
                        set = function(info, val)
                            self.db.profile.resClassHeight = val
                            self:UpdateLayout()
                        end,
                    },
                    offset = {
                        name = "Gap from HUD",
                        type = "range",
                        min = 0, max = 50, step = 1,
                        order = 13,
                        get = function(info) return self.db.profile.resOffset end,
                        set = function(info, val)
                            self.db.profile.resOffset = val
                            self:UpdateLayout()
                        end,
                    },
                    spacing = {
                        name = "Bar Spacing",
                        type = "range",
                        min = 0, max = 10, step = 1,
                        order = 14,
                        get = function(info) return self.db.profile.resSpacing end,
                        set = function(info, val)
                            self.db.profile.resSpacing = val
                            self:UpdateLayout()
                        end,
                    },
                    gap = {
                        name = "Player-Target Gap",
                        desc = "Space between player and target bars.",
                        type = "range",
                        min = 0, max = 50, step = 1,
                        order = 15,
                        get = function(info) return self.db.profile.resGap end,
                        set = function(info, val)
                            self.db.profile.resGap = val
                            self:UpdateLayout()
                        end,
                    },
                },
            },
            cooldowns = {
                name = "Cooldown Manager",
                type = "group",
                order = 3,
                args = {
                    reqNote = {
                        name = "|cffffcc00Requirements:|r Enable \"Cooldown Manager\" in WoW Settings > Gameplay > Gameplay Enhancements.\nConfigure tracked spells via [Advanced Cooldown Settings] in that same menu.",
                        type = "description",
                        order = 0,
                    },
                    enable = {
                        name = "Enable",
                        desc = "Enable management of the native Cooldown Manager frame.",
                        type = "toggle",
                        order = 1,
                        get = function(info) return self.db.profile.cdEnabled end,
                        set = function(info, val)
                            self.db.profile.cdEnabled = val
                            local CD = ActionHud:GetModule("Cooldowns")
                            if val then CD:Enable() else CD:Disable() end
                        end,
                    },
                    position = {
                        name = "Position",
                        desc = "Attach to Top or Bottom of the HUD.",
                        type = "select",
                        values = {"Top", "Bottom"},
                        order = 2,
                        get = function(info) return self.db.profile.cdPosition == "BOTTOM" and 2 or 1 end,
                        set = function(info, val)
                            self.db.profile.cdPosition = (val == 2) and "BOTTOM" or "TOP"
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    gap = {
                        name = "Gap from HUD",
                        desc = "Distance from the HUD (or Resource Bars).",
                        type = "range",
                        min = 0, max = 50, step = 1,
                        order = 3,
                        get = function(info) return self.db.profile.cdGap end,
                        set = function(info, val)
                            self.db.profile.cdGap = val
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    spacing = {
                        name = "Bar Spacing",
                        desc = "Space between Essential and Utility bars.",
                        type = "range",
                        min = 0, max = 50, step = 1,
                        order = 4,
                        get = function(info) return self.db.profile.cdSpacing end,
                        set = function(info, val)
                            self.db.profile.cdSpacing = val
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    reverse = {
                        name = "Reverse Order",
                        desc = "Swap the Essential and Utility bars.",
                        type = "toggle",
                        order = 5,
                        get = function(info) return self.db.profile.cdReverse end,
                        set = function(info, val)
                            self.db.profile.cdReverse = val
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    itemGap = {
                        name = "Icon Spacing",
                        desc = "Space between cooldown icons.",
                        type = "range",
                        min = 0, max = 20, step = 1,
                        order = 6,
                        get = function(info) return self.db.profile.cdItemGap end,
                        set = function(info, val)
                            self.db.profile.cdItemGap = val
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    
                    headerEssential = { type="header", name="Essential Bar", order=10 },
                    essWidth = {
                        name = "Width",
                        type = "range", min = 10, max = 100, step = 1, order = 11,
                        get = function(info) return self.db.profile.cdEssentialWidth end,
                        set = function(info, val) 
                            self.db.profile.cdEssentialWidth = val 
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    essHeight = {
                        name = "Height",
                        type = "range", min = 10, max = 100, step = 1, order = 12,
                        get = function(info) return self.db.profile.cdEssentialHeight end,
                        set = function(info, val) 
                            self.db.profile.cdEssentialHeight = val 
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    
                    headerUtility = { type="header", name="Utility Bar", order=20 },
                    utilWidth = {
                        name = "Width",
                        type = "range", min = 10, max = 100, step = 1, order = 21,
                        get = function(info) return self.db.profile.cdUtilityWidth end,
                        set = function(info, val) 
                            self.db.profile.cdUtilityWidth = val 
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    utilHeight = {
                        name = "Height",
                        type = "range", min = 10, max = 100, step = 1, order = 22,
                        get = function(info) return self.db.profile.cdUtilityHeight end,
                        set = function(info, val) 
                            self.db.profile.cdUtilityHeight = val 
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    
                    headerFont = { type="header", name="Typography", order=25 },
                    fontSize = {
                        name = "Stack Font Size",
                        type = "range", min=8, max=24, step=1, order=26,
                        get = function(info) return self.db.profile.cdCountFontSize end,
                        set = function(info, val)
                            self.db.profile.cdCountFontSize = val
                            ActionHud:GetModule("Cooldowns"):UpdateLayout()
                        end,
                    },
                    
                    debug = {
                        name = "Debug Discovery",
                        desc = "Print widget IDs to chat to help identify frames.",
                        type = "toggle",
                        order = 30,
                        get = function(info) return self.db.profile.debugDiscovery end,
                        set = function(info, val) self.db.profile.debugDiscovery = val end,
                    },
                },
            },
        },
    }
    
    -- Register Options
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud", options)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud", "ActionHud")
    
    -- Profiles
    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Profiles", profiles)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Profiles", "Profiles", "ActionHud")
end
