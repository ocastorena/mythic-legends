--!strict
-- StarterPlayer/StarterPlayerScripts/State/LocalData

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage.Shared.Types)
export type StatePacket = SharedTypes.StatePacket

local LocalData = {}

local cache: { [string]: any } = {}
local revision = 0
local changedBindable = Instance.new("BindableEvent")
local isDestroyed = false

LocalData.OnStateChanged = changedBindable.Event
script:SetAttribute("Revision", revision)

-- Replicated sections are heterogeneous serialized data. Keep that dynamic boundary
-- here; feature controllers expose concrete records to their views.
local function cloneAndFreeze(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local clone = {}
	for key, child in pairs(value) do
		clone[key] = cloneAndFreeze(child)
	end
	return table.freeze(clone)
end

local function valuesEqual(left: any, right: any): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	for key, value in pairs(left) do
		if not valuesEqual(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

function LocalData.IngestPayload(payload: StatePacket): (boolean, string?)
	if isDestroyed then
		return false, "Destroyed"
	end
	if
		type(payload) ~= "table"
		or type(payload.revision) ~= "number"
		or type(payload.values) ~= "table"
	then
		return false, "InvalidPayload"
	end

	local isFull = payload.full == true
	if not isFull then
		if payload.revision <= revision then
			return true, nil
		end
		if payload.revision ~= revision + 1 then
			return false, "RevisionGap"
		end
	elseif payload.revision < revision then
		return true, nil
	end

	if isFull then
		for key, oldValue in pairs(cache) do
			if payload.values[key] == nil then
				cache[key] = nil
				changedBindable:Fire(key, nil, oldValue)
			end
		end
	end

	for key, value in pairs(payload.values) do
		if type(key) == "string" then
			local frozenValue = cloneAndFreeze(value)
			local oldValue = cache[key]
			if not valuesEqual(oldValue, frozenValue) then
				cache[key] = frozenValue
				changedBindable:Fire(key, frozenValue, oldValue)
			end
		end
	end

	if type(payload.removed) == "table" then
		for _, key in ipairs(payload.removed) do
			if type(key) == "string" and cache[key] ~= nil then
				local oldValue = cache[key]
				cache[key] = nil
				changedBindable:Fire(key, nil, oldValue)
			end
		end
	end

	revision = payload.revision
	script:SetAttribute("Revision", revision)
	return true, nil
end

function LocalData.Peek(key: string): any?
	return cache[key]
end

function LocalData.GetRevision(): number
	return revision
end

function LocalData.Destroy()
	if isDestroyed then
		return
	end
	isDestroyed = true
	table.clear(cache)
	revision = 0
	script:SetAttribute("Revision", revision)
	changedBindable:Destroy()
end

return LocalData
