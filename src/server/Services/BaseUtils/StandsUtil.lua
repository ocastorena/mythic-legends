-- ServerScriptService/Systems/BaseService/StandUtil
local StandsUtil = {}

---------- helper functions ----------

-- gets the model for a mythling type/variant 
local function getMythlingModel(typeId: string, variantId: string, mythlingAssets: Folder)
	local mythlingModel = mythlingAssets:FindFirstChild(typeId):Clone()
	local variant = mythlingModel:FindFirstChild("Variants"):FindFirstChild(variantId):Clone()
	variant.Parent = mythlingModel:FindFirstChildWhichIsA("MeshPart")
	return mythlingModel
end

-- places a mythling model on a stand, respecting the stand's orientation 
local function setMythlingModel(mythlingModel: Model, stand: BasePart)
	if not (mythlingModel and stand) then return end
	mythlingModel.Parent = stand
	-- Ensure a PrimaryPart (for pivoting)
	local pp = mythlingModel.PrimaryPart or mythlingModel:FindFirstChildWhichIsA("BasePart")
	if not pp then
		warn("No BasePart found in mythling model")
		mythlingModel.Parent = stand -- fallback
		return
	end
	mythlingModel.PrimaryPart = pp  -- optionally set
	-- Compute the desired CFrame: stand’s CFrame, plus vertical offset, respecting stand’s orientation
	local baseCf = stand.CFrame
	local verticalOffset = (stand.Size.Y * 0.5)  -- how high above stand's top
	local upVec = baseCf.UpVector
	local targetPosition = stand.Position + upVec * verticalOffset
	-- `lookVector` of stand (forward direction) is baseCf.LookVector
	local targetRotation = baseCf - baseCf.Position  -- this isolates the rotation component of stand's CFrame
	-- Final CFrame = position * rotation
	local finalCf = CFrame.new(targetPosition) * targetRotation
	-- Use PivotTo to position + rotate the model
	mythlingModel:PivotTo(finalCf)
end

---------- Public Functions ----------

-- loads mythling models onto stands in the base
function StandsUtil.LoadMythlingsOnStands(baseSection: any, mythlingSection: any, baseModel: Model, mythlingAssets: Folder)
	-- Restore any saved placements now that the base exists
	local baseStands = baseSection.stands
	local standsFolder = baseModel.Stands
		for _, stand in ipairs(standsFolder:GetChildren()) do
		local standId = stand:GetAttribute("Id")
		local mythlingId = baseStands[standId]
		if mythlingId == "" then continue end
		local mythlingData = mythlingSection[mythlingId]
		local mythlingModel = getMythlingModel(mythlingData.typeId, mythlingData.variantId, mythlingAssets)
		setMythlingModel(mythlingModel, stand)
	end
end

-- sets a mythling on a stand, saving the Ids in the base and saving the placement on the stand 
function StandsUtil.SetMythlingOnStand(baseSection: any, mythlingSection: any, baseModel: Model, standId: number, mythlingId: number, mythlingAssets: Folder): BoolValue
	if baseSection.stands[standId] ~= "" then
		return false, "Stand " .. standId .. " already has a mythlingId"
	end
	if mythlingSection[mythlingId].standId ~= -1 then 
		return false, "Mythling " .. mythlingId .. " already has a standId" 
	end
	-- save Ids
	baseSection.stands[standId] = mythlingId
	mythlingSection[mythlingId].standId = standId
	-- place base
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
	local mythlingData = mythlingSection[mythlingId]
	local mythlingModel = getMythlingModel(mythlingData.typeId, mythlingData.variantId, mythlingAssets)
	setMythlingModel(mythlingModel, standModel)
	return true
end

-- removes a mythling from a stand, saving the Ids in the base and clearing the placement on the stand
function StandsUtil.RemoveMythlingFromStand(baseSection: any, mythlingSection: any, baseModel: Model, standId: number)
	local mythlingId = baseSection.stands[standId]
	if mythlingId == "" then return false end
	-- clear stand
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
	local child = standModel:FindFirstChildWhichIsA("Model")
	child:Destroy()
	-- clear saved data
	baseSection.stands[standId] = ""
	mythlingSection[mythlingId].standId = -1
	return true
end

return StandsUtil
