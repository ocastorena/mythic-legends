--!strict
-- ServerScriptService/Services/DataService/Migrations
-- Forward-only profile migrations. Stage changes before touching the loaded document.

local ProductionLedger =
	require(game:GetService("ServerScriptService").Domain.Production.ProductionLedger)

local Migrations = {}

local function finiteNonnegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function standKey(value: any): string?
	local numeric = if type(value) == "string" then tonumber(value) else value
	if not finiteNonnegative(numeric) or numeric % 1 ~= 0 or numeric > 128 then
		return nil
	end
	local key = tostring(numeric)
	if type(value) == "string" and value ~= key then
		return nil
	end
	return key
end

-- This compatibility boundary accepts multiple historical shapes and preserves unknown fields.
-- Keep dynamic access here; validate every field used to calculate or commit migrated work.
function Migrations.Apply(data: any, mythlingsData: any, now: number): (boolean, string?)
	if type(data) ~= "table" then
		return false, "InvalidProfile"
	end
	if data.version == 3 then
		return true, nil
	end
	if data.version ~= nil and data.version ~= 2 then
		return false, "UnsupportedProfileVersion"
	end
	if not finiteNonnegative(now) then
		return false, "InvalidMigrationTime"
	end
	if data.base ~= nil and type(data.base) ~= "table" then
		return false, "InvalidBase"
	end
	local base = data.base or {}
	if base.stands ~= nil and type(base.stands) ~= "table" then
		return false, "InvalidStands"
	end
	if data.mythlings ~= nil and type(data.mythlings) ~= "table" then
		return false, "InvalidMythlings"
	end

	local stagedStands: { [string]: any } = {}
	for savedId, stand in pairs(base.stands or {}) do
		local key = standKey(savedId)
		if not key or type(stand) ~= "table" then
			return false, "InvalidStandRecord"
		end
		if stagedStands[key] ~= nil then
			return false, "ConflictingStandKeys"
		end
		if stand.production ~= nil then
			return false, "AmbiguousLegacyProduction"
		end
		stagedStands[key] = table.clone(stand)
	end

	local assigned: { [string]: boolean } = {}
	local consumedEntries: { any } = {}
	for _, savedEntry in pairs(data.mythlings or {}) do
		if type(savedEntry) ~= "table" then
			return false, "InvalidMythlingRecord"
		end
		-- Legacy records are validated field by field before their staged changes commit.
		local entry = savedEntry :: { [string]: any }
		if entry.standId == nil then
			if entry.lastCollectionAt ~= nil then
				return false, "OrphanLegacyProduction"
			end
			continue
		end

		-- The prototype assignment schema uses numeric stand IDs on Mythling records.
		local key = if type(entry.standId) == "number" then standKey(entry.standId) else nil
		if not key then
			return false, "InvalidStandAssignment"
		end
		if assigned[key] then
			return false, "DuplicateStandAssignment"
		end
		assigned[key] = true

		local definition = type(mythlingsData) == "table" and mythlingsData[entry.typeId] or nil
		local production = type(definition) == "table" and definition.production or nil
		if
			type(production) ~= "table"
			or type(production.materialId) ~= "string"
			or production.materialId == ""
			or not finiteNonnegative(production.materialsPerMinute)
			or not finiteNonnegative(production.baseCapacity)
		then
			return false, "UnknownLegacyProductionDefinition"
		end
		local legacyTime = entry.lastCollectionAt
		if legacyTime ~= nil and not finiteNonnegative(legacyTime) then
			return false, "InvalidLegacyProductionTime"
		end

		local ledger = {
			lastAccruedAt = legacyTime or now,
			materials = {},
		}
		local migratedLedger = ProductionLedger.Accrue(
			ledger,
			now,
			production.materialId,
			production.materialsPerMinute,
			production.baseCapacity
		)
		local stand = stagedStands[key] or {}
		stand.production = migratedLedger
		stagedStands[key] = stand
		table.insert(consumedEntries, entry)
	end

	-- No yielding or validation after this point: commit every migrated field together.
	base.stands = stagedStands
	data.base = base
	for _, entry in ipairs(consumedEntries) do
		entry.lastCollectionAt = nil
	end
	data.version = 3
	return true, nil
end

return table.freeze(Migrations)
