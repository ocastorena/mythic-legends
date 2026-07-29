-- Procedural shield posing for every visible R15 player.
--
-- The relaxed arm mirrors the left hand with position-only IK so both arms share the
-- same neutral pose. Guard bends that arm and rotates the shield in place so its top
-- points upward. Root and leg IK create an asymmetric kneel without changing
-- Humanoid.HipHeight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Weapons"))

type TransformJoint = Motor6D | AnimationConstraint

type LegPose = {
	ikControl: IKControl,
}

type PoseState = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	tool: Tool,
	baseGrip: CFrame,
	shieldGrip: CFrame,
	guardGrip: CFrame,
	crouchRootOffset: CFrame,
	passiveArmIK: IKControl?,
	passiveArmTarget: Attachment?,
	guardArmIK: IKControl?,
	leftHand: BasePart?,
	root: BasePart?,
	legPoses: { LegPose },
	attachments: { Attachment },
	rootJoint: TransformJoint?,
	rootBaseTransform: CFrame,
	alpha: number,
}

local poseStates: { [Player]: PoseState } = {}

local DEFAULT_BLEND_SECONDS = 0.08
local DEFAULT_IK_SMOOTH_TIME = 0.04
local DEFAULT_PASSIVE_TARGET = CFrame.new(1.35, -0.65, 0.1)
local DEFAULT_PASSIVE_POLE = CFrame.new(2.4, 0.2, -0.2)
local DEFAULT_PASSIVE_GRIP = CFrame.Angles(math.rad(-90), math.rad(180), math.rad(180))
	* CFrame.Angles(math.rad(-20), 0, 0)
local DEFAULT_GUARD_GRIP = CFrame.Angles(math.rad(180), 0, 0)
local DEFAULT_GUARD_TARGET = CFrame.new(0.7, 0.05, -1.05)
	* CFrame.Angles(math.rad(-180), math.rad(-105), 0)
local DEFAULT_GUARD_POLE = CFrame.new(1.8, 0.35, -0.65)
local DEFAULT_FRONT_FOOT = CFrame.new(0.55, -2.7, -0.9)
local DEFAULT_FRONT_KNEE_POLE = CFrame.new(0.7, -1.3, -2)
local DEFAULT_KNEELING_FOOT = CFrame.new(-0.55, -2.6, 1.45)
local DEFAULT_KNEELING_KNEE_POLE = CFrame.new(-0.7, -3, -0.45)
local DEFAULT_CROUCH_ROOT = CFrame.new(0, -0.78, 0) * CFrame.Angles(math.rad(-5), 0, 0)

local function getPoseConfig(profile: any): any
	local shield = type(profile) == "table" and profile.shield or nil
	local pose = type(shield) == "table" and shield.pose or nil
	return if type(pose) == "table" then pose else {}
end

local function getCFrame(value: any, fallback: CFrame): CFrame
	return if typeof(value) == "CFrame" then value else fallback
end

local function getEquippedShield(player: Player): (Model?, Humanoid?, Tool?, any?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid and humanoid.Health > 0) then
		return nil, nil, nil, nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local _, profile = WeaponsData.GetProfile(child)
			if profile and profile.combatKind == "Shield" then
				return character, humanoid, child, profile
			end
		end
	end
	return character, humanoid, nil, nil
end

local function findRootJoint(character: Model): TransformJoint?
	for _, descendant in ipairs(character:GetDescendants()) do
		if (descendant.Name == "Root" or descendant.Name == "RootJoint")
			and (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) then
			return descendant
		end
	end
	return nil
end

local function makeAttachment(
	state: PoseState,
	parent: BasePart,
	name: string,
	transform: CFrame
): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = transform
	attachment.Parent = parent
	table.insert(state.attachments, attachment)
	return attachment
end

local function makeIK(
	humanoid: Humanoid,
	name: string,
	ikType: Enum.IKControlType,
	chainRoot: BasePart,
	endEffector: BasePart,
	target: Attachment,
	pole: Attachment?,
	priority: number,
	smoothTime: number,
	weight: number
): IKControl
	local ikControl = Instance.new("IKControl")
	ikControl.Name = name
	ikControl.Type = ikType
	ikControl.ChainRoot = chainRoot
	ikControl.EndEffector = endEffector
	ikControl.Target = target
	ikControl.Pole = pole
	ikControl.Priority = priority
	ikControl.SmoothTime = smoothTime
	ikControl.Weight = weight
	ikControl.Parent = humanoid
	return ikControl
