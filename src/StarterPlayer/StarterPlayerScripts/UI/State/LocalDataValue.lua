--!strict
-- StarterPlayer/StarterPlayerScripts/UI/State/LocalDataValue

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)
-- Adapts one LocalData key into a Fusion Value without creating a second client store.

local Types = require(script.Parent.Parent.Parent.Types)

local LocalDataValue = {}

function LocalDataValue.Observe(
	scope: Fusion.Scope<typeof(Fusion)>,
	localData: Types.LocalDataApi,
	key: string,
	fallback: unknown
): Fusion.Value<unknown>
	local current: unknown = localData.Peek(key)
	local value: Fusion.Value<unknown> = scope:Value(if current == nil then fallback else current)
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
