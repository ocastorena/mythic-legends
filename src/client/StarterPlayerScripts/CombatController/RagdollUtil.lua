-- StarterPlayer/StarterPlayerScripts/CombatController/RagdollUtil

local RagdollUtil = {}

local walkSpeed = nil
local jumpPower = nil

function RagdollUtil.On(char: Model)
	for _, joint in pairs(char:GetDescendants()) do
		if joint:IsA("Motor6D") then
			local socket = Instance.new("BallSocketConstraint")
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.CFrame = joint.C0
			a1.CFrame = joint.C1
			a0.Parent = joint.Part0
			a1.Parent = joint.Part1
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.Parent = joint.Parent
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.Restitution = 0
			joint.Enabled = false
		end
	end
	walkSpeed = char.Humanoid.WalkSpeed
	char.Humanoid.WalkSpeed = 0
	jumpPower = char.Humanoid.JumpPower
	char.Humanoid.JumpPower = 0
	char.Humanoid.AutoRotate = false
end

function RagdollUtil.Off(char: Model)
	
	for _, joint in pairs(char:GetDescendants()) do
		if joint:IsA("BallSocketConstraint") then
			joint:Destroy()
		end
		if joint:IsA("Motor6D") then
			joint.Enabled = true
		end
	end
	
	char.Humanoid.WalkSpeed = walkSpeed
	char.Humanoid.JumpPower = jumpPower
	char.Humanoid.AutoRotate = true
end

return RagdollUtil
