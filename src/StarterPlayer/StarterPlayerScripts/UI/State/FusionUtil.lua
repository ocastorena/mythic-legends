--!strict
-- StarterPlayer/StarterPlayerScripts/UI/State/FusionUtil
-- Specialize Fusion 0.3's union-based generic Use signature at its library boundary.
-- Explicit instantiation prevents the new Luau solver widening known values to nil.

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)

local FusionUtil = {}

function FusionUtil.UseNumber(use: Fusion.Use, value: Fusion.UsedAs<number>): number
	local read = use :: (Fusion.UsedAs<number>) -> number
	return read(value)
end

function FusionUtil.UseBoolean(use: Fusion.Use, value: Fusion.UsedAs<boolean>): boolean
	local read = use :: (Fusion.UsedAs<boolean>) -> boolean
	return read(value)
end

function FusionUtil.UseVector2(use: Fusion.Use, value: Fusion.UsedAs<Vector2>): Vector2
	local read = use :: (Fusion.UsedAs<Vector2>) -> Vector2
	return read(value)
end

function FusionUtil.SpringNumber(
	scope: Fusion.Scope<typeof(Fusion)>,
	value: Fusion.UsedAs<number>,
	speed: number,
	damping: number
): Fusion.Spring<number>
	local spring = Fusion.Spring :: (
		Fusion.Scope<typeof(Fusion)>,
		Fusion.UsedAs<number>,
		number,
		number
	) -> Fusion.Spring<number>
	return spring(scope, value, speed, damping)
end

return FusionUtil
