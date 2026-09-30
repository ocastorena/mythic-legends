--!strict
-- ServerScriptService/Services/BaseService/BaseView
-- Read committed Base state and exact purchase quotes without settling, allocating, or spending.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local BaseState = require(ServerScriptService.Shared.BaseState)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local ShrineConstruction = require(script.Parent.ShrineConstruction)
local BaseExpansionPurchase = require(script.Parent.BaseExpansionPurchase)

local BaseView = {}
export type DataSource = { GetLoadedData: (Player) -> Types.PlayerDoc? }
export type BaseView = { Get: (Player) -> Types.BaseViewResult }

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function currentRevision(data: Types.PlayerDoc): number
	local state: unknown = data.transactions
	if state == nil then
		return 0
	end
	if type(state) == "table" and getmetatable(state) == nil then
		local revision = (state :: { [string]: unknown }).revision
		if whole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function project(data: Types.PlayerDoc): (Types.BaseView?, string?)
	if data.version ~= PlayerData.schemaVersion then
		return nil, "UnsupportedVersion"
	end
	if
		not plain(data.base)
		or not plain(data.base.craftingStation)
		or not plain(data.base.shrines)
	then
		return nil, "InvalidBaseState"
	end
	local status = BaseState.GetStatus(data.base)
	if not status then
		return nil, "InvalidBaseState"
	end
	if not plain(data.currency) or not whole(data.currency.gold) then
		return nil, "InvalidCurrency"
	end
	local materialError = InventoryCapacity.ValidateMaterialState(data)
	if materialError then
		return nil, materialError
	end
	local savedShrines = data.base.shrines
	if not savedShrines or not plain(savedShrines) then
		return nil, "InvalidBaseState"
	end
	local owned: { Types.BaseShrineView } = {}
	for id, shrine in savedShrines do
		if not plain(shrine) then
			return nil, "InvalidBaseState"
		end
		table.insert(owned, {
			id = id,
			shrineId = shrine.shrineId,
			buildSlotId = shrine.buildSlotId,
			level = shrine.level,
		})
	end
	table.sort(owned, function(left: Types.BaseShrineView, right: Types.BaseShrineView)
		return if left.buildSlotId == right.buildSlotId
			then left.id < right.id
			else left.buildSlotId < right.buildSlotId
	end)
	local ids: { string } = {}
	for id in Shrines do
		table.insert(ids, id)
	end
	table.sort(ids)
	local offers: { Types.ShrineBuildOffer } = {}
	for _, id in ids do
		local offer, problem = ShrineConstruction.ReadOffer(data, id)
		if not offer then
			return nil, problem
		end
		table.insert(offers, offer)
	end
	local expansion, expansionCode = BaseExpansionPurchase.ReadOffer(data)
	if not expansion and expansionCode ~= "MaxBaseSlots" then
		return nil, expansionCode
	end
	return {
		status = status,
		buildSlotUpgradeCount = data.base.buildSlotUpgrades :: number,
		shrines = owned,
		buildOffers = offers,
		expansion = expansion,
		expansionCode = expansionCode,
	},
		nil
end

function BaseView.new(
	DataService: DataSource,
	checkAccess: ((Player, Types.PlayerDoc) -> string?)?
): BaseView
	assert(
		type(DataService) == "table" and type(DataService.GetLoadedData) == "function",
		"[BaseService.BaseView] DataService.GetLoadedData required"
	)
	local api = {}
	function api.Get(player: Player): Types.BaseViewResult
		local data = DataService.GetLoadedData(player)
		if not data then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local revision = currentRevision(data)
		if revision < 0 then
			return { ok = false, code = "InvalidTransaction", revision = revision }
		end
		local accessProblem = if checkAccess then checkAccess(player, data) else nil
		if accessProblem then
			return { ok = false, code = accessProblem, revision = revision }
		end
		local view, problem = project(data)
		if not view then
			return { ok = false, code = problem, revision = revision }
		end
		return { ok = true, revision = revision, view = view }
	end
	return api
end

return table.freeze(BaseView)
