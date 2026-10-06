--!strict
-- ServerStorage/Tests/__tests__/SpawnServicePolicy.spec
-- Disposable engine instances exercise service wiring, not authored-map or multiplayer readiness.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local MythlingSpawns = require(ReplicatedStorage.Shared.Configurations.MythlingSpawns)
local SpawnSelection = require(ServerScriptService.Services.MythlingSpawnService.SpawnSelection)
local SpawnLifetimeUtil =
	require(ServerScriptService.Services.MythlingSpawnService.SpawnLifetimeUtil)

local describe, it, expect, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.it,
	JestGlobals.expect,
	JestGlobals.afterEach,
	JestGlobals.jest
local serviceModule = ServerScriptService.Services.MythlingSpawnService
local selectionModule = serviceModule.SpawnSelection
local lifetimeModule = serviceModule.SpawnLifetimeUtil
local logModule = ServerScriptService.Infrastructure.LogUtil
local cleanup: { () -> () } = {}
type Service = ServerTypes.Service & ServerTypes.SpawnApi

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function fixture()
	local root = Instance.new("Folder")
	root.Name = "SpawnServicePolicyTest"
	root.Parent = workspace
	table.insert(cleanup, function()
		root:Destroy()
	end)
	local arena = Instance.new("Part")
	arena.Anchored = true
	arena.Size = Vector3.new(512, 2, 512)
	arena.Parent = root
	local models = Instance.new("Folder")
	models.Parent = root
	local assets = Instance.new("Folder")
	assets.Parent = root
	for _, definition in Mythlings do
		local model = Instance.new("Model")
		model.Name = definition.variants.regular.model
		local part = Instance.new("Part")
		part.Anchored = true
		part.Parent = model
		model.PrimaryPart = part
		model.Parent = assets
	end
	local spawned = Instance.new("RemoteEvent")
	spawned.Parent = root
	local tuning = copy(MythlingSpawns)
	local state = {
		builds = {} :: { { forms: unknown, weights: unknown, pool: SpawnSelection.Pool? } },
		chosenPools = {} :: { SpawnSelection.Pool },
		validations = {} :: { { forms: unknown, rateField: string } },
		resolutionCounts = {} :: { number },
		retuneOnActivation = nil :: number?,
		errors = {} :: { string },
	}
	jest.mock(selectionModule, function()
		return {
			Build = function(forms: unknown, weights: unknown): (SpawnSelection.Pool?, string?)
				local pool, problem = SpawnSelection.Build(forms, weights)
				table.insert(state.builds, { forms = forms, weights = weights, pool = pool })
				return pool, problem
			end,
			Choose = function(
				pool: SpawnSelection.Pool,
				rarityRoll: number,
				formRoll: number
			): string?
				expect(rarityRoll >= 0 and rarityRoll <= 1).toBe(true)
				expect(formRoll >= 0 and formRoll <= 1).toBe(true)
				table.insert(state.chosenPools, pool)
				-- Deterministic form selection leaves actual placement and model activation intact.
				return SpawnSelection.Choose(pool, 0, 0)
			end,
		}
	end)
	jest.mock(lifetimeModule, function()
		return {
			GetDeadline = SpawnLifetimeUtil.GetDeadline,
			Validate = function(
				forms: unknown,
				config: Types.MythlingSpawnConfiguration,
				rateField: string
			): (boolean, string?)
				table.insert(state.validations, { forms = forms, rateField = rateField })
				return SpawnLifetimeUtil.Validate(forms, config, rateField)
			end,
			Resolve = function(
				id: string,
				rarity: string,
				rate: number,
				config: Types.MythlingSpawnConfiguration
			): (number?, string?)
				local count = #models:GetChildren()
				table.insert(state.resolutionCounts, count)
				local retune = state.retuneOnActivation
				if retune and count == tuning.targetActive then
					config.expireSeconds.Common = retune
				end
				return SpawnLifetimeUtil.Resolve(id, rarity, rate, config)
			end,
		}
	end)
	jest.mock(logModule, function()
		return {
			For = function()
				return {
					error = function(message: string)
						table.insert(state.errors, message)
					end,
					warn = function(message: string)
						table.insert(state.errors, message)
					end,
				}
			end,
		}
	end)
	local isolated: Service? = nil
	jest.isolateModules(function()
		local loadService = require :: (ModuleScript) -> Service
		isolated = loadService(serviceModule)
	end)
	local service = assert(isolated, "[SpawnServicePolicy.spec] Expected isolated service")
	table.insert(cleanup, service.Stop)
	local context = (
		{
			Instances = {
				Arena = arena,
				Mythlings = models,
				MythlingAssets = assets,
				Templates = root,
				Bases = root,
			},
			Configurations = { Mythlings = Mythlings, MythlingSpawns = tuning },
			Remotes = { World = { Spawned = spawned } },
		} :: unknown
	) :: ServerTypes.Context
	return { service = service, context = context, tuning = tuning, models = models, state = state }
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(selectionModule)
	jest.unmock(lifetimeModule)
	jest.unmock(logModule)
