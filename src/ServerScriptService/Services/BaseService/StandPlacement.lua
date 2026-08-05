-- ServerScriptService/Services/BaseService/StandPlacement
local StandPlacement = {}

local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local log = LogUtil.For("BaseService.StandPlacement")

local function getMythlingModel(variantId: unknown, mythlingAssets: Folder, mythlingMeta: any): (Model?, string?)
	if type(variantId) ~= "string" or variantId == "" then
		return nil, "Mythling variantId is invalid"
	end
	if type(mythlingMeta) ~= "table" or type(mythlingMeta.variants) ~= "table" then
		return nil, `Missing Mythling metadata for variantId {variantId}`
	end

	local variantDefinition = mythlingMeta.variants[variantId]
	local modelName = type(variantDefinition) == "table" and variantDefinition.model or nil
	if type(modelName) ~= "string" or modelName == "" then
		return nil, `Missing model name in metadata for variantId {variantId}`
	end

	local mythlingAsset = mythlingAssets:FindFirstChild(modelName)
	if not (mythlingAsset and mythlingAsset:IsA("Model")) then
		return nil, `Missing Model '{modelName}' in MythlingAssets for variantId {variantId}`
	end

	local cloneSucceeded, mythlingModel = pcall(function()
		return mythlingAsset:Clone()
	end)
	if not cloneSucceeded or not mythlingModel then
		return nil, `Could not clone Mythling model '{modelName}'`
	end

	local variants = mythlingModel:FindFirstChild("Variants")
	local variant = variants and variants:FindFirstChild(variantId)
	local mesh = mythlingModel:FindFirstChildWhichIsA("MeshPart", true)
	if not (variant and variant:IsA("SurfaceAppearance")) then
		mythlingModel:Destroy()
		return nil, `Missing SurfaceAppearance '{variantId}' in Mythling model '{modelName}'`
	end
	if not mesh then
		mythlingModel:Destroy()
		return nil, `Missing MeshPart in Mythling model '{modelName}'`
	end

	local surfaceSucceeded, surface = pcall(function()
		return variant:Clone()
	end)
	if not surfaceSucceeded or not surface then
		mythlingModel:Destroy()
		return nil, `Could not clone SurfaceAppearance '{variantId}' in Mythling model '{modelName}'`
	end
	surface.Parent = mesh
	return mythlingModel, nil
end

local function setMythlingModel(mythlingModel: Model, stand: BasePart): (boolean, string?)
	local primaryPart = mythlingModel.PrimaryPart or mythlingModel:FindFirstChildWhichIsA("BasePart", true)
	if not primaryPart then
		return false, `No BasePart found in Mythling model '{mythlingModel.Name}'`
	end

	local targetPosition = stand.Position + stand.CFrame.UpVector * (stand.Size.Y * 0.5)
	local targetRotation = stand.CFrame - stand.Position
	local targetCFrame = CFrame.new(targetPosition) * targetRotation
	local placed, placementError = pcall(function()
		mythlingModel.PrimaryPart = primaryPart
		mythlingModel:PivotTo(targetCFrame)
		mythlingModel.Parent = stand
	end)
	if not placed then
		return false, `Could not place Mythling model '{mythlingModel.Name}': {placementError}`
	end
	return true, nil
end

local function getStands(baseModel: any): (Folder?, string?)
	if typeof(baseModel) ~= "Instance" or not baseModel:IsA("Model") then
		return nil, "Base model is invalid"
	end
	local stands = baseModel:FindFirstChild("Stands")
	if not (stands and stands:IsA("Folder")) then
		return nil, "Base model is missing its Stands folder"
	end
	return stands, nil
end

local function findStand(baseModel: any, standId: number): (BasePart?, string?)
	local stands, standsError = getStands(baseModel)
	if not stands then
		return nil, standsError
	end
	for _, stand in stands:GetChildren() do
		if stand:IsA("BasePart") and stand:GetAttribute("Id") == standId then
			return stand, nil
		end
	end
	return nil, `Stand {standId} was not found`
end

function StandPlacement.LoadMythlingsOnStands(
	mythlingSection: any,
	baseModel: any,
	mythlingAssets: Folder,
	MythlingsMeta: any
)
	local stands, standsError = getStands(baseModel)
	if not stands then
		log.warn(standsError)
		return
	end

	local standLookup: { [number]: BasePart } = {}
	for _, stand in stands:GetChildren() do
		local id = stand:GetAttribute("Id")
		if stand:IsA("BasePart") and type(id) == "number" then
			standLookup[id] = stand
		end
	end

	for mythlingId, entry in pairs(mythlingSection) do
		local standId = type(entry) == "table" and entry.standId or nil
		if type(standId) == "number" and standId >= 0 then
			local stand = standLookup[standId]
			if not stand then
				log.warn(`Stand {standId} is missing for Mythling {mythlingId}`)
				continue
			end

			local mythlingMeta = MythlingsMeta[entry.typeId]
			local model, modelError = getMythlingModel(entry.variantId, mythlingAssets, mythlingMeta)
			if not model then
				log.warn(`Could not load Mythling {mythlingId} on stand {standId}: {modelError}`)
				continue
			end
			if stand:FindFirstChildWhichIsA("Model") then
				model:Destroy()
				log.warn(`Could not load Mythling {mythlingId}: stand {standId} is occupied`)
				continue
			end

			local placed, placementError = setMythlingModel(model, stand)
			if not placed then
				model:Destroy()
				log.warn(`Could not load Mythling {mythlingId} on stand {standId}: {placementError}`)
			end
		end
	end
end

function StandPlacement.SetMythlingOnStand(
	mythlingEntry: any,
	baseModel: any,
	standId: number,
	mythlingAssets: Folder,
	mythlingMeta: any
): (boolean, string?)
	if type(mythlingEntry) ~= "table" then
		return false, "Mythling entry is invalid"
	end
	if mythlingEntry.standId ~= nil then
		return false, "Mythling already has a stand"
	end

	local standModel, standError = findStand(baseModel, standId)
	if not standModel then
		return false, standError
	end
	if standModel:FindFirstChildWhichIsA("Model") then
		return false, `Stand {standId} is occupied`
	end

	local mythlingModel, modelError = getMythlingModel(mythlingEntry.variantId, mythlingAssets, mythlingMeta)
	if not mythlingModel then
		return false, modelError
	end
	local placed, placementError = setMythlingModel(mythlingModel, standModel)
	if not placed then
		mythlingModel:Destroy()
		return false, placementError
	end

	-- Persistent state changes only after the model exists on the requested stand.
	mythlingEntry.standId = standId
	return true, nil
end

function StandPlacement.RemoveMythlingFromStand(mythlingEntry: any, baseModel: any): (boolean, string?)
	if type(mythlingEntry) ~= "table" or type(mythlingEntry.standId) ~= "number" then
		return false, "Mythling is not assigned to a valid stand"
	end
	local standModel, standError = findStand(baseModel, mythlingEntry.standId)
	if not standModel then
		return false, standError
	end

	local child = standModel:FindFirstChildWhichIsA("Model")
	if child then
		child:Destroy()
	end
	mythlingEntry.standId = nil
	return true, nil
end

return StandPlacement
