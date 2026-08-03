-- ServerScriptService/ServerModules/Infrastructure/RemoteUtil
-- Canonical list of every remote the game uses, so the source alone describes the API
-- surface between client and server. Bootstrap creates any that are missing, which makes
-- a fresh `rojo build` produce a runnable place instead of one that errors on
-- WaitForChild. Existing instances are reused, never replaced.

local RemoteUtil = {}

RemoteUtil.FOLDER_NAME = "Network"

-- name -> class. Requests are RemoteFunctions (they return a value); the rest are events.
RemoteUtil.DEFINITIONS = {
	AdminEvent = "RemoteEvent",
	BaseEvent = "RemoteEvent",
	ClaimEvent = "RemoteEvent",
	CurrencyEvent = "RemoteEvent",
	MythlingsEvent = "RemoteEvent",
	SpawnEvent = "RemoteEvent",
	CombatImpact = "RemoteEvent",
	PerformAttack = "RemoteEvent",
	SetShieldGuard = "RemoteEvent",
	UpdateState = "RemoteEvent",

	CombatLoadoutRequest = "RemoteFunction",
	GetStands = "RemoteFunction",
	ConsumablesRequest = "RemoteFunction",
	MaterialsRequest = "RemoteFunction",
	MythlingsRequest = "RemoteFunction",
	RequestState = "RemoteFunction",
}

-- Creates the folder and any missing remotes, then returns name -> instance for every
-- remote present. Extras already in the place (not in DEFINITIONS) are still returned so
-- nothing that exists today stops working.
function RemoteUtil.Ensure(parent: Instance): { [string]: Instance }
	local folder = parent:FindFirstChild(RemoteUtil.FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = RemoteUtil.FOLDER_NAME
		folder.Parent = parent
	end

	for name, className in pairs(RemoteUtil.DEFINITIONS) do
		local existing = folder:FindFirstChild(name)
		if existing and existing.ClassName ~= className then
			warn(`[RemoteUtil] {name} is a {existing.ClassName}, expected {className}`)
		elseif not existing then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end

	local remotes = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
			remotes[child.Name] = child
		end
	end
	return remotes
end

return RemoteUtil
