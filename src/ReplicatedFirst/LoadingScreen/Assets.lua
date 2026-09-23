--!strict
-- ReplicatedFirst/LoadingScreen/Assets
-- Selects the first view's assets without visiting catalogues or other players' bases.

local Assets = {}

-- A presentation budget around the actual starting position, independent of map/model pivots.
local SPAWN_ASSET_RADIUS = 96

export type Snapshot = {
	character: Model?,
	characterRoot: BasePart?,
	base: Model?,
	baseSpawn: BasePart?,
	hud: ScreenGui?,
}

function Assets.Resolve(
	world: Instance,
	playerGui: Instance,
	character: Model?,
	userId: number
): Snapshot
	-- Resolve every level again: Runtime, Bases, the base and Spawn may replicate separately.
	local runtime = world:FindFirstChild("Runtime")
	local bases = runtime and runtime:FindFirstChild("Bases")
	local candidate = bases and bases:FindFirstChild(tostring(userId))
	local base = if candidate and candidate:IsA("Model") then candidate else nil
	local spawn = base and base:FindFirstChild("Spawn")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hud = playerGui:FindFirstChild("HUDGui")
	return {
		character = character,
		characterRoot = if root and root:IsA("BasePart") then root else nil,
		base = base,
		baseSpawn = if spawn and spawn:IsA("BasePart") then spawn else nil,
		hud = if hud and hud:IsA("ScreenGui") then hud else nil,
	}
end

function Assets.GetStreamPosition(snapshot: Snapshot): Vector3?
	-- The initial character can exist before BaseService attaches its respawn teleport.
	local root = snapshot.characterRoot or snapshot.baseSpawn
	return if root then root.Position else nil
end

function Assets.IsReady(snapshot: Snapshot): boolean
	return snapshot.characterRoot ~= nil and snapshot.baseSpawn ~= nil and snapshot.hud ~= nil
end

local function isVisualAsset(instance: Instance): boolean
	return instance:IsA("MeshPart")
		or instance:IsA("PartOperation")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("ImageLabel")
		or instance:IsA("ImageButton")
		or instance:IsA("TextLabel")
		or instance:IsA("TextButton")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Animation")
		or instance:IsA("SpecialMesh")
		or instance:IsA("Shirt")
		or instance:IsA("Pants")
		or instance:IsA("ShirtGraphic")
		or instance:IsA("CharacterMesh")
end

local function isNearby(part: BasePart, position: Vector3): boolean
	local offset = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5
	local outside = Vector3.new(
		math.max(math.abs(offset.X) - halfSize.X, 0),
		math.max(math.abs(offset.Y) - halfSize.Y, 0),
		math.max(math.abs(offset.Z) - halfSize.Z, 0)
	)
	return outside.Magnitude <= SPAWN_ASSET_RADIUS
end

function Assets.Collect(
	world: Instance,
	playerGui: Instance,
	loadingGui: ScreenGui,
	snapshot: Snapshot
): { Instance }
	local assets: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local function append(instance: Instance)
		if isVisualAsset(instance) and not seen[instance] then
			seen[instance] = true
			table.insert(assets, instance)
		end
	end

	local function appendVisibleUi(root: Instance)
		if root:IsA("ScreenGui") and not root.Enabled then
			return
		end
		if root:IsA("GuiObject") and not root.Visible then
			return
		end
		append(root)
		for _, child in root:GetChildren() do
			appendVisibleUi(child)
		end
	end
	appendVisibleUi(loadingGui)
	-- Only roots that can be visible immediately after the loading screen closes.
	for _, name in { "HUDGui", "HotbarGui", "StaminaGui", "CombatActionGui" } do
		local root = playerGui:FindFirstChild(name)
		if root and root:IsA("ScreenGui") then
			appendVisibleUi(root)
		end
	end
	if snapshot.character then
		for _, instance in snapshot.character:GetDescendants() do
			append(instance)
		end
	end

	local position = Assets.GetStreamPosition(snapshot)
	if not position then
		return assets
	end
	local function appendNearby(root: Instance?)
		if not root then
			return
		end
		for _, instance in root:GetDescendants() do
			if not isVisualAsset(instance) then
				continue
			end
			local part = if instance:IsA("BasePart")
				then instance
				else instance:FindFirstAncestorWhichIsA("BasePart")
			if part and part:IsA("BasePart") and isNearby(part, position) then
				append(instance)
			end
		end
	end
	if snapshot.baseSpawn and isNearby(snapshot.baseSpawn, position) then
		appendNearby(snapshot.base)
	end
	local authoredWorld = world:FindFirstChild("World")
	if authoredWorld then
		-- FloatingIsland is the central island's underside, not an assumed player spawn.
		local arena = authoredWorld:FindFirstChild("Arena")
		local visuals = arena and arena:FindFirstChild("Visuals")
		appendNearby(visuals and visuals:FindFirstChild("FloatingIsland"))
		local baseIslands = authoredWorld:FindFirstChild("BaseIslands")
		if baseIslands then
			for _, island in baseIslands:GetChildren() do
				local collision = island:FindFirstChild("Collision")
				local grass = collision and collision:FindFirstChild("Grass")
				if grass and grass:IsA("BasePart") and isNearby(grass, position) then
					appendNearby(island)
				end
			end
		end
	end
	return assets
end

return Assets