end

local function addLegIK(
	state: PoseState,
	root: BasePart,
	side: string,
	footTargetCFrame: CFrame,
	kneePoleCFrame: CFrame,
	smoothTime: number
)
	local upperLeg = state.character:FindFirstChild(side .. "UpperLeg")
	local foot = state.character:FindFirstChild(side .. "Foot")
	if not (upperLeg and upperLeg:IsA("BasePart") and foot and foot:IsA("BasePart")) then
		return
	end

	local footTarget = makeAttachment(
		state,
		root,
		"ShieldPose" .. side .. "FootTarget",
		footTargetCFrame
	)
	local kneePole = makeAttachment(
		state,
		root,
		"ShieldPose" .. side .. "KneePole",
		kneePoleCFrame
	)
	local legIK = makeIK(
		state.humanoid,
		"ShieldPose" .. side .. "LegIK",
		Enum.IKControlType.Position,
		upperLeg,
		foot,
		footTarget,
		kneePole,
		8,
		smoothTime,
		0
	)
	table.insert(state.legPoses, {
		ikControl = legIK,
	})
end

local function destroyPose(player: Player)
	local state = poseStates[player]
	if not state then
		return
	end

	poseStates[player] = nil
	if state.tool.Parent then
		state.tool.Grip = state.baseGrip
	end
	if state.rootJoint and state.rootJoint.Parent then
		state.rootJoint.Transform = state.rootBaseTransform
	end
	if state.passiveArmIK and state.passiveArmIK.Parent then
		state.passiveArmIK:Destroy()
	end
	if state.guardArmIK and state.guardArmIK.Parent then
		state.guardArmIK:Destroy()
	end
	for _, legPose in ipairs(state.legPoses) do
		if legPose.ikControl.Parent then
			legPose.ikControl:Destroy()
		end
	end
	for _, attachment in ipairs(state.attachments) do
		if attachment.Parent then
			attachment:Destroy()
		end
	end
end

local function createPose(
	player: Player,
	character: Model,
	humanoid: Humanoid,
	tool: Tool,
	profile: any
): PoseState
	local pose = getPoseConfig(profile)
	local rootJoint = findRootJoint(character)
	local state: PoseState = {
		player = player,
		character = character,
		humanoid = humanoid,
		tool = tool,
		baseGrip = tool.Grip,
		shieldGrip = tool.Grip * getCFrame(pose.passiveGripOffset, DEFAULT_PASSIVE_GRIP),
		guardGrip = CFrame.identity,
		crouchRootOffset = getCFrame(pose.crouchRootOffset, DEFAULT_CROUCH_ROOT),
		passiveArmIK = nil,
		passiveArmTarget = nil,
		guardArmIK = nil,
		leftHand = nil,
		root = nil,
		legPoses = {},
		attachments = {},
		rootJoint = rootJoint,
		rootBaseTransform = if rootJoint then rootJoint.Transform else CFrame.identity,
		alpha = if player:GetAttribute("ShieldActive") == true then 1 else 0,
	}
	state.guardGrip = state.shieldGrip * getCFrame(pose.guardGripOffset, DEFAULT_GUARD_GRIP)

	local root = character:FindFirstChild("HumanoidRootPart")
	local upperArm = character:FindFirstChild("RightUpperArm")
	local hand = character:FindFirstChild("RightHand")
	local leftHand = character:FindFirstChild("LeftHand")
	if root and root:IsA("BasePart")
		and upperArm and upperArm:IsA("BasePart")
		and hand and hand:IsA("BasePart") then
		state.root = root
		state.leftHand = if leftHand and leftHand:IsA("BasePart") then leftHand else nil
		local smoothTime = if type(pose.ikSmoothTime) == "number"
			then math.clamp(pose.ikSmoothTime, 0, 0.5)
			else DEFAULT_IK_SMOOTH_TIME
		local passiveTarget = makeAttachment(
			state,
			root,
			"ShieldPosePassiveHandTarget",
			getCFrame(pose.passiveHandTarget, DEFAULT_PASSIVE_TARGET)
		)
		local passivePole = makeAttachment(
			state,
			root,
			"ShieldPosePassiveElbowPole",
			getCFrame(pose.passiveElbowPole, DEFAULT_PASSIVE_POLE)
		)
		local guardTarget = makeAttachment(
			state,
			root,
			"ShieldPoseGuardHandTarget",
			getCFrame(pose.guardHandTarget, DEFAULT_GUARD_TARGET)
		)
		local guardPole = makeAttachment(
			state,
			root,
			"ShieldPoseGuardElbowPole",
			getCFrame(pose.guardElbowPole, DEFAULT_GUARD_POLE)
		)

		state.passiveArmIK = makeIK(
			humanoid,
			"ShieldPosePassiveArmIK",
			Enum.IKControlType.Position,
			upperArm,
			hand,
			passiveTarget,
			passivePole,
			10,
			smoothTime,
			1 - state.alpha
		)
		state.passiveArmTarget = passiveTarget
		state.guardArmIK = makeIK(
			humanoid,
			"ShieldPoseGuardArmIK",
			Enum.IKControlType.Transform,
			upperArm,
			hand,
			guardTarget,
			guardPole,
			11,
			smoothTime,
			state.alpha
		)

		if rootJoint then
			addLegIK(
				state,
				root,
				"Left",
				getCFrame(pose.kneelingFootTarget, DEFAULT_KNEELING_FOOT),
				getCFrame(pose.kneelingKneePole, DEFAULT_KNEELING_KNEE_POLE),
				smoothTime
			)
			addLegIK(
				state,
				root,
				"Right",
				getCFrame(pose.frontFootTarget, DEFAULT_FRONT_FOOT),
				getCFrame(pose.frontKneePole, DEFAULT_FRONT_KNEE_POLE),
				smoothTime
			)
		end
	end

	tool.Grip = state.shieldGrip
	poseStates[player] = state
	return state
