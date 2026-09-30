--!strict
-- ServerScriptService/Services/MythlingSpawnService/SpawnLifetimeUtil
-- Validate named overrides and rarity defaults without creating or restarting a contest deadline.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local SpawnLifetimeUtil = {}
type LifetimeTables = { defaults: { [string]: number }, overrides: { [string]: number } }

local function record(value: unknown): { [unknown]: unknown }?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	return value :: { [unknown]: unknown }
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function positive(value: unknown): boolean
	return type(value) == "number" and value > 0 and value < 2 ^ 53
end

local function lifetimeTables(tuning: unknown): LifetimeTables?
	local fields = record(tuning)
	if not fields then
		return nil
	end
	local defaults = record(fields.expireSeconds)
	local overrides = record(fields.formExpireSeconds)
	if not defaults or not overrides then
		return nil
	end
	for _, entries in { defaults, overrides } do
		for id, seconds in entries do
			if not isId(id) or not positive(seconds) then
				return nil
			end
		end
	end
	return {
		defaults = defaults :: { [string]: number },
		overrides = overrides :: { [string]: number },
	}
end

local function resolve(
	formId: unknown,
	rarity: unknown,
	rate: unknown,
	tables: LifetimeTables
): (number?, string?)
	if not isId(formId) then
		return nil, "InvalidFormId"
	end
	if not isId(rarity) then
		return nil, "InvalidFormDefinition"
	end
	-- Every used rarity needs a valid default, even when this form has an override. The legacy
	-- global default never hides an incomplete rarity policy.
	local default = tables.defaults[rarity :: string]
	if not default then
		return nil, "InvalidLifetimeConfiguration"
	end
	if not positive(rate) then
		return nil, "InvalidCaptureRate"
	end
	local captureSeconds = 100 / (rate :: number)
	if not positive(captureSeconds) then
		return nil, "InvalidCaptureRate"
	end
	local lifetime = tables.overrides[formId :: string] or default
	-- Strictly positive arrival slack is necessary, not proof of reachability on the actual map.
	if lifetime <= captureSeconds then
		return nil, "InsufficientLifetime"
	end
	return lifetime, nil
end

function SpawnLifetimeUtil.GetDeadline(now: number, lifetime: number): number?
	if type(now) ~= "number" or not (now >= 0 and now < 2 ^ 53) or not positive(lifetime) then
		return nil
	end
	local deadline = now + lifetime
	if not (deadline > now and deadline < 2 ^ 53) then
		return nil
	end
	return deadline
end

function SpawnLifetimeUtil.Resolve(
	formId: string,
	rarity: string,
	captureProgressPerSecond: number,
	tuning: Types.MythlingSpawnConfiguration
): (number?, string?)
	local tables = lifetimeTables(tuning)
	if not tables then
		return nil, "InvalidLifetimeConfiguration"
	end
	return resolve(formId, rarity, captureProgressPerSecond, tables)
end

function SpawnLifetimeUtil.Validate(
	rawForms: unknown,
	tuning: Types.MythlingSpawnConfiguration,
	rateField: string
): (boolean, string?)
	local tables = lifetimeTables(tuning)
	if not tables then
		return false, "InvalidLifetimeConfiguration"
	end
	local forms = record(rawForms)
	if not forms or next(forms) == nil then
		return false, "InvalidFormDefinition"
	end
	if rateField ~= "captureProgressPerSecond" and rateField ~= "fillRate" then
		return false, "InvalidCaptureRate"
	end
	for formId, rawDefinition in forms do
		local definition = record(rawDefinition)
		if not definition then
			return false, "InvalidFormDefinition"
		end
		local lifetime, problem = resolve(formId, definition.rarity, definition[rateField], tables)
		if not lifetime then
			return false, problem
		end
	end
	return true, nil
end

return table.freeze(SpawnLifetimeUtil)
