--!strict
-- ReplicatedStorage/Shared/Configurations/CombatRuntime
-- Server observation/publication tuning; effect strength and durations belong to ElementalSwordEffects.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	stateStepSeconds = 0.1,
	earthLanding = {
		supportAllowanceStuds = 0.3,
		minimumGroundNormalY = 0.5,
		takeoffVelocityStudsPerSecond = 1,
	},
})
