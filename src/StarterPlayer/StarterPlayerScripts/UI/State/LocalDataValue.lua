-- StarterPlayer/StarterPlayerScripts/UI/State/LocalDataValue
-- Adapts one LocalData key into a Fusion Value without creating a second client store.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local LocalDataValue = {}

function LocalDataValue.observe(scope: any, localData: Types.LocalDataApi, key: string, fallback: any): any
	local current = localData.Peek(key)
	local value = scope:Value(if current == nil then fallback else current)
	table.insert(
		scope,
		localData.OnStateChanged:Connect(function(changedKey, nextValue)
			if changedKey == key then
				value:set(if nextValue == nil then fallback else nextValue)
			end
		end)
	)
	return value
end

return LocalDataValue
