--!strict
-- ServerStorage/Tests/__tests__/EquipmentSelection.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local EquipmentSelection =
	require(StarterPlayer.StarterPlayerScripts.Controllers.CombatController.EquipmentSelection)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local cleanup: { Instance } = {}
local FINISHES = { "fire", "water", "earth", "air", "light", "dark" }

type Mounted = {
	character: Model,
	hand: EquipmentSelection.Hand,
	handPart: Part,
	otherHand: Part,
	torso: Part,
	folder: Folder,
	model: Model,
	handle: Part,
	hitbox: Part,
	motor: Motor6D,
}

-- Bind only detached test metadata; production crafted definitions remain deliberately unbound.
local function resolveBound(definitionId: unknown, finishId: unknown?): Types.ResolvedEquipment?
	local original = EquipmentCatalog.Resolve(definitionId, finishId)
	if not original then
		return nil
	end
	local resolved = table.clone(original)
	resolved.profile = table.clone(original.profile)
	if resolved.profile.modelName == "" then
		resolved.profile.modelName = "DisposableBoundEquipment"
	end
	return resolved
end

local function part(name: string, parent: Instance): Part
	local created = Instance.new("Part")
	created.Name, created.Parent = name, parent
	return created
end

local function mounted(definitionId: string, finishId: string?): Mounted
	local metadata = assert(resolveBound(definitionId, finishId), "Expected configured test item")
	local hand: EquipmentSelection.Hand = if metadata.profile.kind == "Shield"
		then "Left"
		else "Right"
	local character = Instance.new("Model")
	table.insert(cleanup, character)
	character:SetAttribute(`{hand}Equipped`, definitionId)
	character:SetAttribute(`{hand}EquipmentInstanceId`, "selected_copy")
	character:SetAttribute(`{hand}EquipmentFinishId`, finishId or "")
	local right, left = part("RightHand", character), part("LeftHand", character)
	local torso = part("UpperTorso", character)
	local handPart, otherHand =
		if hand == "Right" then right else left, if hand == "Right" then left else right
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "EquippedEquipment", character
	local model = Instance.new("Model")
	model.Name, model.Parent = `{hand}Equipment`, folder
	model:SetAttribute("EquipmentId", definitionId)
	model:SetAttribute("EquipmentInstanceId", "selected_copy")
	model:SetAttribute("EquipmentFinishId", finishId or "")
	model:SetAttribute("EquipmentSlot", hand)
	local handle, hitbox = part("Handle", model), part("Hitbox", model)
	model.PrimaryPart = handle
	local motor = Instance.new("Motor6D")
	motor.Name, motor.Parent = `{hand}HandMotor`, handPart
	motor.Part0, motor.Part1 = handPart, handle
	return {
		character = character,
		hand = hand,
		handPart = handPart,
		otherHand = otherHand,
		torso = torso,
		folder = folder,
		model = model,
		handle = handle,
		hitbox = hitbox,
		motor = motor,
	}
end

local function selectBound(f: Mounted): EquipmentSelection.Selection
	return (
		assert(
			EquipmentSelection.Resolve(f.character, f.hand, resolveBound),
			"Expected bound selection"
		)
	)
end

afterEach(function()
	for _, instance in cleanup do
		instance:Destroy()
	end
	table.clear(cleanup)
end)

