--!strict
-- ServerStorage/Tests/__tests__/LoadoutUtil.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local LoadoutUtil = require(ServerScriptService.Services.CombatService.LoadoutUtil)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local cleanup: { Instance } = {}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function profile(): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	data.equipment = {
		starter_wooden_sword = { definitionId = "wooden_sword", isStarterGrant = true },
		starter_wooden_shield = { definitionId = "wooden_shield", isStarterGrant = true },
		selected = { definitionId = "elemental_sword", finishId = "fire" },
		other_copy = { definitionId = "elemental_sword", finishId = "fire" },
	}
	data.combatLoadout = {
		primaryWeaponInstanceId = "selected",
		shieldInstanceId = "starter_wooden_shield",
	}
	return data
end

local function character(): Model
	local model = Instance.new("Model")
	table.insert(cleanup, model)
	for _, name in { "RightHand", "LeftHand", "UpperTorso" } do
		local part = Instance.new("Part")
		part.Name = name
		part.Parent = model
	end
	return model
end

local function mounted()
	local data, model = profile(), character()
	LoadoutUtil.WriteAttributes(model, data)
	local folder = Instance.new("Folder")
	folder.Name = "EquippedEquipment"
	folder.Parent = model
	local equipment = Instance.new("Model")
	equipment.Name = "RightEquipment"
	equipment:SetAttribute("EquipmentId", "elemental_sword")
	equipment:SetAttribute("EquipmentInstanceId", "selected")
	equipment:SetAttribute("EquipmentFinishId", "fire")
	equipment.Parent = folder
	local handle = Instance.new("Part")
	handle.Parent = equipment
	equipment.PrimaryPart = handle
	local hand = model:FindFirstChild("RightHand") :: BasePart
	local torso = model:FindFirstChild("UpperTorso") :: BasePart
	local motor = Instance.new("Motor6D")
	motor.Name = "RightHandMotor"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.Parent = hand
	return {
		data = data,
		character = model,
		equipment = equipment,
		handle = handle,
		hand = hand,
		torso = torso,
		motor = motor,
	}
end

afterEach(function()
	for _, instance in cleanup do
		instance:Destroy()
	end
	table.clear(cleanup)
end)

