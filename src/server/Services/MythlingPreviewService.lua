-- ServerScriptService/Services/MythlingPreviewService
-- Publishes sanitized visual-only Mythling models for client ViewportFrame previews.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MythlingPreviewService = {}

MythlingPreviewService.Priority = 5

local PREVIEW_FOLDER_NAME = "MythlingPreviewAssets"

local function sanitize(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("Sound")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("JointInstance")
			or descendant:IsA("Constraint")
			or descendant:IsA("Humanoid")
			or descendant:IsA("AnimationController")
			or descendant:IsA("Animation")
			or descendant:IsA("ValueBase") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
end

function MythlingPreviewService.Init(context)
	local existing = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local previews = Instance.new("Folder")
	previews.Name = PREVIEW_FOLDER_NAME
	previews.Parent = ReplicatedStorage

	local published: { [string]: boolean } = {}
	for _, definition in pairs(context.Metadata.Mythlings) do
		for _, variant in pairs(definition.variants) do
			local modelName = variant.model
			if type(modelName) == "string" and not published[modelName] then
				local source = context.Instances.MythlingAssets:FindFirstChild(modelName)
				if source and source:IsA("Model") then
					local preview = source:Clone()
					preview.Name = modelName
					sanitize(preview)
					preview.Parent = previews
					published[modelName] = true
				else
					warn(`[MythlingPreviewService] Missing model: {tostring(modelName)}`)
				end
			end
		end
	end
end

return MythlingPreviewService
