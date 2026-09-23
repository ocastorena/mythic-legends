--!strict
-- ReplicatedStorage/Shared/Configurations/AdminCommands

local Types = require(script.Parent.Parent.Types)
local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

local config: Types.AdminCommandsConfiguration = {
	commandBurst = 3,
	commandRefillPerSecond = 1,
	streamTimeoutSeconds = 5,
	arrivalPaddingStuds = 0.5,
	groundProbeAboveStuds = 2,
	groundProbeBelowStuds = 8,
	minimumGroundNormalY = 0.7,
	islandMarkerName = "TeleportPoint",
	-- A destination becomes available when its authored island has a landing marker.
	destinations = {
		fire = { displayName = "Fire Island", islandName = "FireIsland" },
		water = { displayName = "Water Island", islandName = "WaterIsland" },
		earth = { displayName = "Earth Island", islandName = "EarthIsland" },
		air = { displayName = "Air Island", islandName = "AirIsland" },
		light = { displayName = "Light Island", islandName = "LightIsland" },
		dark = { displayName = "Dark Island", islandName = "DarkIsland" },
	},
}

return FreezeUtil.DeepFreeze(config)
