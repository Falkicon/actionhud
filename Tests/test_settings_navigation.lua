-- Exercise real Ace registration with the numeric category IDs used by Retail.
local host = assert(loadfile("Tests/support/wow.lua"))()
local categories, registered, opened = {}, {}, {}
local function register(frame, name)
	local id = 1000 + #registered
	local category = { ID = id, GetID = function() return id end, GetName = function() return name end }
	registered[#registered + 1] = category
	categories[id] = category
	return category
end
C_SettingsUtil = { OpenSettingsPanel = function() end }
Settings.RegisterCanvasLayoutCategory = register
Settings.RegisterCanvasLayoutSubcategory = function(_, frame, name) return register(frame, name) end
Settings.GetCategory = function(id) return categories[id] end
Settings.OpenToCategory = function(id)
	assert(type(id) == "number" and categories[id], "Settings expects a registered category ID, never a frame")
	opened[#opened + 1] = id
end
local compartment
AddonCompartmentFrame = { RegisterAddon = function(_, entry) compartment = entry end }
local addon = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local commands = LibStub("AceConsole-3.0").commands
local mainID = registered[1]:GetID()
for _, command in ipairs({ "ah", "actionhud" }) do
	assert(commands[command], "settings slash aliases must be registered")
	SlashCmdList[commands[command]]("")
	assert(opened[#opened] == mainID, "slash command must open the registered ActionHud category")
end
assert(#opened == 2)
compartment.func()
assert(#opened == 3 and opened[3] == mainID, "addon compartment must use the same category navigation")
assert(addon:OpenSettings() == true and #opened == 4)
host:SetCombat(true)
SlashCmdList[commands.ah]("")
assert(addon:OpenSettings() == false and #opened == 4, "settings navigation must stay blocked during combat")
host:SetCombat(false)
SlashCmdList[commands.ah]("")
assert(#opened == 5 and opened[5] == mainID)
host:AssertNoErrors()
print("SUCCESS: slash aliases and addon compartment open the registered Retail settings category")
