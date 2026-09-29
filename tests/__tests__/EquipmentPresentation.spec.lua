--!strict
-- ServerStorage/Tests/__tests__/EquipmentPresentation.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Equipment = require(ReplicatedStorage.Shared.Configurations.Equipment)
local EquipmentPresentation =
	require(ServerScriptService.Services.CombatService.EquipmentPresentation)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local cleanup: { Instance } = {}

local function part(parent: Instance, name: string): Part
	local value = Instance.new("Part")
	value.Name = name
	value.Parent = parent
	return value
end

local function asset(parent: Folder, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local handle = part(model, "Handle")
	local hitbox = part(model, "Hitbox")
	model.PrimaryPart = handle
	handle.Anchored = true
	for _, nameId in { "HandGripAttachment", "SheathAttachment" } do
		local attachment = Instance.new("Attachment")
		attachment.Name = nameId
		attachment.CFrame = if nameId == "HandGripAttachment"
			then CFrame.new(1, 2, 3)
			else CFrame.new(4, 5, 6)
		attachment.Parent = handle
	end
	local authoredWeld = Instance.new("WeldConstraint")
	authoredWeld.Name = "PreviewWeld"
	authoredWeld.Part0 = handle
	authoredWeld.Part1 = hitbox
	authoredWeld.Parent = handle
	return model
end

local function fixture()
	local assets = Instance.new("Folder")
	local character = Instance.new("Model")
	table.insert(cleanup, assets)
	table.insert(cleanup, character)
	local sword, shield = asset(assets, "WoodenSword"), asset(assets, "WoodenShield")
	local right, left, torso =
		part(character, "RightHand"), part(character, "LeftHand"), part(character, "UpperTorso")
	character:SetAttribute("CombatReady", true)
	for _, hand in { "Right", "Left" } do
		character:SetAttribute(
			`{hand}Equipped`,
			if hand == "Right" then "wooden_sword" else "wooden_shield"
		)
		character:SetAttribute(`{hand}EquipmentInstanceId`, `{hand}_owned`)
		character:SetAttribute(`{hand}EquipmentFinishId`, "")
	end
	return {
		assets = assets,
		character = character,
		sword = sword,
		shield = shield,
		right = right,
		left = left,
		torso = torso,
		api = EquipmentPresentation.new(assets, Equipment.definitions),
	}
end

afterEach(function()
	for _, instance in cleanup do
		instance:Destroy()
	end
	table.clear(cleanup)
end)

describe("EquipmentPresentation", function()
	it(
		"clones authored wooden models into hand mounts and copies exact instance/finish identity",
		function()
			local f = fixture()
			-- Presentation copies identity authored by the owning service; it does not resolve saves.
			f.character:SetAttribute("RightEquipmentFinishId", "retained_finish")
			f.api.Rebuild(f.character)
			local folder = assert(
				f.character:FindFirstChild("EquippedEquipment"),
				"[EquipmentPresentation.spec] Expected equipment folder"
			)
			for _, hand in { "Right", "Left" } do
				local model = folder:FindFirstChild(`{hand}Equipment`) :: Model
				local limb = if hand == "Right" then f.right else f.left
				local motor = limb:FindFirstChild(`{hand}HandMotor`) :: Motor6D
				expect(model == (if hand == "Right" then f.sword else f.shield)).toBe(false)
				expect(model:GetAttribute("EquipmentId")).toBe(
					if hand == "Right" then "wooden_sword" else "wooden_shield"
				)
				expect(model:GetAttribute("EquipmentInstanceId")).toBe(`{hand}_owned`)
				expect(model:GetAttribute("EquipmentFinishId")).toBe(
					if hand == "Right" then "retained_finish" else ""
				)
				expect(motor.Part0).toBe(limb)
				expect(motor.Part1).toBe(model.PrimaryPart)
				expect(motor.C1).toBe(CFrame.new(1, 2, 3))
				expect(model:FindFirstChild("PreviewWeld", true)).toBeNil()
				for _, child in model:GetDescendants() do
					if child:IsA("BasePart") then
						expect(
							child.Anchored or child.CanCollide or child.CanTouch or child.CanQuery
						).toBe(false)
						expect(child.Massless).toBe(true)
					end
				end
			end
			expect((f.sword.PrimaryPart :: BasePart).Anchored).toBe(true)
			expect(f.sword:FindFirstChild("PreviewWeld", true) ~= nil).toBe(true)
		end
	)

	it("rebuilds hand mounts as sheath mounts without retaining old clones or motors", function()
		local f = fixture()
		f.api.Rebuild(f.character)
		local folder = assert(
			f.character:FindFirstChild("EquippedEquipment"),
			"[EquipmentPresentation.spec] Expected folder"
		)
		local oldModel = assert(
			folder:FindFirstChild("RightEquipment"),
			"[EquipmentPresentation.spec] Expected model"
		)
		local oldMotor = assert(
			f.right:FindFirstChild("RightHandMotor"),
			"[EquipmentPresentation.spec] Expected motor"
		)
		f.character:SetAttribute("CombatReady", false)
		f.api.Rebuild(f.character)
		expect(oldModel.Parent).toBeNil()
		expect(oldMotor.Parent).toBeNil()
		expect(f.right:FindFirstChild("RightHandMotor")).toBeNil()
		expect(f.left:FindFirstChild("LeftHandMotor")).toBeNil()
		local current = assert(
			f.character:FindFirstChild("EquippedEquipment"),
			"[EquipmentPresentation.spec] Expected sheath models"
		)
		for _, hand in { "Right", "Left" } do
			local model = current:FindFirstChild(`{hand}Equipment`) :: Model
			local motor = f.torso:FindFirstChild(`{hand}SheathMotor`) :: Motor6D
			expect(motor.Part0).toBe(f.torso)
			expect(motor.Part1).toBe(model.PrimaryPart)
			expect(motor.C1).toBe(CFrame.new(4, 5, 6))
			expect(model:GetAttribute("EquipmentInstanceId")).toBe(`{hand}_owned`)
		end
	end)

	it("does not substitute wooden assets for explicitly unbound crafted definitions", function()
		local f = fixture()
		f.api.Rebuild(f.character)
		f.character:SetAttribute("RightEquipped", "elemental_sword")
		f.character:SetAttribute("RightEquipmentFinishId", "fire")
		f.character:SetAttribute("LeftEquipped", "elemental_shield")
		f.character:SetAttribute("LeftEquipmentFinishId", "water")
		f.api.Rebuild(f.character)
		expect(f.character:FindFirstChild("EquippedEquipment")).toBeNil()
		expect(f.right:FindFirstChild("RightHandMotor")).toBeNil()
		expect(f.left:FindFirstChild("LeftHandMotor")).toBeNil()
		expect(f.sword.Parent).toBe(f.assets)
		expect(f.shield.Parent).toBe(f.assets)
	end)

	it(
		"clears only owned equipment assemblies and mount motors without clearing selection attributes",
		function()
			local f = fixture()
			local unrelated = Instance.new("Motor6D")
			unrelated.Name = "RootJoint"
			unrelated.Parent = f.torso
			f.api.Rebuild(f.character)
			f.api.Clear(f.character)
			f.api.Clear(f.character)
			expect(f.character:FindFirstChild("EquippedEquipment")).toBeNil()
			expect(f.right:FindFirstChild("RightHandMotor")).toBeNil()
			expect(f.left:FindFirstChild("LeftHandMotor")).toBeNil()
			expect(unrelated.Parent).toBe(f.torso)
			expect(f.character:GetAttribute("RightEquipped")).toBe("wooden_sword")
			expect(f.character:GetAttribute("RightEquipmentInstanceId")).toBe("Right_owned")
			expect(f.character:GetAttribute("LeftEquipmentInstanceId")).toBe("Left_owned")
		end
	)
end)
