--!strict
-- ServerScriptService/Services/CombatService/MovementRestrictions
-- Compose voluntary movement rules without touching forced motion or collision behavior.

export type Rule = {
	walkSpeedMultiplier: number,
	blockJump: boolean,
	blockRotation: boolean,
}
export type MovementRestrictions = { Apply: (Rule) -> (), Clear: () -> () }

local MovementRestrictions = {}

function MovementRestrictions.new(character: Model, humanoid: Humanoid): MovementRestrictions
	local walkSpeed: number? = nil
	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	local autoRotate: boolean? = nil
	local api = {}

	local function ownsHumanoid(): boolean
		return humanoid:IsDescendantOf(character)
	end

	function api.Clear()
		-- An old owner must never restore values onto a Humanoid moved to another character.
		-- Dead but still-owned Humanoids can safely release these properties before disposal.
		if ownsHumanoid() then
			if walkSpeed ~= nil then
				humanoid.WalkSpeed = walkSpeed
			end
			if jumpPower ~= nil then
				humanoid.JumpPower = jumpPower
			end
			if jumpHeight ~= nil then
				humanoid.JumpHeight = jumpHeight
			end
			if autoRotate ~= nil then
				humanoid.AutoRotate = autoRotate
			end
		end
		walkSpeed, jumpPower, jumpHeight, autoRotate = nil, nil, nil, nil
	end

	function api.Apply(rule: Rule)
		assert(
			type(rule) == "table"
				and type(rule.walkSpeedMultiplier) == "number"
				and rule.walkSpeedMultiplier == rule.walkSpeedMultiplier
				and rule.walkSpeedMultiplier >= 0
				and rule.walkSpeedMultiplier <= 1
				and type(rule.blockJump) == "boolean"
				and type(rule.blockRotation) == "boolean",
			"[CombatService.MovementRestrictions] Invalid movement rule"
		)
		if not ownsHumanoid() or humanoid.Health <= 0 then
			api.Clear()
			return
		end
		-- Capture each property only when this owner first overrides it. Water does not own
		-- jump/rotation, and a guard-to-Water transition must retain the original walking base.
		if rule.walkSpeedMultiplier ~= 1 then
			local baseline = walkSpeed or humanoid.WalkSpeed
			walkSpeed = baseline
			humanoid.WalkSpeed = baseline * rule.walkSpeedMultiplier
		elseif walkSpeed ~= nil then
			humanoid.WalkSpeed = walkSpeed
			walkSpeed = nil
		end
		if rule.blockJump then
			if jumpPower == nil then
				jumpPower = humanoid.JumpPower
			end
			if jumpHeight == nil then
				jumpHeight = humanoid.JumpHeight
			end
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		else
			if jumpPower ~= nil then
				humanoid.JumpPower = jumpPower
				jumpPower = nil
			end
			if jumpHeight ~= nil then
				humanoid.JumpHeight = jumpHeight
				jumpHeight = nil
			end
		end
		if rule.blockRotation then
			if autoRotate == nil then
				autoRotate = humanoid.AutoRotate
			end
			humanoid.AutoRotate = false
		elseif autoRotate ~= nil then
			humanoid.AutoRotate = autoRotate
			autoRotate = nil
		end
	end

	return api
end

return table.freeze(MovementRestrictions)