describe("LoadoutUtil", function()
	it(
		"never chooses replacements or rewrites empty, dangling, or unsupported saved selections",
		function()
			for _, reference in { "missing", "unsupported", "" } do
				local data = profile()
				data.equipment.unsupported = { definitionId = "retained_legacy" }
				data.combatLoadout.primaryWeaponInstanceId = if reference == ""
					then nil
					else reference
				data.combatLoadout.shieldInstanceId = nil
				local before = copy(data)
				expect(LoadoutUtil.Resolve(data, "PrimaryWeapon")).toBeNil()
				expect(LoadoutUtil.Resolve(data, "Shield")).toBeNil()
				local snapshot = LoadoutUtil.Snapshot(data)
				expect(snapshot.primaryWeaponInstanceId).toBe(
					if reference == "" then nil else reference
				)
				expect(data).toEqual(before)
			end
		end
	)

	it(
		"snapshots all named variants in stable instance order without private owned metadata",
		function()
			local data = profile()
			data.equipment = {}
			for _, kind in { "sword", "shield" } do
				for _, finish in { "fire", "water", "earth", "air", "light", "dark" } do
					local id = `{kind}_{finish}`
					data.equipment[id] = {
						definitionId = `elemental_{kind}`,
						finishId = finish,
						isStarterGrant = false,
					}
					local raw = data.equipment[id] :: any
					raw.privatePrice = 99
				end
			end
			data.equipment.legacy = { definitionId = "unknown_legacy", finishId = "retained" }
			local before = copy(data)
			local snapshot = LoadoutUtil.Snapshot(data)
			expect(#snapshot.equipment).toBe(12)
			for index, entry in snapshot.equipment do
				local owned = data.equipment[entry.instanceId]
				expect(entry).toEqual({
					instanceId = entry.instanceId,
					definitionId = owned.definitionId,
					finishId = owned.finishId,
				})
				if index > 1 then
					expect(snapshot.equipment[index - 1].instanceId < entry.instanceId).toBe(true)
				end
			end
			expect(snapshot.primaryWeaponInstanceId).toBe("selected")
			expect(data).toEqual(before)
		end
	)

	it(
		"compares exact owned instance and finish instead of just the shared base definition",
		function()
			local data = profile()
			local first = assert(
				LoadoutUtil.Resolve(data, "PrimaryWeapon"),
				"[LoadoutUtil.spec] Expected selection"
			)
			expect(LoadoutUtil.Same(first, first)).toBe(true)
			data.combatLoadout.primaryWeaponInstanceId = "other_copy"
			local other = assert(
				LoadoutUtil.Resolve(data, "PrimaryWeapon"),
				"[LoadoutUtil.spec] Expected copy"
			)
			expect(LoadoutUtil.Same(first, other)).toBe(false)
			data.combatLoadout.primaryWeaponInstanceId = "selected"
			data.equipment.selected.finishId = "water"
			local changed = assert(
				LoadoutUtil.Resolve(data, "PrimaryWeapon"),
				"[LoadoutUtil.spec] Expected variant"
			)
			expect(LoadoutUtil.Same(first, changed)).toBe(false)
		end
	)

	it(
		"resolves Shield only with an empty or valid one-handed primary without repairing incompatible state",
		function()
			local data = profile()
			data.equipment.future = { definitionId = "future_two_hand" }
			local base = assert(
				EquipmentCatalog.Resolve("wooden_sword"),
				"[LoadoutUtil.spec] Expected starter"
			)
			local future = table.clone(base)
			future.definitionId = "future_two_hand"
			future.profile = table.clone(base.profile)
			future.profile.handsRequired = 2
			local function resolve(id: unknown, finish: unknown?): Types.ResolvedEquipment?
				return if id == "future_two_hand"
					then future
					else EquipmentCatalog.Resolve(id, finish)
			end
			data.combatLoadout.primaryWeaponInstanceId = "future"
			local before = copy(data)
			expect(LoadoutUtil.Resolve(data, "Shield", resolve)).toBeNil()
			expect(data).toEqual(before)
			data.combatLoadout.primaryWeaponInstanceId = "missing"
			expect(LoadoutUtil.Resolve(data, "Shield", resolve)).toBeNil()
			data.combatLoadout.primaryWeaponInstanceId = nil
			expect(LoadoutUtil.Resolve(data, "Shield", resolve) ~= nil).toBe(true)
			data.combatLoadout.primaryWeaponInstanceId = "starter_wooden_sword"
			expect(LoadoutUtil.Resolve(data, "Shield", resolve) ~= nil).toBe(true)
		end
	)

	it(
		"writes all three identity attributes per hand and clears stale attributes for empty slots",
		function()
			local data, model = profile(), character()
			local before = copy(data)
			LoadoutUtil.WriteAttributes(model, data)
			expect(model:GetAttribute("RightEquipped")).toBe("elemental_sword")
			expect(model:GetAttribute("RightEquipmentInstanceId")).toBe("selected")
			expect(model:GetAttribute("RightEquipmentFinishId")).toBe("fire")
			expect(model:GetAttribute("LeftEquipped")).toBe("wooden_shield")
			expect(model:GetAttribute("LeftEquipmentInstanceId")).toBe("starter_wooden_shield")
			expect(model:GetAttribute("LeftEquipmentFinishId")).toBe("")
			expect(data).toEqual(before)
			data.combatLoadout = {}
			LoadoutUtil.WriteAttributes(model, data)
			for _, hand in { "Right", "Left" } do
				for _, suffix in { "Equipped", "EquipmentInstanceId", "EquipmentFinishId" } do
					expect(model:GetAttribute(`{hand}{suffix}`)).toBe("")
				end
			end
		end
	)

	it(
		"accepts only the exact owned/current identity attached by genuine hand Motor6D endpoints",
		function()
			local good = mounted()
			local selected = assert(
				LoadoutUtil.GetMounted(good.data, good.character, "PrimaryWeapon"),
				"[LoadoutUtil.spec] Expected mounted selection"
			)
			expect(selected.instanceId).toBe("selected")
			for _, mismatch in
				{
					"owned",
					"selection",
					"finish",
					"character-definition",
					"character-instance",
					"character-finish",
					"model-definition",
					"model-instance",
					"model-finish",
					"part0",
					"part1",
					"primary",
					"motor-class",
					"sheath",
				}
			do
				local f = mounted()
				if mismatch == "owned" then
					f.data.equipment.selected = nil
				elseif mismatch == "selection" then
					f.data.combatLoadout.primaryWeaponInstanceId = "other_copy"
				elseif mismatch == "finish" then
					f.data.equipment.selected.finishId = "water"
				elseif mismatch == "character-definition" then
					f.character:SetAttribute("RightEquipped", "wooden_sword")
				elseif mismatch == "character-instance" then
					f.character:SetAttribute("RightEquipmentInstanceId", "other_copy")
				elseif mismatch == "character-finish" then
					f.character:SetAttribute("RightEquipmentFinishId", "water")
				elseif mismatch == "model-definition" then
					f.equipment:SetAttribute("EquipmentId", "wooden_sword")
				elseif mismatch == "model-instance" then
					f.equipment:SetAttribute("EquipmentInstanceId", "other_copy")
				elseif mismatch == "model-finish" then
					f.equipment:SetAttribute("EquipmentFinishId", "water")
				elseif mismatch == "part0" then
					f.motor.Part0 = f.torso
				elseif mismatch == "part1" then
					f.motor.Part1 = f.torso
				elseif mismatch == "primary" then
					f.equipment.PrimaryPart = nil
				elseif mismatch == "motor-class" then
					f.motor:Destroy()
					local impostor = Instance.new("Folder")
					impostor.Name = "RightHandMotor"
					impostor.Parent = f.hand
				else
					f.motor.Name = "RightSheathMotor"
					f.motor.Parent = f.torso
					f.motor.Part0 = f.torso
				end
				expect(LoadoutUtil.GetMounted(f.data, f.character, "PrimaryWeapon")).toBeNil()
			end
		end
	)
end)
