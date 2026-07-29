-- ReplicatedStorage/Client/Ui/MythlingPreviewUtil
-- Renders a sanitized Mythling model inside a GUI without touching live world creatures.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MythlingPreviewUtil = {}

local PREVIEW_NAME = "MythlingViewport"
local FIELD_OF_VIEW = 28
local DISPLAY_ROTATION = CFrame.Angles(0, math.rad(-12), 0)

local previewAssets = ReplicatedStorage:WaitForChild("MythlingPreviewAssets")

local function applyVariant(model: Model, variantId: string)
	local variants = model:FindFirstChild("Variants", true)
	local appearance = variants and variants:FindFirstChild(variantId)
	local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
	if appearance and appearance:IsA("SurfaceAppearance") and mesh then
		for _, child in ipairs(mesh:GetChildren()) do
			if child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		appearance:Clone().Parent = mesh
	end
	if variants then
		variants:Destroy()
	end
end

local function centerAndPose(model: Model): Vector3
	local bounds = model:GetBoundingBox()
	local centerOffset = CFrame.new(-bounds.Position)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = DISPLAY_ROTATION * centerOffset * descendant.CFrame
		end
	end
	local _, size = model:GetBoundingBox()
	return size
end

function MythlingPreviewUtil.Clear(container: GuiObject)
	local existing = container:FindFirstChild(PREVIEW_NAME)
	if existing then
		existing:Destroy()
	end
end

function MythlingPreviewUtil.Render(container: GuiObject, modelName: string?, variantId: string?): boolean
	MythlingPreviewUtil.Clear(container)
	if not modelName then
		return false
	end

	local source = previewAssets:FindFirstChild(modelName)
	if not (source and source:IsA("Model")) then
		return false
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = PREVIEW_NAME
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(135, 145, 160)
	viewport.LightColor = Color3.fromRGB(255, 238, 214)
	viewport.LightDirection = Vector3.new(-1, -0.8, 0.5)
	viewport.ZIndex = container.ZIndex + 1
	viewport.Parent = container

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local model = source:Clone()
	model.Name = "MythlingModel"
	model.Parent = worldModel
	applyVariant(model, variantId or "regular")

	if not model:FindFirstChildWhichIsA("BasePart", true) then
		viewport:Destroy()
		return false
	end

	local size = centerAndPose(model)
	local largestVisibleDimension = math.max(size.X, size.Y)
	local halfFieldOfView = math.rad(FIELD_OF_VIEW * 0.5)
	local distance = largestVisibleDimension * 0.5 / math.tan(halfFieldOfView)
	distance = distance * 1.18 + size.Z * 0.5

	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(
		Vector3.new(distance * 0.08, size.Y * 0.04, -distance),
		Vector3.zero
	)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return true
end

return MythlingPreviewUtil