end)

describe("MythlingSpawnService policy integration", function()
	it(
		"validates both catalogues before spawning and explicitly selects the prototype pool",
		function()
			local f = fixture()
			f.service.Init(f.context)
			expect(#f.state.builds).toBe(2)
			expect(f.state.builds[1].forms).toEqual(MythlingForms)
			expect(f.state.builds[1].weights).toBe(f.tuning.rarityWeights)
			expect(f.state.builds[2].forms).toBe(Mythlings)
			expect(f.state.builds[2].weights).toBe(f.tuning.prototypeRarityWeights)
			expect(f.state.validations).toEqual({
				{ forms = MythlingForms, rateField = "captureProgressPerSecond" },
				{ forms = Mythlings, rateField = "fillRate" },
			})
			expect(#f.models:GetChildren()).toBe(0)
			expect(f.service.IsCaptureReady()).toBe(false)
			f.service.Start()
			expect(f.service.IsCaptureReady()).toBe(true)
			expect(#f.state.chosenPools).toBe(12)
			for _, pool in f.state.chosenPools do
				expect(pool).toBe(f.state.builds[2].pool)
			end
			for _, entry in f.service.GetActiveMythlings() do
				expect(entry.typeId).toBe("mythling_0001")
				expect(entry.rarity).toBe(Mythlings.mythling_0001.rarity)
				expect(entry.fillRate).toBe(Mythlings.mythling_0001.fillRate)
				expect(entry.lifetimeSeconds).toBe(240)
			end
			f.service.Start()
			expect(#f.state.chosenPools).toBe(12)
			f.service.Stop()
			f.service.Stop()
			expect(f.service.IsCaptureReady()).toBe(false)
			expect(#f.models:GetChildren()).toBe(0)
		end
	)

	it(
		"resolves initial deadlines only after the full prefill and never recomputes active timers",
		function()
			local f = fixture()
			f.service.Init(f.context)
			f.state.retuneOnActivation = 300
			f.service.Start()
			expect(#f.state.resolutionCounts).toBe(24)
			for index = 1, 12 do
				expect(f.state.resolutionCounts[index]).toBe(index - 1)
				expect(f.state.resolutionCounts[index + 12]).toBe(12)
			end
			local startedAt: number? = nil
			local deadlines: { [string]: number } = {}
			for id, entry in f.service.GetActiveMythlings() do
				startedAt = startedAt or entry.startedAt
				expect(entry.startedAt).toBe(startedAt)
				expect(entry.lifetimeSeconds).toBe(300)
				expect(entry.expireAt).toBe(entry.startedAt + 300)
				deadlines[id] = entry.expireAt
			end
			f.tuning.expireSeconds.Common = 600
			for id, entry in f.service.GetActiveMythlings() do
				f.service.SetOvertime(id)
				expect(entry.expireAt).toBe(deadlines[id])
				expect(entry.lifetimeSeconds).toBe(300)
			end
			expect(#f.state.resolutionCounts).toBe(24)
			expect(#f.state.chosenPools).toBe(12)
		end
	)

	it(
		"keeps the whole initial population closed when its activation deadline is unsafe",
		function()
			local f = fixture()
			f.service.Init(f.context)
			f.state.retuneOnActivation = 2 ^ 53 - 1
			f.service.Start()
			expect(f.service.IsCaptureReady()).toBe(false)
			expect(f.service.GetActiveMythlings()).toEqual({})
			expect(f.models:GetAttribute("RefillFailed")).toBe(true)
			expect(#f.models:GetChildren()).toBe(12)
			expect(#f.state.chosenPools).toBe(12)
			expect(#f.state.errors).toBe(1)
			for _, model in f.models:GetChildren() do
				expect(model:GetAttribute("CaptureReady")).toBe(false)
				expect(model:GetAttribute("ExpireAt")).toBeNil()
				expect(model:GetAttribute("State")).toBe("PREFILL")
			end
		end
	)

	it(
		"rejects incomplete selection or impossible lifetimes before any model is created",
		function()
			local cases: { (Types.MythlingSpawnConfiguration) -> () } = {
				function(tuning)
					tuning.rarityWeights.Epic = nil
				end,
				function(tuning)
					tuning.prototypeRarityWeights.Legendary = nil
				end,
				function(tuning)
					tuning.expireSeconds.Epic = nil
				end,
				function(tuning)
					tuning.expireSeconds.Legendary = nil
				end,
				function(tuning)
					tuning.formExpireSeconds.mythling_0003 = 60
				end,
				function(tuning)
					tuning.formExpireSeconds.mythling_0001 = 20
				end,
			}
			for _, change in cases do
				local f = fixture()
				change(f.tuning)
				expect(function()
					f.service.Init(f.context)
				end).toThrow()
				expect(f.service.IsCaptureReady()).toBe(false)
				expect(#f.models:GetChildren()).toBe(0)
				expect(#f.state.chosenPools).toBe(0)
			end
		end
	)
end)
