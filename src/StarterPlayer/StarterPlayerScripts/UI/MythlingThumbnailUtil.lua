-- StarterPlayer/StarterPlayerScripts/UI/MythlingThumbnailUtil
-- Renders authoring-generated thumbnail images without replicating gameplay models.

local MythlingThumbnailUtil = {}

local GENERATED_IMAGE_NAME = "MythlingThumbnail"

type ImageGui = ImageLabel | ImageButton

local function directImage(container: GuiObject): ImageGui?
	if container:IsA("ImageLabel") or container:IsA("ImageButton") then
		return container
	end
	return nil
end

local function generatedImage(container: GuiObject): ImageLabel
	local existing = container:FindFirstChild(GENERATED_IMAGE_NAME)
	if existing and existing:IsA("ImageLabel") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local image = Instance.new("ImageLabel")
	image.Name = GENERATED_IMAGE_NAME
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = container.ZIndex + 1
	image.Parent = container
	return image
end

function MythlingThumbnailUtil.Clear(container: GuiObject)
	local image = directImage(container)
	if image then
		image.Image = ""
	end

	local generated = container:FindFirstChild(GENERATED_IMAGE_NAME)
	if generated then
		generated:Destroy()
	end
end

function MythlingThumbnailUtil.Render(container: GuiObject, thumbnail: string?): boolean
	MythlingThumbnailUtil.Clear(container)
	if type(thumbnail) ~= "string" or thumbnail == "" then
		return false
	end

	local image = directImage(container) or generatedImage(container)
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = thumbnail
	return true
end

return MythlingThumbnailUtil
