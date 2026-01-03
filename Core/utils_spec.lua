-- ActionHud Core Tests
-- Sandbox-compatible tests for pure Lua logic

describe("ActionHud Core", function()
	describe("SafeCompare", function()
		it("returns false for nil first arg", function()
			assert.is_false(ActionHudCore.SafeCompare(nil, 5, ">"))
		end)

		it("returns false for nil second arg", function()
			assert.is_false(ActionHudCore.SafeCompare(5, nil, ">"))
		end)

		it("returns false for both nil", function()
			assert.is_false(ActionHudCore.SafeCompare(nil, nil, "=="))
		end)

		it("compares greater than correctly", function()
			assert.is_true(ActionHudCore.SafeCompare(10, 5, ">"))
			assert.is_false(ActionHudCore.SafeCompare(5, 10, ">"))
			assert.is_false(ActionHudCore.SafeCompare(5, 5, ">"))
		end)

		it("compares less than correctly", function()
			assert.is_true(ActionHudCore.SafeCompare(5, 10, "<"))
			assert.is_false(ActionHudCore.SafeCompare(10, 5, "<"))
			assert.is_false(ActionHudCore.SafeCompare(5, 5, "<"))
		end)

		it("compares greater than or equal correctly", function()
			assert.is_true(ActionHudCore.SafeCompare(10, 5, ">="))
			assert.is_true(ActionHudCore.SafeCompare(5, 5, ">="))
			assert.is_false(ActionHudCore.SafeCompare(5, 10, ">="))
		end)

		it("compares less than or equal correctly", function()
			assert.is_true(ActionHudCore.SafeCompare(5, 10, "<="))
			assert.is_true(ActionHudCore.SafeCompare(5, 5, "<="))
			assert.is_false(ActionHudCore.SafeCompare(10, 5, "<="))
		end)

		it("compares equality correctly", function()
			assert.is_true(ActionHudCore.SafeCompare(5, 5, "=="))
			assert.is_false(ActionHudCore.SafeCompare(5, 6, "=="))
		end)

		it("compares inequality correctly", function()
			assert.is_true(ActionHudCore.SafeCompare(5, 6, "~="))
			assert.is_false(ActionHudCore.SafeCompare(5, 5, "~="))
		end)

		it("returns false for unknown operator", function()
			assert.is_false(ActionHudCore.SafeCompare(5, 5, "??"))
		end)
	end)

	describe("Clamp", function()
		it("returns min for nil value", function()
			assert.equals(0, ActionHudCore.Clamp(nil, 0, 100))
		end)

		it("returns min for non-number value", function()
			assert.equals(0, ActionHudCore.Clamp("abc", 0, 100))
			assert.equals(10, ActionHudCore.Clamp({}, 10, 50))
		end)

		it("clamps to minimum", function()
			assert.equals(0, ActionHudCore.Clamp(-10, 0, 100))
		end)

		it("clamps to maximum", function()
			assert.equals(100, ActionHudCore.Clamp(200, 0, 100))
		end)

		it("returns value in range", function()
			assert.equals(50, ActionHudCore.Clamp(50, 0, 100))
		end)

		it("handles edge cases at boundaries", function()
			assert.equals(0, ActionHudCore.Clamp(0, 0, 100))
			assert.equals(100, ActionHudCore.Clamp(100, 0, 100))
		end)
	end)

	describe("ValidateIconSize", function()
		it("clamps width below minimum", function()
			local result = ActionHudCore.ValidateIconSize(5, 50)
			assert.equals(10, result.width)
		end)

		it("clamps width above maximum", function()
			local result = ActionHudCore.ValidateIconSize(200, 50)
			assert.equals(100, result.width)
		end)

		it("clamps height below minimum", function()
			local result = ActionHudCore.ValidateIconSize(50, 5)
			assert.equals(10, result.height)
		end)

		it("clamps height above maximum", function()
			local result = ActionHudCore.ValidateIconSize(50, 200)
			assert.equals(100, result.height)
		end)

		it("accepts valid sizes", function()
			local result = ActionHudCore.ValidateIconSize(20, 15)
			assert.equals(20, result.width)
			assert.equals(15, result.height)
		end)

		it("handles nil values", function()
			local result = ActionHudCore.ValidateIconSize(nil, nil)
			assert.equals(10, result.width)
			assert.equals(10, result.height)
		end)
	end)

	describe("ValidateFontSize", function()
		it("clamps to minimum 4", function()
			assert.equals(4, ActionHudCore.ValidateFontSize(2))
		end)

		it("clamps to maximum 24", function()
			assert.equals(24, ActionHudCore.ValidateFontSize(30))
		end)

		it("accepts valid sizes", function()
			assert.equals(12, ActionHudCore.ValidateFontSize(12))
		end)

		it("handles nil", function()
			assert.equals(4, ActionHudCore.ValidateFontSize(nil))
		end)
	end)

	describe("ValidateOpacity", function()
		it("clamps negative to 0", function()
			assert.equals(0, ActionHudCore.ValidateOpacity(-0.5))
		end)

		it("clamps above 1 to 1", function()
			assert.equals(1, ActionHudCore.ValidateOpacity(1.5))
		end)

		it("accepts valid values", function()
			assert.equals(0.5, ActionHudCore.ValidateOpacity(0.5))
			assert.equals(0, ActionHudCore.ValidateOpacity(0))
			assert.equals(1, ActionHudCore.ValidateOpacity(1))
		end)

		it("handles nil", function()
			assert.equals(0, ActionHudCore.ValidateOpacity(nil))
		end)
	end)

	describe("ValidateCooldownFontSize", function()
		it("clamps to minimum 4", function()
			assert.equals(4, ActionHudCore.ValidateCooldownFontSize(2))
		end)

		it("clamps to maximum 16", function()
			assert.equals(16, ActionHudCore.ValidateCooldownFontSize(20))
		end)

		it("accepts valid sizes", function()
			assert.equals(8, ActionHudCore.ValidateCooldownFontSize(8))
		end)
	end)

	describe("ValidateOffset", function()
		it("clamps to minimum -1000", function()
			assert.equals(-1000, ActionHudCore.ValidateOffset(-2000))
		end)

		it("clamps to maximum 1000", function()
			assert.equals(1000, ActionHudCore.ValidateOffset(2000))
		end)

		it("accepts valid offsets", function()
			assert.equals(-220, ActionHudCore.ValidateOffset(-220))
			assert.equals(0, ActionHudCore.ValidateOffset(0))
			assert.equals(500, ActionHudCore.ValidateOffset(500))
		end)
	end)

	describe("ValidateGap", function()
		it("clamps negative to 0", function()
			assert.equals(0, ActionHudCore.ValidateGap(-5))
		end)

		it("clamps above 50 to 50", function()
			assert.equals(50, ActionHudCore.ValidateGap(100))
		end)

		it("accepts valid gaps", function()
			assert.equals(4, ActionHudCore.ValidateGap(4))
			assert.equals(0, ActionHudCore.ValidateGap(0))
		end)
	end)
end)
