--!strict
-- ServerScriptService/Services/CombatService/ElementalHits
-- Called once only after server hit eligibility and paid Shield-block resolution.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Effects = require(ReplicatedStorage.Shared.Configurations.ElementalSwordEffects)
local CombatState = require(script.Parent.CombatState)

local ElementalHits = {}

function ElementalHits.ApplyAcceptedHit(
	attacker: CombatState.State,
	target: CombatState.State,
	now: number,
	effectId: string?,
	blocked: boolean
): number
	-- Existing burns/timers continue through a block. Neither Air nor Light scales Shield slides,
	-- and even a final paid block prevents the new effect or Dark refund.
	CombatState.Advance(attacker, now)
	CombatState.Advance(target, now)
	if blocked then
		return 1
	end
	local horizontalMultiplier = 1
	local effect = if effectId then Effects[effectId] else nil
	if effect and effectId then
		if effect.kind == "Push" then
			horizontalMultiplier = effect.horizontalMultiplier
		elseif effect.kind == "Refund" then
			CombatState.Refund(attacker, now, effect.stamina)
		else
			CombatState.ApplyNegative(target, now, effectId, effect)
		end
	end
	-- Apply Light to the complete outgoing horizontal component after any Air bonus. The caller
	-- keeps upward velocity, tumble, immunity, and the original accepted-hit identity unchanged.
	return horizontalMultiplier * CombatState.GetHorizontalMultiplier(attacker, now)
end

return table.freeze(ElementalHits)
