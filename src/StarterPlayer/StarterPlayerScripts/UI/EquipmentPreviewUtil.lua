-- StarterPlayer/StarterPlayerScripts/UI/EquipmentPreviewUtil
-- Renders a Tool or Equipment Model's visible parts directly in UI, avoiding separate
-- thumbnail assets that can drift from the authored equipment.

local EquipmentPreviewUtil = {}

local PREVIEW_NAME = "EquipmentViewport"
local FIELD_OF_VIEW = 28
local DISPLAY_ROTATION = CFrame.Angles(math.rad(60), 0, math.rad(-35))

local function removeNonVisualDescendants(part: BasePart)
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("Sound")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("JointInstance")
			or descendant:IsA("Constraint") then
			descendant:Destroy()
		end
	end
end

local function cloneVisibleParts(source: Instance, worldModel: WorldModel): Model?
	local model = Instance.new("Model")
	model.Name = "EquipmentModel"
	model.Parent = worldModel

	for _, descendant in ipairs(source:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local part = descendant:Clone()
			removeNonVisualDescendants(part)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Parent = model
		end
	end

	if not model:FindFirstChildWhichIsA("BasePart", true) then
		model:Destroy()
		return nil
	end
	return model
end

local function centerAndPose(model: Model): Vector3
	local initialBounds = model:GetBoundingBox()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = DISPLAY_ROTATION * initialBounds:ToObjectSpace(descendant.CFrame)
		end
	end

	local posedBounds, posedSize = model:GetBoundingBox()
	local centerOffset = -posedBounds.Position
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Position += centerOffset
		end
	end
	return posedSize
end

function EquipmentPreviewUtil.Clear(container: GuiObject)
	local existing = container:FindFirstChild(PREVIEW_NAME)
	if existing then
		existing:Destroy()
	end
end

function EquipmentPreviewUtil.Render(container: GuiObject, source: Instance?): boolean
	EquipmentPreviewUtil.Clear(container)
	if not source then
		return false
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = PREVIEW_NAME
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(155, 135, 115)
	viewport.LightColor = Color3.fromRGB(255, 232, 198)
	viewport.LightDirection = Vector3.new(-1, -0.8, -0.6)
	viewport.ZIndex = container.ZIndex + 1
	viewport.Parent = container

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	local model = cloneVisibleParts(source, worldModel)
	if not model then
		viewport:Destroy()
		return false
	end

	local posedSize = centerAndPose(model)
	local largestVisibleDimension = math.max(posedSize.X, posedSize.Y)
	local halfFieldOfView = math.rad(FIELD_OF_VIEW * 0.5)
	local distance = largestVisibleDimension * 0.5 / math.tan(halfFieldOfView)
	distance = distance * 1.18 + posedSize.Z * 0.5

	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return true
end

return EquipmentPreviewUtil
