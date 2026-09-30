--!strict
-- ServerScriptService/Services/CraftingService
-- Owns headless crafting commands and automatic receipt resolution, never Station presentation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local Crafting = require(ReplicatedStorage.Shared.Configurations.Crafting)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local LogUtil = require(ServerScriptService.Infrastructure.LogUtil)
local CraftingJobs = require(script.CraftingJobs)
local CraftingCommands = require(script.CraftingCommands)
local DueJobs = require(script.DueJobs)

local CraftingService = {}
local lifecycle = ServiceLifecycle.new("CraftingService")
local log = LogUtil.For("CraftingService")
local commands: CraftingCommands.CraftingCommands?
local scheduler: DueJobs.DueJobs?

function CraftingService.Init(context: ServerTypes.Context)
	local DataService = context.Services.DataService
	local jobs = CraftingJobs.new()
	commands = CraftingCommands.new(DataService, jobs)
	-- These pure closures remain valid during DataService's final release even after Stop.
	DataService.RegisterMutationPreparation("Crafting", jobs.SettleDueToDraft)
	DataService.RegisterProfileSettlement("Crafting", function(draft, now)
		return jobs.SettleDueToDraft(draft, now)
	end)
	scheduler = DueJobs.new(
		DataService,
		function()
			return Players:GetPlayers()
		end,
		Crafting.resolutionIntervalSeconds,
		nil,
		function(player, code)
			log.error(`Crafting settlement failed for userId {player.UserId}`, code)
		end
	)
end

function CraftingService.Start()
	if not lifecycle:Start() then
		return
	end
	local timer = scheduler
	assert(timer, "[CraftingService] Init must precede Start")
	lifecycle.trove:Connect(RunService.Heartbeat, timer.Step)
end

function CraftingService.Stop()
	if not lifecycle:Stop() then
		return
	end
	commands = nil
	scheduler = nil
end

local function available(player: Player): boolean
	return lifecycle:IsRunning()
		and typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

function CraftingService.GetStation(
	player: Player,
	request: Types.GetCraftingStationRequest
): Types.CraftingStationViewResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.GetStation(player, request)
end

function CraftingService.StartJob(
	player: Player,
	request: Types.StartCraftingRequest
): Types.TransactionResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.Start(player, request)
end

function CraftingService.CancelJob(
	player: Player,
	request: Types.CancelCraftingRequest
): Types.TransactionResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.Cancel(player, request)
end

return CraftingService
