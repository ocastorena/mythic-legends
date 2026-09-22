--!strict
-- ServerScriptService/Services/CharacterService
-- One terminal server lifetime; character overrides belong to their character Trove.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Trove = require(ReplicatedStorage.Packages.Trove)
local PlayerUtil = require(ServerScriptService.Infrastructure.PlayerUtil)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)

local ServerTypes = require(ServerScriptService.Domain.Types)
local CharacterService = {}
local lifecycle = ServiceLifecycle.new("CharacterService")
local playerTroves: { [Player]: Trove.Trove } = {}
local isInitialized = false

local function configureCharacter(character: Model, owner: Trove.Trove)
	local configured: { [Humanoid]: boolean } = {}
	local function configure(child: Instance)
		if not child:IsA("Humanoid") or configured[child] then
			return
		end
		configured[child] = true
		local wasEnabled = child:GetStateEnabled(Enum.HumanoidStateType.Climbing)
		child:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		owner:Add(function()
			if
				child.Parent == character
				and not child:GetStateEnabled(Enum.HumanoidStateType.Climbing)
			then
				child:SetStateEnabled(Enum.HumanoidStateType.Climbing, wasEnabled)
			end
		end)
	end
	owner:Connect(character.ChildAdded, configure)
	for _, child in character:GetChildren() do
		configure(child)
	end
end

local function removePlayer(player: Player)
	local owner = playerTroves[player]
	if owner then
		playerTroves[player] = nil
		lifecycle.trove:Remove(owner)
	end
end

function CharacterService.Init(_context: ServerTypes.Context): ()
	isInitialized = true
end

function CharacterService.Start()
	assert(isInitialized, "[CharacterService] Init must run before Start")
	if not lifecycle:Start() then
		return
	end
	PlayerUtil.OnPlayer(function(player)
		local owner = lifecycle.trove:Extend()
		playerTroves[player] = owner
		local characterOwner = owner:Extend()
		local function onCharacter(character: Model)
			characterOwner:Clean()
			configureCharacter(character, characterOwner)
		end
		owner:Connect(player.CharacterAdded, onCharacter)
		owner:Connect(player.CharacterRemoving, function()
			characterOwner:Clean()
		end)
		if player.Character then
			onCharacter(player.Character)
		end
	end, lifecycle.trove)
	lifecycle.trove:Connect(Players.PlayerRemoving, removePlayer)
end

function CharacterService.Stop()
	if lifecycle:Stop() then
		table.clear(playerTroves)
	end
end

return CharacterService