end

local function updatePlayer(player: Player, deltaTime: number)
	local character, humanoid, tool, profile = getEquippedShield(player)
	local state = poseStates[player]
	if not (character and humanoid and tool and profile) then
		destroyPose(player)
		return
	end

	if not state
		or state.character ~= character
		or state.humanoid ~= humanoid
		or state.tool ~= tool then
		destroyPose(player)
		state = createPose(player, character, humanoid, tool, profile)
	end

	local pose = getPoseConfig(profile)
	local targetAlpha = if player:GetAttribute("ShieldActive") == true then 1 else 0
	local blendSeconds = if type(pose.blendSeconds) == "number"
		then math.max(0.01, pose.blendSeconds)
		else DEFAULT_BLEND_SECONDS
	local blendStep = math.min(1, deltaTime / blendSeconds)
	if state.alpha < targetAlpha then
		state.alpha = math.min(targetAlpha, state.alpha + blendStep)
	elseif state.alpha > targetAlpha then
		state.alpha = math.max(targetAlpha, state.alpha - blendStep)
	end

	if state.passiveArmIK then
		state.passiveArmIK.Weight = 1 - state.alpha
	end
	if state.guardArmIK then
		state.guardArmIK.Weight = state.alpha
	end
	for _, legPose in ipairs(state.legPoses) do
		legPose.ikControl.Weight = state.alpha
	end

	local passiveArmTarget = state.passiveArmTarget
	local leftHand = state.leftHand
	local root = state.root
	if passiveArmTarget and leftHand and root then
		local leftHandPosition = root.CFrame:PointToObjectSpace(leftHand.Position)
		passiveArmTarget.Position = Vector3.new(
			-leftHandPosition.X,
			leftHandPosition.Y,
			leftHandPosition.Z
		)
	end

	-- Guard rotates the shield around the grip axis so its authored top points upward.
	-- Position still comes from the arm IK, keeping the shield attached to the forearm.
	state.tool.Grip = state.shieldGrip:Lerp(state.guardGrip, state.alpha)
end

RunService.PreSimulation:Connect(function()
	for _, state in pairs(poseStates) do
		local rootJoint = state.rootJoint
		if rootJoint and rootJoint.Parent and state.alpha > 0.001 then
			rootJoint.Transform = state.rootBaseTransform:Lerp(
				state.rootBaseTransform * state.crouchRootOffset,
				state.alpha
			)
		end
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	for _, player in ipairs(Players:GetPlayers()) do
		updatePlayer(player, deltaTime)
	end

	for player in pairs(poseStates) do
		if player.Parent ~= Players then
			destroyPose(player)
		end
	end
end)
