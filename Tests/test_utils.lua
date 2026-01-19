--[[
    ActionHud - Utils Unit Tests
    Verifies Midnight-safe comparisons and API wrappers.
    Run from Addon root: lua Tests/test_utils.lua
]]

-- 1. Mock WoW Environment
_G = _G or {}
local buildInfo = { "11.2.8", "58234", "Dec 22 2025", 120000 }
GetBuildInfo = function()
	return unpack(buildInfo)
end
GetTime = function()
	return 1000
end
wipe = function(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

-- Midnight secret value mocking
local secretValues = {}
issecretvalue = function(v)
	return secretValues[v] == true
end

-- 2. Load Utils
local ns = {}
local function loadUtils()
	local path = "Utils.lua"
	local f = io.open(path, "r")
	if not f then
		f = io.open("../" .. path, "r")
		if not f then
			error("Cannot open " .. path)
		end
	end
	local content = f:read("*a")
	f:close()
	local chunk, err = load(content, path)
	if not chunk then
		error(err)
	end
	chunk("ActionHud", ns)
end

print("Loading Utils.lua...")
loadUtils()
local Utils = ns.Utils

-- 3. Test Setup
local function assert_equal(expected, actual, msg)
	if expected ~= actual then
		error(string.format("%s\nExpected: '%s'\nActual:   '%s'", msg or "Fail", tostring(expected), tostring(actual)))
	end
end

-- 4. Execute Tests
print("Running Utils Tests...")

-- Test: IS_MIDNIGHT detection
assert_equal(true, Utils.IS_MIDNIGHT, "IS_MIDNIGHT detection failed")

-- Test: IsValueSecret
print("  Testing IsValueSecret...")
local normalValue = 100
local secretValue = { isSecret = true } -- Just a placeholder object
secretValues[secretValue] = true

assert_equal(false, Utils.IsValueSecret(normalValue), "Normal value identified as secret")
assert_equal(true, Utils.IsValueSecret(secretValue), "Secret value not identified")
assert_equal(false, Utils.IsValueSecret(nil), "nil identified as secret")

-- Test: SafeCompare
print("  Testing SafeCompare...")
assert_equal(true, Utils.SafeCompare(10, 5, ">"), "10 > 5 failed")
assert_equal(false, Utils.SafeCompare(5, 10, ">"), "5 > 10 failed")
assert_equal(true, Utils.SafeCompare(5, 10, "<"), "5 < 10 failed")
assert_equal(true, Utils.SafeCompare(10, 10, "=="), "10 == 10 failed")
assert_equal(nil, Utils.SafeCompare(secretValue, 10, ">"), "Secret value comparison should return nil")
assert_equal(nil, Utils.SafeCompare(10, secretValue, "<"), "Comparison with secret value should return nil")
assert_equal(nil, Utils.SafeCompare(nil, 10, ">"), "nil comparison should return nil")

-- Test: GetActionCooldownSafe (Mocking C_ActionBar)
print("  Testing GetActionCooldownSafe...")
C_ActionBar = {
	GetActionCooldown = function(id)
		if id == 1 then
			return { startTime = 100, duration = 30, isEnabled = true, modRate = 1 }
		elseif id == 999 then
			error("Attempt to access secret action cooldown")
		end
		return nil
	end,
}

local start, dur, enabled, mod = Utils.GetActionCooldownSafe(1)
assert_equal(100, start, "GetActionCooldownSafe startTime failed")
assert_equal(30, dur, "GetActionCooldownSafe duration failed")
assert_equal(true, enabled, "GetActionCooldownSafe enabled failed")

-- Test fallback/error handling
local start2, dur2, enabled2, mod2 = Utils.GetActionCooldownSafe(999)
assert_equal(0, start2, "GetActionCooldownSafe error fallback failed")

print("SUCCESS: Utils module verified!")
