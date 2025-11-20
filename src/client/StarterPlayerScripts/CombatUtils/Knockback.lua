-- /Knockback
local RagdollUtil = require(script.Parent.RagdollUtil)

local Knockback = {}

function Knockback.Start(impulse: Vector3, char: Character, hitDuration: number)
	-- check if we already got hit
	if char:GetAttribute("Hit") then return end
	char:SetAttribute("Hit", true)
	local hum = char.Humanoid
	local hrp = char.HumanoidRootPart
	-- Pause auto-getup during our window
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	hum:ChangeState(Enum.HumanoidStateType.Physics)

	RagdollUtil.On(char)
	-- One-shot momentum change (mass-scaled Δv)
	hrp:ApplyImpulse(impulse)

	-- Let physics rule briefly, then restore
	task.wait(hitDuration)
	RagdollUtil.Off(char)
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	task.wait(0.5)
	char:SetAttribute("Hit", false)
end

return Knockback
