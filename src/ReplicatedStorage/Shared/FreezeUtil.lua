--!strict
-- ReplicatedStorage/Shared/FreezeUtil
-- Freeze configuration graphs once, including children of already-frozen tables.

local FreezeUtil = {}

type PlainTable = { [unknown]: unknown }

local function freezeTable(value: PlainTable, visited: { [PlainTable]: boolean })
	if visited[value] then
		return
	end
	visited[value] = true
	for key, child in value do
		if type(key) == "table" then
			freezeTable(key :: PlainTable, visited)
		end
		if type(child) == "table" then
			freezeTable(child :: PlainTable, visited)
		end
	end
	if not table.isfrozen(value) then
		table.freeze(value)
	end
end

function FreezeUtil.DeepFreeze<T>(value: T): T
	if type(value) == "table" then
		freezeTable(value, {})
	end
	return value
end

return table.freeze(FreezeUtil)
