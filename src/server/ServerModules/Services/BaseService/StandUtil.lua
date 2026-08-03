-- ServerScriptService/ServerModules/Services/BaseService/StandUtil
local StandUtil = {}

local ServerScriptService = game:GetService("ServerScriptService")

local LogUtil = require(ServerScriptService.ServerModules.Infrastructure.LogUtil)
local log = LogUtil.For("BaseService.StandUtil")

---------- helper functions ----------

-- gets the model for a mythling type/variant
local function getMythlingModel(variantId: string, mythlingAssets: Folder, mythlingMeta: any)
	local variantModel = mythlingMeta.variants[variantId].model
	if not variantModel then
		log.warn(`Missing variant model in metadata for variantId {variantId}`)
		return nil
	end

	local mythlingAsset = mythlingAssets:FindFirstChild(variantModel)
	if not mythlingAsset then
		log.warn(`Missing variant model in MythlingAssets for variantId {variantId}`)
	end

	local mythlingModel = mythlingAsset:Clone()
	local variant = mythlingModel:FindFirstChild("Variants"):FindFirstChild(variantId):Clone()
	variant.Parent = mythlingModel:FindFirstChildWhichIsA("MeshPart")
	return mythlingModel
end

-- places a mythling model on a stand, respecting the stand's orientation
local function setMythlingModel(mythlingModel: Model, stand: BasePart)
	if not (mythlingModel and stand) then
		return
	end
	mythlingModel.Parent = stand
	-- Ensure a PrimaryPart (for pivoting)
	local pp = mythlingModel.PrimaryPart or mythlingModel:FindFirstChildWhichIsA("BasePart")
	if not pp then
		log.warn("No BasePart found in mythling model")
		mythlingModel.Parent = stand -- fallback
		return
	end
	mythlingModel.PrimaryPart = pp -- optionally set
	-- Compute the desired CFrame: stand’s CFrame, plus vertical offset, respecting stand’s orientation
	local baseCf = stand.CFrame
	local verticalOffset = (stand.Size.Y * 0.5) -- how high above stand's top
	local upVec = baseCf.UpVector
	local targetPosition = stand.Position + upVec * verticalOffset
	-- `lookVector` of stand (forward direction) is baseCf.LookVector
	local targetRotation = baseCf - baseCf.Position -- this isolates the rotation component of stand's CFrame
	-- Final CFrame = position * rotation
	local finalCf = CFrame.new(targetPosition) * targetRotation
	-- Use PivotTo to position + rotate the model
	mythlingModel:PivotTo(finalCf)
end

---------- Public Functions ----------

-- loads mythling models onto stands in the base
function StandUtil.LoadMythlingsOnStands(
	mythlingSection: any,
	baseModel: any,
	mythlingAssets: Folder,
	MythlingsMeta: any
)
	-- standId -> stand instance
	local standLookup = {}
	for _, stand in ipairs(baseModel.Stands:GetChildren()) do
		local id = stand:GetAttribute("Id")
		if id ~= nil then
			standLookup[id] = stand
		end
	end

	for mythlingId, entry in pairs(mythlingSection) do
		local standId = entry.standId
		if standId and standId >= 0 then
			local stand = standLookup[standId]
			if stand then
				local mythlingMeta = MythlingsMeta[entry.typeId]
				local model = getMythlingModel(entry.variantId, mythlingAssets, mythlingMeta)
				setMythlingModel(model, stand)
			else
				log.warn(("Stand %s missing for mythling %s"):format(tostring(standId), tostring(mythlingId)))
			end
		end
	end
end

-- sets a mythling on a stand, saving the Ids in the base and saving the placement on the stand
function StandUtil.SetMythlingOnStand(
	mythlingEntry: any,
	baseModel: any,
	standId: number,
	mythlingAssets: Folder,
	mythlingMeta: any
)
	if mythlingEntry.standId then
		return false, `[StandUtil] Mythling already has stand`
	end
	-- Resolve the target before mutating persistent state.
	local standModel = nil
	local stands = baseModel.Stands:GetChildren()
	for _, stand in pairs(stands) do
		if stand:GetAttribute("Id") == standId then
			standModel = stand
		end
	end
	if not standModel then
		return false, "Stand model not found"
	end
	mythlingEntry.standId = standId
	local mythlingModel = getMythlingModel(mythlingEntry.variantId, mythlingAssets, mythlingMeta)
	setMythlingModel(mythlingModel, standModel)
	return true
end

-- removes a mythling from a stand, saving the Ids in the base and clearing the placement on the stand
function StandUtil.RemoveMythlingFromStand(mythlingEntry: any, baseModel: any)
	-- clear stand
	local standModel = nil
	local stands = baseModel.Stands:GetChildren()
	for _, stand in pairs(stands) do
		if stand:GetAttribute("Id") == mythlingEntry.standId then
			standModel = stand
		end
	end
	if not standModel then
		return false, "Stand model not found"
	end
	local child = standModel:FindFirstChildWhichIsA("Model")
	if child then
		child:Destroy()
	end
	-- clear saved data

	mythlingEntry.standId = nil

	return true
end

return StandUtil