describe("EquipmentSelection", function()
	it(
		"resolves both wooden hands and compares identity independently of fresh catalogue tables",
		function()
			for _, definition in { "wooden_sword", "wooden_shield" } do
				local f = mounted(definition, nil)
				local first = assert(
					EquipmentSelection.Resolve(f.character, f.hand),
					"Expected wooden selection"
				)
				local again =
					assert(EquipmentSelection.Resolve(f.character, f.hand), "Expected same mount")
				expect(first.character).toBe(f.character)
				expect(first.hand).toBe(f.hand)
				expect(first.instanceId).toBe("selected_copy")
				expect(first.item.definitionId).toBe(definition)
				expect(first.item.finishId).toBeNil()
				expect(first.item.rarity).toBe("Common")
				expect(first.model).toBe(f.model)
				expect(first.hitbox).toBe(f.hitbox)
				expect(first.motor).toBe(f.motor)
				expect(first.limb).toBe(f.handPart)
				expect(first.primaryPart).toBe(f.handle)
				expect(first.item == again.item).toBe(false)
				expect(EquipmentSelection.Same(first, again)).toBe(true)
				expect(EquipmentSelection.IsCurrent(f.character, first)).toBe(true)
			end
		end
	)

	it(
		"retains all twelve named variants when explicitly bound without granting a wooden fallback",
		function()
			for _, kind in { "sword", "shield" } do
				for _, finish in FINISHES do
					local definition = `elemental_{kind}`
					local f = mounted(definition, finish)
					local canonical = assert(
						EquipmentCatalog.Resolve(definition, finish),
						"Expected launch variant"
					)
					local selected = selectBound(f)
					expect(selected.item.definitionId).toBe(definition)
					expect(selected.item.finishId).toBe(finish)
					expect(selected.item.displayName).toBe(canonical.displayName)
					expect(selected.item.rarity).toBe("Rare")
					expect(selected.item.element).toBe(canonical.element)
					expect(selected.item.effectId).toBe(canonical.effectId)
					expect(selected.item.profile.kind).toBe(canonical.profile.kind)
					expect(EquipmentSelection.Same(selected, selectBound(f))).toBe(true)
					expect(EquipmentSelection.IsCurrent(f.character, selected, resolveBound)).toBe(
						true
					)
					expect(canonical.profile.modelName).toBe("")
					expect(EquipmentSelection.Resolve(f.character, f.hand)).toBeNil()
					expect(EquipmentSelection.IsCurrent(f.character, selected)).toBe(false)
				end
			end
		end
	)

	it(
		"rejects missing, malformed, unknown and incomplete character metadata without altering it",
		function()
			local cases: { { suffix: string, value: unknown } } = {
				{ suffix = "Equipped", value = nil },
				{ suffix = "Equipped", value = "" },
				{ suffix = "Equipped", value = false },
				{ suffix = "Equipped", value = string.rep("x", 129) },
				{ suffix = "Equipped", value = "unknown_definition" },
				{ suffix = "EquipmentInstanceId", value = nil },
				{ suffix = "EquipmentInstanceId", value = "" },
				{ suffix = "EquipmentInstanceId", value = 123 },
				{ suffix = "EquipmentInstanceId", value = string.rep("x", 129) },
				{ suffix = "EquipmentFinishId", value = nil },
				{ suffix = "EquipmentFinishId", value = "" },
				{ suffix = "EquipmentFinishId", value = false },
				{ suffix = "EquipmentFinishId", value = string.rep("x", 129) },
				{ suffix = "EquipmentFinishId", value = "unknown_finish" },
			}
			for _, case in cases do
				local f = mounted("elemental_sword", "fire")
				f.character:SetAttribute(`Right{case.suffix}`, case.value)
				local before = f.character:GetAttributes()
				expect(EquipmentSelection.Resolve(f.character, "Right", resolveBound)).toBeNil()
				expect(f.character:GetAttributes()).toEqual(before)
			end
			local wood = mounted("wooden_sword", nil)
			wood.character:SetAttribute("RightEquipmentFinishId", "fire")
			wood.model:SetAttribute("EquipmentFinishId", "fire")
			expect(EquipmentSelection.Resolve(wood.character, "Right")).toBeNil()
			wood.character:SetAttribute("RightEquipmentFinishId", nil)
			wood.model:SetAttribute("EquipmentFinishId", nil)
			expect(EquipmentSelection.Resolve(wood.character, "Right")).toBeNil()
		end
	)

	it("requires exact model identity, finish and slot for each hand", function()
		for _, definition in { "elemental_sword", "elemental_shield" } do
			for _, field in
				{ "EquipmentId", "EquipmentInstanceId", "EquipmentFinishId", "EquipmentSlot" }
			do
				for _, value in { "other", false } do
					local f = mounted(definition, "fire")
					f.model:SetAttribute(field, value)
					expect(EquipmentSelection.Resolve(f.character, f.hand, resolveBound)).toBeNil()
				end
				local f = mounted(definition, "fire")
				f.model:SetAttribute(field, nil)
				expect(EquipmentSelection.Resolve(f.character, f.hand, resolveBound)).toBeNil()
			end
			local f = mounted(definition, "fire")
			f.character:SetAttribute(`{f.hand}EquipmentInstanceId`, "other_copy")
			expect(EquipmentSelection.Resolve(f.character, f.hand, resolveBound)).toBeNil()
		end
	end)

	it("rejects wrong roles, hand endpoints, sheathed mounts, and incomplete geometry", function()
		local corruptions: { (Mounted) -> () } = {
			function(f)
				f.motor.Part0 = f.otherHand
			end,
			function(f)
				f.motor.Part1 = f.torso
			end,
			function(f)
				f.motor.Part0 = nil
			end,
			function(f)
				f.motor.Part1 = nil
			end,
			function(f)
				f.model.PrimaryPart = nil
			end,
			function(f)
				f.hitbox.Name = "OldHitbox"
			end,
			function(f)
				f.hitbox.Parent = f.character
			end,
			function(f)
				f.handPart.Name = "MissingHand"
			end,
			function(f)
				f.model.Name = "OtherEquipment"
			end,
			function(f)
				f.folder.Name = "OtherEquipmentFolder"
			end,
			function(f)
				f.motor.Name, f.motor.Parent, f.motor.Part0 =
					`{f.hand}SheathMotor`, f.torso, f.torso
			end,
			function(f)
				f.motor:Destroy()
				local impostor = Instance.new("Folder")
				impostor.Name, impostor.Parent = `{f.hand}HandMotor`, f.handPart
			end,
			function(f)
				f.hitbox:Destroy()
				local impostor = Instance.new("Folder")
				impostor.Name, impostor.Parent = "Hitbox", f.model
			end,
		}
		for _, corrupt in corruptions do
			local f = mounted("elemental_sword", "fire")
			local selected = selectBound(f)
			corrupt(f)
			expect(EquipmentSelection.Resolve(f.character, "Right", resolveBound)).toBeNil()
			expect(EquipmentSelection.IsCurrent(f.character, selected, resolveBound)).toBe(false)
		end
		local f = mounted("elemental_sword", "fire")
		local function wrongRole(id: unknown, finish: unknown?): Types.ResolvedEquipment?
			local item = resolveBound(id, finish)
			if item then
				item.profile.kind = "Shield"
			end
			return item
		end
		expect(EquipmentSelection.Resolve(f.character, "Right", wrongRole)).toBeNil()
		local shield = mounted("elemental_shield", "fire")
		local function wrongShieldRole(id: unknown, finish: unknown?): Types.ResolvedEquipment?
			local item = resolveBound(id, finish)
			if item then
				item.profile.kind = "PrimaryWeapon"
			end
			return item
		end
		expect(EquipmentSelection.Resolve(shield.character, "Left", wrongShieldRole)).toBeNil()
	end)

	it(
		"invalidates old selections for same-base copy, finish, model, motor and hitbox swaps",
		function()
			local replacements: { (Mounted) -> () } = {
				function(f)
					f.character:SetAttribute("RightEquipmentInstanceId", "second_copy")
					f.model:SetAttribute("EquipmentInstanceId", "second_copy")
				end,
				function(f)
					f.character:SetAttribute("RightEquipmentFinishId", "water")
					f.model:SetAttribute("EquipmentFinishId", "water")
				end,
				function(f)
					local model = f.model:Clone()
					f.model:Destroy()
					model.Parent = f.folder
					f.motor.Part1 = model.PrimaryPart
				end,
				function(f)
					local motor = f.motor:Clone()
					f.motor:Destroy()
					motor.Parent = f.handPart
				end,
				function(f)
					local hitbox = f.hitbox:Clone()
					f.hitbox:Destroy()
					hitbox.Parent = f.model
				end,
				function(f)
					local handle = part("ReplacementHandle", f.model)
					f.model.PrimaryPart = handle
					f.motor.Part1 = handle
				end,
				function(f)
					f.handPart.Name = "OldRightHand"
					local hand = part("RightHand", f.character)
					f.motor.Parent, f.motor.Part0 = hand, hand
				end,
			}
			for _, replace in replacements do
				local f = mounted("elemental_sword", "fire")
				local before = selectBound(f)
				replace(f)
				local after = selectBound(f)
				expect(EquipmentSelection.Same(before, after)).toBe(false)
				expect(EquipmentSelection.IsCurrent(f.character, before, resolveBound)).toBe(false)
				expect(EquipmentSelection.IsCurrent(f.character, after, resolveBound)).toBe(true)
			end
		end
	)

	it(
		"never carries an action selection onto a replacement character with identical metadata",
		function()
			local first, replacement =
				mounted("elemental_sword", "fire"), mounted("elemental_sword", "fire")
			local selected, newSelection = selectBound(first), selectBound(replacement)
			expect(EquipmentSelection.Same(selected, newSelection)).toBe(false)
			expect(EquipmentSelection.IsCurrent(replacement.character, selected, resolveBound)).toBe(
				false
			)
			expect(EquipmentSelection.IsCurrent(replacement.character, newSelection, resolveBound)).toBe(
				true
			)
			local detached = Instance.new("Model")
			table.insert(cleanup, detached)
			expect(EquipmentSelection.Resolve(detached, "Right", resolveBound)).toBeNil()
			expect(EquipmentSelection.Resolve(detached, "Left", resolveBound)).toBeNil()
		end
	)
end)
