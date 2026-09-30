--!strict
-- ServerScriptService/Services/MythlingSpawnService/SpawnSelection
-- Select a configured rarity, then an equally likely form; this does not impose population quotas.

local FreezeUtil = require(game:GetService("ReplicatedStorage").Shared.FreezeUtil)

local SpawnSelection = {}

export type Bucket = {
	rarity: string,
	weight: number,
	cumulativeWeight: number,
	forms: { string },
}
export type Pool = {
	totalWeight: number,
	buckets: { Bucket },
}

local MAX_SAFE_INTEGER = 2 ^ 53 - 1

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isPlain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function isRoll(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

function SpawnSelection.Build(rawForms: unknown, rawWeights: unknown): (Pool?, string?)
	if not isPlain(rawForms) or not isPlain(rawWeights) then
		return nil, "InvalidSpawnConfiguration"
	end
	local groups: { [string]: { string } } = {}
	local rarities: { string } = {}
	for id, rawDefinition in rawForms :: { [unknown]: unknown } do
		if not isId(id) or not isPlain(rawDefinition) then
			return nil, "InvalidSpawnConfiguration"
		end
		-- Only explicit rarity participates. Names, assets, stage, and record IDs are unrelated.
		local rarity = (rawDefinition :: { [string]: unknown }).rarity
		if not isId(rarity) then
			return nil, "InvalidSpawnConfiguration"
		end
		local name = rarity :: string
		local forms = groups[name]
		if not forms then
			forms = {}
			groups[name] = forms
			table.insert(rarities, name)
		end
		table.insert(forms, id :: string)
	end
	if #rarities == 0 then
		return nil, "InvalidSpawnConfiguration"
	end
	local weights = rawWeights :: { [unknown]: unknown }
	for rarity, weight in weights do
		if
			not isId(rarity)
			or not groups[rarity :: string]
			or type(weight) ~= "number"
			or not (weight > 0 and weight < math.huge)
		then
			return nil, "InvalidSpawnConfiguration"
		end
	end
	table.sort(rarities)
	local pool: Pool = { totalWeight = 0, buckets = {} }
	for _, rarity in rarities do
		local weight = weights[rarity]
		if type(weight) ~= "number" then
			return nil, "InvalidSpawnConfiguration"
		end
		local cumulative = pool.totalWeight + weight
		if cumulative > MAX_SAFE_INTEGER or cumulative <= pool.totalWeight then
			-- Reject both unsafe totals and a positive group lost to floating-point precision.
			return nil, "InvalidSpawnConfiguration"
		end
		local forms = groups[rarity]
		table.sort(forms)
		table.insert(pool.buckets, {
			rarity = rarity,
			weight = weight,
			cumulativeWeight = cumulative,
			forms = forms,
		})
		pool.totalWeight = cumulative
	end
	FreezeUtil.DeepFreeze(pool)
	return pool, nil
end

function SpawnSelection.Choose(pool: Pool, rarityRoll: number, formRoll: number): string?
	if not isRoll(rarityRoll) or not isRoll(formRoll) then
		return nil
	end
	-- Buckets and forms use half-open intervals. The permitted endpoint 1 selects the last.
	local selected = pool.buckets[#pool.buckets]
	for _, bucket in pool.buckets do
		if rarityRoll < bucket.cumulativeWeight / pool.totalWeight then
			selected = bucket
			break
		end
	end
	local index = math.min(#selected.forms, math.floor(formRoll * #selected.forms) + 1)
	return selected.forms[index]
end

return table.freeze(SpawnSelection)
