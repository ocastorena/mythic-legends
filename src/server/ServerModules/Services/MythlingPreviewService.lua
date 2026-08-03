-- ServerScriptService/ServerModules/Services/MythlingPreviewService
-- Publishes sanitized visual-only Mythling models for client ViewportFrame previews.

local ServerScriptService = game:GetService("ServerScriptService")

local LogUtil = require(ServerScriptService.ServerModules.Infrastructure.LogUtil)
local log = LogUtil.For("MythlingPreviewService")

local MythlingPreviewService = {}

MythlingPreviewService.Priority = 5
local Context: any

local function clearPreviews(previews: Folder)
	for _, child in ipairs(previews:GetChildren()) do
		child:Destroy()
	end
end

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
	Context = context
end

function MythlingPreviewService.Start()
	local previews = Context.Instances.MythlingPreviews
	clearPreviews(previews)

	local published: { [string]: boolean } = {}
	for _, definition in pairs(Context.Metadata.Mythlings) do
		for _, variant in pairs(definition.variants) do
			local modelName = variant.model
			if type(modelName) == "string" and not published[modelName] then
				local source = Context.Instances.MythlingAssets:FindFirstChild(modelName)
				if source and source:IsA("Model") then
					local preview = source:Clone()
					preview.Name = modelName
					sanitize(preview)
					preview.Parent = previews
					published[modelName] = true
				else
					log.warn(`Missing model: {tostring(modelName)}`)
				end
			end
		end
	end
end

function MythlingPreviewService.Stop()
	if Context then
		clearPreviews(Context.Instances.MythlingPreviews)
	end
end

return MythlingPreviewService
