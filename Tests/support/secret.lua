-- Shared stand-in for WoW 12.x secret values.
--
-- Tokens are userdata (like native secrets, never mistaken for info tables)
-- whose metatable fails and counts every operation the client forbids for
-- tainted code: arithmetic, ordering, concatenation, length, indexing and
-- string conversion. Lua 5.1 cannot intercept `secret == number` (it is
-- silently false) or truthiness tests, so those stay the responsibility of
-- reviews and in-game combat testing.
local Secret = { operations = 0, values = setmetatable({}, { __mode = "k" }) }

local function forbidden(operation)
	return function()
		Secret.operations = Secret.operations + 1
		error("secret value used in Lua " .. operation, 2)
	end
end

local metatable = {
	__add = forbidden("arithmetic"), __sub = forbidden("arithmetic"), __mul = forbidden("arithmetic"),
	__div = forbidden("arithmetic"), __mod = forbidden("arithmetic"), __pow = forbidden("arithmetic"),
	__unm = forbidden("arithmetic"), __lt = forbidden("comparison"), __le = forbidden("comparison"),
	__eq = forbidden("comparison"), __concat = forbidden("concatenation"), __len = forbidden("length"),
	__index = forbidden("indexing"), __newindex = forbidden("indexing"), __call = forbidden("call"),
	__tostring = forbidden("string conversion"),
}

-- Wraps a public value; the underlying value is only visible to test code.
function Secret.new(value)
	local token = newproxy(true)
	local meta = getmetatable(token)
	for key, handler in pairs(metatable) do meta[key] = handler end
	Secret.values[token] = { value = value }
	return token
end

function Secret.is(value)
	return type(value) == "userdata" and Secret.values[value] ~= nil
end

function Secret.reveal(value)
	local entry = Secret.is(value) and Secret.values[value]
	if entry then return entry.value end
	return value
end

function Secret.Reset()
	Secret.operations = 0
end

function Secret.AssertUntouched(message)
	assert(Secret.operations == 0, (message or "secret values were used in Lua") .. ": " .. Secret.operations)
end

return Secret
