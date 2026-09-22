--!strict
-- ServerScriptService/Services/CombatService/EquipmentPresentation
-- Clones and attaches authored equipment; the calling character lifetime owns cleanup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local LogUtil = require(ServerScriptService.Infrastructure.LogUtil)
local log = LogUtil.For("CombatService.EquipmentPresentation")
local EQUIPMENT_FOLDER_NAME = "EquippedEquipment"
local EquipmentPresentation = {}

function EquipmentPresentation.new(
	equipmentAssets: Folder,
	profiles: { [string]: Types.EquipmentProfile }
)
	local function getEquipmentFolder(character: Model): Folder
		local existing = character:FindFirstChild(EQUIPMENT_FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = EQUIPMENT_FOLDER_NAME
		folder.Parent = character
		return folder
	end

	local function clearEquipment(character: Model)
		local folder = character:FindFirstChild(EQUIPMENT_FOLDER_NAME)
		if folder then
			folder:Destroy()
		end
		for _, motorName in
			{ "RightHandMotor", "LeftHandMotor", "RightSheathMotor", "LeftSheathMotor" }
		do
			local motor = character:FindFirstChild(motorName, true)
			if motor and motor:IsA("Motor6D") then
				motor:Destroy()
			end
		end
	end

	local function prepareEquipmentModel(model: Model): boolean
		local primaryPart = model.PrimaryPart
		if not primaryPart then
			log.warn(`{model:GetFullName()} has no PrimaryPart`)
			return false
		end
		for _, attachmentName in { "HandGripAttachment", "SheathAttachment" } do
			local attachment = model:FindFirstChild(attachmentName, true)
			if not attachment or not attachment:IsA("Attachment") then
				log.warn(`{model:GetFullName()} needs {attachmentName}`)
				return false
			end
		end
		local hitbox = model:FindFirstChild("Hitbox", true)
		if not hitbox or not hitbox:IsA("BasePart") then
			log.warn(`{model:GetFullName()} needs a Hitbox BasePart`)
			return false
		end
		-- Rebuild one predictable rigid assembly instead of stacking runtime welds on top of
		-- authored preview welds each time the Equipment moves between hand and sheath.
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") then
				descendant:Destroy()
			end
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Massless = true
				if descendant ~= primaryPart then
					local weld = Instance.new("WeldConstraint")
					weld.Name = "EquipmentAssemblyWeld"
					weld.Part0 = primaryPart
					weld.Part1 = descendant
					weld.Parent = primaryPart
				end
			end
		end
		return true
	end

	local function cloneEquipment(character: Model, slot: string, definitionId: string): Model?
		local profile = profiles[definitionId]
		local asset = profile and equipmentAssets:FindFirstChild(profile.modelName)
		if not asset or not asset:IsA("Model") then
			log.warn(`Missing authored Equipment model for {definitionId}`)
			return nil
		end
		local model = asset:Clone()
		model.Name = `{slot}Equipment`
		model:SetAttribute("EquipmentId", definitionId)
		model:SetAttribute("EquipmentSlot", slot)
		if not prepareEquipmentModel(model) then
			model:Destroy()
			return nil
		end
		model.Parent = getEquipmentFolder(character)
		return model
	end

	local function authoredOffset(model: Model, attachmentName: string): CFrame?
		local attachment = model:FindFirstChild(attachmentName, true)
		local primaryPart = model.PrimaryPart
		if attachment and attachment:IsA("Attachment") and primaryPart then
			return (primaryPart.CFrame:ToObjectSpace(attachment.WorldCFrame))
		end
		return nil
	end

	local function createMotor(
		name: string,
		parent: BasePart,
		part0: BasePart,
		part1: BasePart,
		offset: CFrame
	)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C1 = offset
		motor.Parent = parent
	end

	local function attachSlot(
		character: Model,
		slot: string,
		definitionId: string,
		combatReady: boolean
	)
		if definitionId == "" then
			return
		end
		local model = cloneEquipment(character, slot, definitionId)
		local primaryPart = model and model.PrimaryPart
		if not model or not primaryPart then
			return
		end
		if combatReady then
			local hand = character:FindFirstChild(`{slot}Hand`)
			local offset = authoredOffset(model, "HandGripAttachment")
			if hand and hand:IsA("BasePart") and offset then
				createMotor(`{slot}HandMotor`, hand, hand, primaryPart, offset)
			else
				model:Destroy()
			end
		else
			local torso = character:FindFirstChild("UpperTorso")
			local offset = authoredOffset(model, "SheathAttachment")
			if torso and torso:IsA("BasePart") and offset then
				createMotor(`{slot}SheathMotor`, torso, torso, primaryPart, offset)
			else
				model:Destroy()
			end
		end
	end

	local function rebuildAttachments(character: Model)
		clearEquipment(character)
		local combatReady = character:GetAttribute("CombatReady") == true
		local rightId = character:GetAttribute("RightEquipped")
		attachSlot(
			character,
			"Right",
			if type(rightId) == "string" then rightId else "",
			combatReady
		)
		local leftId = character:GetAttribute("LeftEquipped")
		attachSlot(character, "Left", if type(leftId) == "string" then leftId else "", combatReady)
	end

	return { Clear = clearEquipment, Rebuild = rebuildAttachments }
end

return EquipmentPresentation
